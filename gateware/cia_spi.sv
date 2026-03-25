// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
// Copyright (C) 2026  Dag Lem <resid@nimrod.no>
//
// This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
//
// You may redistribute and modify this source and make products using it under
// the terms of the CERN-OHL-S v2 (https://ohwr.org/cern_ohl_s_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
//
// Source location: https://github.com/daglem/reDIP-CIA
// ----------------------------------------------------------------------------

`default_nettype none

// Override four-state semantics of ternary operator.
`ifdef __ICARUS__
  `define bit(v) bit'(v)
`else
  `define bit(v) (v)
`endif

module cia_spi (
    input  logic        clk,
    input  logic        res,
    input  logic        r_w,
    input  logic        start,
    input  cia::reg8_t  data_i,
    output cia::reg8_t  data_o,
    input  cia::spi_i_t spi_i,
    output cia::spi_o_t spi_o,
    output logic        busy,
    output logic        erase,
    output logic        prog
);

    // States.
    typedef enum logic [1:0] {
        IDLE,
        CONTROL,
        TRANSFER,
        DONE
    } state_t;

    // Control byte - see spi_commands.hex
    typedef struct packed {
        logic       await;  // Keep reading data bytes until data bit 0 = 0 (BUSY bit for command 05h).
        logic       erase;  // Clear erase status bit when BUSY bit is cleared.
        logic       prog;   // Clear program status bit when BUSY bit is cleared.
        logic       read;   // Read a single data byte at the end of command.
        logic [3:0] count;  // Number of bytes in command.
    } control_t;

    state_t     state;
    control_t   control;
    logic [4:0] offset;  // 5 bit offset to index up to 31 bytes.
    logic [2:0] bitno;   // 8 bits in a byte.
    logic       cs;
    logic       sclk;
    cia::reg8_t sr_i;
    cia::reg8_t sr_o;

    // Module outputs.
    always_comb begin
        spi_o.cs_n = ~cs;
        spi_o.sclk = sclk & cs;  // SPI Mode 0: SCLK is low when /CS is high.
        spi_o.so   = sr_o[7];
    end

    // BRAM block containing SPI command data.
    // We only address a small part of the SB_RAM40_4K physical RAM.
    // Using BRAM saves around 50 LCs, i.e. almost 5% of the official number of
    // 1100 LCs in the iCE5LP1K.
    (* nomem2reg *)
    (* no_rw_check *)
    cia::reg8_t commands[32];
    cia::reg8_t rdata;  // BRAM read port

    logic next_byte;
    logic writing;
    logic read_rdy;
    logic erase_next;
    logic prog_next;
    logic xfer_rdy;

    always_comb begin
        next_byte  = state == TRANSFER && bitno == '0;
        writing    = control.count != '1;
        erase_next = (control.await && control.erase && read_rdy && ~spi_i.si) ? '0 : erase;
        prog_next  = (control.await && control.prog  && read_rdy && ~spi_i.si) ? '0 : prog;
        xfer_rdy   = control.read ? read_rdy && !(control.erase && erase_next) && !(control.prog && prog_next) : !writing;
    end

    // Update of state, SPI shift / sample.
    always_ff @(posedge clk) begin
        if (res) begin
            state  <= IDLE;
            busy   <= '0;
            erase  <= '0;
            prog   <= '0;
            cs     <= '0;
            sr_i   <= '0;
            data_o <= '0;
        end else begin
            sclk   <= ~sclk;

            if (state == IDLE && start) begin
                state  <= CONTROL;
                busy   <= '1;
                offset <= r_w ? 'd0 : 'd6;
                erase  <= ~r_w;
                prog   <= ~r_w;
                sclk   <= '0;

                if (~r_w) begin
                    // Store data byte in BRAM at end of 02h Page Program command.
                    commands[22] <= data_i;
                end
            end

            if (~sclk) begin  // Before rising edge of SCLK (sample edge)
                if (state == TRANSFER) begin
                    // Delay read one SCLK cycle (two clk cycles) to account
                    // for registered I/O.
                    read_rdy <= next_byte && !writing;

                    // Update status for erase and program.
                    erase <= erase_next;
                    prog  <= prog_next;

                    if (!writing && control.read) begin
                        // Shift in SI bit.
                        sr_i <= { sr_i[6:0], spi_i.si };
                    end

                    if (xfer_rdy) begin
                        state <= CONTROL;
                        cs    <= '0;
                    end
                end

                if (state == DONE) begin
                    state  <= IDLE;
                    // Store data byte.
                    data_o <= sr_i;
                    busy   <= '0;
                end

                if (state == CONTROL || (state == TRANSFER && writing && next_byte)) begin
                    // Read next byte from BRAM to prepare for next falling edge.
                    // Note that the next control byte is read immediately after
                    // transfer of the last command byte.
                    rdata  <= commands[offset];
                    offset <= offset + 'd1;

                    if (state == TRANSFER) begin
                        control.count <= control.count - 'd1;
                    end
                end
            end

            if (sclk) begin  // Before falling edge of SCLK (shift edge)
                if (state == CONTROL) begin
                    state   <= `bit(rdata == '0) ? DONE : TRANSFER;
                    // Copy control byte from BRAM port.
                    control <= rdata;
                    bitno   <= '0;
                end

                if (state == TRANSFER) begin
                    cs    <= '1;
                    bitno <= bitno - 'd1;

                    if (writing) begin
                        if (next_byte) begin
                            // Copy command byte from BRAM port to shift register;
                            // first SO bit ready.
                            sr_o <= rdata;
                        end else begin
                            // Shift out next SO bit.
                            sr_o <= { sr_o[6:0], 1'b0 };
                        end
                    end
                end
            end
        end
    end

    initial begin
        $readmemh("spi_commands.hex", commands);
    end

`ifdef __ICARUS__
    // Iverilog currently flattens structs.
    logic [3:0] count;
    always_comb count = control.count;
`endif
endmodule

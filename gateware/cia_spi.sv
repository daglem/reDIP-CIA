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

    typedef struct packed {
        logic       loop;   // Repeat 05h Read Status Register 1 until BUSY bit = 0.
        logic       erase;  // Output Status register 1 BUSY bit to erase status bit.
        logic       prog;   // Output Status register 1 BUSY bit to program status bit.
        logic       read;   // Read a single data byte at the end of command.
        logic [3:0] count;  // Number of bytes in command.
    } control_t;

    typedef logic [4:0] offset_t;  // 5 bit offset to index up to 32 bytes.
    typedef logic [7:0] bitoff_t;  // Handle command sequences of up to 32 bytes = 256 bits.

    // Extended state.
    typedef struct packed {
        state_t      state;
        control_t    control;
        offset_t     offset;
        bitoff_t     bitno;
        logic        busy;
        logic        erase;
        logic        prog;
        logic        cs;
        logic        sclk;
    } vars_t;

    vars_t current, next;

    cia::reg8_t sr_i;
    cia::reg8_t sr_o;

    // Module outputs.
    always_comb begin
        spi_o.cs_n = ~current.cs;
        spi_o.sclk = current.sclk & current.cs;  // SPI Mode 0: SCLK is low when /CS is high.
        spi_o.so   = sr_o[7];

        busy  = current.busy;
        erase = current.erase;
        prog  = current.prog;
    end

    // BRAM block containing SPI command data.
    // We only address a small part of the SB_RAM40_4K physical RAM.
    // Using BRAM saves around 50 LCs, i.e. almost 5% of the official number of
    // 1100 LCs in the iCE5LP1K.
    (* nomem2reg *)
    (* no_rw_check *)
    cia::reg8_t commands[32];
    cia::reg8_t rdata;  // BRAM read port

    bitoff_t bitlen;
    logic    next_byte;

    always_comb begin
        // For read commands we add 8 bits to read one byte, one bit for
        // SI vs. SO delay, and two bits for registered SO and registered SI.
        // Note that for simplicity we simply clock out bits from the next
        // bytes in BRAM as the final data bits are clocked in.
        bitlen    = { current.control.count, 3'd0 } + (current.control.read ? 8'd11 : 8'd0);
        next_byte = current.bitno[2:0] == '0;
    end

    // Update of state, SPI shift / sample.
    always_ff @(posedge clk) begin
        if (res) begin
            current <= '0;
            sr_o    <= '0;
            sr_i    <= '0;
            data_o  <= '0;
        end else begin
            current <= next;

            if (current.state == IDLE && start && ~r_w) begin
                // Store data byte in BRAM at end of 02h Page Program command.
                commands[22] <= data_i;
            end

            if (~current.sclk) begin  // Before rising edge of SCLK (sample edge)
                if (current.control.read) begin
                    if (current.state == TRANSFER) begin
                        // Shift in SI bit.
                        sr_i <= { sr_i[6:0], spi_i.si };
                    end

                    if (current.state == DONE) begin
                        // Store data byte.
                        data_o <= sr_i;
                    end
                end

                if (current.state == CONTROL || (current.state == TRANSFER && next_byte)) begin
                    // Read next byte from BRAM to prepare for next falling edge.
                    rdata <= commands[current.offset + offset_t'(current.state == TRANSFER) + offset_t'(current.bitno[7:3])];
                end
            end

            if (current.sclk) begin  // Before falling edge of SCLK (shift edge)
                if (current.state == TRANSFER) begin
                    if (next_byte) begin
                        // Copy byte from BRAM port to shift register; first SO bit ready.
                        sr_o <= rdata;
                    end else begin
                        // Shift out next SO bit.
                        sr_o <= { sr_o[6:0], 1'b0 };
                    end
                end
            end
        end
    end

    // Combinational logic for next state.
    always_comb begin
        next = current;

        next.sclk = ~current.sclk;

        unique case (current.state)
          IDLE: if (start) begin
              next.state  = CONTROL;
              next.sclk   = '0;
              next.busy   = '1;
              next.offset = offset_t'(r_w ? 0 : 6);
              next.erase  = ~r_w;
              next.prog   = ~r_w;
          end
          CONTROL: if (current.sclk) begin
              if (rdata == '0) begin
                  next.state   = DONE;
              end else begin
                  // Copy byte from BRAM port to control register.
                  next.state   = TRANSFER;
                  next.control = rdata;
              end
          end else begin
              next.cs     = '0;
          end
          TRANSFER: if (current.sclk) begin
              // Bring /CS low as SCLK goes low, for SPI Mode 0.
              next.cs      = '1;
              if (current.bitno == bitlen) begin
                  next.state = CONTROL;
                  next.bitno = '0;

                  if (!(current.control.loop && sr_i[0])) begin
                      // No loop or Status Register 1 BUSY bit is cleared; continue with next command.
                      next.offset = current.offset + offset_t'(1) + offset_t'(current.control.count);

                      if (current.control.erase) begin
                          next.erase = '0;
                      end
                      if (current.control.prog) begin
                          next.prog  = '0;
                      end
                  end
              end else begin
                  next.bitno = current.bitno + bitoff_t'(1);
              end
          end
          DONE: begin
              next.state  = IDLE;
              next.busy   = '0;
          end
        endcase
    end

    initial begin
        $readmemh("spi_commands.hex", commands);
    end

`ifdef __ICARUS__
    // Iverilog currently flattens structs.
    state_t  state;
    offset_t offset;
    bitoff_t bitno;
    always_comb begin
        state  = current.state;
        offset = current.offset;
        bitno  = current.bitno;
    end
`endif
endmodule

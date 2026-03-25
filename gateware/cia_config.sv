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

module cia_config (
    input  logic        clk,
    input  logic        res,
    input  logic        icr_r,
    input  logic        icr_w,
    input  cia::reg8_t  data,
    input  cia::spi_i_t spi_i,
    output cia::spi_o_t spi_o,
    output cia::model_t model,
    output logic[1:0]   icr65
);

    // The commands which can be written to the ICR register are:
    //
    //   CFG0 - Report CIA model in ICR bits 6:5
    //   CFG1 - Configure MOS 6526
    //   CFG2 - Configure MOS 8521
    //   CFG3 - Configure MOS 8520
    //   CFG6 - Read configuration from flash, report CIA model in ICR bits 6:5
    //   CFG7 - Write configuration to flash, report status in ICR bits 6:5
    //
    // where each character must first be converted by
    //   byte = (chr - 64)*16
    // and each number by
    //   byte = (num - 48)*16
    //
    // Using letters @ - G and numbers 0-7, we only set bits 4-6 in the ICR
    // register. This scheme is minimally intrusive (only clearing the MASK FLG
    // bit), and is highly unlikely to cause involuntary configuration changes
    // (no-op values, flipping of unused bits 5 and 6).

    // States.
    typedef enum logic [1:0] {
        INIT,
        PROMPT,
        READ,
        WRITE
    } state_t;

    // Extended state.
    typedef struct packed {
        state_t      state;
        cia::model_t model;
        logic [1:0]  cmdlen;  // Number of characters accepted in CFGn input.
        logic        rstat;   // Report CIA model in ICR after read from flash.
        logic [1:0]  icr65;   // ICR bits 6:5 output.
        logic        wear;    // A flash erase / program cycle has been performed.
    } vars_t;

    vars_t current, next;

    // Module outputs.
    always_comb begin
        model = current.model;
        icr65 = current.icr65;
    end

    logic       icr_cmd;
    logic [2:0] chr;
    logic       spi_start;
    logic       spi_busy;
    logic       spi_erase;
    logic       spi_prog;
    cia::reg8_t spi_data;

    always_comb begin
        icr_cmd = { data[7], data[3:0] } == 0;
        chr     = data[6:4];
    end

    // Update of state.
    always_ff @(posedge clk) begin
        if (res) begin
            current <= '0;  // current.state <= INIT
        end else begin
            current <= next;
        end
    end

    // Combinational logic for next state.
    always_comb begin
        next = current;

        spi_start = '0;

        if (icr_r) begin
            // ICR read resets command input and clears ICR status.
            next.cmdlen = '0;
            next.icr65  = '0;
        end

        unique0 case (current.state)
          INIT: if (~res) begin
              next.state = READ;
              spi_start  = '1;
          end
          PROMPT: if (icr_w) begin
              next.cmdlen = '0;

              if (icr_cmd) begin
                  unique case (current.cmdlen)
                    'd0: if (chr == 'd3) next.cmdlen = 'd1;  // C
                    'd1: if (chr == 'd6) next.cmdlen = 'd2;  // CF
                    'd2: if (chr == 'd7) next.cmdlen = 'd3;  // CFG
                    'd3: begin                               // CFG n
                        unique0 case (chr)
                          'd0: begin                         // CFG 0
                              next.icr65  = current.model;
                          end
                          'd1, 'd2, 'd3: begin               // CFG 1-3
                              next.model  = cia::model_t'(chr[1:0]);
                          end
                          'd6: begin                         // CFG 6
                              next.state  = READ;
                              next.rstat  = '1;
                              spi_start   = '1;
                          end
                          'd7: if (!current.wear) begin      // CFG 7
                              // Allow only one erase / program cycle per reset;
                              // this makes it impossible for a malicious program
                              // to wear out the flash 4K block.
                              next.state  = WRITE;
                              next.wear   = '1;
                              spi_start   = '1;
                          end
                        endcase
                    end
                  endcase
              end
          end
          READ: begin
              if (~spi_busy) begin
                  next.state = PROMPT;
                  // Default to MOS8521. An erased flash will report 'hFF, i.e.
                  // initial programming of the configuration byte is not necessary.
                  next.model = `bit(spi_data >= '1 || spi_data <= 'd3) ? cia::model_t'(spi_data) : cia::MOS8521;
                  if (current.rstat)
                      next.icr65 = next.model;
              end
          end
          WRITE: begin
              if (~spi_busy)
                  next.state = PROMPT;
              next.icr65 = { spi_erase, spi_prog };
          end
        endcase
    end

    // Read / write configuration in SPI flash.
    cia_spi cia_spi (
      .clk    (clk),
      .res    (res),
      .r_w    (next.state == READ),
      .start  (spi_start),
      .data_i (8'(current.model)),
      .data_o (spi_data),
      .spi_i  (spi_i),
      .spi_o  (spi_o),
      .busy   (spi_busy),
      .erase  (spi_erase),
      .prog   (spi_prog)
    );

endmodule

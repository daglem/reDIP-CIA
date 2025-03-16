// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
// Copyright (C) 2025  Dag Lem <resid@nimrod.no>
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

module cia_ports (
    input  logic        clk,
    input  logic        phi2_up,
    input  logic        phi2_dn,
    input  logic        res,
    input  logic        rd,
    input  logic        we,
    input  cia::reg4_t  addr,
    input  cia::reg8_t  data,
    input  cia::reg8_t  pa,
    input  cia::reg8_t  pb,
    input  logic        ta_pb,
    input  logic        tb_pb,
    input  logic        ta_pbon,
    input  logic        tb_pbon,
    output cia::ports_t regs,
    output cia::ports_t pads,
    output logic        pc_n
);

    (* nowrshmsk *)
    cia::ports_t ports; // Register file.
    logic [2:0] prb_rw; // Shift register used to control /PC
    cia::reg8_t pra;    // Registered port inputs
    cia::reg8_t prb;

    always_comb begin
        // Some observations regarding /PC:
        //
        // * The /PC pulse width will normally be one cycle.
        // * If reads/writes of PRB are made on consecutive cycles, the pulse
        //   width will be stretched to two cycles.
        // * If two reads/writes of PRB are made with one intermittent cycle,
        //   only one single cycle pulse will be generated.
        pc_n = ~(prb_rw[0] & ~prb_rw[2]);

        regs.pra  = pra;
        regs.prb  = prb;
        regs.ddra = ports.ddra;
        regs.ddrb = ports.ddrb;

        pads.pra = ports.pra;
        // PB6 and PB7 can be configured to output timer signals.
        pads.prb = {
            tb_pbon ? tb_pb : ports.prb[7],
            ta_pbon ? ta_pb : ports.prb[6],
            ports.prb[5:0]
        };

        pads.ddra = ports.ddra;
        // PB6 and PB7 DDRs may be overridden for output of timer signals.
        pads.ddrb = {
            tb_pbon | ports.ddrb[7],
            ta_pbon | ports.ddrb[6],
            ports.ddrb[5:0]
        };
    end

    // Register writes.
    always_ff @(posedge clk) begin
        if (res) begin
            // Reset at any time.
            // In the real CIA chips, reset is made while PHI1 is high.
            ports <= '0;
        end else if (phi2_dn && we && addr[3:2] == 2'b00) begin
            // Store register value on the falling edge of PHI2.
            // In real CIA chips, writes are made while PHI2 is high. Since
            // these writes could otherwise cause glitching of port outputs
            // during PHI2, real CIA chips latch register values on PHI1.
            // However here we make writes on the falling edge of PHI2, and
            // thus there is no need for further buffering of the registers.
            ports[{ ~addr[1:0], 3'b000 } +: 8] <= data;
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            // Read or write of PRB is shifted in.
            prb_rw <= { prb_rw[1:0], (rd | we) && addr == 'h1 };
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_up) begin
            // Read port inputs on the rising edge of PHI2.
            // In the real CIA chips, port inputs are latched by PHI1.
            pra <= pa;
            prb <= pb;
        end
    end
endmodule

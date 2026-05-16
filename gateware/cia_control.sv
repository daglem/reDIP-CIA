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

module cia_control #(
    parameter CR  // 0 = CRA, 1 = CRB
)(
    input  logic        clk,
    input  logic        phi2_dn,
    input  logic        res,
    input  logic        cr_w,
    input  cia::reg8_t  data,
    input  logic        t_ufl,
    input  logic        cnt_up,
    input  logic        t0_int,  // Only used by CRB
    input  logic        cnt,     // Only used by CRB
    output cia::reg8_t  regs,
    output cia::tctrl_t t_ctrl
);

    // Control register.
    // CRA and CRB only differ in bits 6 and 7, and bit 7 is not referenced here.
    // For simplicity we use the type for CRA.
    cia::cra_t cr;
    cia::cra_t cr_next;

    // Control signals.
    logic cr_w_prev;
    logic cnt_prev;

    always_comb begin
        // Multiplexers for register updates.
        // cra.start and cra.runmode are both latched by PHI1.
        // Since ~cra.runmode is injected into the continuous refresh of
        // cra.start, there is a race where a slightly delayed change
        // of cra.runmode from 1 to 0 at the start of PHI1 causes
        // cra.start to be cleared for an extra cycle.
        // Test: vice-testprogs/general/Lorenz-2.15/src/flipos.prg
        cr_next        = cr_w ? data : cr;
        cr_next.start &= ~((cr.runmode | cr_next.runmode) & t_ufl);

        // Timer control signals.
        t_ctrl.start  = cr.start;
        t_ctrl.toggle = cr.outmode;

        // Contrary to what's stated in the datasheet, the control register
        // LOAD bit is actually stored, and is ANDed with the control register
        // write line from the previous cycle.
        //
        // An interesting observation is that if the control register is
        // written in two consecutive cycles, the last written LOAD bit will
        // override the first.
        t_ctrl.force_load = cr.load & cr_w_prev;

        if (CR == 0) begin
            // CRA:
            // INMODE  1=TIMER A counts positive CNT transitions, 0=TIMER A counts PHI2 pulses.
            t_ctrl.count = (~cr.inmode | cnt_up) & cr.start;
        end else begin
            // CRB:
            // CRB6 CRB5
            // 0    0    TIMER B counts PHI2 pulses.
            // 0    1    TIMER B counts positive CNT transistions.
            // 1    0    TIMER B counts TIMER A underflow pulses.
            // 1    1    TIMER B counts TIMER A underflow pulses while CNT is high.
            t_ctrl.count = cr[6] ?
                           t0_int & (~cr[5] | cnt_prev) & cr.start :
                           (~cr[5] | cnt_up) & cr.start;
        end

        // Read control registers. The LOAD bit is not output.
        regs = { cr[7:5], 1'b0, cr[3:0] };
    end

    // Update of control registers.
    always_ff @(posedge clk) begin
        if (res) begin
            // Reset at any time.
            // In the real CIA chips, reset is made while PHI1 is high.
            // Also, the stored LOAD bit is not reset in a real chip.
            cr <= '0;
        end else if (phi2_dn) begin
            cr <= cr_next;
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            cr_w_prev <= cr_w;
            cnt_prev  <= cnt;
        end
    end
endmodule

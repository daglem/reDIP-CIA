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

module cia_control (
    input  logic          clk,
    input  logic          phi2_dn,
    input  logic          res,
    input  logic          we,
    input  cia::reg4_t    addr,
    input  cia::reg8_t    data,
    input  logic          cnt,
    input  logic          cnt_up,
    input  logic          ta_ufl,
    input  logic          tb_ufl,
    input  logic          ta_int,
    output cia::control_t regs,
    output cia::tctrl_t   ta_ctrl,
    output cia::tctrl_t   tb_ctrl
);

    // Control registers.
    cia::control_t ctrl;
    cia::control_t ctrl_next;

    // Control signals.
    logic cra_w;
    logic cra_w_prev;
    logic crb_w;
    logic crb_w_prev;
    logic cnt_prev;

    always_comb begin
        cra_w = we && addr == 'hE;
        crb_w = we && addr == 'hF;

        // Multiplexers for register updates.
        ctrl_next.cra        = cra_w ? data : ctrl.cra;
        ctrl_next.cra.start &= ~(ctrl.cra.runmode & ta_ufl);

        ctrl_next.crb        = crb_w ? data : ctrl.crb;
        ctrl_next.crb.start &= ~(ctrl.crb.runmode & tb_ufl);

        // Timer control signals.
        ta_ctrl.start = ctrl_next.cra.start;
        tb_ctrl.start = ctrl_next.crb.start;

        ta_ctrl.toggle = ctrl.cra.outmode;
        tb_ctrl.toggle = ctrl.crb.outmode;

        ta_ctrl.one_shot = ctrl.cra.runmode;
        tb_ctrl.one_shot = ctrl.crb.runmode;

        // Contrary to what's stated in the datasheet, the control register
        // LOAD bit is actually stored, and is ANDed with the control register
        // write line from the previous cycle.
        //
        // An interesting observation is that if the control register is
        // written in two consecutive cycles, the last written LOAD bit will
        // override the first.
        ta_ctrl.force_load = ctrl_next.cra.load & cra_w_prev;
        tb_ctrl.force_load = ctrl_next.crb.load & crb_w_prev;

        // INMODE  1=TIMER A counts positive CNT transitions, 0=TIMER A counts PHI2 pulses.
        ta_ctrl.count = (~ctrl.cra.inmode | cnt_up) & ctrl.cra.start;

        // CRB6 CRB5
        // 0    0    TIMER B counts PHI2 pulses.
        // 0    1    TIMER B counts positive CNT transistions.
        // 1    0    TIMER B counts TIMER A underflow pulses.
        // 1    1    TIMER B counts TIMER A underflow pulses while CNT is high.
        tb_ctrl.count = (ctrl.crb.inmode[1] ?
                         ta_int & (~ctrl.crb.inmode[0] | cnt_prev) :
                         ~ctrl.crb.inmode[0] | cnt_up
                        ) & ctrl.crb.start;

        // Read control registers. The LOAD bit is not output.
        regs.cra = { ctrl.cra[7:5], 1'b0, ctrl.cra[3:0] };
        regs.crb = { ctrl.crb[7:5], 1'b0, ctrl.crb[3:0] };
    end

    // Update of control registers.
    always_ff @(posedge clk) begin
        if (res) begin
            // Reset at any time.
            // In the real CIA chips, reset is made while PHI1 is high.
            // Also, the stored LOAD bit is not reset in a real chip.
            ctrl <= '0;
        end else if (phi2_dn) begin
            ctrl <= ctrl_next;
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            cra_w_prev <= cra_w;
            crb_w_prev <= crb_w;
            cnt_prev   <= cnt;
        end
    end
endmodule

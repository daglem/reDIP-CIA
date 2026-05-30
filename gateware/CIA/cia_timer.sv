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

module cia_timer (
    input  logic           clk,
    input  logic           phi2_dn,
    input  logic           res,
    input  logic           lo_w,
    input  logic           hi_w,
    input  cia::reg8_t     data,
    /* verilator lint_off UNUSEDSIGNAL */
    input  cia::tctrl_t    ctrl,
    /* verilator lint_off UNUSEDSIGNAL */
    output cia::timer_t    regs,
    output cia::one_shot_t one_shot,  // One-shot timer control
    output logic           intr,
    output logic           pb
);

    cia::reg16_t prescaler; // Timer latch
    cia::reg16_t prescaler_next;
    cia::reg16_t counter;   // Timer counter
    cia::reg16_t counter_next;

    logic hi_w_prev;        // Register write
    logic start_prev;       // Control register start
    logic ufl;              // Timer underflow
    logic reload;           // Reload counter from latch
    logic reload_prev;
    logic count_prev;
    logic intr_up;
    logic toggle;           // Timer underflow toggle
    logic toggle_prev;
    logic pulse;            // Timer underflow pulse
    logic os_loaded;        // MOS 8520 one-shot timer loaded
    logic os_loaded_prev;

    always_comb begin
        prescaler_next = { hi_w ? data : prescaler[15:8], lo_w ? data : prescaler[7:0] };
        counter_next = counter - count_prev;

        // Timer underflow when the timer reaches 0 while counting.
        ufl = ~(reload_prev ? |prescaler_next : |counter_next) & ctrl.count;

        // Load timer on timer underflow, force load, or write to timer
        // high byte while the timer is stopped.
        // In real CIA chips, res is also ORed in. We use a separate reset.
        // NB! ctrl.one_shot is only set for MOS 8520
        reload = ufl | ctrl.force_load | (hi_w_prev & (~ctrl.start | ctrl.one_shot));

        // Read registers.
        regs.lo = counter[ 7:0];
        regs.hi = counter[15:8];

        // One-shot control signals.
        one_shot.stop = ufl;
        // MOS 8520 start.
        one_shot.start = ctrl.one_shot & hi_w;

        // SR latch keeping state of MOS 8520 one-shot timer load.
        if      (reload_prev | res) os_loaded = '1;
        else if (one_shot.start)    os_loaded = '0;
        else                        os_loaded = os_loaded_prev;

        one_shot.loaded = ctrl.one_shot & os_loaded;

        // PB6 / PB7 timer output toggle.
        if      ((~start_prev & ctrl.start) | (intr_up & ~toggle_prev)) toggle = 1;
        else if (res | (intr_up & toggle_prev))                         toggle = 0;
        else                                                            toggle = toggle_prev;

        // Timer output, which may appear on PB6 / PB7.
        pulse = intr;
        pb    = ctrl.toggle ? toggle : pulse;
    end

    // Writes to timer latch.
    always_ff @(posedge clk) begin
        if (res) begin
            // Reset at any time.
            // In the real CIA chips, reset is made while PHI1 is high.
            prescaler <= '1;
            counter   <= '1;
        end else if (phi2_dn) begin
            // Store register value on the falling edge of PHI2.
            // In real CIA chips, writes are made while PHI2 is high.
            prescaler <= prescaler_next;

            // Timer load or count.
            counter <= reload || reload_prev ? prescaler_next : counter_next;
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            hi_w_prev      <= hi_w;
            start_prev     <= ctrl.start;
            reload_prev    <= reload;
            count_prev     <= ctrl.count;
            intr           <= ufl;
            intr_up        <= ~intr & ufl;
            toggle_prev    <= toggle;
            os_loaded_prev <= os_loaded;
        end
    end
endmodule

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
    input  logic        clk,
    input  logic        phi2_dn,
    input  logic        res,
    input  logic        lo_w,
    input  logic        hi_w,
    input  cia::reg8_t  data,
    input  cia::tctrl_t ctrl,
    output cia::timer_t regs,
    output logic        ufl,
    output logic        intr,
    output logic        pb
);

    cia::reg16_t prescaler; // Timer latch
    cia::reg16_t prescaler_next;
    cia::reg16_t counter;   // Timer counter
    cia::reg16_t counter_next;

    logic hi_w_prev;        // Register write
    logic start_prev;       // Control register start
    logic reload;           // Reload counter from latch
    logic reload_prev;
    logic count_prev;
    logic intr_up;
    logic toggle;           // Timer underflow toggle
    logic toggle_prev;
    logic pulse;            // Timer underflow pulse

    always_comb begin
        prescaler_next = { hi_w ? data : prescaler[15:8], lo_w ? data : prescaler[7:0] };
        counter_next = counter - { 15'b0, count_prev };

        // Timer underflow when the timer reaches 0 while counting.
        ufl = ~(reload_prev ? |prescaler_next : |counter_next) & ctrl.count;

        // Load timer on timer underflow, force load, or write to timer
        // high byte while the timer is stopped.
        // In real CIA chips, res is also ORed in. We use a separate reset.
        reload = ufl | ctrl.force_load | (hi_w_prev & ~ctrl.start);

        // Read registers.
        regs.lo = counter[ 7:0];
        regs.hi = counter[15:8];

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
            if (reload || reload_prev) begin
                counter <= prescaler_next;
            end else begin
                counter <= counter_next;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            hi_w_prev   <= hi_w;
            start_prev  <= ctrl.start;
            reload_prev <= reload;
            count_prev  <= ctrl.count;
            intr        <= ufl;
            intr_up     <= ~intr & ufl;
            toggle_prev <= toggle;
        end
    end
endmodule

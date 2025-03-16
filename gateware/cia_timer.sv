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
    output logic        t_int,
    output logic        pb
);

    cia::reg16_t prescaler; // Timer latch
    cia::reg16_t counter;   // Timer counter

    logic hi_w_prev;        // Register write
    logic start_prev;       // Control register start
    logic underflow;        // Timer underflow
    logic reload;           // Reload counter from latch
    logic toggle;           // Timer underflow toggle
    logic pulse;            // Timer underflow pulse

    always_comb begin
        // Timer underflow when the timer is 0 and is about to count down.
        underflow = ~|counter & ctrl.count;

        // Load timer on timer underflow, force load, or write to timer
        // high byte while the timer is stopped.
        reload = underflow | ctrl.force_load | (hi_w_prev & ~start_prev);

        // Read registers.
        regs.lo = counter[ 7:0];
        regs.hi = counter[15:8];

        // Timer output, which may appear on PB6 / PB7.
        t_int = pulse;
        pb    = ctrl.outmode ? toggle : t_int;
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
            if (lo_w) begin
                prescaler[ 7:0] <= data;
            end
            if (hi_w) begin
                prescaler[15:8] <= data;
            end

            // Timer load or count.
            if (reload) begin
                counter <= prescaler;
            end else begin
                counter <= counter - { 15'b0, ctrl.count };
            end
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            if (res) begin
                toggle <= 1'b0;
            end else if (~start_prev & ctrl.start) begin
                toggle <= 1'b1;
            end else if (underflow) begin
                toggle <= ~toggle;
            end

            hi_w_prev  <= hi_w;
            start_prev <= ctrl.start;
            pulse      <= underflow;
        end
    end
endmodule

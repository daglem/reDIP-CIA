// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS PIA/VIA/CIA FPGA emulation platform.
// Copyright (C) 2025 - 2026  Dag Lem <resid@nimrod.no>
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

module via_serial (
    input  logic        clk,
    input  logic        phi2,
    input  logic        rd,
    input  logic        we,
    input  via::reg4_t  addr,
    input  via::reg8_t  data,
    /* verilator lint_off UNUSEDSIGNAL */
    input  via::acr_t   acr,
    input  via::ifr_t   ifr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        t2l_ufl,
    input  logic        scli_cb1,
    input  logic        si_cb2,
    output via::sflag_t sflag_o,
    output via::reg8_t  sr,
    output logic        sclo_cb1,
    output logic        so_cb2
);
    logic asel_sr;
    logic sr_run;
    logic sr_in;
    logic sr_shift;
    logic sr_cnt1_0;
    logic sr_done;
    logic sclk_reg, sclk_prev;
    logic sclk_edge;
    logic sclk_toggle;
    logic sclk_next;

    via::reg8_t sr_latch;
    via::reg5_t sr_cnt, sr_cnt_latch;  // 5 bit ring counter, counting 8 bit shifts

    // Register write / shift.
    always_comb begin
        asel_sr = (addr == 'ha);
        sr_in   = acr.shift_mode[2] ? so_cb2 : si_cb2;  // Circular shift in output mode
    end

    always_ff @(posedge clk) begin
        if (we && asel_sr) begin
            sr_latch <= data;
        end else if (~phi2) begin
            // Note that it takes an extra FPGA cycle for so_cb2 to reach
            // sr_latch[0] via sr_in in output mode.
            { so_cb2, sr_latch } <= sr_shift ? { sr, sr_in } : { so_cb2, sr };
        end

        if (phi2) begin
            sr_shift <= sclk_edge & ~ifr.sr;
            sr       <= sr_latch;
        end
    end

    // Shift count.
    always_ff @(posedge clk) begin
        if (sflag_o.r_sr) begin
            sr_run <= '1;
        end else if (acr.shift_mode == 'b000 || ifr.sr) begin  // SR disabled or IFR flag set.
            sr_run <= '0;
        end

        if (~phi2) begin
            // Timer 2 rate or PHI2 rate.
            sclk_toggle <= (((acr.shift_mode == 'b100 | acr.shift_mode[1:0] == 'b01) & t2l_ufl) | acr.shift_mode[1:0] == 'b10) & ~ifr.sr;
        end

        if (phi2 & ~sr_run) begin
            sclk_next <= '1;
        end else if (~phi2 & sclk_toggle) begin
            sclk_next <= ~sclo_cb1;
        end

        if (phi2) begin
            sclo_cb1 <= sclk_next;
        end

        if (~sr_run) begin
            sr_cnt_latch <= '1;
        end else if (~(we && asel_sr) & ~phi2) begin
            sr_cnt_latch <= sr_shift ? { ~sr_cnt[0], sr_cnt[4:1] } : sr_cnt;
        end

        if (phi2) begin
            sr_cnt    <= sr_cnt_latch;
            sr_cnt1_0 <= ~(sr_cnt_latch[1] | sflag_o.s_sr);
        end
    end

    always_comb begin
        sr_done = sr_cnt_latch[2] & sr_cnt1_0;
    end

    // Serial clock input edge detector.
    always_ff @(posedge clk) begin
        if (phi2) begin
            // NB! The real chip samples CB1 using an SR latch, without any
            // valid mechanism to avoid an illegal state for the latch.
            //
            // On CB1 edges, both SR latch inputs are in an undefined
            // state. The latch may thus read both inputs as "1" and set both
            // outputs to "0". If this coincides with a PHI2 negative edge, the
            // CB1 edge goes undetected in this cycle. After the falling edge
            // of PHI2, both SR latch inputs are set to "0", and it is now
            // undefined which of the "0" latch outputs will eventually "win"
            // over the other to become "1" and be kept by the edge detection
            // latches following the SR latch. If the SR latch output
            // corresponding to the post-edge CB1 level prevails, the CB1 edge
            // is forever lost.
            sclk_reg <= scli_cb1;
        end

        if (~phi2) begin
            sclk_prev <= sclk_reg;
        end
    end

    always_comb begin
        // Falling edge for output, rising edge for input.
        sclk_edge = acr.shift_mode[2] ? sclk_prev & ~sclk_reg : ~sclk_prev & sclk_reg;
    end

    always_comb begin
        // External clock or clock out, and count finished.
        sflag_o.s_sr = (acr.shift_mode[1:0] == 'b11 | sclo_cb1) & sr_done;
        // Read or write of SR.
        sflag_o.r_sr = (rd | we) & asel_sr;
    end
endmodule

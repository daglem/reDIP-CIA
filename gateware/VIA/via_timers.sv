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

module via_timers (
    input  logic        clk,
    input  logic        res,
    input  logic        phi2,
    input  logic        rd,
    input  logic        we,
    input  via::reg4_t  addr,
    input  via::reg8_t  data,
    /* verilator lint_off UNUSEDSIGNAL */
    input  via::acr_t   acr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        t2_pb6,
    output via::tregs_t regs,
    output via::tflag_t tflag_o,
    output logic        t1_pb7,
    output logic        t2l_ufl
);

    // Timer 1.
    logic w_t1c_h;
    logic t1_load;
    logic t1_ufl, t1_ufl_prev;
    logic t1_run;
    logic t1_pb7_prev;
    logic s_t1, s_t1_prev;

    // NB! T1 powerup values are not deterministic, however all ones is a common value.
    via::reg16_t t1_latch = '1, t1_count = '1, t1_count_prev;

    // Timer 2.
    logic w_t2c_h;
    logic t2_cin;
    logic t2l_load;
    logic t2l_ufl_prev;
    logic t2h_ufl;
    logic t2_run;
    logic t2_pb6_reg, t2_pb6_last, t2_pb6_prev;
    logic s_t2, s_t2_prev;

    // NB! T2 powerup values are not deterministic, however all ones is a common value.
    via::reg8_t  t2l_latch = '1;
    via::reg16_t t2_count = '1, t2_count_prev, t2_count_next;

    // Register writes.
    always_ff @(posedge clk) begin
        if (we) begin
            unique0 case (addr)
              'h4,
              'h6: t1_latch[ 7:0] <= data;
              'h5,
              'h7: t1_latch[15:8] <= data;
              'h8: t2l_latch      <= data;
              // 'h9 T2C-H is handled under Load / count below.
            endcase
        end
    end

    // Timer load / count.
    always_ff @(posedge clk) begin
        // Timer 1.

        // Load / count.
        if (~phi2) begin
            t1_count <= t1_load ? t1_latch : t1_count_prev - 1'b1;
            t1_ufl   <= ~|t1_count_prev & ~w_t1c_h;
        end

        if (phi2) begin
            t1_count_prev <= t1_count;
            t1_ufl_prev   <= t1_ufl;
        end

        // Timer 2.

        // PB6 edge detector signals.
        if (~phi2) begin
            t2_pb6_reg  <= t2_pb6;
            t2_pb6_prev <= t2_pb6_last;
        end

        if (phi2) begin
            t2_pb6_last <= t2_pb6_reg;
        end

        // Load / count.
        if (~phi2) begin
            t2_count[ 7:0] <= t2l_load ? t2l_latch : t2_count_next[ 7:0];
            t2_count[15:8] <= w_t2c_h  ? data      : t2_count_next[15:8];
            t2h_ufl        <= ~|t2_count_prev      & t2_cin & ~w_t2c_h;
            t2l_ufl        <= ~|t2_count_prev[7:0] & t2_cin & ~t2l_load;
        end

        if (phi2) begin
            t2_cin        <= ~acr.t2_pb6_in | (t2_pb6_prev & ~t2_pb6_last);  // PHI2 rate or PB6 negative edge
            t2_count_prev <= t2_count;
            t2l_ufl_prev  <= t2l_ufl;
        end
    end

    always_comb begin
        // Timer 1.
        w_t1c_h  = we && addr == 'h5;
        // Load: Timer 1 underflow or write to T1C-H.
        t1_load  = t1_ufl_prev | w_t1c_h;

        // Timer 2.
        w_t2c_h  = we && addr == 'h9;
        // Load: Timer 2 underflow and shift rate controlled by Timer 2, or write to T2C-H.
        t2l_load = (t2l_ufl_prev && (acr.shift_mode == 'b100 || acr.shift_mode[1:0] == 'b01)) | w_t2c_h;

        t2_count_next = t2_count_prev - t2_cin;
    end

    // Timer outputs.
    always_ff @(posedge clk) begin
        // Timer 1.

        if (w_t1c_h) begin
            t1_run <= '1;
        end else if (res | (s_t1_prev & ~acr.t1_free_run)) begin
            t1_run <= '0;
        end

        if (phi2) begin
            s_t1 <= t1_run & t1_ufl;
        end

        if (~phi2) begin
            s_t1_prev   <= s_t1;
            t1_pb7_prev <= t1_pb7;
        end

        // Timer 1 output.
        if (w_t1c_h) begin
            t1_pb7 <= '0;
        end else if (~acr.t1_pb7_out) begin
            t1_pb7 <= '1;
        end else begin
            t1_pb7 <= (phi2 & t1_run & t1_ufl) | ~t1_pb7_prev;
        end

        // Timer 2.

        if (w_t2c_h) begin
            t2_run <= '1;
        end else if (res | s_t2_prev) begin
            t2_run <= '0;
        end

        if (phi2) begin
            s_t2 <= t2_run & t2h_ufl;
        end

        if (~phi2) begin
            s_t2_prev <= s_t2;
        end
    end

    // Timer flag outputs.
    always_comb begin
        // Timer 1.
        tflag_o.s_t1 = s_t1;
        tflag_o.r_t1 = (rd && addr == 'h4) || w_t1c_h;  // Read from T1C-L or write to T1C-H

        // Timer 2.
        tflag_o.s_t2 = s_t2;
        tflag_o.r_t2 = (rd && addr == 'h8) || w_t2c_h;  // Read from T2C-L or write to T2C-H
    end

    // Register outputs.
    always_comb begin
        { regs.t1.hi,       regs.t1.lo }       = t1_count;
        { regs.t1_latch.hi, regs.t1_latch.lo } = t1_latch;
        { regs.t2.hi,       regs.t2.lo }       = t2_count;
    end
endmodule

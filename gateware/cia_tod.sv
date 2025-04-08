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

module cia_tod (
    input  logic       clk,
    input  logic       phi2_up,
    input  logic       phi2_dn,
    input  logic       res,
    input  logic       rd,
    input  logic       we,
    input  cia::reg4_t addr,
    input  cia::reg8_t data,
    input  logic       tod,
    input  logic       todin,
    input  logic       w_alarm,
    output cia::tod_t  regs,
    output logic       tod_int
);

    (* nowrshmsk *)
    cia::tod_t  alarm;      // Alarm setting
    cia::tod_t  clock;      // Clock
    cia::tod_t  cnext;      // Next clock update
    cia::tod_t  clatch;     // Latched clock
    logic       rlatch;     // Read latch
    logic       alarm_eq;   // TOD alarm
    logic       alarm_eq_prev = 1;  // Initialize to 1 in case of short reset
    logic [1:0] jc2;        // Two-bit Johnson counter dividing PHI2 by 4
    logic       phi20;      // PHI2/4
    logic       phi20_up;
    logic       phi20_dn;
    logic       tod_det;    // TOD pad positive edge detector
    logic       tod_det_prev;
    logic [2:0] jc3;        // Three-bit Johnson counter bit, dividing TOD input by 5 or 6,
    logic [2:0] jc3_next;   // generating a 100ms period clock from 50Hz or 60Hz
    logic       jc3_o;      // Internal counter output
    logic       jc3_o_next;
    logic       ts;         // Counter output - tenths of seconds
    logic       ts_next;
    logic       ts_prev;
    logic       ts_cin;
    logic       tod_start;  // Run clock

    // Address decode.
    cia::reg2_t addr_tod;
    logic       we_tod;
    logic       we_clk;
    logic       we_10ths;
    logic       we_sec;
    logic       we_min;
    logic       we_hr;
    logic       rd_10ths;
    logic       rd_hr;

    // BCD count carries.
    logic ts_c;  // 10ths of second
    logic sl_c;  // seconds
    logic sh_c;
    logic ml_c;  // minutes
    logic mh_c;
    logic hl_c;  // hours
    /* verilator lint_off UNUSEDSIGNAL */
    logic hh_c;
    /* verilator lint_on UNUSEDSIGNAL */

    // Logic for hour 12 -> 01.
    cia::reg4_t cnext_tod_hr_hl;
    logic       cnext_tod_hr_hh;
    logic       h12;
    logic       h12_next;

    initial begin
        clock.tod_hr.hl = 4'd1;  // CIA bug: Powerup to 01:00:00.0
    end

    always_comb begin
        addr_tod = addr[1:0];
        we_tod   = we && addr[3:2] == 2'b10;
        we_clk   = we_tod && ~w_alarm;
        we_10ths = we_clk && addr_tod == 'h0;
        we_sec   = we_clk && addr_tod == 'h1;
        we_min   = we_clk && addr_tod == 'h2;
        we_hr    = we_clk && addr_tod == 'h3;

        rd_10ths = rd && addr == 'h8 && ~w_alarm;
        rd_hr    = rd && addr == 'hB && ~w_alarm;

        // Johnson counter dividing TOD input by 5 or 6.
        jc3_next   = { jc3[1:0], ~jc3[2] };  // Shift
        jc3_o_next = (jc3[1] ^ todin) | jc3[0] | ~jc3[2];  // Shift -> count bit
        ts_next    = ~(jc3_o & tod_start);

        alarm_eq = clock == alarm;

        phi20_dn = phi20 & phi2_dn;

        // 10ths of second input.
        ts_cin   = ~ts_prev & ts & phi20_dn;
    end

    bcd_update #(9) ts_update (we_10ths, data[3:0], clock.tod_10ths.t, ts_cin, cnext.tod_10ths.t, ts_c);
    bcd_update #(9) sl_update (we_sec,   data[3:0], clock.tod_sec.sl,  ts_c,   cnext.tod_sec.sl,  sl_c);
    bcd_update #(5) sh_update (we_sec,   data[6:4], clock.tod_sec.sh,  sl_c,   cnext.tod_sec.sh,  sh_c);
    bcd_update #(9) ml_update (we_min,   data[3:0], clock.tod_min.ml,  sh_c,   cnext.tod_min.ml,  ml_c);
    bcd_update #(5) mh_update (we_min,   data[6:4], clock.tod_min.mh,  ml_c,   cnext.tod_min.mh,  mh_c);
    bcd_update #(9) hl_update (we_hr ,   data[3:0], clock.tod_hr.hl,   mh_c,   cnext_tod_hr_hl,   hl_c);
    bcd_update #(1) hh_update (we_hr,    data[4],   clock.tod_hr.hh,   hl_c,   cnext_tod_hr_hh,   hh_c);

    always_comb begin
        // 12:59:59.9 -> 01:00:00.0
        { cnext.tod_hr.hh, cnext.tod_hr.hl } =
            h12 && ~we_hr && mh_c ?
                { 1'd0, 4'd1 } :
                { cnext_tod_hr_hh, cnext_tod_hr_hl };
        // Flip PM bit when clock reaches 12:00:00.0.
        // CIA bug: Writing "PM 1 2" inverts the written PM bit.
        h12_next = cnext.tod_hr.hh == 'd1 && cnext.tod_hr.hl == 'd2;
        cnext.tod_hr.pm =
            we_hr ?
                data[7] ^ h12_next :
                clock.tod_hr.pm ^ (~h12 && h12_next);

        regs = rlatch ? clatch : clock;
    end

    cia_negedge tod_posedge (
        .clk     (clk),
        .res     (res),
        .phi2_dn (phi20_dn),
        .signal  (~tod),  // Inverted signal for posedge
        .trigger (tod_det)
    );

    always_ff @(posedge clk) begin
        if (res) begin
            alarm <= '0;
            clock <= '0;
            clock.tod_hr.hl <= 4'd1;  // CIA bug: Reset to 01:00:00.0
            h12   <= 0;
        end else if (phi2_dn) begin
            if (we_tod & w_alarm) begin
                alarm[{ ~addr_tod, 3'b000 } +: 8] <= data;
            end

            // Update clock.
            clock <= cnext;
            h12   <= h12_next;
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            // Stop clock on write to hours register, start on write to
            // 10ths of seconds register.
            if (we_hr | res) begin
                tod_start <= 0;
            end else if (we_10ths) begin
                tod_start <= 1;
            end

            // Latch clock on read of hours register, read "on the fly"
            // after read of 10ths of seconds register.
            if (rd_10ths | res) begin
                rlatch  <= 0;
            end else if (rd_hr) begin
                clatch  <= clock;
                rlatch  <= 1;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (~tod_det_prev) begin
            if (~tod_det) begin
                if (ts_next) begin
                    // Reset counter bits.
                    jc3   <= '0;
                    jc3_o <= 0;
                end
            end else begin // tod_det
                if (phi20_up) begin
                    // Clock Johnson counter.
                    jc3   <= jc3_next;
                    jc3_o <= jc3_o_next;
                end
            end

            // 10ths of second output.
            ts <= ts_next;
        end

        if (phi20_up) begin
            tod_det_prev <= tod_det;
            ts_prev <= ts;
        end

        if (phi20_dn) begin
            alarm_eq_prev <= alarm_eq;
            tod_int       <= ~alarm_eq_prev && alarm_eq;
        end

        // Note that phi20 is delayed by one FPGA cycle with respect to phi2.
        if (phi2_up) begin
            jc2      <= { jc2[0], ~jc2[1] };
            phi20    <= ~|jc2;
            phi20_up <= ~|jc2;
        end else if (phi2_dn) begin
            // Just to make simulation closer to reality.
            phi20    <= 0;
            phi20_up <= 0;
        end else begin
            phi20_up <= 0;
        end
    end
endmodule

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
    input  logic       phi2,
    input  logic       phi2_up,
    input  logic       phi2_dn,
    input  logic       res,
    input  logic       rd,
    input  logic       we,
    input  cia::reg4_t addr,
    input  cia::reg8_t data,
    input  logic       tod,
    input  logic       tod50hz,
    input  logic       w_alarm,
    output cia::tod_t  regs,
    output logic       tod_int
);

    (* nowrshmsk *)
    cia::tod_t  alarm;      // Alarm setting
    cia::tod_t  clock;      // Clock
    cia::tod_t  cnext;      // Next clock update
    cia::tod_t  clatch;     // Latched clock
    logic       alarm_eq;   // TOD alarm
    logic       alarm_eq_next;
    logic       alarm_eq_prev;
    logic [1:0] jc2;        // Two-bit Johnson counter dividing PHI2 by 4
    logic       phi20;      // PHI2/4
    logic       phi20_prev;
    logic       phi20_up;
    logic       phi20_dn;
    logic       tod_up;     // TOD pad positive edge detector
    logic       tod_shift;
    logic       tod_shift_prev;
    logic [2:0] tod_div;    // Three-bit Johnson counter, dividing TOD input by 5 or 6,
    logic [2:0] tod_div_out;// generating a 100ms period clock from 50Hz or 60Hz
    logic       tod_done;   // Counter output - tenths of seconds
    logic       tod_tick;
    logic       tod_tick_state;
    logic       tod_tick_prev;
    logic       tod_tick_up;
    logic       ts_cin;
    logic       tod_start;  // Run clock
    logic       tod_start_state;
    logic       tod_sample; // Read from running clock as opposed to from latch.
    logic       tod_sample_state;

    // Address decode.
    cia::reg2_t addr_tod;
    logic       we_tod;
    logic       we_clk;
    logic       we_10ths;
    logic       we_10ths_prev;
    logic       we_sec;
    logic       we_min;
    logic       we_hr;
    logic       rd_10ths;
    logic       rd_10ths_prev;
    logic       rd_hr;

    // BCD count carries.
    logic ts_c;  // 10ths of second
    logic sl_c;  // seconds
    logic sh_c;
    logic ml_c;  // minutes
    logic mh_c;
    logic hl_c;  // hours
    logic hl_9_c;
    logic hl_2_c;
    /* verilator lint_off UNUSEDSIGNAL */
    logic hh_c;
    /* verilator lint_on UNUSEDSIGNAL */

    // Logic for hour 12 -> 01.
    cia::reg4_t cnext_tod_hr_hl_9;
    cia::reg4_t cnext_tod_hr_hl_2;
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

        tod_int  = ~alarm_eq_prev && alarm_eq;

        // RS latch starting/stopping clock. Stop on write to hours register,
        // start on write to 10ths of seconds register.
        if      (we_hr | res)   tod_start = 0;
        else if (we_10ths_prev) tod_start = 1;
        else                    tod_start = tod_start_state;

        // RS latch controlling readout. Read from latch after read of hours
        // register, Read "on the fly" after read of 10ths of seconds register.
        if      (rd_hr)               tod_sample = 0;
        else if (rd_10ths_prev | res) tod_sample = 1;
        else                          tod_sample = tod_sample_state;

        // SR latch controlling counter shift.
        if (phi20_prev) tod_shift = tod_up;
        else            tod_shift = tod_shift_prev;

`ifdef TOD_PHI20_NODELAY
        // In order to match emulators which do not use PHI2/4 for clocking.
        phi20    = phi2;
        phi20_up = phi2_up;
        phi20_dn = phi2_dn;
`else
        phi20    = ~|jc2 & phi2;
        phi20_up = phi20 & phi2_up;
        phi20_dn = phi20_prev & phi2_dn;
`endif

        // 10ths of second input.
        ts_cin   = tod_tick_up & phi20_prev;
    end

    bcd_update #(9)    ts_update   (we_10ths, data[3:0], clock.tod_10ths.t, ts_cin, cnext.tod_10ths.t, ts_c  );
    bcd_update #(9)    sl_update   (we_sec,   data[3:0], clock.tod_sec.sl,  ts_c,   cnext.tod_sec.sl,  sl_c  );
    bcd_update #(5)    sh_update   (we_sec,   data[6:4], clock.tod_sec.sh,  sl_c,   cnext.tod_sec.sh,  sh_c  );
    bcd_update #(9)    ml_update   (we_min,   data[3:0], clock.tod_min.ml,  sh_c,   cnext.tod_min.ml,  ml_c  );
    bcd_update #(5)    mh_update   (we_min,   data[6:4], clock.tod_min.mh,  ml_c,   cnext.tod_min.mh,  mh_c  );
    bcd_update #(9)    hl_update_9 (we_hr ,   data[3:0], clock.tod_hr.hl,   mh_c,   cnext_tod_hr_hl_9, hl_9_c);
    bcd_update #(2, 4) hl_update_2 (we_hr ,   data[3:0], clock.tod_hr.hl,   mh_c,   cnext_tod_hr_hl_2, hl_2_c);
    always_comb begin
        // 09:59:59.9 -> 10:00:00.0
        // 12:59:59.9 -> 01:00:00.0
        // 19:59:59:9 -> 1A:00:00:0
        { cnext.tod_hr.hl, hl_c } = clock.tod_hr.hh ?
                                    { cnext_tod_hr_hl_2 | { 3'b0, hl_2_c }, hl_2_c } :
                                    { cnext_tod_hr_hl_9,                    hl_9_c };
    end
    bcd_update #(1)    hh_update   (we_hr,    data[4],   clock.tod_hr.hh,   hl_c,   cnext_tod_hr_hh,   hh_c  );

    always_comb begin
        cnext.tod_hr.hh = cnext_tod_hr_hh;

        // Flip PM bit when clock reaches 12:00:00.0.
        // CIA bug: Writing "PM 1 2" inverts the written PM bit.
        h12_next = cnext.tod_hr.hh == 'd1 && cnext.tod_hr.hl == 'd2;
        cnext.tod_hr.pm = we_hr ?
                          data[7] ^ h12_next :
                          clock.tod_hr.pm ^ (~h12 && h12_next);

        regs = tod_sample ? clock : clatch;
    end

    cia_edgedet tod_posedge (
        .clk       (clk),
        .res       (res),
        .phi2_dn   (phi20_dn),
        .pad_i     (tod),
        .posedge_o (tod_up)
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
        // Update SR latch states.
        if (phi2_dn) begin
            we_10ths_prev    <= we_10ths;
            rd_10ths_prev    <= rd_10ths;
            tod_start_state  <= tod_start;
            tod_sample_state <= tod_sample;
        end

        if (phi2_up && tod_sample) begin
            clatch <= clock;
        end

`ifndef TOD_INT_NODELAY
        if (phi20_up) begin
            alarm_eq_next <= clock == alarm;
        end

        if (phi20_dn) begin
            alarm_eq <= alarm_eq_next;
        end
`endif

        if (phi2_dn) begin
            alarm_eq_prev <= alarm_eq;
        end
    end

    always_comb begin
`ifdef TOD_INT_NODELAY
        // In order to match emulators which do not correctly delay the alarm.
        alarm_eq = clock == alarm;
`endif

        if (~tod_shift) tod_tick = ~tod_start | tod_done;
        else            tod_tick = tod_tick_state;
    end

    always_ff @(posedge clk) begin
        phi20_prev <= phi20;

        // Two-bit Johnson counter dividing PHI2 by 4.
        if (phi2_dn) begin
            jc2 <= { jc2[0], ~jc2[1] };
        end

        if (phi20_dn) begin
            tod_shift_prev <= tod_shift;
        end

        // Johnson counter dividing TOD input by 5 or 6 (for 50 or 60 Hz).
        // Note that shifting goes on during both PHI1 and PHI2.
        if (tod_shift) begin
            // Shift in.
            tod_div  <= tod_tick ? 3'b1 : { tod_div_out[1:0], ~tod_div_out[2] };
            tod_done <= tod_tick ? 1'b0 : ~|{ tod_div_out[1] ^ tod50hz, tod_div_out[0], ~tod_div_out[2] };
        end else if (tod_shift_prev) begin
            // Shift out.
            tod_div_out <= tod_div;
        end else begin
            // Refresh.
            tod_done <= tod_tick;
            if (tod_tick) begin
                tod_div     <= '0;
                tod_div_out <= '0;
            end
        end

        if (phi2_dn) begin
            tod_tick_state <= tod_tick;
        end

        if (phi20_up) begin
            tod_tick_prev <= tod_tick;
            tod_tick_up   <= ~tod_tick_prev & tod_tick;
        end
    end
endmodule

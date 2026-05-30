// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
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

// MOS 8520 TOD
module cia_cnt (
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
    input  logic       w_alarm,
    output cia::cnt_t  regs,
    output logic       cnt_int
);

    cia::reg24_t alarm;      // Alarm setting
    cia::reg24_t counter;    // Counter
    cia::reg24_t cnext;      // Next counter update
    cia::reg24_t clatch;     // Latched counter
    logic        alarm_eq;   // TOD alarm
    logic        alarm_eq_next;
    logic        alarm_eq_prev;
    logic [1:0]  jc2;        // Two-bit Johnson counter dividing PHI2 by 4
    logic        phi20;      // PHI2/4
    logic        phi20_prev;
    logic        phi20_up;
    logic        phi20_dn;
    logic        tod_up;     // TOD pad positive edge detector
    logic        tod_start;  // Run counter
    logic        tod_start_state;
    logic        tod_sample; // Read from running counter as opposed to from latch.
    logic        tod_sample_state;

    // Address decode.
    cia::reg2_t addr_tod;
    logic       we_tod;
    logic       we_cnt;
    logic       we_lsb;
    logic       we_lsb_prev;
    logic       we_mid;
    logic       we_msb;
    logic       rd_lsb;
    logic       rd_lsb_prev;
    logic       rd_msb;

    // Counter carries.
    logic cnt_c;
    logic lsb_c;
    logic mid_c;

    always_comb begin
        addr_tod = addr[1:0];
        we_tod   = we && addr[3:2] == 2'b10;
        we_cnt   = we_tod && ~w_alarm;
        we_lsb   = we_cnt && addr_tod == 'h0;
        we_mid   = we_cnt && addr_tod == 'h1;
        we_msb   = we_cnt && addr_tod == 'h2;

        rd_lsb   = rd && addr == 'h8 && ~w_alarm;
        rd_msb   = rd && addr == 'hA && ~w_alarm;

        cnt_int  = ~alarm_eq_prev && alarm_eq;

        // RS latch starting/stopping counter. Start on write to LSB register,
        // stop on write to MSB register.
        if      (we_lsb_prev)  tod_start = 1;
        else if (we_msb | res) tod_start = 0;
        else                   tod_start = tod_start_state;

        // RS latch controlling readout. Read from latch after read of MSB
        // register, Read "on the fly" after read of LSB register.
        if      (rd_msb)            tod_sample = 0;
        else if (rd_lsb_prev | res) tod_sample = 1;
        else                        tod_sample = tod_sample_state;

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

        // Counter carry input.
        cnt_c   = tod_start & tod_up;
    end

    always_comb begin
        { lsb_c, cnext [7: 0] } = we_lsb ? 9'(data) : 9'(counter [7: 0]) + cnt_c;
        { mid_c, cnext[15: 8] } = we_mid ? 9'(data) : 9'(counter[15: 8]) + lsb_c;
                 cnext[23:16]   = we_msb ?    data  :    counter[23:16]  + mid_c;

        { regs.cnt.msb, regs.cnt.mid, regs.cnt.lsb } = tod_sample ? counter : clatch;
        regs.nc = '0;
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
            alarm   <= '0;
            counter <= '0;
        end else if (phi2_dn) begin
            if (we_tod & w_alarm) begin
                unique0 case (addr_tod)
                  'h0: alarm[ 7: 0] <= data;
                  'h1: alarm[15: 8] <= data;
                  'h2: alarm[23:16] <= data;
                endcase
            end

            // Update counter.
            counter <= cnext;
        end
    end

    always_ff @(posedge clk) begin
        // Update SR latch states.
        if (phi2_dn) begin
            we_lsb_prev      <= we_lsb;
            rd_lsb_prev      <= rd_lsb;
            tod_start_state  <= tod_start;
            tod_sample_state <= tod_sample;
        end

        if (phi2_up && tod_sample) begin
            clatch <= counter;
        end

`ifndef TOD_INT_NODELAY
        if (phi20_up) begin
            alarm_eq_next <= counter == alarm;
        end

        if (phi20_dn) begin
            alarm_eq <= alarm_eq_next;
        end
`endif

        if (phi2_dn) begin
            alarm_eq_prev <= alarm_eq;
        end
    end

`ifdef TOD_INT_NODELAY
    always_comb begin
        // In order to match emulators which do not correctly delay the alarm.
        alarm_eq = counter == alarm;
    end
`endif

    always_ff @(posedge clk) begin
        phi20_prev <= phi20;

        // Two-bit Johnson counter dividing PHI2 by 4.
        if (phi2_dn) begin
            jc2 <= { jc2[0], ~jc2[1] };
        end
    end
endmodule

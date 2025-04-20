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

module cia_serial (
    input  logic       clk,
    input  logic       phi2_up,
    input  logic       phi2_dn,
    input  logic       res,
    input  logic       we,
    input  cia::reg4_t addr,
    input  cia::reg8_t data,
    input  logic       sp_tx,
    input  logic       ta_int,
    input  logic       cnt_up,
    input  logic       sp_in,
    output cia::reg8_t regs,
    output logic       cnt_out,
    output logic       sp_out,
    output logic       sp_int
);

    cia::reg8_t sdr;    // Serial Data Register
    cia::reg8_t sr;     // Shift register

    logic we_sdr;       // Register write
    logic txmode;       // CRA.SPMODE after phi2_dn
    logic sp_res;       // Serial Port reset
    logic sp_res_next;

    logic tx_init;      // Initiate transmission
    logic tx_active;    // Transmission is active
    logic sdr_to_sr;    // Load shift register from SDR on start of transmission
    logic sdr_to_sr_next;
    logic sr_to_sdr;    // Load SDR from shift register on end of reception
    logic tx_osc;       // Internal transmission oscillator
    logic tx_osc_prev;
    logic tx_osc_2;     // Divided by two (toggle)
    logic tx_osc_2_prev;
    logic tx_clk;       // Internal transmission clock
    logic tx_cnt;       // Transmission oscillator to CNT pad
    logic tx_sp;        // Data bit to SP pad
    logic tx_sp_next;
    logic rx_clk;       // Reception clock from CNT pad edge detector
    logic sr_clk;       // Shift register clock
    logic sr_clk_next;
    logic sr_clk_prev;

    cia::reg4_t sr_cnt; // 4 bit Johnson counter, counting 8 bit shifts
    cia::reg4_t sr_cnt_out;
    logic       sr_done;
    logic       sr_done_prev = 1;

    always_comb begin
        we_sdr = we && addr == 'hC;

        rx_clk = ~txmode & cnt_up;
        tx_clk = txmode & (~tx_osc_2_prev & tx_osc_2);
        sr_clk_next = rx_clk | tx_clk;

        // Reset on change of CRA.SPMODE.
        sp_res_next = res | (txmode ^ sp_tx);

        sdr_to_sr_next = tx_init & (~tx_active | sp_int);

        sr_cnt_out = sr_cnt & {4{~sp_res_next}};
        sr_done    = ~|sr_cnt_out;

        cnt_out = tx_cnt | ~txmode;
        sp_out  = tx_sp | ~txmode;
        regs    = sdr;
    end

    // Load SDR.
    always_ff @(posedge clk) begin
        if (res) begin
            sdr <= '0;
        end else if (phi2_dn) begin
            // Assume that the write signal wins, as it is delayed a bit.
            if (we_sdr) begin
                sdr <= data;
            end else if (sr_to_sdr) begin
                sdr <= ~sr;
            end
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            // TX init - SR latch.
            if      (we_sdr & sp_tx)               tx_init <= 1;
            else if (sp_res_next | sdr_to_sr_next) tx_init <= 0;

            tx_osc      <= ta_int & (tx_active | tx_osc_2);
            tx_osc_prev <= tx_osc;

            sp_res      <= sp_res_next;
            tx_cnt      <= ~tx_osc_2_prev;
            tx_sp       <= tx_sp_next;

            txmode      <= sp_tx;
            sr_clk      <= sr_clk_next;
            sdr_to_sr   <= sdr_to_sr_next;

            sp_int       <= ~sr_done_prev & sr_done;
            sr_done_prev <= sr_done;
        end
    end

    always_ff @(posedge clk) begin
        // Clock on the rising edge of PHI2, sampling sp_in at approximately
        // the same time as in a real CIA chip.
        if (phi2_up) begin
            // TX active - RS latch.
            if      (sp_res | (~tx_init & sp_int)) tx_active <= 0;
            else if (sdr_to_sr)                    tx_active <= 1;

            // Load shift register for transmission.
            // sdr_to_sr and sr_clk cannot be active simultaneously.
            unique0 case ({ sdr_to_sr, sr_clk })
              2'b01: sr <= { sr[6:0], ~(sp_in | txmode) };
              2'b10: sr <= sdr;
            endcase

            // Internal TX oscillator.
            if (sp_res) begin
                tx_osc_2 <= 0;
            end if (~tx_osc_prev & tx_osc) begin
                tx_osc_2 <= ~tx_osc_2;
            end
            tx_osc_2_prev <= tx_osc_2;

            sr_to_sdr <= ~txmode & sp_int;

            // Output bit.
            if (~txmode) begin
                tx_sp_next <= 0;
            end else if (sr_clk) begin
                tx_sp_next <= sr[7];
            end
        end

        if (phi2_up) begin
            // Clock Johnson counter, counting 8 bit shifts.
            if (sr_clk_prev & ~sr_clk) begin
                sr_cnt <= sp_res ? 4'b1 : { sr_cnt[2:0], ~sr_cnt[3] };
            end
            sr_clk_prev <= sr_clk;
        end else if (phi2_dn) begin
            // Note extra check for res to handle short resets in simulation.
            if ((~(sr_clk | sr_clk_next) && sp_res_next) || res) begin
                sr_cnt <= '0;
            end
        end
    end
endmodule

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
    input  logic       txmode,
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
    logic we_sdr_prev;  // Register write
    logic sp_res;       // Serial Port reset

    logic txmode_prev;
    logic tx_init;      // Initiate transmission
    logic tx_init_prev;
    logic tx_active;    // Transmission is active
    logic tx_active_prev;
    logic sdr_to_sr;    // Load shift register from SDR on start of transmission
    logic sr_to_sdr;    // Load SDR from shift register on end of reception
    logic tx_osc_in;    // Internal transmission oscillator input
    logic tx_osc_in_prev;
    logic tx_osc_out;   // Internal transmission oscillator output (toggle - i.e. divided by two)
    logic tx_osc_out_prev;
    logic tx_clk;       // Internal transmission clock
    logic tx_cnt;       // Transmission oscillator to CNT pad
    logic tx_sp;        // Data bit to SP pad
    logic tx_sp_next;
    logic rx_clk;       // Reception clock from CNT pad edge detector
    logic sr_clk;       // Shift register clock
    /* verilator lint_off UNUSEDSIGNAL */
    logic sr_clk_prev;
    /* verilator lint_on UNUSEDSIGNAL */

    cia::reg4_t sr_cnt; // 4 bit Johnson counter, counting 8 bit shifts
    cia::reg4_t sr_cnt_out;
    logic       sr_cnt_shift;
    logic       sr_done;
    logic       sr_done_prev;
    logic       phi2_dn_prev;

    always_comb begin
        we_sdr = we && addr == 'hC;

        rx_clk = ~txmode & cnt_up;
        tx_clk = txmode & (~tx_osc_out_prev & tx_osc_out);

        // Reset on change of CRA.SPMODE.
        sp_res = res | (txmode_prev ^ txmode);

        // Output of Johnson counter.
        sp_int = ~sr_done_prev & sr_done;

        // TX init - SR latch.
        if      (we_sdr_prev & txmode) tx_init = 1;
        else if (sp_res | sdr_to_sr)   tx_init = 0;
        else                           tx_init = tx_init_prev;

        // TX active - RS latch.
        if      (sp_res | (~tx_init & sp_int)) tx_active = 0;
        else if (sdr_to_sr)                    tx_active = 1;
        else                                   tx_active = tx_active_prev;

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
            tx_osc_in_prev <= tx_osc_in;
            tx_osc_in      <= ta_int & (tx_active | tx_osc_out);

            tx_cnt      <= ~tx_osc_out_prev;
            tx_sp       <= tx_sp_next;

            we_sdr_prev <= we_sdr;
            txmode_prev <= txmode;

            sr_clk_prev <= sr_clk;
            sr_clk      <= rx_clk | tx_clk;
            sdr_to_sr   <= tx_init & (~tx_active | sp_int);
        end
    end

    always_ff @(posedge clk) begin
        // Clock on the rising edge of PHI2, sampling sp_in at approximately
        // the same time as in a real CIA chip.
        if (phi2_up) begin
            // Keep states for latches.
            tx_init_prev   <= tx_init;
            tx_active_prev <= tx_active;

            // Clock in received bit or load shift register for transmission.
            // sdr_to_sr and sr_clk cannot be active simultaneously.
            unique0 case ({ sdr_to_sr, sr_clk })
              2'b01: sr <= { sr[6:0], ~(sp_in | txmode) };
              2'b10: sr <= sdr;
            endcase

            // Internal TX oscillator.
            tx_osc_out_prev <= tx_osc_out;
            if (sp_res) begin
                tx_osc_out <= 0;
            end if (~tx_osc_in_prev & tx_osc_in) begin
                tx_osc_out <= ~tx_osc_out;
            end

            sr_to_sdr <= ~txmode & sp_int;

            // Output bit.
            if (~txmode) begin
                tx_sp_next <= 0;
            end else if (sr_clk) begin
                tx_sp_next <= sr[7];
            end
        end

        if (phi2_up) begin
            sr_cnt_shift <= sr_clk;
        end

        // Clock Johnson counter, counting 8 bit shifts.
        if (sr_cnt_shift) begin
            // Shift in.
            sr_cnt <= sp_res ? 4'b1 : { sr_cnt_out[2:0], ~sr_cnt_out[3] };
        end else begin
            // sr_clk_prev, sr_clk, and sp_res are all latched by PHI1.
            // There is thus a race between counter refresh and reset,
            // so it would seem counter reset is not necessarily deterministic.
            // It is possible that gate delays should be taken into consideration.
            // On the other hand, VICE cia-sdr-icr tests seem to indicate that
            // sr_clk_prev is not taken into consideration at all(!)
            // FIXME: Determine what is actually going on in the original chip.
            // if (~(sr_clk_prev | sr_clk) & sp_res) begin
            if (~sr_clk & sp_res) begin
                // Reset (and refresh in original chip).
                sr_cnt     <= '0;
                sr_cnt_out <= '0;
            end else begin
                // Shift out.
                sr_cnt_out <= sr_cnt;
            end
        end

        phi2_dn_prev <= phi2_dn;

        if (phi2_dn_prev) begin
            // Delayed one FPGA cycle to pick up change of sp reset.
            sr_done_prev <= sr_done;
            sr_done      <= ~|sr_cnt_out | sp_res;
        end
    end
endmodule

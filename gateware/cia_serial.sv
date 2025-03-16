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
    input  logic       spmode,
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
    logic we_sdr_prev;
    logic spmode_prev;
    logic sp_res;       // Serial Port reset

    logic [1:0] phi1;   // Extra synchronization steps for SR latches
    logic tx_init_n;    // Initiate transmission
    logic tx_active;    // Transmission is active
    logic sdr_to_sr;    // Load shift register from SDR on start of transmission
    logic sr_to_sdr;    // Load SDR from shift register on end of reception
    logic tx_osc;       // Internal transmission oscillator
    logic tx_osc_prev;
    logic tx_clk;       // Internal transmission clock
    logic tx_cnt;       // Transmission oscillator to CNT pad
    logic tx_sp;        // Data bit to SP pad
    logic tx_sp_next;
    logic rx_clk;       // Reception clock from CNT pad edge detector
    logic sr_clk;       // Shift register clock

    cia::reg4_t sr_cnt; // 4 bit Johnson counter, counting 8 bit shifts
    cia::reg4_t sr_cnt_out;
    logic       sr_done;
    logic       sr_done_prev;

    always_comb begin
        we_sdr = we && addr == 'hC;

        rx_clk = ~spmode & cnt_up;
        tx_clk = spmode & tx_osc_prev & ~tx_osc;

        // Reset on change of spmode.
        sp_res = res | (spmode_prev ^ spmode);

        sr_cnt_out = sr_cnt & {4{~sp_res}};
        sr_done    = ~|sr_cnt_out;

        cnt_out = tx_cnt | ~spmode;
        sp_out  = tx_sp | ~spmode;
        regs    = sdr;
    end

    always_ff @(posedge clk) begin
        if (res) begin
            sdr <= '0;
        end else if (phi2_dn) begin
            // Write to SDR (serial data register).
            // we_sdr connects the data bus to the SDR during PHI2, while
            // sr_to_sdr connects the shift register to the SDR during PHI2.
            // This implies that the data bus and the SDR will be short
            // circuited if we_sdr and sr_to_sdr are active at the same cycle.
            unique0 case ({ sr_to_sdr, we_sdr })
              2'b11: sdr <= data & sr;
              2'b01: sdr <= data;
              2'b10: sdr <= sr;
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            // Internal TX oscillator.
            if (sp_res) begin
                tx_osc <= 0;
            end if (ta_int & (tx_active | ~tx_osc)) begin
                tx_osc <= ~tx_osc;
            end
            tx_osc_prev <= tx_osc;
            tx_cnt      <= tx_osc_prev;
            tx_sp       <= tx_sp_next;

            we_sdr_prev  <= we_sdr;
            spmode_prev  <= spmode;
            sr_clk       <= rx_clk | tx_clk;
            sr_done_prev <= sr_done;
            sp_int       <= ~sr_done_prev & sr_done;
            sr_to_sdr    <= ~spmode & sp_int;
            sdr_to_sr    <= ~tx_init_n & (~tx_active | sp_int);
        end
    end

    always_ff @(posedge clk) begin
        // Clock on the rising edge of PHI2, sampling sp_in at approximately
        // the same time as in a real CIA chip.
        if (phi2_up) begin
            // Load shift register for transmission.
            // sdr_to_sr and sr_clk cannot be active simultaneously.
            unique0 case ({ sdr_to_sr, sr_clk })
              2'b01: begin
                  // Clock shift register and bit counter.
                  sr     <= { sr[6:0], sp_in | spmode };
                  sr_cnt <= { sr_cnt_out[2:0], ~sr_cnt_out[3] };
              end
              2'b10: begin
                  sr     <= sdr;
              end
            endcase

            // Output bit.
            if (~spmode) begin
                tx_sp_next <= 1;
            end else if (sr_clk) begin
                tx_sp_next <= sr[7];
            end
        end
    end

    // Extra synchronization steps for SR latches.
    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            phi1 <= 1;
        end else if (phi1 == 1) begin
            phi1 <= 2;
        end else begin
            phi1 <= 0;
        end

        if (phi1 == 1) begin
            // TX init - SR latch.
            if (we_sdr_prev & spmode) begin
                tx_init_n <= 1;
            end else if (sp_res | sdr_to_sr) begin
                tx_init_n <= 0;
            end
        end

        if (phi1 == 2) begin
            // TX active - SR latch.
            if (sdr_to_sr) begin
                tx_active <= 1;
            end else if (sp_res | (~tx_init_n & sp_int)) begin
                tx_active <= 0;
            end
        end
    end
endmodule

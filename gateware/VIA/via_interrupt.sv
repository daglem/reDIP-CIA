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

module via_interrupt (
    input  logic        clk,
    input  logic        res,
    input  logic        we,
    input  via::reg4_t  addr,
    input  via::reg8_t  data,
    input  via::pflag_t pflag,
    input  via::sflag_t sflag,
    input  via::tflag_t tflag,
    output via::reg8_t  ifr,
    output via::reg8_t  ier,
    output logic        irq_n
);

    logic [6:0] r, s;

    always_comb begin
        // Reset signals for interrupt flags.
        r = {
            tflag.r_t1,
            tflag.r_t2,
            pflag.r_cb1,
            pflag.r_cb2,
            sflag.r_sr,
            pflag.r_ca1,
            pflag.r_ca2
        } | ({ 7'(we) } & data[6:0]);

        // Set signals for interrupt flags.
        s = {
            tflag.s_t1,
            tflag.s_t2,
            pflag.s_cb1,
            pflag.s_cb2,
            sflag.s_sr,
            pflag.s_ca1,
            pflag.s_ca2
        };

        // IRQ when any enabled interrupt flag is set.
        irq_n = ~|(ifr & ier);
    end

    // Update registers.
    always_ff @(posedge clk) begin
        if (res) begin
            // Asynchronous reset (with respect to PHI2).
            ier      <= 'b10000000;
        end else if (we && addr == 'he) begin
            // Set or clear interrupt enable bits.
            ier[6:0] <= data[7] ? ier[6:0] | data[6:0] : ier[6:0] & ~data[6:0];
        end

        // Reset or set interrupt flags.
        for (int i = 0; i < $bits(r); i++) begin
            if (r[i]) begin
                ifr[i] <= '0;
            end else if (s[i]) begin
                ifr[i] <= '1;
            end
        end
    end
endmodule

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

module via_control (
    input  logic       clk,
    input  logic       res,
    input  logic       we,
    input  via::reg4_t addr,
    input  via::reg8_t data,
    output via::reg8_t acr,
    output via::reg8_t pcr
);

    // Register writes.
    always_ff @(posedge clk) begin
        if (res) begin
            // Asynchronous reset (with respect to PHI2).
            acr <= '0;
        end else if (we && addr == 'hb) begin
            acr <= data;
        end

        if (res) begin
            // Asynchronous reset (with respect to PHI2).
            pcr <= '0;
        end else if (we && addr == 'hc) begin
            pcr <= data;
        end
    end
endmodule

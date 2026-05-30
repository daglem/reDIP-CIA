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

module via_edgedet (
    input  logic clk,
    input  logic res,
    input  logic phi2,
    input  logic pad_i,
    input  logic det_pos,
    input  logic flag_i,
    output logic flag_o
);
    logic pad_start;

    // The simple DFF + combinational ciruit below captures the gist of the VIA
    // control input edge detector circuits. The only functional difference is
    // that reset cannot cause an invalid SR latch state during PHI2.
    //
    // The edge detector works as follows:
    //
    // 1. During PHI2, detects and stores any occurence of the required input
    //    start level, i.e. input = 0 for positive edge, and vice versa.
    // 2. Detects any occurence of the desired edge by comparing the current
    //    input level to the stored level. A detected edge will in turn set the
    //    corresponding bit in the IFR register.
    // 3. As long as the corresponding IFR bit is set, the current input level
    //    will keep getting stored during PHI2, i.e. the required input start
    //    level must occur again for the next desired edge to be detected.
    always_ff @(posedge clk) begin
        if (res) begin
            pad_start <= '0;
        end else if (phi2 & ((pad_i ^ det_pos) | flag_i)) begin
            pad_start <= pad_i;
        end
    end

    always_comb begin
        flag_o = det_pos ? ~pad_start & pad_i : pad_start & ~pad_i;
    end
endmodule

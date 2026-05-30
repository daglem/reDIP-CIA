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

// Synchronized positive edge detector.
module cia_edgedet (
    input  logic clk,
    input  logic res,
    input  logic phi2_dn,
    input  logic pad_i,
    output logic posedge_o
);

    logic pad_i_prev = 1;
    logic posedge_i;

    always_ff @(posedge clk) begin
        // Synchronize input edges in a similar fashion as in the real CIA.
        // The reset signal is included for the TOD synchronizer, which keeps
        // a detected edge until reset is released.
        if (posedge_o & ~res) begin
            // Any input edges are discarded until the next PHI1.
            posedge_i <= 0;
        end else if (~pad_i_prev & pad_i) begin
            posedge_i <= 1;
        end

        pad_i_prev <= pad_i;

        if (phi2_dn) begin
            // Synchronized output available from PHI1.
            posedge_o <= posedge_i;
        end
    end
endmodule

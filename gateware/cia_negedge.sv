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

// Negative edge detector.
module cia_negedge (
    input  logic clk,
    input  logic res,
    input  logic phi2_dn,
    input  logic signal,
    output logic trigger
);

    logic signal_prev;
    logic edgedet;

    always_ff @(posedge clk) begin
        // Synchronize with PHI2 in a similar fashion as the real CIA.
        // The res signal is included for the TOD synchronizer, which keeps
        // a detected edge until reset is released.
        if (signal_prev & ~signal) begin
            edgedet <= 1;
        end else if (phi2_dn & ~res) begin
            edgedet <= 0;
        end

        signal_prev <= signal;

        // Trigger signal ready for the next PHI2.
        if (phi2_dn) begin
            trigger <= edgedet;
        end
    end
endmodule

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

module bcd_add #(
    parameter MAX = 9,
    parameter WID = $clog2(MAX + 1)
)(
    input  logic [WID-1:0] din,
    input  logic           cin,
    output logic [WID-1:0] dout,
    output logic           cout
);

    always_comb begin
        { dout, cout } = (din == MAX && cin) ? { WID'(1'b0), 1'b1 } : { din + WID'(cin), 1'b0 };
    end
endmodule

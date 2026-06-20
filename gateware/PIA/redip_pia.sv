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

(* top *)
module redip_pia (
    // Clock input
    inout logic PHI2,
    // Reset input
    inout logic RES,
    // Chip select inputs
    inout logic CS0,
    inout logic CS1,
    inout logic CS2,
    // Read/write input
    inout logic R_W,
    // Address inputs
    inout logic RS0,
    inout logic RS1,

    // Data bus inputs/outputs
    inout logic D0,
    inout logic D1,
    inout logic D2,
    inout logic D3,
    inout logic D4,
    inout logic D5,
    inout logic D6,
    inout logic D7,

    // I/O ports
    inout logic PA0,
    inout logic PA1,
    inout logic PA2,
    inout logic PA3,
    inout logic PA4,
    inout logic PA5,
    inout logic PA6,
    inout logic PA7,

    inout logic PB0,
    inout logic PB1,
    inout logic PB2,
    inout logic PB3,
    inout logic PB4,
    inout logic PB5,
    inout logic PB6,
    inout logic PB7,

    // Control lines.
    inout logic CA1,
    inout logic CA2,
    inout logic CB1,
    inout logic CB2,
    // Interrupt request outputs
    inout logic IRQA,
    inout logic IRQB
);

    // PIA core bus I/O.
    pia::bus_i_t bus_i;
    pia::bus_o_t bus_o;

    // FPGA clock and reset.
    logic clk_24;
    logic rst_24;

    // iCE40 FPGA initialization.
    ice40_init ice40_init (
        .boot   (1'b0),
        .image  (2'b00),
        .clk_24 (clk_24),
        .rst_24 (rst_24)
    );

    // PIA I/O pads.
    pia_io pia_io (
        .clk          (clk_24),
        .pad_phi2     (PHI2),
        .pad_res_n    (RES),
        .pad_cs0      (CS0),
        .pad_cs1      (CS1),
        .pad_cs2_n    (CS2),
        .pad_r_w_n    (R_W),
        .pad_addr     ({ RS1, RS0 }),
        .pad_data     ({ D7, D6, D5, D4, D3, D2, D1, D0 }),
        .pad_pa       ({ PA7, PA6, PA5, PA4, PA3, PA2, PA1, PA0 }),
        .pad_pb       ({ PB7, PB6, PB5, PB4, PB3, PB2, PB1, PB0 }),
        .pad_ca1      (CA1),
        .pad_ca2      (CA2),
        .pad_cb1      (CB1),
        .pad_cb2      (CB2),
        .pad_irqa_n   (IRQA),
        .pad_irqb_n   (IRQB),
        .bus_i        (bus_i),
        .bus_o        (bus_o)
    );

    // PIA core.
    pia_core pia_core (
        .clk     (clk_24),
        .rst     (rst_24),
        .bus_i   (bus_i),
        .bus_o   (bus_o)
    );
endmodule

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

(* top *)
module redip_cia (
    // Clock input
    inout logic PHI2,
    // Reset input
    inout logic RES,
    // Chip select input
    inout logic CS,
    // Read/write input
    inout logic R_W,
    // Address inputs
    inout logic RS0,
    inout logic RS1,
    inout logic RS2,
    inout logic RS3,

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

    // PC output
    inout logic PC,
    // FLAG input
    inout logic FLAG,
    // Time Of Day clock input (50Hz or 60Hz)
    inout logic TOD,
    // Counter input/output
    inout logic CNT,
    // Serial port input/output
    inout logic SP,
    // Interrupt request output
    inout logic IRQ
);

    // CIA API parameters.
    cia::bus_i_t bus_i;
    cia::bus_o_t bus_o;

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

    // CIA I/O pads.
    cia_io cia_io (
        .clk        (clk_24),
        .pad_phi2   (PHI2),
        .pad_res_n  (RES),
        .pad_cs_n   (CS),
        .pad_r_w_n  (R_W),
        .pad_addr   ({ RS3, RS2, RS1, RS0 }),
        .pad_data   ({ D7, D6, D5, D4, D3, D2, D1, D0 }),
        .pad_pa     ({ PA7, PA6, PA5, PA4, PA3, PA2, PA1, PA0 }),
        .pad_pb     ({ PB7, PB6, PB5, PB4, PB3, PB2, PB1, PB0 }),
        .pad_pc_n   (PC),
        .pad_flag_n (FLAG),
        .pad_tod    (TOD),
        .pad_cnt    (CNT),
        .pad_sp     (SP),
        .pad_irq_n  (IRQ),
        .bus_i      (bus_i),
        .bus_o      (bus_o)
    );

    // CIA core API.
    /* verilator lint_off PINMISSING */
    cia_core cia_core (
`ifdef MOS6526
        .model   (cia::MOS6526),
`else
        .model   (cia::MOS8521),
`endif
        .clk     (clk_24),
        .rst     (rst_24),
        .bus_i   (bus_i),
        .bus_o   (bus_o)
    );
    /* verilator lint_on PINMISSING */
endmodule

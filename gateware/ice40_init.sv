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

module ice40_init (
    input  logic       boot,
    input  logic [1:0] image,
    output logic       clk_24,
    output logic       rst_24
);

    // Boot configuration image.
    SB_WARMBOOT warmboot (
        .BOOT (boot),
        .S1   (image[1]),
        .S0   (image[0])
    );

    // HFOSC: 48MHz -> 24MHz
    /* verilator lint_off PINMISSING */
    SB_HFOSC #(
        .CLKHF_DIV ("0b01")
    ) hfosc (
        .CLKHFPU(1'b1),
        .CLKHFEN(1'b1),
        .CLKHF(clk_24)
    );
    /* verilator lint_on PINMISSING */

    // Hold reset for a minimum of 10us (minimum 240 cycles at 24MHz),
    // to allow BRAM to power up.
    logic [7:0] bram_cnt = '0;

    // Reset for 24MHz clock.
    // Reset is asserted from the very beginning.
    always_comb begin
        rst_24 = !(bram_cnt == 8'hff);
    end

    always_ff @(posedge clk_24) begin
        if (rst_24) begin
            bram_cnt <= bram_cnt + 1;
        end
    end
endmodule

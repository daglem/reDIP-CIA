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

`ifdef __ICARUS__
`define NO_ICE40_DEFAULT_ASSIGNMENTS
`elsif VERILATOR
`define NO_ICE40_DEFAULT_ASSIGNMENTS
`endif

/* verilator lint_off PINMISSING */

module pia_io (
    // FPGA clock.
    input  logic        clk,
    // PIA I/O pads.
    inout  logic        pad_phi2,
    inout  logic        pad_res_n,
    inout  logic        pad_cs0,
    inout  logic        pad_cs1,
    inout  logic        pad_cs2_n,
    inout  logic        pad_r_w_n,
    inout  pia::reg2_t  pad_addr,
    inout  pia::reg8_t  pad_data,
    inout  pia::reg8_t  pad_pa,
    inout  pia::reg8_t  pad_pb,
    inout  logic        pad_ca1,
    inout  logic        pad_ca2,
    inout  logic        pad_cb1,
    inout  logic        pad_cb2,
    inout  logic        pad_irqa_n,
    inout  logic        pad_irqb_n,
    // PIA internal bus I/O.
    output pia::bus_i_t bus_i,
    input  pia::bus_o_t bus_o
);

    // Define pin functions for the SB_IO PIN_TYPE parameter by ORing together
    // one flag from each block below.
    //
    // For input only, specify only a PIN_IN flag.
    // For output only, specify PIN_IN_UNREG, a PIN_OUT flag, and a PIN_OE flag.
    // For input/output, specify a PIN_IN flag, a PIN_OUT flag, and a PIN_OE flag.
    `define PIN_IN_UNREG       6'b0000_01
    `define PIN_IN_REG         6'b0000_00
    `define PIN_IN_UNREG_LATCH 6'b0000_11
    `define PIN_IN_REG_LATCH   6'b0000_10
    `define PIN_IN_DDR         6'b0000_00

    `define PIN_OUT_UNREG      6'b0010_00
    `define PIN_OUT_REG        6'b0001_00
    `define PIN_OUT_REG_INV    6'b0011_00
    `define PIN_OUT_DDR        6'b0000_00

    `define PIN_OE_ENABLED     6'b0100_00
    `define PIN_OE_UNREG       6'b1000_00
    `define PIN_OE_REG         6'b1100_00

    // Control signals.
    logic       phi2_io;
    logic       phi1_io;  // Inverted phi2_io
    logic       phi2_x;
    logic       phi2;
    logic       ddrd;
    logic       res_n_x,  res_n;
    pia::reg8_t pa_x,     pa;
    pia::reg8_t pb_x,     pb;
    logic       ca1_x,    ca1;
    logic       ca2_x,    ca2;
    logic       cb1_x,    cb1;
    logic       cb2_x,    cb2;

    always_comb begin
        // phi1 is used to latch D0-D7 after the falling edge of phi2.
        phi1_io = ~phi2_io;

        // Appease Verilator by avoiding a mix of blocking and non-blocking
        // assignments to parts of the same variable.
        bus_i.phi2      = phi2;
        bus_i.res_n     = res_n;
        bus_i.ports.pa  = pa;
        bus_i.ports.pb  = pb;
        bus_i.ports.ca1 = ca1;
        bus_i.ports.ca2 = ca2;
        bus_i.ports.cb1 = cb1;
        bus_i.ports.cb2 = cb2;
    end

    always_ff @(posedge clk) begin
        // Bring phi2 into FPGA clock domain.
        phi2_x <= phi2_io;
        phi2   <= phi2_x;

        // The data output must be held by the output enable for at least 10ns
        // after the falling edge of phi2 (ref. MOS6500 and MOS6510 datasheets).
        // This is ensured since the SB_IO OE register is delayed by one FPGA clock.
        // We delay the start of the pin OE by ANDing with phi2, in order to avoid
        // glitches for output signals at the rising edge of phi2.
        // We cannot fully avoid the possibility of metastability and thus
        // glitches for the pin OE, however this will not cause any interfacing
        // issues since it will settle as soon as CS1, /CS2, R_W, and PHI2 are stable.
        ddrd   <= bus_i.cs0 & bus_i.cs1 & ~bus_i.cs2_n & bus_i.r_w_n & phi2_io & phi2;

        // The remaining signals are already registered on the I/O input,
        // so we only add one extra register stage wrt. metastability.
        res_n  <= res_n_x;
        pa     <= pa_x;
        pb     <= pb_x;
        ca1    <= ca1_x;
        ca2    <= ca2_x;
        cb1    <= cb1_x;
        cb2    <= cb2_x;
    end

    // phi2_io is configured as a simple input pin (not registered, i.e. without
    // any delay), so that the signal can be used to latch other signals,
    // which are stable until at least 10ns after the falling edge of phi2
    // (ref. MOS6510 datasheet).
    SB_IO #(
        .PIN_TYPE    (`PIN_IN_UNREG)
    ) io_phi2 (
        .PACKAGE_PIN (pad_phi2),
        .D_IN_0      (phi2_io)
    );

    // Registered input for /RES. Note that /RES may be applied at any time and
    // can thus be metastable.
    SB_IO #(
        .PIN_TYPE     (`PIN_IN_REG)
    ) io_res (
        .PACKAGE_PIN  (pad_res_n),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (res_n_x)
    );

    // Chip select.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_cs0 (
        .PACKAGE_PIN       (pad_cs0),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.cs0)
    );

    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_cs1 (
        .PACKAGE_PIN       (pad_cs1),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.cs1)
    );

    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_cs2_n (
        .PACKAGE_PIN       (pad_cs2_n),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.cs2_n)
    );

    // R/W.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_r_w_n (
        .PACKAGE_PIN       (pad_r_w_n),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.r_w_n)
    );

    // Address pin inputs.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_addr[1:0] (
        .PACKAGE_PIN       (pad_addr),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.addr)
    );

    // Bidirectional data pins.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_data[7:0] (
        .PACKAGE_PIN       (pad_data),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .OUTPUT_CLK        (clk),
        .OUTPUT_ENABLE     (ddrd),
        .D_IN_0            (bus_i.data),
        .D_OUT_0           (bus_o.data)
    );

    // Bidirectional I/O port pins.

    // PA0-PA7 are open drain.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_pa[7:0] (
        .PACKAGE_PIN   (pad_pa),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (bus_o.ports.ddra & ~bus_o.ports.pa),
        .D_IN_0        (pa_x),
        .D_OUT_0       (8'b0)
    );

    // PB0-PB7 are push-pull.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_pb[7:0] (
        .PACKAGE_PIN   (pad_pb),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (bus_o.ports.ddrb),
        .D_IN_0        (pb_x),
        .D_OUT_0       (bus_o.ports.pb)
    );

    // CA1 is input only.
    SB_IO #(
        .PIN_TYPE     (`PIN_IN_REG)
    ) io_ca1 (
        .PACKAGE_PIN  (pad_ca1),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (ca1_x)
    );

    // CA2 is open drain.
    // NB! Pullup to VCC, which would have to be external.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_ca2 (
        .PACKAGE_PIN   (pad_ca2),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.ports.ca2),
        .D_IN_0        (ca2_x),
        .D_OUT_0       (1'b0)
    );

    // CB1 is input only.
    SB_IO #(
        .PIN_TYPE     (`PIN_IN_REG)
    ) io_cb1 (
        .PACKAGE_PIN  (pad_cb1),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (cb1_x)
    );

    // CB2 is push-pull.
    // NB! Pullup to VCC, which would have to be external.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_cb2 (
        .PACKAGE_PIN   (pad_cb2),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (bus_o.ports.ddrcb2),
        .D_IN_0        (cb2_x),
        .D_OUT_0       (bus_o.ports.cb2)
    );

    // /IRQA and /IRQB are open drain, output only.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_UNREG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_irqa_n (
        .PACKAGE_PIN   (pad_irqa_n),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.irqa_n),
        .D_OUT_0       (1'b0)
    );

    SB_IO #(
        .PIN_TYPE      (`PIN_IN_UNREG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_irqb_n (
        .PACKAGE_PIN   (pad_irqb_n),
`ifdef NO_ICE40_DEFAULT_ASSIGNMENTS
        .CLOCK_ENABLE  (1'b1),
`endif
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.irqb_n),
        .D_OUT_0       (1'b0)
    );
endmodule

/* verilator lint_on PINMISSING */

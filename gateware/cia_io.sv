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

/* verilator lint_off PINMISSING */

module cia_io (
    // FPGA clock and reset.
    input  logic        clk,
    // I/O pads.
    inout  logic        pad_phi2,
    inout  logic        pad_res_n,
    inout  logic        pad_cs_n,
    inout  logic        pad_r_w_n,
    inout  cia::reg4_t  pad_addr,
    inout  cia::reg8_t  pad_data,
    inout  cia::reg8_t  pad_pa,
    inout  cia::reg8_t  pad_pb,
    inout  logic        pad_pc_n,
    inout  logic        pad_flag_n,
    inout  logic        pad_tod,
    inout  logic        pad_cnt,
    inout  logic        pad_sp,
    inout  logic        pad_irq_n,
    // Internal interfaces.
    output cia::bus_i_t bus_i,
    input  cia::bus_o_t bus_o
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
    cia::reg8_t pa_x,     pa;
    cia::reg8_t pb_x,     pb;
    logic       cnt_x,    cnt;
    logic       sp_x,     sp;
    logic       tod_x,    tod;
    logic       flag_n_x, flag_n;

    always_comb begin
        // phi1 is used to hold signals after the falling edge of phi2.
        phi1_io      = ~phi2_io;

        // Appease Verilator by avoiding a mix of blocking and non-blocking
        // assignments to parts of the same variable.
        bus_i.phi2   = phi2;
        bus_i.res_n  = res_n;
        bus_i.pa     = pa;
        bus_i.pb     = pb;
        bus_i.cnt    = cnt;
        bus_i.sp     = sp;
        bus_i.tod    = tod;
        bus_i.flag_n = flag_n;
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
        // issues since it will settle as soon as /CS, R_W, and PHI2 are stable.
        ddrd   <= ~bus_i.cs_n & bus_i.r_w_n & phi2_io & phi2;

        // Address and data signals are latched by PHI2.

        // The remaining signals are already registered on the I/O input,
        // so we only add one extra register stage wrt. metastability.
        res_n  <= res_n_x;
        pa     <= pa_x;
        pb     <= pb_x;
        cnt    <= cnt_x;
        sp     <= sp_x;
        tod    <= tod_x;
        flag_n <= flag_n_x;
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
`ifdef VERILATOR
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (res_n_x)
    );

    // Hold other (registered) inputs at phi1, i.e. D-latch enable = phi2.
    // This allows us to read out the signals after the falling edge of phi2,
    // where the signals were stable.

    // Chip select.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_cs_n (
        .PACKAGE_PIN       (pad_cs_n),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.cs_n)
    );

    // R/W.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_r_w_n (
        .PACKAGE_PIN       (pad_r_w_n),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
        .CLOCK_ENABLE      (1'b1),
`endif
        .INPUT_CLK         (clk),
        .D_IN_0            (bus_i.r_w_n)
    );

    // Address pin inputs.
    SB_IO #(
        .PIN_TYPE          (`PIN_IN_REG_LATCH)
    ) io_addr[3:0] (
        .PACKAGE_PIN       (pad_addr),
        .LATCH_INPUT_VALUE (phi1_io),
`ifdef VERILATOR
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
`ifdef VERILATOR
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
    // NB! Push-pull on the MOS8520.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_pa[7:0] (
        .PACKAGE_PIN   (pad_pa),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (bus_o.ports.ddra & ~bus_o.ports.pra),
        .D_IN_0        (pa_x),
        .D_OUT_0       (1'b0)
    );

    // PB0-PB7 are push-pull.
    // NB! Open drain on the MOS8520.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_pb[7:0] (
        .PACKAGE_PIN   (pad_pb),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (bus_o.ports.ddrb),
        .D_IN_0        (pb_x),
        .D_OUT_0       (bus_o.ports.prb)
    );

    // /PC, /FLAG, CNT, SP, TOD, /IRQ.
    // Note that inputs may be applied at any time and can thus be metastable.

    // /PC is push-pull, output only.
    // NB! Open drain on the MOS8520.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_UNREG | `PIN_OUT_REG | `PIN_OE_ENABLED)
    ) io_pc_n (
        .PACKAGE_PIN   (pad_pc_n),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .OUTPUT_CLK    (clk),
        .D_OUT_0       (bus_o.pc_n)
    );

    // /FLAG is input only.
    SB_IO #(
        .PIN_TYPE     (`PIN_IN_REG)
    ) io_flag_n (
        .PACKAGE_PIN  (pad_flag_n),
`ifdef VERILATOR
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (flag_n_x)
    );

    // TOD is input only.
    SB_IO #(
        .PIN_TYPE     (`PIN_IN_REG)
    ) io_tod (
        .PACKAGE_PIN  (pad_tod),
`ifdef VERILATOR
        .CLOCK_ENABLE (1'b1),
`endif
        .INPUT_CLK    (clk),
        .D_IN_0       (tod_x)
    );

    // CNT is open drain.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_cnt (
        .PACKAGE_PIN   (pad_cnt),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.cnt),
        .D_IN_0        (cnt_x),
        .D_OUT_0       (1'b0)
    );

    // SP is open drain.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_REG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_sp (
        .PACKAGE_PIN   (pad_sp),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .INPUT_CLK     (clk),
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.sp),
        .D_IN_0        (sp_x),
        .D_OUT_0       (1'b0)
    );

    // /IRQ is open drain, output only.
    SB_IO #(
        .PIN_TYPE      (`PIN_IN_UNREG | `PIN_OUT_REG | `PIN_OE_REG)
    ) io_irq_n (
        .PACKAGE_PIN   (pad_irq_n),
`ifdef VERILATOR
        .CLOCK_ENABLE  (1'b1),
`endif
        .OUTPUT_CLK    (clk),
        .OUTPUT_ENABLE (~bus_o.irq_n),
        .D_OUT_0       (1'b0)
    );
endmodule

/* verilator lint_on PINMISSING */

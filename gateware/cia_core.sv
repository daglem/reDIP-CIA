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

module cia_core (
    input  cia::model_t model,
    input  logic        clk,
    input  logic        rst,
    input  cia::bus_i_t bus_i,
    output cia::bus_o_t bus_o
`ifdef VERILATOR
    ,
    output cia::icr_t   icr
`endif
);

`ifdef VM_TRACE
    initial begin
        $dumpfile("cia_core.fst");
        $dumpvars;
    end
`endif

    logic phi2_up;   // PHI2 clock edges
    logic phi2_dn;
    logic phi2_prev;
    logic res;       // Reset signal
    logic rd;        // Read enable
    logic we;        // Write enable
    logic cnt_up;    // CNT edge detector
    logic flag_int;  // /FLAG edge detector interrupt
    logic tod_int;   // Time Of Day interrupt
    logic sp_int;    // Serial Port interrupt
    /* verilator lint_off UNOPTFLAT */
    logic ta_ufl;    // Timer A underflow
    logic tb_ufl;    // Timer B underflow
    logic ta_int;    // Timer A interrupt
    logic tb_int;    // Timer B interrupt
    /* verilator lint_off UNOPTFLAT */
    logic ta_pb;     // Timer A PB output
    logic tb_pb;     // Timer B PB output

    // Timer control signals.
    cia::tctrl_t ta_ctrl;
    cia::tctrl_t tb_ctrl;

    // Register map.
    cia::registers_t regs;

    always_comb begin
        phi2_up = ~phi2_prev &  bus_i.phi2;
        phi2_dn =  phi2_prev & ~bus_i.phi2;

        // Combine FPGA and CIA bus resets.
        res = rst | ~bus_i.res_n;

        // The signals are delayed by one FPGA cycle (using phi2_prev instead of phi2).
        rd = phi2_prev & ~bus_i.cs_n &  bus_i.r_w_n;
        we = phi2_prev & ~bus_i.cs_n & ~bus_i.r_w_n;

        // Output addressed value.
        bus_o.data = regs[{ ~bus_i.addr, 3'b000 } +: 8];

`ifdef VERILATOR
        icr = regs.icr;
`endif
    end

    always_ff @(posedge clk) begin
        phi2_prev <= bus_i.phi2;
    end

    // CNT edge detector.
    cia_edgedet cnt_posedge (
        .clk       (clk),
        .res       (1'b0),
        .phi2_dn   (phi2_dn),
        .pad_i     (bus_i.cnt),
        .posedge_o (cnt_up)
    );

    // /FLAG edge detector.
    cia_edgedet flag_negedge (
        .clk       (clk),
        .res       (1'b0),
        .phi2_dn   (phi2_dn),
        .pad_i     (~bus_i.flag_n),  // Inverted signal for posedge
        .posedge_o (flag_int)
    );

    // I/O ports.
    cia_ports ports (
        .clk     (clk),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .pa      (bus_i.pa),
        .pb      (bus_i.pb),
        .ta_pb   (ta_pb),
        .tb_pb   (tb_pb),
        .ta_pbon (regs.control.cra.pbon),
        .tb_pbon (regs.control.crb.pbon),
        .regs    (regs.ports),
        .pads    (bus_o.ports),
        .pc_n    (bus_o.pc_n)
    );

    // Timer A.
    cia_timer timer_a (
        .clk     (clk),
        .phi2_dn (phi2_dn),
        .res     (res),
        .lo_w    (we && bus_i.addr == 'h4),
        .hi_w    (we && bus_i.addr == 'h5),
        .data    (bus_i.data),
        .ctrl    (ta_ctrl),
        .regs    (regs.ta),
        .ufl     (ta_ufl),
        .intr    (ta_int),
        .pb      (ta_pb)
    );

    // Timer B.
    cia_timer timer_b (
        .clk     (clk),
        .phi2_dn (phi2_dn),
        .res     (res),
        .lo_w    (we && bus_i.addr == 'h6),
        .hi_w    (we && bus_i.addr == 'h7),
        .data    (bus_i.data),
        .ctrl    (tb_ctrl),
        .regs    (regs.tb),
        .ufl     (tb_ufl),
        .intr    (tb_int),
        .pb      (tb_pb)
    );

    // Time Of Day.
    cia_tod tod (
        .clk     (clk),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .tod     (bus_i.tod),
        .todin   (regs.control.cra.todin),
        .w_alarm (regs.control.crb.alarm),
        .regs    (regs.tod),
        .tod_int (tod_int)
    );

    // Serial Port.
    cia_serial serial (
        .clk     (clk),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .txmode  (regs.control.cra.spmode),
        .ta_int  (ta_int),
        .cnt_up  (cnt_up),
        .sp_in   (bus_i.sp),
        .regs    (regs.sdr),
        .cnt_out (bus_o.cnt),
        .sp_out  (bus_o.sp),
        .sp_int  (sp_int)
    );

    // Interrupt Control.
    cia_interrupt interrupt (
        .model   (model),
        .clk     (clk),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .sources ({ flag_int, sp_int, tod_int, tb_int, ta_int }),
        .regs    (regs.icr),
        .irq_n   (bus_o.irq_n)
    );

    // Control Registers.
    cia_control control (
        .clk     (clk),
        .phi2_dn (phi2_dn),
        .res     (res),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .cnt     (bus_i.cnt),
        .cnt_up  (cnt_up),
        .ta_ufl  (ta_ufl),
        .tb_ufl  (tb_ufl),
        .ta_int  (ta_int),
        .regs    (regs.control),
        .ta_ctrl (ta_ctrl),
        .tb_ctrl (tb_ctrl)
    );
endmodule

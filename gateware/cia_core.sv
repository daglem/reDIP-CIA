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
    logic alrm_int;  // Time Of Day interrupt
    logic sp_int;    // Serial Port interrupt
    cia::one_shot_t ta_one_shot;  // CRA control inputs for one-shot timer
    cia::one_shot_t tb_one_shot;  // CRB control inputs for one-shot timer
    logic ta_int;    // Timer A interrupt
    logic tb_int;    // Timer B interrupt
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

        // Combine FPGA and CIA bus resets.
        res <= rst | ~bus_i.res_n;
    end

    // CNT edge detector.
    cia_edgedet cnt_posedge (
        .clk       (clk),
        .res       (1'b0),
        .phi2_dn   (phi2_dn),
`ifdef VERILATOR
        // Emulate open drain pad otherwise handled in cia_io.sv
        .pad_i     (bus_i.cnt & bus_o.cnt),
`else
        .pad_i     (bus_i.cnt),
`endif
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
        .ta_pbon (regs.cra.pbon),
        .tb_pbon (regs.crb.pbon),
        .regs    (regs.ports),
        .pads    (bus_o.ports),
        .pc_n    (bus_o.pc_n)
    );

    // Timer A.
    cia_timer timer_a (
        .clk      (clk),
        .phi2_dn  (phi2_dn),
        .res      (res),
        .lo_w     (we && bus_i.addr == 'h4),
        .hi_w     (we && bus_i.addr == 'h5),
        .data     (bus_i.data),
        .ctrl     (ta_ctrl),
        .regs     (regs.ta),
        .one_shot (ta_one_shot),
        .intr     (ta_int),
        .pb       (ta_pb)
    );

    // Timer B.
    cia_timer timer_b (
        .clk      (clk),
        .phi2_dn  (phi2_dn),
        .res      (res),
        .lo_w     (we && bus_i.addr == 'h6),
        .hi_w     (we && bus_i.addr == 'h7),
        .data     (bus_i.data),
        .ctrl     (tb_ctrl),
        .regs     (regs.tb),
        .one_shot (tb_one_shot),
        .intr     (tb_int),
        .pb       (tb_pb)
    );

    // Time Of Day (MOS 6526/8521).
    cia::tod_t tod_regs;
    logic      tod_int;
    cia_tod tod (
        .clk     (clk),
        .phi2    (bus_i.phi2),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .tod     (bus_i.tod),
        .tod50hz (regs.cra.todin),
        .w_alarm (regs.crb.alarm),
        .regs    (tod_regs),
        .tod_int (tod_int)
    );

    // TOD counter (MOS 8520).
    cia::cnt_t cnt_regs;
    logic      cnt_int;
    cia_cnt cnt (
        .clk     (clk),
        .phi2    (bus_i.phi2),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .tod     (bus_i.tod),
        .w_alarm (regs.crb.alarm),
        .regs    (cnt_regs),
        .cnt_int (cnt_int)
    );

    always_comb begin
        regs.tod = (model == cia::MOS8520) ? cnt_regs : tod_regs;
        alrm_int = (model == cia::MOS8520) ? cnt_int  : tod_int;
    end

    // Serial Port.
    cia_serial serial (
        .clk     (clk),
        .phi2_up (phi2_up),
        .phi2_dn (phi2_dn),
        .res     (res),
        .we      (we),
        .addr    (bus_i.addr),
        .data    (bus_i.data),
        .txmode  (regs.cra.spmode),
        .ta_int  (ta_int),
        .cnt_up  (cnt_up),
`ifdef VERILATOR
        // Emulate open drain pad otherwise handled in cia_io.sv
        .sp_in   (bus_i.sp & bus_o.sp),
`else
        .sp_in   (bus_i.sp),
`endif
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
        .sources ({ flag_int, sp_int, alrm_int, tb_int, ta_int }),
        .regs    (regs.icr),
        .irq_n   (bus_o.irq_n)
    );

    // Control Register A.
    cia_control #(0) control_a (
        .model    (model),
        .clk      (clk),
        .phi2_dn  (phi2_dn),
        .res      (res),
        .cr_w     (we && bus_i.addr == 'hE),
        .data     (bus_i.data),
        .cnt_up   (cnt_up),
        .t0_int   ('0),  // Not used by CRA
        .cnt      ('0),  // Not used by CRA
        .one_shot (ta_one_shot),
        .regs     (regs.cra),
        .t_ctrl   (ta_ctrl)
    );

    // Control Register B.
    cia_control #(1) control_b (
        .model    (model),
        .clk      (clk),
        .phi2_dn  (phi2_dn),
        .res      (res),
        .cr_w     (we && bus_i.addr == 'hF),
        .data     (bus_i.data),
        .cnt_up   (cnt_up),
        .t0_int   (ta_int),
        .cnt      (bus_i.cnt),
        .one_shot (tb_one_shot),
        .regs     (regs.crb),
        .t_ctrl   (tb_ctrl)
    );
endmodule

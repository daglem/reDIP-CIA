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

module via_core (
    input  logic        clk,
    input  logic        rst,
    input  via::bus_i_t bus_i,
    output via::bus_o_t bus_o
`ifdef VERILATOR
    ,
    output via::ifr_t   ifr
`endif
);

`ifdef VM_TRACE
    initial begin
        $dumpfile("via_core.fst");
        $dumpvars;
    end
`endif

    logic res;      // Reset signal
    logic rd;       // Read enable
    logic rd_phi2;
    logic we;       // Write enable
    logic we_phi2;

    // Signals latched on PHI1 = 0.
    // Note that these signals must be stable before the rising edge of PHI2.
    // This differs from other MOS chips, where the signals only have to be
    // stable some time before the falling edge of PHI2.
    logic       cs;
    logic       r_w_n;
    via::reg4_t addr_phi1;

    // Signals latched on PHI2=0.
    via::reg4_t addr;  // From addr_phi1
    via::reg8_t data;

    // Register map.
    via::regs_t regs;

    always_comb begin
        // Reads are performed during PHI2, while writes are performed during
        // the following PHI1.
        rd = rd_phi2 &  bus_i.phi2;
        we = we_phi2 & ~bus_i.phi2;

        // Output addressed value.
        bus_o.data = regs[{ ~addr, 3'b000 } +: 8];

`ifdef VERILATOR
        ifr = regs.ifr;
`endif
    end

    always_ff @(posedge clk) begin
        if (~bus_i.phi2) begin
            cs        <= bus_i.cs1 & ~bus_i.cs2_n;
            r_w_n     <= bus_i.r_w_n;
            addr_phi1 <= bus_i.addr;
        end

        if (bus_i.phi2) begin
            addr <= addr_phi1;
            data <= bus_i.data;
        end

        // Register rd to synchronize with addr at the start of phi2, avoiding
        // spurious use of previous addr value.
        rd_phi2 <= bus_i.phi2 & cs & r_w_n & ~res;

        // Interestingly, write enable is not reset if CS is kept active into
        // the next cycle.
        if ((bus_i.phi2 & ~cs) | res) begin
            we_phi2 <= '0;
        end else if (bus_i.phi2 & cs & ~r_w_n) begin
            we_phi2 <= '1;
        end

        // Combine FPGA and VIA bus resets.
        res <= rst | ~bus_i.res_n;
    end

    // Ports.
    via::pflag_t pflag;
    logic        t1_pb7;
    logic        sclo_cb1;
    logic        so_cb2;

    via_ports ports (
        .clk      (clk),
        .phi2     (bus_i.phi2),
        .res      (res),
        .cs       (cs),
        .rd       (rd),
        .we       (we),
        .addr     (addr),
        .data     (data),
        .ports    (bus_i.ports),
        .acr      (regs.acr),
        .pcr      (regs.pcr),
        .ifr      (regs.ifr),
        .t1_pb7   (t1_pb7),
        .sclo_cb1 (sclo_cb1),
        .so_cb2   (so_cb2),
        .regs     (regs.pregs),
        .ports_o  (bus_o.ports),
        .pflag_o  (pflag)
    );

    always_comb begin
        regs.pra_no_hs = regs.pregs.pra;
    end

    // Timers.
    via::tflag_t tflag;
    logic        t2l_ufl;

    via_timers timers (
        .clk     (clk),
        .phi2    (bus_i.phi2),
        .res     (res),
        .rd      (rd),
        .we      (we),
        .addr    (addr),
        .data    (data),
        .acr     (regs.acr),
        .t2_pb6  (bus_i.ports.pb[6]),
        .regs    (regs.tregs),
        .tflag_o (tflag),
        .t1_pb7  (t1_pb7),
        .t2l_ufl (t2l_ufl)
    );

    // Serial Port.
    via::sflag_t sflag;

    via_serial serial (
        .clk      (clk),
        .phi2     (bus_i.phi2),
        .rd       (rd),
        .we       (we),
        .addr     (addr),
        .data     (data),
        .acr      (regs.acr),
        .ifr      (regs.ifr),
        .t2l_ufl  (t2l_ufl),
        .scli_cb1 (bus_i.ports.cb1),
        .si_cb2   (bus_i.ports.cb2),
        .sr       (regs.sr),
        .sflag_o  (sflag),
        .sclo_cb1 (sclo_cb1),
        .so_cb2   (so_cb2)
    );

    // Interrupt Control.
    via_interrupt interrupt (
        .clk   (clk),
        .res   (res),
        .we    (we),
        .addr  (addr),
        .data  (data),
        .pflag (pflag),
        .sflag (sflag),
        .tflag (tflag),
        .ifr   (regs.ifr),
        .ier   (regs.ier),
        .irq_n (bus_o.irq_n)
    );

    // Auxiliary Control Register and Peripheral Control Register.
    via_control control (
        .clk  (clk),
        .res  (res),
        .we   (we),
        .addr (addr),
        .data (data),
        .acr  (regs.acr),
        .pcr  (regs.pcr)
    );
endmodule

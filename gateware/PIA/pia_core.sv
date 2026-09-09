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

module pia_core (
    input  logic        clk,
    input  logic        rst,
    input  pia::bus_i_t bus_i,
    output pia::bus_o_t bus_o
);

`ifdef VM_TRACE
    initial begin
        $dumpfile("pia_core.fst");
        $dumpvars;
    end
`endif

    logic res;  // Reset signal
    logic cs;   // Chip select
    logic rd;   // Read enable
    logic rd_phi2;
    logic we;   // Write enable
    logic we_phi2;

    // Signals latched on PHI2=0.
    // Address lines are not latched for reads in the real MOS 6520 chip,
    // however the effect is the same since data outputs are only enabled
    // during PHI2.
    pia::reg2_t addr;
    pia::reg8_t data;

    // Register map.
    pia::regs_t regs;

    always_comb begin
        cs = bus_i.cs0 & bus_i.cs1 & ~bus_i.cs2_n;

        // Reads are performed during PHI2, while writes are performed during
        // the following PHI1.
        rd = rd_phi2 &  bus_i.phi2;
        we = we_phi2 & ~bus_i.phi2;

        // Output addressed value.
        bus_o.data = regs[{ ~addr, 3'b000 } +: 8];
    end

    always_ff @(posedge clk) begin
        if (bus_i.phi2) begin
            addr <= bus_i.addr;
            data <= bus_i.data;
        end

        // Register rd to synchronize with addr at the start of phi2, avoiding
        // spurious use of previous addr value.
        rd_phi2 <= bus_i.phi2 & cs & bus_i.r_w_n & ~res;

        // Interestingly, write enable is not reset if CS is kept active into
        // the next cycle.
        if ((bus_i.phi2 & ~cs) | res) begin
            we_phi2 <= '0;
        end else if (bus_i.phi2 & cs & ~bus_i.r_w_n) begin
            we_phi2 <= '1;
        end

        // Combine FPGA and PIA bus resets.
        res <= rst | ~bus_i.res_n;
    end

    // Ports.
    pia_ports ports (
        .clk     (clk),
        .phi2    (bus_i.phi2),
        .res     (res),
        .cs      (cs),
        .rd      (rd),
        .we      (we),
        .addr    (addr),
        .data    (data),
        .ports   (bus_i.ports),
        .regs    (regs),
        .ports_o (bus_o.ports),
        .irqa_n  (bus_o.irqa_n),
        .irqb_n  (bus_o.irqb_n)
    );
endmodule

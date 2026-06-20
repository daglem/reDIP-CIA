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

module pia_ports (
    input  logic       clk,
    input  logic       phi2,
    input  logic       res,
    input  logic       cs,
    input  logic       rd,
    input  logic       we,
    input  pia::reg2_t addr,
    input  pia::reg8_t data,
    input  pia::pin_t  ports,
    output pia::regs_t regs,
    output pia::pout_t ports_o,
    output logic       irqa_n,
    output logic       irqb_n
);
    // Registers.
    pia::reg8_t pra, ddra;
    pia::cr_t   cra;
    pia::reg8_t prb, ddrb;
    pia::cr_t   crb;

    // Control lines
    logic ca1_flag;
    logic ca2_flag;
    logic cb1_flag;
    logic cb2_flag;
    logic r_hsa;
    logic r_hsb;
    logic w_hsb;
    logic ca2_out;
    logic cb2_out;

    // Address selects
    logic asel_0;
    logic asel_2;

    always_comb begin
        asel_0 = (addr == 'h0);
        asel_2 = (addr == 'h2);
    end

    // Register writes.
    always_ff @(posedge clk) begin
        // PRA
        if (res) begin
            pra  <= '0;
        end else if (we & asel_0 & cra.prsel) begin
            pra  <= data;
        end

        // DDRA
        if (res) begin
            ddra <= '0;
        end else if (we & asel_0 & ~cra.prsel) begin
            ddra <= data;
        end

        // CRA
        if (r_hsa | res) begin
            // Read of PRA.
            cra.irq1 <= '0;
        end else if (ca1_flag) begin
            cra.irq1 <= '1;
        end

        if (cra.c2_mode[2] | r_hsa | res) begin
            // Output mode or read of PRA.
            cra.irq2 <= '0;
        end else if (ca2_flag) begin
            cra.irq2 <= '1;
        end

        if (res) begin
            cra[5:0] <= '0;
        end else if (we && addr == 'h1) begin
            cra[5:0] <= data[5:0];
        end

        // PRB
        if (res) begin
            prb  <= '0;
        end else if (we & asel_2 & crb.prsel) begin
            prb  <= data;
        end

        // DDRB
        if (res) begin
            ddrb <= '0;
        end else if (we & asel_2 & ~crb.prsel) begin
            ddrb <= data;
        end

        // CRB
        if (r_hsb | res) begin
            // Read of PRB.
            crb.irq1 <= '0;
        end else if (cb1_flag) begin
            crb.irq1 <= '1;
        end

        if (crb.c2_mode[2] | r_hsb | res) begin
            // Output mode or read of PRB.
            crb.irq2 <= '0;
        end else if (cb2_flag) begin
            crb.irq2 <= '1;
        end

        if (res) begin
            crb[5:0] <= '0;
        end else if (we && addr == 'h3) begin
            crb[5:0] <= data[5:0];
        end
    end

    // Handshake signals.
    always_ff @(posedge clk) begin
        if (phi2 & ~cs) begin
            r_hsa <= '0;
        end else if (rd & cra.prsel & asel_0) begin
            r_hsa <= '1;
        end

        if (phi2 & ~cs) begin
            r_hsb <= '0;
        end else if (rd & crb.prsel & asel_2) begin
            r_hsb <= '1;
        end

        if (~(phi2 | we)) begin
            w_hsb <= '0;
        end else if (we & crb.prsel & asel_2) begin
            w_hsb <= '1;
        end
    end

    // Control line inputs, setting IRQ flags.
    pia_edgedet ca1_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.ca1),
        .det_pos (cra.c1_mode[1]),
        .flag_i  (cra.irq1),
        .flag_o  (ca1_flag)
    );

    pia_edgedet ca2_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.ca2),
        .det_pos (cra.c2_mode[1]),
        .flag_i  (cra.irq2),
        .flag_o  (ca2_flag)
    );

    pia_edgedet cb1_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.cb1),
        .det_pos (crb.c1_mode[1]),
        .flag_i  (crb.irq1),
        .flag_o  (cb1_flag)
    );

    pia_edgedet cb2_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.cb2),
        .det_pos (crb.c2_mode[1]),
        .flag_i  (crb.irq2),
        .flag_o  (cb2_flag)
    );

    // Control line outputs.
    always_ff @(posedge clk) begin
        if ((cra.c2_mode[1:0] == 'b00 && cra.irq1) ||         // Handshake on read - reset CA2 high with an active transition on CAl.
            (cra.c2_mode[1:0] == 'b01 && (phi2 & ~r_hsa)) ||  // Pulse output mode - reset CA2 high after a read of PRA.
            (cra.c2_mode[1:0] == 'b11) ||                     // Manual output mode - CA2 held high.
            ~cra.c2_mode[2])                                  // Input mode
        begin
            ca2_out <= '1;
        end else if (cra.c2_mode[1:0] == 'b10 ||              // Manual output mode - CA2 held low.
                     (~phi2 & r_hsa))                         // Handshake on read - set CA2 low following a read of PRA.
        begin
            ca2_out <= '0;
        end

        if ((crb.c2_mode[1:0] == 'b00 && crb.irq1) ||         // Handshake on write - reset CB2 high with an active transition on CBl.
            (crb.c2_mode[1:0] == 'b01 && (phi2 & ~w_hsb)) ||  // Pulse output mode - reset CB2 high after a write of PRB.
            (crb.c2_mode[1:0] == 'b11) ||                     // Manual output mode - CB2 held high.
            ~crb.c2_mode[2])                                  // Input mode
        begin
            cb2_out <= '1;
        end else if (crb.c2_mode[1:0] == 'b10 ||               // Manual output mode - CB2 held low.
                     (phi2 & w_hsb))                           // Handshake on write - set CB2 low following a write of PRB.
        begin
            cb2_out <= '0;
        end
    end

    // Port outputs.
    always_comb begin
        ports_o.pa     = pra;
        ports_o.ddra   = ddra;
        ports_o.pb     = prb;
        ports_o.ddrb   = ddrb;
        ports_o.cb2    = cb2_out;
        ports_o.ca2    = ca2_out;
        ports_o.ddrcb2 = crb.c2_mode[2];

        // IRQ and IRQ enable.
        irqa_n = (cra.irq1 & cra.c1_mode[0]) | (cra.irq2 & cra.c2_mode[0]);
        irqb_n = (crb.irq1 & crb.c1_mode[0]) | (crb.irq2 & crb.c2_mode[0]);
    end

    // Register outputs.
    always_comb begin
        regs.pra = cra.prsel ? ports.pa : ddra;
        regs.cra = cra;
        // Read Port B outputs back in.
        regs.prb = crb.prsel ? ((~ddrb & ports.pb) | (ddrb & prb)) : ddrb;
        regs.crb = crb;
    end
endmodule

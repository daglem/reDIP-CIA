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

module via_ports (
    input  logic        clk,
    input  logic        phi2,
    input  logic        res,
    input  logic        cs,
    input  logic        rd,
    input  logic        we,
    input  via::reg4_t  addr,
    input  via::reg8_t  data,
    input  via::pin_t   ports,
    /* verilator lint_off UNUSEDSIGNAL */
    input  via::acr_t   acr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  via::pcr_t   pcr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  via::ifr_t   ifr,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic        t1_pb7,
    input  logic        sclo_cb1,
    input  logic        so_cb2,
    output via::pregs_t regs,
    output via::pout_t  ports_o,
    output via::pflag_t pflag_o
);

    // Register address selects.
    logic asel_prb;
    logic asel_pra;

    via::pregs_t oregs; // Register file (ORB, ORA, DDRB, DDRA).
    via::reg8_t  pa_in;
    via::reg8_t  pb_in;
    logic        ifr_cb1_phi1;
    logic        ca2_out;
    logic        cb2_out;

    // Handshake signals.
    logic r_ira;
    logic w_ora;
    logic r_hsa;
    logic r_hsb;
    logic w_hsa;
    logic w_hsb;

    // Register writes.
    always_ff @(posedge clk) begin
        if (res) begin
            // Asynchronous reset (with respect to PHI2).
            oregs <= '0;
        end else if (we) begin
            unique0 case (addr)
              'h0: oregs.prb  <= data;
              'h1,
              'hf: oregs.pra  <= data;
              'h2: oregs.ddrb <= data;
              'h3: oregs.ddra <= data;
            endcase
        end
    end

    // Handshake signals.
    always_ff @(posedge clk) begin
        // Read from IRA.
        // Interestingly, the read flag is not reset if CS is kept active into
        // the next cycle.
        unique0 if (rd & asel_pra) begin
            r_ira <= '1;
        end else if (phi2 & ~cs) begin
            r_ira <= '0;
        end

        if (~phi2) begin
            r_hsa <= r_ira;
        end

        // Write to ORA.
        unique0 if (we & asel_pra) begin
            w_ora <= '1;
        end else if (~(we | phi2)) begin
            w_ora <= '0;
        end

        if (phi2) begin
            w_hsa <= w_ora;
        end

        // Write to ORB.
        unique0 if (we & asel_prb) begin
            w_hsb <= '1;
        end else if (~(we | phi2)) begin
            w_hsb <= '0;
        end
    end

    always_comb begin
        asel_prb = (addr == 'h0);
        asel_pra = (addr == 'h1);

        r_hsb    = rd & asel_prb;

        // Handshake: Reset of IFR flags.
        pflag_o.r_ca2 = pcr.ca2_mode[2] | (~pcr.ca2_mode[0] & (r_hsa | w_hsa));  // Output mode or read/write of IRA/ORA in interrupt input mode.
        pflag_o.r_ca1 = r_hsa | w_hsa;                                           // Read/write of IRA/ORA.
        pflag_o.r_cb2 = pcr.cb2_mode[2] | (~pcr.cb2_mode[0] & (r_hsb | w_hsb));  // Output mode or read/write of IRB/ORB in interrupt input mode.
        pflag_o.r_cb1 = r_hsb | w_hsb;                                           // Read/write of IRB/ORB.
    end

    // Data lines.
    always_comb begin
        // Port outputs.
        ports_o.pa      = oregs.pra;
        ports_o.pb      = oregs.prb;
        // Special handling for Port B bit 7.
        ports_o.pb[7]   = acr.t1_pb7_out ? t1_pb7 : oregs.prb[7];

        ports_o.ddra    = oregs.ddra;
        ports_o.ddrb    = oregs.ddrb;
        // Special handling for Port B bit 7.
        ports_o.ddrb[7] = oregs.ddrb[7] | acr.t1_pb7_out;

        // Control line outputs.
        ports_o.ca2     = ca2_out;                                                 // CA2 output.
        ports_o.cb1     = sclo_cb1;                                                // SR clock output.
        ports_o.cb2     = acr.shift_mode[2] ? so_cb2 : cb2_out;                    // SR data output or CB2 output.
        ports_o.ddrcb1  = acr.shift_mode != 'b000 && acr.shift_mode[1:0] != 'b11;  // SR enabled and doesn't use external clock.
        ports_o.ddrcb2  = acr.shift_mode[2] | pcr.cb2_mode[2];                     // SR output mode or CB2 output mode.

        // Port inputs - IRA / IRB.
        regs.pra  = pa_in;
        // Read Port B outputs back in.
        regs.prb  = (~ports_o.ddrb & pb_in) | (ports_o.ddrb & oregs.prb);

        regs.ddra = oregs.ddra;
        regs.ddrb = oregs.ddrb;
    end

    // Port inputs.
    always_ff @(posedge clk) begin
        if (~(acr.pa_latch & ifr.ca1)) begin
            pa_in <= ports.pa;
        end

        if (~phi2) begin
            ifr_cb1_phi1 <= ifr.cb1;
        end

        if (~(acr.pb_latch & ifr_cb1_phi1)) begin
            pb_in <= ports.pb;
        end
    end

    // Control line inputs, setting IFR flags.
    via_edgedet ca1_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.ca1),
        .det_pos (pcr.ca1_inmode),
        .flag_i  (ifr.ca1),
        .flag_o  (pflag_o.s_ca1)
    );

    via_edgedet ca2_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.ca2),
        .det_pos (pcr.ca2_mode[1]),
        .flag_i  (ifr.ca2),
        .flag_o  (pflag_o.s_ca2)
    );

    via_edgedet cb1_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.cb1),
        .det_pos (pcr.cb1_inmode),
        .flag_i  (ifr.cb1),
        .flag_o  (pflag_o.s_cb1)
    );

    via_edgedet cb2_in(
        .clk     (clk),
        .res     (res),
        .phi2    (phi2),
        .pad_i   (ports.cb2),
        .det_pos (pcr.cb2_mode[1]),
        .flag_i  (ifr.cb2),
        .flag_o  (pflag_o.s_cb2)
    );

    // Control line outputs.
    always_ff @(posedge clk) begin
        if ((pcr.ca2_mode[1:0] == 'b00 && ifr.ca1) ||           // Handshake output mode - reset CA2 high with an active transition on CAl.
            (pcr.ca2_mode[1:0] == 'b01 && ~(r_hsa | w_hsa)) ||  // Pulse output mode - reset CA2 high after a read/write of IRA/ORA.
            (pcr.ca2_mode[1:0] == 'b11) ||                      // Manual output mode - CA2 held high.
            ~pcr.ca2_mode[2])                                   // Input mode
        begin
            ca2_out <= '1;
        end else if (pcr.ca2_mode[1:0] == 'b10 ||               // Manual output mode - CA2 held low.
                     (~phi2 & r_hsa) || (phi2 & w_hsa))         // Set CA2 low following a read/write of IRA/ORA.
        begin
            ca2_out <= '0;
        end

        if ((pcr.cb2_mode[1:0] == 'b00 && ifr.cb1) ||           // Handshake output mode - reset CB2 high with an active transition on CBl.
            (pcr.cb2_mode[1:0] == 'b01 && (phi2 & ~w_hsb)) ||   // Pulse output mode - reset CB2 high after a write of ORB.
            (pcr.cb2_mode[1:0] == 'b11) ||                      // Manual output mode - CB2 held high.
            ~pcr.cb2_mode[2])                                   // Input mode
        begin
            cb2_out <= '1;
        end else if (pcr.cb2_mode[1:0] == 'b10 ||               // Manual output mode - CB2 held low.
                     (phi2 & w_hsb))                            // Set CB2 low following a write of ORB.
        begin
            cb2_out <= '0;
        end
    end
endmodule

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

module cia_interrupt (
    input  cia::model_t model,
    input  logic        clk,
    input  logic        phi2_up,
    input  logic        phi2_dn,
    input  logic        res,
    input  logic        rd,
    input  logic        we,
    input  cia::reg4_t  addr,
    /* verilator lint_off UNUSEDSIGNAL */
    input  cia::reg8_t  data,
    /* verilator lint_on UNUSEDSIGNAL */
    input  logic[4:0]   sources,
    output cia::reg8_t  regs,
    output logic        irq_n
    );

    logic [4:0] flags;
    logic [4:0] flags_prev;
    logic [4:0] mask;
    logic [4:0] sources_prev;  // For MOS6526 delay
    logic [4:0] sources_model;
    logic       rd_flags;
    logic       rd_or_res;
    logic       ir_set;
    logic       ir_n;
    logic       ir_n_prev;
    logic       irq;
    logic       irq_prev;

    always_comb begin
        rd_or_res = rd_flags | res;

        sources_model = model == cia::MOS6526 ? sources_prev : sources;

        for (int i = 0; i < 5; i++) begin
            // SR latches setting interrupt source flags.
            // FIXME: Some (all?) CIA chips have a bug where this works as
            // an RS latch instead of an SR latch, causing flags to be lost
            // when a read is made on the same cycle as an interrupt
            // FIXME: Can this also cause interrupts to be lost below?
            if      (sources_model[i]) flags[i] = 1;
            else if (rd_or_res)        flags[i] = 0;
            else                       flags[i] = flags_prev[i];
        end

        ir_set = |(flags & mask);

        // SR/RS latch setting IR flag and /IRQ pad.
        unique case ({ rd_or_res, ir_set })
          2'b00: { ir_n, irq } = { ir_n_prev, irq_prev };
          2'b01: { ir_n, irq } = 2'b01;
          2'b10: { ir_n, irq } = 2'b10;
          2'b11: { ir_n, irq } = 2'b00;
        endcase

        irq_n = ~irq;
        regs  = { ~ir_n, 2'b0, flags };
    end

    always_ff @(posedge clk) begin
        if (phi2_up) begin
            // Delay interrupt sources for MOS6526.
            sources_prev <= sources;
        end

        if (phi2_up) begin
            ir_n_prev  <= ir_n;
            irq_prev   <= irq;

            flags_prev <= flags;
        end

        if (phi2_dn) begin
            if (res) begin
                mask <= '0;
            end else if (we && addr == 'hD) begin
                mask <= data[7] ? mask | data[4:0] : mask & ~data[4:0];
            end

            rd_flags <= rd && addr == 'hD;
        end
    end
endmodule

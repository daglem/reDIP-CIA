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

    logic [4:0] sources_prev;  // For MOS6526 delay
    logic [4:0] sources_model;
    logic [4:0] flags;
    logic [4:0] flags_prev;
    logic [4:0] mask;
    logic       r_flags;
    logic       w_mask;
    logic       w_mask_prev;
    logic       ir_clr;
    logic       ir_set;
    logic       ir_set_prev;  // For MOS8521 delay
    logic       ir_set_model;
    cia::reg8_t icr;
    cia::reg8_t icr_prev;
    logic       icr7;
    logic       icr7_prev;
    logic       irq;
    logic       irq_prev;

    always_comb begin
        r_flags = rd && addr == 'hD;
        w_mask  = we && addr == 'hD;

        sources_model = (model == cia::MOS6526) ? sources_prev : sources;

        for (int i = 0; i < 5; i++) begin
            // SR latches setting interrupt source flags.
            if      (sources_model[i]) flags[i] = 1;
            else if (ir_clr)           flags[i] = 0;
            else                       flags[i] = flags_prev[i];
        end

        ir_set       = |(flags & mask);
        ir_set_model = (model == cia::MOS6526) ? ir_set : ir_set_prev;

        // SR/RS latch setting IR flag and /IRQ pad.
        unique case ({ ir_set_model, ir_clr })
          2'b00: { icr7, irq } = { icr7_prev, irq_prev };
          2'b01: { icr7, irq } = 2'b00;
          2'b10: { icr7, irq } = 2'b11;
          2'b11: { icr7, irq } = 2'b10;
        endcase

        irq_n = ~irq;
        icr   = { icr7, 2'b0, flags };
        // The polysilicon strips used as gates to clear ICR bits are extremely
        // long, and the gate voltages rise so slowly that previously set bits
        // can still be read out during the next cycle.
        regs  = icr | icr_prev;
    end

    always_ff @(posedge clk) begin
        if (phi2_dn) begin
            // Delay interrupt sources for the MOS6526.
            sources_prev <= sources;
            // Keep ICR value for the next cycle.
            icr_prev <= icr;
        end

        // Update latch states.
        icr7_prev  <= icr7;
        irq_prev   <= irq;
        flags_prev <= flags;

        if (phi2_up | w_mask) begin  // Has the same effect as "if (phi2)"
            ir_set_prev <= ir_set;
        end

        if ((model == cia::MOS6526) && phi2_up) begin
            ir_clr <= 0;
        end else if (phi2_dn) begin
            ir_clr <= r_flags | res;
        end

        // Normally, a write to the ICR takes effect at PHI1.
        // An interesting observation is that if the ICR is written in two
        // consecutive cycles, the second write takes effect already at PHI2.
        // The 650x/651x MPUs sample interrupt signals on PHI2, so we must
        // implement this behavior accurately.
        if (res) begin
            mask <= '0;
        end else if (w_mask && (phi2_dn || w_mask_prev)) begin
            mask <= data[7] ? mask | data[4:0] : mask & ~data[4:0];
        end

        if (phi2_dn) begin
            w_mask_prev <= w_mask;
        end
    end
endmodule

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

    logic [1:0] phi1;  // Extra synchronization steps for SR and RS latches
    logic [4:0] flags;
    logic [4:0] mask;
    logic [4:0] sources_prev;  // For MOS6526 delay
    logic       rd_flags;
    logic       wr_mask;
    logic       irq;

    always_comb begin
        wr_mask = we && addr == 'hD && phi2_dn;

        irq_n = ~irq;
        regs  = { irq, 2'b0, flags };
    end

    always_ff @(posedge clk) begin
        if (res) begin
            mask <= '0;
        end else if (wr_mask) begin
            mask <= data[7] ? mask | data[4:0] : mask & ~data[4:0];
        end

        if (phi2_dn) begin
            rd_flags <= rd && addr == 'hD;

            // Delay interrupt sources for MOS6526.
            sources_prev <= sources;
        end

        // Extra synchronization steps for SR and RS latches.
        if (phi2_dn) begin
            phi1 <= 1;
        end else if (phi1 == 1) begin
            phi1 <= 2;
        end else begin
            phi1 <= 0;
        end

        if (phi1 == 1) begin
            for (int i = 0; i < 5; i++) begin
                // SR latches setting interrupt source flags.
                // FIXME: Some (all?) CIA chips have a bug where this works as
                // an RS latch instead of an SR latch, causing flags to be lost
                // when a read is made on the same cycle as an interrupt
                // FIXME: Can this also cause interrupts to be lost below?
                if (model == cia::MOS6526 ? sources_prev[i] : sources[i]) begin
                    flags[i] <= 1;
                end else if (res | rd_flags) begin
                    flags[i] <= 0;
                end
            end
        end

        // RS latch setting IRQ flag.
        if (phi1 == 2) begin
            if (res | rd_flags) begin
                irq <= 0;
            end else if (|(flags & mask)) begin
                irq <= 1;
            end
        end
    end
endmodule

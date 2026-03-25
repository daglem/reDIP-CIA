// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
// Copyright (C) 2026  Dag Lem <resid@nimrod.no>
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

// A 24MHz clock implies a time step of 1/48MHz = 20.833ns.
// For simplicity we simulate using a 1MHz clock, i.e. 1us time steps.
`timescale 1us / 1us

module cia_config_tb ();

    logic        clk = '0;
    logic        res = '0;
    logic        icr_r = '0;
    logic        icr_w = '0;
    cia::reg8_t  data = '0;
    cia::spi_i_t spi_i = '0;
    cia::spi_o_t spi_o;
    cia::model_t model;
    logic [1:0]  icr65;

    cia_config cia_config (
        .clk   (clk),
        .res   (res),
        .icr_r (icr_r),
        .icr_w (icr_w),
        .data  (data),
        .spi_i (spi_i),
        .spi_o (spi_o),
        .model (model),
        .icr65 (icr65)
    );

    task write_command (input string cmd);
        static byte c, b;
        icr_w = '1;
        
        for (int i = 0; i < cmd.len(); i++) begin
            c = cmd[i];
            b = (c >= 'h40 ? c - 'h40 : c - 'h30)*16;
            data = b;
            #2;
        end

        icr_w = '0;
        while (cia_config.spi_busy) #1;
        #2;
    endtask

    always #1 clk   = ~clk;
    always #4 spi_i = ~spi_i;

    initial begin
        $dumpfile("cia_config.fst");
        $dumpvars;

        res = '1;
        #10 res = '0;
        #2;  // Wait for initial read from flash to start.
        while (cia_config.spi_busy) #1;
        #2;
        
        write_command("CFG0");
        icr_r = '1;
        #2;
        icr_r = '0;
        
        write_command("CFG3");
        write_command("CFG7");
        write_command("CFG6");

        $finish;
    end

`ifdef __ICARUS__
    // Iverilog currently flattens structs.
    logic cs_n;
    logic sclk;
    logic so;
    logic si;
    always_comb begin
        cs_n = spi_o.cs_n;
        sclk = spi_o.sclk;
        so   = spi_o.so;
        si   = spi_i.si;
    end
`endif
endmodule

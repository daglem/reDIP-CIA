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

/* verilator lint_off DECLFILENAME */
package pia;
/* verilator lint_on DECLFILENAME */

    typedef logic  [7:0] reg8_t;   // Data bus, register bytes
    typedef logic  [2:0] reg3_t;   // Address bus, register bits
    typedef logic  [1:0] reg2_t;   // Register bits

    // Port input lines.
    typedef struct packed {
        reg8_t pb;
        reg8_t pa;
        logic  cb2;
        logic  cb1;
        logic  ca2;
        logic  ca1;
    } pin_t;

    // Port output lines.
    typedef struct packed {
        reg8_t pb;
        reg8_t pa;
        reg8_t ddrb;
        reg8_t ddra;
        logic  cb2;
        logic  ca2;
        logic  ddrcb2;
    } pout_t;

    typedef struct packed {
        logic  irq1;
        logic  irq2;
        reg3_t c2_mode;
        logic  prsel;    // 1 = Select PRA/B register, 0 = Select DDRA/B register.
        reg2_t c1_mode;  // Posedge, IRQ enable
    } cr_t;

    // Registers.
    typedef struct packed {
        reg8_t pra;  // CRA[2] = 1: PRA, CRA[2] = 0: DDRA
        cr_t   cra;
        reg8_t prb;  // CRB[2] = 1: PRB, CRB[2] = 0: DDRB
        cr_t   crb;
    } regs_t;

    // Bus input signals.
    typedef struct packed {
        logic  phi2;
        logic  res_n;
        logic  cs0;
        logic  cs1;
        logic  cs2_n;
        logic  r_w_n;
        reg2_t addr;
        reg8_t data;
        pin_t  ports;
    } bus_i_t;

    // Bus output signals.
    typedef struct packed {
        reg8_t data;
        pout_t ports;
        logic  irqa_n;
        logic  irqb_n;
    } bus_o_t;
endpackage

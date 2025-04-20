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

/* verilator lint_off DECLFILENAME */
package cia;
/* verilator lint_on DECLFILENAME */

    typedef logic [15:0] reg16_t;  // Timer counter, timer latch
    typedef logic  [7:0] reg8_t;   // Data bus, register bytes
    typedef logic  [3:0] reg4_t;   // Address bus, BCD count
    typedef logic  [2:0] reg3_t;   // BCD count
    typedef logic  [1:0] reg2_t;

    typedef enum logic [0:0] {
        MOS6526,
        MOS8521
    } model_t;

    typedef struct packed {
        reg8_t pra;
        reg8_t prb;
        reg8_t ddra;
        reg8_t ddrb;
    } ports_t;

    typedef struct packed {
        reg8_t lo;
        reg8_t hi;
    } timer_t;

    typedef struct packed {
        struct packed {
            reg4_t zero;
            reg4_t t;
        } tod_10ths;
        struct packed {
            logic zero;
            reg3_t sh;
            reg4_t sl;
        } tod_sec;
        struct packed {
            logic zero;
            reg3_t mh;
            reg4_t ml;
        } tod_min;
        struct packed {
            logic pm;
            reg2_t zero;
            logic  hh;
            reg4_t hl;
        } tod_hr;
    } tod_t;

    typedef struct packed {
        logic ir_s_c;
        logic z7;
        logic z6;
        logic flg;
        logic sp;
        logic alrm;
        logic tb;
        logic ta;
    } icr_t;

    typedef struct packed {
        logic todin;
        logic spmode;
        logic inmode;
        logic load;
        logic runmode;
        logic outmode;
        logic pbon;
        logic start;
    } cra_t;

    typedef struct packed {
        logic alarm;
        logic [1:0] inmode;
        logic load;
        logic runmode;
        logic outmode;
        logic pbon;
        logic start;
    } crb_t;

    typedef struct packed {
        cra_t cra;
        crb_t crb;
    } control_t;

    typedef struct packed {
        // I/O port registers.
        ports_t   ports;
        // Timer registers.
        timer_t   ta;
        timer_t   tb;
        // Time Of Day registers.
        tod_t     tod;
        // Serial data register.
        reg8_t    sdr;
        // Interrupt control register.
        icr_t     icr;
        // Control registers.
        control_t control;
    } registers_t;

    // Timer control inputs.
    typedef struct packed {
        logic count;
        logic force_load;
        logic toggle;
        logic start;
    } tctrl_t;

    // Bus input signals.
    typedef struct packed {
        logic  phi2;
        logic  res_n;
        logic  cs_n;
        logic  r_w_n;
        reg4_t addr;
        reg8_t data;
        reg8_t pa;
        reg8_t pb;
        logic  flag_n;
        logic  tod;
        logic  cnt;
        logic  sp;
    } bus_i_t;

    // Bus output signals.
    typedef struct packed {
        reg8_t  data;
        ports_t ports;
        logic   pc_n;
        logic   cnt;
        logic   sp;
        logic   irq_n;
    } bus_o_t;

endpackage

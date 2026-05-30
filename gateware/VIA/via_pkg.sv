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
package via;
/* verilator lint_on DECLFILENAME */

    typedef logic [15:0] reg16_t;  // Timer counter, timer latch
    typedef logic  [7:0] reg8_t;   // Data bus, register bytes
    typedef logic  [4:0] reg5_t;   // Ring counter
    typedef logic  [3:0] reg4_t;   // Address bus
    typedef logic  [2:0] reg3_t;   // Register bits

    // Port registers.
    typedef struct packed {
        reg8_t prb;
        reg8_t pra;
        reg8_t ddrb;
        reg8_t ddra;
    } pregs_t;

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
        logic  cb1;
        logic  cb2;
        logic  ca2;
        logic  ddrcb1;
        logic  ddrcb2;
    } pout_t;

    // Port interrupt flags.
    typedef struct packed {
        logic s_ca1;
        logic s_ca2;
        logic s_cb1;
        logic s_cb2;
        logic r_ca1;
        logic r_ca2;
        logic r_cb1;
        logic r_cb2;
    } pflag_t;

    // Serial interrupt flags.
    typedef struct packed {
        logic s_sr;
        logic r_sr;
    } sflag_t;

    typedef struct packed {
        reg8_t lo;
        reg8_t hi;
    } timer_t;

    // Timer registers.
    typedef struct packed {
        timer_t t1;
        timer_t t1_latch;
        timer_t t2;
    } tregs_t;

    // Timer interrupt flags.
    typedef struct packed {
        logic s_t1;
        logic s_t2;
        logic r_t1;
        logic r_t2;
    } tflag_t;

    typedef struct packed {
        logic  t1_pb7_out;
        logic  t1_free_run;
        logic  t2_pb6_in;
        reg3_t shift_mode;
        logic  pb_latch;
        logic  pa_latch;
    } acr_t;

    typedef struct packed {
        reg3_t cb2_mode;
        logic  cb1_inmode;
        reg3_t ca2_mode;
        logic  ca1_inmode;
    } pcr_t;

    typedef struct packed {
        logic irq;
        logic t1;
        logic t2;
        logic cb1;
        logic cb2;
        logic sr;
        logic ca1;
        logic ca2;
    } ifr_t;

    typedef struct packed {
        // I/O port registers.
        pregs_t pregs;
        // Timer registers.
        tregs_t tregs;
        // Shift register.
        reg8_t  sr;
        // Auxiliary Control Register.
        acr_t   acr;
        // Peripheral Control Register.
        pcr_t   pcr;
        // Interrupt Flag Register.
        ifr_t   ifr;
        // Interrupt Enable Register.
        ifr_t   ier;
        // PRA, no handshake.
        reg8_t  pra_no_hs;
    } regs_t;

    // Bus input signals.
    typedef struct packed {
        logic   phi2;
        logic   res_n;
        logic   cs1;
        logic   cs2_n;
        logic   r_w_n;
        reg4_t  addr;
        reg8_t  data;
        pin_t   ports;
    } bus_i_t;

    // Bus output signals.
    typedef struct packed {
        reg8_t  data;
        pout_t  ports;
        logic   irq_n;
    } bus_o_t;
endpackage

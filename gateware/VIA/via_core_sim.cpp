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

// Run "make sim" to create simulation executables.
//
// The simulation reads lines on the following format, each line specifying a
// number of cycles to step before further processing an operation, as seen
// from the perspective of the CPU:
//
// cycles R/W/I register/port/pin value
//
// Register/port/pin values:
// * 0-F: Register address (R/W/I)
// * PA, PB: Port input/output (R/W)
// * CA1, CA2, CB1, CB2, RES: Pin input (R)
// * IRQ, CA2, CB1, CB2: Pin output (W)
//
// MOS chips are latched designs, internally using a two phase clock.
// To match the sequence of operations in the silicon and in this simulation,
// operations within the same cycle must be ordered as follows:
//
//   1. Pin and port outputs (PHI1 - after falling edge of PHI2)
//   2. Pin and port inputs (PHI2 - before falling edge of PHI2)
//      - must be set before register read, and to avoid splitting
//        read into two operations (address at PHI1, read at PHI2),
//        we set the inputs earlier - before the rising edge of PHI2.
//   3. Register read/write (PHI1 - before rising edge of PHI2)
//      - all 6522 bus input signals except data are latched on PHI1=0.
//        Reads are then performed during PHI2. Writes are set up during
//        PHI2, but not actually performed until the following PHI1.
//   4. Interrupt (PHI2 - before falling edge of PHI2, sampled by CPU)
//
// No processing is done for interrupts (I), however a line containing the IFR
// register address and value is output for every interrupt, in order to
// facilitate comparison with the input file.
//
// To run simulation on via_gold.mosio, writing simulation output to diff with
// to via_sim.mosio:
//
// sim_log/via_sim < via_gold.mosio  # Default output file is via_sim.mosio
// sim_log/via_sim -i via_gold.mosio -o via_sim.mosio
//
// To write a waveform dump for GTKWave or Surfer to the file via_core.fst,
// and .mosio output to the default output file via_sim.mosio:
//
// sim_trace/via_sim < via_gold.mosio
//

#include "Vvia_core.h"
#include <verilated.h>
#include <climits>
#include <format>
#include <fstream>
#include <getopt.h>
#include <stdio.h>
#include <unistd.h>
#include <iomanip>
#include <iostream>
#include <string_view>

using namespace std;

static string input_filename;
static string output_filename = "via_sim.mosio";

static struct option long_opts[] = {
    { "input",         required_argument, 0, 'i' },
    { "output",        required_argument, 0, 'o' },
    { "help",          no_argument,       0, 'h' },
    { 0,               0,                 0, 0   }
};

static void parse_args(int argc, char** argv) {
    int opt;
    int opt_ix = -1;
    while ((opt = getopt_long(argc, argv, "i:o:h", long_opts, &opt_ix)) != -1) {
        string val = optarg ? optarg : "";
        switch (opt) {
        case 'i':
            input_filename = val;
            break;
        case 'o':
            output_filename = val;
            break;
        case 'h':
            cout << "Usage: " << argv[0] << " [verilator-options] [options]" << R"(
Read lines of VIA communication (cycles R/W/I register/port/pin value)
from standard input.
Write a file to diff with to "via_sim.mosio" (default) or to specified file.)"
#if VM_TRACE == 1
                 << R"(
Write waveform dump to "via_core.fst".)"
#endif
                 << R"(

Options:
  -i, --input filename         Read from specified .mosio file.
  -o, --output filename        Write to specified .mosio file.
  -h, --help                   Display this information.
)";
            exit(EXIT_SUCCESS);
        default:
            goto help;
        }

        opt_ix = -1;
        continue;

    help:
        cerr << "Try '" << argv[0] << " --help' for more information." << endl;
        exit(EXIT_FAILURE);
    }
}


// The time between each edge of a 24MHz clock is 1/24Mz/2 = 20.833ns = 20833ps.
// In simulation a 4MHz clock is sufficient (two cycles between PHI2 edges),
// i.e. 1/4MHz/2 = 125ns between each edge.
const uint64_t timestep = 125;

static void clk(Vvia_core* core) {
    // Verilator doesn't automatically compute combinational logic before
    // sequential blocks are computed. Since our design clocks on the positive
    // edge of the FPGA clock, we can change non-clock inputs before the
    // negative edge of the input clock, saving a call to eval().
    core->clk = 0; core->eval();
    core->contextp()->timeInc(timestep);
    core->clk = 1; core->eval();
    core->contextp()->timeInc(timestep);
}

// In simulation a 4MHz FPGA clock is sufficient (2 cycles between PHI2 edges).
static void clk2(Vvia_core* core) {
    for (int i = 0; i < 2; i++) {
        clk(core);
    }
}

static bool phi2_hi = false;

static void phi1(Vvia_core* core) {
    core->bus_i &= ~(1LL << 36);  // PHI2 low
    core->bus_i |= (0b11LL << 32);  // Release /CS2 and /W
    clk(core);  // First half of PHI1
    phi2_hi = false;
}

static void phi2(Vvia_core* core) {
    if (phi2_hi) {
        cerr << "Error - phi2(core) called twice" << endl;
        exit(EXIT_FAILURE);
    }

    clk(core);  // Second half of PHI1
    core->bus_i |= (1LL << 36);  // PHI2 high
    clk2(core);
    phi2_hi = true;
}

static void read_reg(Vvia_core* core, int addr, int& val) {
    // Release /RES, set CS1, pull down /CS2, release /W
    core->bus_i = (core->bus_i & 0xfffffff) | (0b01101LL << 32) | (uint64_t(addr) << 28);
    phi2(core);
    val = (core->bus_o >> 38) & 0xff;
}

static void write_reg(Vvia_core* core, int addr, int data) {
    // Release /RES, set CS1, pull down /CS2, set /W
    core->bus_i = (core->bus_i & 0xfffff) | (0b01100LL << 32) | (uint64_t(addr) << 28) | (uint64_t(data) << 20);
    phi2(core);
}

static array<string, 3> ops = { "W", "R", "I" };
static array<string, 2> ports = { "PA", "PB" };
static array<string, 5> in_pins = { "CA1", "CA2", "CB1", "CB2", "RES" };
static array<string, 4> out_pins = { "IRQ", "CA2", "CB1", "CB2" };

static void write_pin(Vvia_core* core, int ix_pin, int& val) {
    val = (core->bus_o >> ix_pin) & 1;
}

static void read_pin(Vvia_core* core, int ix_pin, int val) {
    if (ix_pin == 4) {  // RES
        core->bus_i = (core->bus_i & ~(1LL << 35)) | (uint64_t(val) << 35);
    } else {
        int o = ix_pin + 2;
        if (ix_pin == 1) {  // CA2
            // Read pulled down output back in.
            val = ((core->bus_o >> o) & 1) & val;
        } else if (ix_pin == 2 || ix_pin == 3) {  // CB1 or CB2
            // Read output back in, otherwise input.
            uint8_t ddr = (core->bus_o >> (o - 3));
            val = (((core->bus_o >> o) & ddr) | (val & ~ddr)) & 1;
        }
        core->bus_i = (core->bus_i & ~(1LL << ix_pin)) | (uint64_t(val) << ix_pin);
    }
}

static void write_port(Vvia_core* core, int ix_port, int& val) {
    int o = ix_port == 0 ? 22 : 30;  // PA or PB
    val = (core->bus_o >> o) & 0xff;
}

static void read_port(Vvia_core* core, int ix_port, int val) {
    int i, o;
    bool open_drain;
    if (ix_port == 0) {  // PA
        i = 4;
        o = 22;
        open_drain = true;
    } else {  // PB
        i = 12;
        o = 30;
        open_drain = false;
    }

    // Read output bits back in, other bits from input.
    uint8_t ddr = core->bus_o >> (o - 16);
    uint8_t in = open_drain ?
        ((core->bus_o >> o) | ~ddr) & val :
        ((core->bus_o >> o) & ddr) | (val & ~ddr);
    core->bus_i = (core->bus_i & ~(0xffLL << i)) | (uint64_t(in) << i);
}


static bool irq_n_prev = true;

static bool interrupt(Vvia_core* core) {
    bool irq_n = core->bus_o & 1;
    bool irq = irq_n_prev && !irq_n;
    irq_n_prev = irq_n;
    return irq;
}

void input_error(int lineno, string msg, string input) {
    cerr << (input_filename.empty() ? "stdin" : input_filename) << " line " << lineno << ": " << msg << " in input \"" << input << "\"" << endl;
    exit(EXIT_FAILURE);
}

int parse_line(int lineno, string& line, int& cycles, int& ix_op, string& addr_name, int& addr, int& data) {
    string op, val;
    istringstream lineio(line);
    lineio >> cycles >> op >> addr_name >> val >> ws;
    if (!lineno) {
        input_error(lineno, "Bad format", line);
    }

    // Operation: W/R/I
    auto it = ranges::find(ops, op);
    if (it == ops.end()) {
        input_error(lineno, "Invalid operation", line);
    }
    ix_op = distance(ops.begin(), it);

    // Value
    const char* last = val.data() + val.size();
    auto [ptrd, ecd] = from_chars(val.data(), last, data, 16);
    if (ecd != std::errc{} || ptrd != last) {
        input_error(lineno, "Invalid value", line);
    }

    // Addressed element.
    // Try parsing as register address.
    last = addr_name.data() + addr_name.size();
    auto [ptra, eca] = from_chars(addr_name.data(), last, addr, 16);
    if (addr_name.size() == 1 && eca == std::errc{} && ptra == last) {
        if (addr < 0x0 || addr > 0xF || (ix_op == 2 && addr != 0xD)) {
            input_error(lineno, "Invalid address", line);
        }
        if (data < 0x0 || data > 0xFF) {
            input_error(lineno, "Invalid value", line);
        }

        // Register
        return 0;
    }

    // Not a register address, try port names.
    it = ranges::find(ports, addr_name);
    if (it != ports.end()) {
        addr = distance(ports.begin(), it);
        if (data < 0x0 || data > 0xFF) {
            input_error(lineno, "Invalid value", line);
        }
        // Port
        return 1;
    }

    // Not a port, try input/output pin names.
    if (ix_op == 0) {
        // Write
        it = ranges::find(out_pins, addr_name);
        if (it != out_pins.end()) {
            addr = distance(out_pins.begin(), it);
            if (data < 0 || data > 1) {
                input_error(lineno, "Invalid value", line);
            }
            // Output pin
            return 2;
        }
    } else if (ix_op == 1) {
        // Read
        it = ranges::find(in_pins, addr_name);
        if (it != in_pins.end()) {
            addr = distance(in_pins.begin(), it);
            if (data < 0 || data > 1) {
                input_error(lineno, "Invalid value", line);
            }
            // Input pin
            return 3;
        }
    }

    input_error(lineno, "Invalid pin/port name", line);
    exit(EXIT_FAILURE);
}

int main(int argc, char** argv, char** env) {
#if VM_TRACE == 1
    Verilated::traceEverOn(true);
#endif
    Verilated::commandArgs(argc, argv);

    parse_args(argc, argv);

    // Skip over "+verilator+" arguments.
    while (optind < argc && strncmp(argv[optind], "+verilator+", 11) == 0) {
        optind++;
    }

    if (optind < argc) {
        cerr << argv[0]
             << ": unrecognized argument '" << argv[optind] << "'" << endl;
        cerr << "Try '" << argv[0] << " --help' for more information." << endl;
        return EXIT_FAILURE;
    }

    if (input_filename.empty() && isatty(fileno(stdin))) {
        cerr << argv[0] << ": standard input is a terminal." << endl;
        return EXIT_FAILURE;
    }

    auto core = new Vvia_core;

    core->clk   = 0;
    core->rst   = 0;
    core->bus_i = 0;
    core->bus_i |= (0b1111LL << 32);  // Release /RES, set CS, release /CS2 and /W

    auto fin = input_filename.empty() ? ifstream() : ifstream(input_filename);
    if (!fin) {
        cerr << "Error opening " << input_filename << ": " << strerror(errno) << endl;
        return EXIT_FAILURE;
    }
    auto& in = input_filename.empty() ? cin : fin;
    auto out = ofstream(output_filename);

    string line;
    constexpr const char* fmt = "{} {} {} {:02X}\n";
    constexpr const char* fmt_pin = "{} {} {} {}\n";
    //constexpr string_view fmt{"{} {} {} {:02X}"};

    // First half cycle.
    phi1(core);

    int cycles_spent = 0;
    for (int lineno = 1; getline(in, line); lineno++) {
        int cycles, ix_op, addr, data;
        string addr_name;
        int obj = parse_line(lineno, line, cycles, ix_op, addr_name, addr, data);

        for (int i = 0; i < cycles; i++) {
            if (!phi2_hi) {
                phi2(core);
            }
            if (interrupt(core)) {
                out << format(fmt, cycles_spent + i, "I", "D", core->ifr);
                cycles_spent = 0;
                cycles -= i;
                i = 0;
            }
            phi1(core);
        }

        // i == cycles
        if (obj == 0) {
            // Register
            if (ix_op < 2) {
                // Note that these functions call phi2(core)
                if (ix_op == 0) {
                    write_reg(core, addr, data);
                } else {
                    read_reg(core, addr, data);
                }
                out << format(fmt, cycles_spent + cycles, ops[ix_op], addr_name, data);
            } else {
                // Interrupt
                cycles_spent += cycles;
                continue;
            }
        } else if (obj == 1) {
            // Port
            if (ix_op == 0) {
                write_port(core, addr, data);
            } else {
                read_port(core, addr, data);
            }
            out << format(fmt, cycles_spent + cycles, ops[ix_op], addr_name, data);
        } else {
            // Pin
            if (ix_op == 0) {
                write_pin(core, addr, data);
            } else {
                read_pin(core, addr, data);
            }
            out << format(fmt_pin, cycles_spent + cycles, ops[ix_op], addr_name, data);
        }

        cycles_spent = 0;
    }

    // Check for any interrupt in the final half cycle.
    if (!phi2_hi) {
        phi2(core);
        if (interrupt(core)) {
            out << format(fmt, cycles_spent, "I", "D", core->ifr);
        }
    }

    out.close();

    core->final();
    delete core;

    return EXIT_SUCCESS;
}

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
// * RES, SP, CNT, TOD, FLAG: Pin input (R)
// * IRQ, SP, CNT, PC: Pin output (W)
//
// No processing is done for interrupts (I), however a line containing the ICR
// register address and value is output for every interrupt, in order to
// facilitate comparison with the input file.
//
// To run simulation on cia_gold.mosio, writing simulation output to diff with
// to cia_sim.mosio:
//
// sim_log/cia_sim < cia_gold.mosio  # Default output file is cia_sim.mosio
// sim_log/cia_sim -i cia_gold.mosio -o cia_sim.mosio
//
// To write a waveform dump for GTKWave or Surfer to the file cia_core.fst,
// and .mosio output to the default output file cia_sim.mosio:
//
// sim_trace/cia_sim < cia_gold.mosio
//

#include "Vcia_core.h"
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
static string output_filename = "cia_sim.mosio";
static uint64_t tod_frequency = 0; // In Hz
static uint64_t tod_timestep = 0;  // In picoseconds
static int cia_model = 1;  // MOS8521

static struct option long_opts[] = {
    { "input",         required_argument, 0, 'i' },
    { "output",        required_argument, 0, 'o' },
    { "tod-frequency", required_argument, 0, 'f' },
    { "cia-model",     required_argument, 0, 'm' },
    { "help",          no_argument,       0, 'h' },
    { 0,               0,                 0, 0   }
};

static void parse_args(int argc, char** argv) {
    int opt;
    int opt_ix = -1;
    while ((opt = getopt_long(argc, argv, "i:o:f:m:h", long_opts, &opt_ix)) != -1) {
        string val = optarg ? optarg : "";
        switch (opt) {
        case 'i':
            input_filename = val;
            break;
        case 'o':
            output_filename = val;
            break;
        case 'f':
            try {
                tod_frequency = stoll(val);
                if (tod_frequency < 1 || tod_frequency > 1000000) {
                    goto fail;
                }
                tod_timestep = 1e12/tod_frequency/2;
            } catch (exception const&) {
                goto fail;
            }
            break;
        case 'm':
            if      (val == "6526") cia_model = 0;
            else if (val == "8521") cia_model = 1;
            else                    goto fail;
            break;
        case 'h':
            cout << "Usage: " << argv[0] << " [verilator-options] [options]" << R"(
Read lines of CIA communication (cycles R/W/I register/port/pin value)
from standard input.
Write a file to diff with to "cia_sim.mosio" (default) or to specified file.)"
#if VM_TRACE == 1
                 << R"(
Write waveform dump to "cia_core.fst".)"
#endif
                 << R"(

Options:
  -i, --input filename         Read from specified .mosio file.
  -o, --output filename        Write to specified .mosio file.
  -m, --cia-model {6526|8521}  Specify CIA model (default: 8521).
  -f, --tod-frequency Hz       Generate internal TOD signal (1 - 1M)Hz.
  -h, --help                   Display this information.
)";
            exit(EXIT_SUCCESS);
        default:
            goto help;
        }

        opt_ix = -1;
        continue;

    fail:
        cerr << argv[0]
             << ": option '"
             << (opt_ix != -1 ? "--" : "-")
             << (opt_ix != -1 ? string(long_opts[opt_ix].name) : string(1, (char)opt))
             << "' has invalid argument '" << val << "'"
             << endl;
    help:
        cerr << "Try '" << argv[0] << " --help' for more information." << endl;
        exit(EXIT_FAILURE);
    }
}


// 20.833ns = 20833ps between each edge of the 24MHz FPGA clock.
// In simulation a 4MHz clock is sufficient (2 cycles between PHI2 edges),
// i.e. 250ns between each edge.
const uint64_t timestep = 125;

uint64_t tod_count = 0;
bool tod_hi = false;

static void clk(Vcia_core* core) {
    // Verilator doesn't automatically compute combinational logic before
    // sequential blocks are computed. Since our design clocks on the positive
    // edge of the FPGA clock, we can change non-clock inputs before the
    // negative edge of the input clock, saving a call to eval().
    core->clk = 0; core->eval();
    core->contextp()->timeInc(timestep);
    core->clk = 1; core->eval();
    core->contextp()->timeInc(timestep);

    if (tod_timestep && (tod_count += 2*timestep) >= tod_timestep) {
        // Toggle TOD input.
        tod_hi = !tod_hi;
        tod_count -= tod_timestep;
        core->bus_i = (core->bus_i & ~(1LL << 2)) | (uint64_t(tod_hi) << 2);
    }
}

// In simulation a 4MHz FPGA clock is sufficient (2 cycles between PHI2 edges).
static void clk2(Vcia_core* core) {
    for (int i = 0; i < 2; i++) {
        clk(core);
    }
}

static bool phi2_hi = false;

static bool phi2(Vcia_core* core) {
    // Were we were already in phi2?
    bool rc = phi2_hi;

    if (!phi2_hi) {
        core->bus_i |= (1LL << 35);  // PHI2 high
        clk2(core);
        phi2_hi = true;
    }

    return rc;
}

static void phi1(Vcia_core* core) {
    core->bus_i &= ~(1LL << 35);  // PHI2 low
    clk2(core);
    core->bus_i |= (0b11LL << 32);  // Release /CS and /W
    phi2_hi = false;
}

static void read_reg(Vcia_core* core, int addr, int& val) {
    core->bus_i = (core->bus_i & 0xfffffff) | (0b1101LL << 32) | (uint64_t(addr) << 28);
    if (phi2(core)) {
        // We were already in phi2, so we must call eval() to set the address.
        core->eval();
        cerr << "already in phi2 on read" << endl;
    }
    val = (core->bus_o >> 36) & 0xff;
}

static void write_reg(Vcia_core* core, int addr, int data) {
    core->bus_i = (core->bus_i & 0xfffff) | (0b1100LL << 32) | (uint64_t(addr) << 28) | (uint64_t(data) << 20);
    if (phi2(core)) {
        // We were already in phi2, so we must call eval() to set the address / data.
        core->eval();
        cerr << "already in phi2 on write" << endl;
    }
    /*
    core->bus_i = (core->bus_i & 0xfffffff) | (0b1101LL << 32) | (uint64_t(addr) << 28);
    phi2(core);
    core->bus_i |= (uint64_t(data) << 20);
    */
}

static array<string, 3> ops = { "W", "R", "I" };
static array<string, 2> ports = { "PA", "PB" };
static array<string, 5> in_pins = { "SP", "CNT", "TOD", "FLAG", "RES" };
static array<string, 4> out_pins = { "IRQ", "SP", "CNT", "PC" };

static void write_pin(Vcia_core* core, int ix_pin, int& val) {
    val = (core->bus_o >> ix_pin) & 1;
}

static void read_pin(Vcia_core* core, int ix_pin, int val) {
    if (ix_pin == 4) {  // RES
        core->bus_i = (core->bus_i & ~(1LL << 34)) | (uint64_t(val) << 34);
    } else {
        if (ix_pin == 0 || ix_pin == 1) {  // SP or CNT
            // Read pulled down output back in.
            int o = ix_pin + 1;
            val = ((core->bus_o >> o) & 1) & val;
        }
        core->bus_i = (core->bus_i & ~(1LL << ix_pin)) | (uint64_t(val) << ix_pin);
    }
}

static void write_port(Vcia_core* core, int ix_port, int& val) {
    int o = ix_port == 0 ? 28 : 20;  // PA or PB

    // Only pull line down when DDR bit is set for output.
    val = ((core->bus_o >> o) | ~(core->bus_o >> (o - 16))) & 0xff;
    // val = (core->bus_o >> o) & 0xff;
}

static void read_port(Vcia_core* core, int ix_port, int val) {
    if (phi2_hi) {
        cerr << "already in phi2 on read_port" << endl;
    }
    int i, o;
    if (ix_port == 0) {  // PA
        i = 12;
        o = 28;
    } else {  // PB
        i = 4;
        o = 20;
    }

    /*
    // Read output bits back in, other bits from input.
    uint8_t ddr = core->bus_o >> (o - 16);
    uint8_t in = ((core->bus_o >> o) & ddr) | (val & ~ddr);
    core->bus_i = (core->bus_i & ~(0xffLL << i)) | (uint64_t(in) << i);
    */
    core->bus_i = (core->bus_i & ~(0xffLL << i)) | (uint64_t(val) << i);
}


static bool irq_n_prev = true;

static bool interrupt(Vcia_core* core, int& val) {
    bool irq_n = core->bus_o & 1;
    bool irq = irq_n_prev && !irq_n;
    irq_n_prev = irq_n;

    if (!irq) {
        return false;
    }

    // Read ICR register via debug-only port.
    val = core->icr;

    return true;
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
    if (eca == std::errc{} && ptra == last) {
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

    auto core = new Vcia_core;

    core->model = cia_model;
    core->clk   = 0;
    core->rst   = 0;
    core->bus_i = 0;
    core->bus_i |= (0b111LL << 32);  // Release /RES, /CS and /W
    core->bus_i |= 0b1011L; // Release /FLAG, CNT, and SP.

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

    int cycles_spent = 0;
    bool skip_cycle = false;
    for (int lineno = 1; getline(in, line); lineno++) {
        bool irq = false;
        int flags;
        int cycles, ix_op, addr, data;
        string addr_name;
        int obj = parse_line(lineno, line, cycles, ix_op, addr_name, addr, data);

        for (int i = 0; i < cycles;) {
            if (!skip_cycle) {
                phi2(core);
                phi1(core);
            }
            skip_cycle = false;
            i++;

            irq = interrupt(core, flags);
            if (irq && i < cycles) {
                out << format(fmt, cycles_spent + i, "I", "D", flags);
                cycles_spent = 0;
                cycles -= i;
                i = 0;
                irq = false;
            }
        }

        if (skip_cycle && (obj == 0 || ix_op > 0)) {
            input_error(lineno, "Previously skipped cycle", line);
        }

        // i == cycles
        if (obj == 0) {
            // Register
            if (ix_op < 2) {
                if (ix_op == 0) {
                    write_reg(core, addr, data);
                } else {
                    read_reg(core, addr, data);
                }
            } else {
                // Interrupt
                cycles_spent += cycles;
            }
        } else if (obj == 1) {
            // Port
            if (ix_op == 0) {
                // Currently not used.
                if (!skip_cycle) {
                    phi2(core);
                    phi1(core);
                    skip_cycle = true;
                }
                write_port(core, addr, data);
            } else {
                read_port(core, addr, data);
            }
        } else {
            // Pin
            if (ix_op == 0) {
                if (!skip_cycle) {
                    phi2(core);
                    phi1(core);
                    skip_cycle = true;
                }
                write_pin(core, addr, data);
            } else {
                read_pin(core, addr, data);
            }
        }

        if (ix_op < 2) {
            // Read or write.
            if (obj <= 1) {
                // Reg or port
                out << format(fmt, cycles_spent + cycles, ops[ix_op], addr_name, data);
            } else {
                // Pin
                out << format(fmt_pin, cycles_spent + cycles, ops[ix_op], addr_name, data);
            }
            cycles_spent = 0;
        }

        if (irq) {
            out << format(fmt, cycles_spent, "I", "D", flags);
            cycles_spent = 0;
        }
    }

    out.close();

    core->final();
    delete core;

    return EXIT_SUCCESS;
}

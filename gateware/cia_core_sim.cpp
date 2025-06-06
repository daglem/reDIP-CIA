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
// number of cycles to step before further processing:
//
// cycles R/W/I register/port/pin value
//
// Register/port/pin values:
// * 0-F: Register address (R/W/I)
// * PA, PB: Port input/output (R/W)
// * RES, SP, CNT, TOD, FLAG: Pin input (W)
// * IRQ, SP, CNT, PC: Pin output (R)
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
// In simulation an 8MHz clock is sufficient (4 cycles between PHI2 edges),
// i.e. 62.500ns = 62500ps between each edge.
const uint64_t timestep = 62500;

uint64_t tod_count = 0;
bool tod_hi = false;

static void clk(Vcia_core* core) {
    // Verilator doesn't automatically compute combinational logic before
    // sequential blocks are computed. Since our design clocks on the positive
    // edge of the FPGA clock, we can change non-clock inputs on the negative
    // edge of the input clock, saving a call to eval().
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

// In simulation an 8MHz FPGA clock is sufficient (4 cycles between PHI2 edges).
static void clk4(Vcia_core* core) {
    for (int i = 0; i < 4; i++) {
        clk(core);
    }
}

static void phi2(Vcia_core* core) {
    core->bus_i |= (1LL << 35);  // PHI2 high
    clk4(core);
}

static void phi1(Vcia_core* core) {
    core->bus_i &= ~(1LL << 35);  // PHI2 low
    clk4(core);
}

static void read(Vcia_core* core, uint8_t addr, uint8_t& val) {
    core->bus_i = (core->bus_i & 0xfffffff) | (0b1101LL << 32) | (uint64_t(addr) << 28);
    phi2(core);
    val = (core->bus_o >> 36) & 0xff;
    phi1(core);
    core->bus_i |= (1LL << 33);  // Release /CS
}

static void write(Vcia_core* core, uint8_t addr, uint8_t data) {
    core->bus_i = (core->bus_i & 0xfffff) | (0b1100LL << 32) | (uint64_t(addr) << 28) | (uint64_t(data) << 20);
    phi2(core);
    phi1(core);
    core->bus_i |= (0b11LL << 32);  // Release /CS and /W
}

string out_pins[] = { "IRQ", "SP", "CNT", "PC" };

static bool read_pin(Vcia_core* core, string& name, uint8_t& val) {
    int i = -1;
    for (auto pin_name : out_pins) {
        i++;
        if (name != pin_name) continue;
        val = (core->bus_o >> i) & 1;
        return true;
    }
    return false;
}

string in_pins[] = { "SP", "CNT", "TOD", "FLAG" };

static bool write_pin(Vcia_core* core, string& name, uint8_t val) {
    if (name == "RES") {
        core->bus_i = (core->bus_i & ~(1LL << 34)) | (uint64_t(val) << 34);
        return true;
    }

    int i = -1;
    for (auto pin_name : in_pins) {
        i++;
        if (name != pin_name) continue;
        if (name == "SP" || name == "CNT") {
            // Read pulled down output back in.
            int o = i + 1;
            val = ((core->bus_o >> o) & 1) & val;
        }
        core->bus_i = (core->bus_i & ~(1LL << i)) | (uint64_t(val) << i);
        return true;
    }
    return false;
}

static bool read_port(Vcia_core* core, string& name, uint8_t& val) {
    int o;
    if (name == "PA") {
        o = 28;
    } else if (name == "PB") {
        o = 20;
    } else {
        return false;
    }

    // Only pull line down when DDR bit is set for output.
    val = (core->bus_o >> o) | ~(core->bus_o >> (o - 16));
    return true;
}

static bool write_port(Vcia_core* core, string& name, uint8_t val) {
    int i, o;
    if (name == "PA") {
        i = 12;
        o = 28;
    } else if (name == "PB") {
        i = 4;
        o = 20;
    } else {
        return false;
    }

    // Read output bits back in, other bits from input.
    uint8_t ddr = core->bus_o >> (o - 16);
    uint8_t in = ((core->bus_o >> o) & ddr) | (val & ~ddr);
    core->bus_i = (core->bus_i & ~(0xffLL << i)) | (uint64_t(in) << i);
    return true;
}


static bool irq_n_prev = true;

static bool interrupt(Vcia_core* core, string& addr, uint8_t& val) {
    bool irq_n = core->bus_o & 1;
    bool irq = irq_n_prev && !irq_n;
    irq_n_prev = irq_n;

    if (!irq) {
        return false;
    }

    // Read ICR register via debug-only port.
    addr = "D";
    val = core->icr;

    return true;
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
    // Reset
    core->rst = 1;
    phi2(core);
    phi1(core);
    core->rst = 0;

    auto fin = input_filename.empty() ? ifstream() : ifstream(input_filename);
    auto& in = input_filename.empty() ? cin : fin;
    auto out = ofstream(output_filename);

    string line;
    constexpr const char* fmt = "{} {} {} {:02X}\n";
    constexpr const char* fmt_pin = "{} {} {} {}\n";
    //constexpr string_view fmt{"{} {} {} {:02X}"};

    int skip_cycle = 0;
    int cycles_left = 0;
    for (int lineno = 1; getline(in, line); lineno++) {
        int cycles;
        string op, addr, val;

        istringstream lineio(line);
        lineio >> cycles >> op >> addr >> val >> ws;

        int cycles_spent = 0;
        for (int i = 0; i < cycles; i++) {
            if (!skip_cycle) {
                phi2(core);
                phi1(core);
            }
            skip_cycle = 0;

            string icr;
            uint8_t flags;
            if (interrupt(core, icr, flags)) {
                out << format(fmt, i + 1 - cycles_spent, "I", icr, flags);
                cycles_spent = i + 1;
            }
        }
        cycles -= cycles_spent;

        if (op == "I") {
            cycles_left = cycles;
            continue;
        } else if (op != "R" && op != "W") {
            cerr << "Invalid operation in line " << lineno << ": " << op << endl;
            exit(EXIT_FAILURE);
        }

        cycles += cycles_left;
        cycles_left = 0;

        uint8_t data{};
        const char* last = val.data() + val.size();
        auto [ptrd, ecd] = from_chars(val.data(), last, data, 16);
        if (ecd != std::errc{} || ptrd != last) {
            cerr << "Invalid value in line " << lineno << ": " << val << endl;
            exit(EXIT_FAILURE);
        }

        uint8_t reg;
        last = addr.data() + addr.size();
        auto [ptra, eca] = from_chars(addr.data(), last, reg, 16);
        if (eca == std::errc{} && ptra == last) {
            if (reg < 0x0 || reg > 0xF) {
                cerr << "Invalid address in line " << lineno << ": " << addr << endl;
                exit(EXIT_FAILURE);
            }
            if (data < 0x0 || data > 0xFF) {
                cerr << "Invalid value in line " << lineno << ": " << val << endl;
                exit(EXIT_FAILURE);
            }

            if (op == "R") {
                read(core, reg, data);
            } else if (op == "W") {
                write(core, reg, data);
            }

            line = format(fmt, cycles, op, addr, data);

            // read()/write() steps one cycle; adjust for that in the next line.
            skip_cycle = 1;
        } else {
            // Assume pin or port name.
            bool port = addr == "PA" || addr == "PB";
            uint8_t maxval = port ? 0xFF : 1;
            if (data < 0 || data > maxval) {
                cerr << "Invalid value in line " << lineno << ": " << val << endl;
                exit(EXIT_FAILURE);
            }

            if (op == "R") {
                if (!read_pin(core, addr, data) && !read_port(core, addr, data)) {
                    cerr << "Invalid pin/port name in line " << lineno << ": " << addr << endl;
                    exit(EXIT_FAILURE);
                }
            } else {
                if (!write_pin(core, addr, data) && !write_port(core, addr, data)) {
                    cerr << "Invalid pin/port name in line " << lineno << ": " << addr << endl;
                    exit(EXIT_FAILURE);
                }
            }

            if (port) {
                line = format(fmt, cycles, op, addr, data);
            } else {
                line = format(fmt_pin, cycles, op, addr, data);
            }
        }

        out << line;
    }

    out.close();

    core->final();
    delete core;

    return EXIT_SUCCESS;
}

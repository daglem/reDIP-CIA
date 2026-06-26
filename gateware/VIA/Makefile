TOP = redip_via
PKG = via_pkg.sv
MOD = $(TOP).sv \
	../ice40_init.sv \
	via_io.sv \
	via_edgedet.sv \
	via_ports.sv \
	via_timers.sv \
	via_serial.sv \
	via_interrupt.sv \
	via_control.sv \
	via_core.sv

CELLS_SIM = \
	../cells_sim/SB_HFOSC.v \
	../cells_sim/SB_IO.v \
	../cells_sim/SB_WARMBOOT.v

SRC = $(PKG) $(MOD)

all: $(TOP).bin

lint:
	verilator --lint-only -I.. -I../cells_sim -Wall -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wno-PROCASSINIT -Wpedantic +systemverilogext+sv $(FLG) $(PKG) $(TOP).sv --top $(TOP)

lint-slang:
	slang --lint-only --single-unit -y. -y.. -y../cells_sim -Wconversion -Wextra -Wparentheses -Wpedantic -Wunused -Wno-implicit-net-port -Wno-unconnected-port $(FLG) $(PKG) $(TOP).sv -top $(TOP)

$(TOP).json: $(SRC) Makefile
	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); synth_ice40 -device u -dff -top $(TOP) -json $@'

%.asc: %.json %.pcf
	nextpnr-ice40 --u1k --package sg48 --freq 24 --json $*.json --pcf $*.pcf --asc $@

%.bin: %.asc
	icepack $< $@

prog: $(TOP).bin
	iceprog $<

sim:
	verilator --Mdir sim_trace -DVM_TRACE -Wno-CASEINCOMPLETE --timescale "1us/1ns" --trace-fst --trace-structs --trace-underscore --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build via_pkg.sv via_core.sv --top via_core via_core_sim.cpp -o via_sim
	verilator --Mdir sim_log $(SIM_OPTS) -Wno-CASEINCOMPLETE --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build via_pkg.sv via_core.sv --top via_core via_core_sim.cpp -o via_sim

clean:
	rm -rf $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_log obj_dir a.out

.PHONY: all prog clean

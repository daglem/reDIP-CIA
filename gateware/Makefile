TOP = redip_cia
PKG = cia_pkg.sv
MOD = $(TOP).sv \
	ice40_init.sv \
	bcd_add.sv \
	bcd_update.sv \
	cia_io.sv \
	cia_negedge.sv \
	cia_ports.sv \
	cia_timer.sv \
	cia_tod.sv \
	cia_serial.sv \
	cia_interrupt.sv \
	cia_control.sv \
	cia_core.sv

MOS6526 ?= 0
ifeq "$(MOS6526)" "1"
FLG += -DMOS6526
endif

SRC = $(PKG) $(MOD)

all: $(TOP).bin

lint:
	verilator --lint-only -Icells_sim -Wall -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wpedantic +systemverilogext+sv $(FLG) $(PKG) $(TOP).sv --top $(TOP)

lint-slang:
	slang --lint-only -y. -ycells_sim -Wconversion -Wextra -Wparentheses -Wpedantic -Wunused -Wno-implicit-net-port -Wno-unconnected-port -Wno-useless-cast $(FLG) $(PKG) $(TOP).sv -top $(TOP)

$(TOP).json: $(SRC) Makefile
	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); scratchpad -copy abc9.script.flow3 abc9.script; synth_ice40 -abc9 -abc2 -device u -top $(TOP) -json $@'
#	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); synth_ice40 -abc9 -device u -dff -top $(TOP) -json $@'

%.asc: %.json %.pcf
	nextpnr-ice40 --u1k --package sg48 --freq 24 --json $*.json --pcf $*.pcf --asc $@

%.bin: %.asc
	icepack $< $@

prog: $(TOP).bin
	iceprog $<

sim:
	verilator --Mdir sim_trace -DVM_TRACE -Wno-CASEINCOMPLETE --timescale "1us/1ps" --trace-fst --trace-structs --trace-underscore --clk clk --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build -Icells_sim cia_pkg.sv cia_core.sv --top cia_core cia_core_sim.cpp -o cia_sim
	verilator --Mdir sim_log -Wno-CASEINCOMPLETE --clk clk --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build -Icells_sim cia_pkg.sv cia_core.sv --top cia_core cia_core_sim.cpp -o cia_sim

clean:
	rm -rf $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_log

.PHONY: all prog sim clean

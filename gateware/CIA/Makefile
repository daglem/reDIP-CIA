TOP = redip_cia
PKG = cia_pkg.sv
MOD = $(TOP).sv \
	../ice40_init.sv \
	bcd_add.sv \
	bcd_update.sv \
	cia_spi.sv \
	cia_config.sv \
	cia_io.sv \
	cia_edgedet.sv \
	cia_ports.sv \
	cia_timer.sv \
	cia_tod.sv \
	cia_cnt.sv \
	cia_serial.sv \
	cia_interrupt.sv \
	cia_control.sv \
	cia_core.sv

CELLS_SIM = \
	../cells_sim/SB_HFOSC.v \
	../cells_sim/SB_IO.v \
	../cells_sim/SB_WARMBOOT.v

ifneq ($(origin CIA_MODEL), undefined)
  FLG += -DCIA_MODEL=$(CIA_MODEL)
else
  # Disable final deep-sleep SPI flash command
  ICEPACK_FLG = -s
endif

ifneq ($(origin NO_MOS8520), undefined)
  FLG += -DNO_MOS8520
endif

SRC = $(PKG) $(MOD)

all: $(TOP).bin

lint:
	verilator --lint-only -I.. -I../cells_sim -Wall -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wno-PROCASSINIT -Wpedantic +systemverilogext+sv $(FLG) $(PKG) $(TOP).sv --top $(TOP)

lint-slang:
	slang --lint-only --single-unit -y. -y.. -y../cells_sim -Wconversion -Wextra -Wparentheses -Wpedantic -Wunused -Wno-implicit-net-port -Wno-unconnected-port -Wno-useless-cast $(FLG) $(PKG) $(TOP).sv -top $(TOP)

$(TOP).json: $(SRC) Makefile
	yosys -p 'read_verilog -sv $(FLG) $(PKG) $(MOD); synth_ice40 -device u -dff -top $(TOP) -json $@'

%.asc: %.json %.pcf
	nextpnr-ice40 --u1k --package sg48 --freq 24 --json $*.json --pcf $*.pcf --asc $@

%.bin: %.asc
	icepack $(ICEPACK_FLG) $< $@

prog: $(TOP).bin
	iceprog $<

SIM_EMULATOR ?= 0
ifeq "$(SIM_EMULATOR)" "1"
SIM_OPTS = -DTOD_PHI20_NODELAY -DTOD_INT_NODELAY
endif

sim:
	verilator --Mdir sim_trace $(SIM_OPTS) -DVM_TRACE -Wno-CASEINCOMPLETE --timescale "1us/1ns" --trace-fst --trace-structs --trace-underscore --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build cia_pkg.sv cia_core.sv --top cia_core cia_core_sim.cpp -o cia_sim
	verilator --Mdir sim_log $(SIM_OPTS) -Wno-CASEINCOMPLETE --cc -O3 -CFLAGS "--std=c++20 -Wall" --x-assign fast --x-initial 0 --noassert --exe --build cia_pkg.sv cia_core.sv --top cia_core cia_core_sim.cpp -o cia_sim

# NB! Doesn't simulate correctly due to missing support for inout ports in Verilator.
test-config:
	verilator -I.. -I../cells_sim -DTESTBENCH -Wall -Wno-VARHIDDEN -Wno-CASEINCOMPLETE -Wno-PROCASSINIT --pins-inout-enables --binary --timescale "1ns/1ns" --trace-fst --trace-structs --trace-underscore --top cia_config_tb cia_pkg.sv cia_config_tb.sv && obj_dir/Vcia_config_tb

# NB! Currently requires changing several always_comb to assign in order to avoid compilation errors.
test-config-iverilog:
	iverilog -g2023 -DTESTBENCH -c <(echo +timescale+1ns/1ns) -s cia_config_tb $(PKG) $(CELLS_SIM) $(MOD) cia_config_tb.sv && vvp a.out

clean:
	rm -rf $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_log obj_dir a.out

.PHONY: all prog sim clean

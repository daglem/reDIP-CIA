TOP = redip_pia
PKG = pia_pkg.sv
MOD = $(TOP).sv \
	../ice40_init.sv \
	pia_io.sv \
	pia_edgedet.sv \
	pia_ports.sv \
	pia_core.sv

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

clean:
	rm -rf $(TOP).json $(TOP).asc $(TOP).bin sim_trace sim_log obj_dir a.out

.PHONY: all prog clean

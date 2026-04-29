all: cia-config.prg

%.prg: %.asm
	64tass -C -a -i $< -o $@

clean:
	rm cia-config.prg

.PHONY: all clean

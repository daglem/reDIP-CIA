# reDIP CIA gateware

## Description

The reDIP CIA FPGA gateware provides cycle exact CIA emulation for the
[reDIP CIA](https://github.com/daglem/reDIP-CIA) hardware.

The gateware implementation is based on the excellent schematics of the
[MOS 8520](https://6502.org/forum/viewtopic.php?f=4&t=7368) and
[MOS 8521](https://6502.org/forum/viewtopic.php?f=4&t=7418) chips provided by
Frank "androSID" Wolf and Dieter "ttlworks" Müller.

By default, emulation of MOS 6526/8521 and MOS 8520 CIA chips is configurable
via [software](/software/), initially
configured as MOS 8521.

The emulation can alternatively be locked down at build time via one of

* `make MOS6526`
* `make MOS8521`
* `make MOS8520`

With projects in mind which use the reDIP CIA core gateware as part of a larger
whole to emulate the Commmodore 64, there is also an option to disable code for
the MOS 8520 (used in Commodore Amiga computers and 1581 disk drives). This
frees up some FPGA resources:

* `make NO_MOS8520`

## Installation

The gateware is built via `make` (see above) and may be installed on the reDIP
CIA hardware e.g. using an
[FTDI cable](https://ftdichip.com/products/c232hm-ddhsl-0-2/).

The gateware can be installed via `make prog`, which programs the on-board
flash chip via `iceprog`. Note that this makes configurable gateware generated
by `make` or `make NO_MOS8520` default to MOS 8521. The default can
alternatively be specified via one of

* `make prog-MOS6526`  # C64, SX-64, Ultimax
* `make prog-MOS8521`  # C64, C128, 1570, 1571
* `make prog-MOS8520`  # Amiga, 1581

## License

This gateware is part of reDIP CIA, a MOS 6526/8520/8521 CIA FPGA emulation
platform.\
Copyright (C) 2025 - 2026  Dag Lem \<resid@nimrod.no\>

The source describes Open Hardware and is licensed under the CERN-OHL-S v2.

You may redistribute and modify the source and make products using it under
the terms of the [CERN-OHL-S v2](https://ohwr.org/cern_ohl_s_v2.txt).

This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.

Source location:
[https://github.com/daglem/reDIP-CIA](https://github.com/daglem/reDIP-CIA)

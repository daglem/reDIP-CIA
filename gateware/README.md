# reDIP CIA gateware

## Description

The reDIP CIA FPGA gateware provides cycle exact CIA emulation for the
[reDIP CIA](https://github.com/daglem/reDIP-CIA) hardware.

The gateware implementation is based on the excellent schematics of the
[MOS 8520](https://6502.org/forum/viewtopic.php?f=4&t=7368) and
[MOS 8521](https://6502.org/forum/viewtopic.php?f=4&t=7418) chips provided by
Frank "androSID" Wolf and Dieter "ttlworks" Müller.

By default, the MOS 8521 chip is emulated. The gateware can also be configured
for MOS 6526 and (untested!) MOS 8520 emulation via `make CIA_MODEL=MOS6526`
and `make CIA_MODEL=MOS8520`, respectively.

## Installation

The gateware is built via `make` and may be installed on the reDIP CIA hardware
e.g. via `make prog` using an
[FTDI cable](https://ftdichip.com/products/c232hm-ddhsl-0-2/).

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

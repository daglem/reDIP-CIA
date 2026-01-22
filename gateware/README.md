# reDIP CIA gateware

## Description

The reDIP CIA FPGA gateware provides cycle exact CIA emulation for the
[reDIP CIA](https://github.com/daglem/reDIP-CIA) hardware.

The gateware implementation is based on the [excellent schematics](http://forum.6502.org/viewtopic.php?f=4&t=7418)
of the MOS 8521 chip provided by Frank "androSID" Wolf and Dieter "ttlworks" Müller.

By default, the MOS 8521 chip is emulated. The gateware also implements MOS
6526 emulation; this can be built via `make MOS6526=1`. Note however that the
6526 emulation is not yet accurate.

## Installation

The gateware is built via `make` and may be installed on the reDIP CIA hardware
e.g. via `make prog` using an [FTDI cable](https://ftdichip.com/products/c232hm-ddhsl-0-2/).

## License

This gateware is part of reDIP CIA, a MOS 6526/8521 CIA FPGA emulation platform.
Copyright (C) 2025 - 2026  Dag Lem \<resid@nimrod.no\>

The source describes Open Hardware and is licensed under the CERN-OHL-S v2.

You may redistribute and modify the source and make products using it under
the terms of the [CERN-OHL-S v2](https://ohwr.org/cern_ohl_s_v2.txt).

This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.

Source location: [https://github.com/daglem/reDIP-CIA](https://github.com/daglem/reDIP-CIA)

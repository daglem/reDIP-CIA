# reDIP CIA

## MOS 6520 PIA / MOS 6522 VIA / MOS 6526/8520/8521 CIA FPGA replacement
![Board](hardware/documentation/reDIP-CIA-board.png)

## Overview
The reDIP CIA is an open source FPGA board which combines the following in a
DIP-40 size package:

* Lattice iCE5LP1K FPGA
* 1Mbit FLASH
* 5V tolerant I/O

The reDIP CIA provides an open source hardware platform for MOS 6520 PIA /
MOS 6522 VIA / MOS 6526/8520/8521 CIA replacements.

Designs for the iCE5LP1K FPGA can be processed by
[yosys](https://github.com/YosysHQ/yosys/) and
[nextpnr](https://github.com/YosysHQ/nextpnr/).

## I/O interfaces

### DIP-40 header pins:

* 5V input
* 35 FPGA GPIO
* 3 FPGA open-drain I/O
* GND

All FPGA header I/O is 5V tolerant, and can drive 5V TTL.

### SPI / programming header:

A separate header footprint is provided for (Q)SPI flash programming, with
pinout borrowed from the
[iCEBreaker Bitsy](https://codeberg.org/icebreaker-fpga/icebreaker).

## MOS 6526/8521 and MOS 8520 CIA compatibility

The board is fully pin compatible with the venerable MOS 6526/8521 and MOS 8520
CIA chips.

Cycle accurate emulation of the MOS 6526/8521 and MOS 8520 CIA chips has been
implemented in [gateware](gateware/CIA/), configurable via [software](software/).

## MOS 6522 VIA compatibility

Cycle accurate emulation of the MOS 6522 VIA chip has been implemented in
[gateware](gateware/VIA/).

## MOS 6520 PIA compatibility

Cycle accurate emulation of the MOS 6520 VIA chip has been implemented in
[gateware](gateware/PIA/).

## Thanks

The gateware implementations would not have been possible without the
[outstanding work](https://6502.org/forum/viewtopic.php?t=7427) on varius MOS
chips by Frank "androSID" Wolf and Dieter "ttlworks" Müller.

Wagner Rodriguez has tested the 8520 CIA implementation with the [Versatile
Amiga Testprogram](https://aminet.net/package/util/misc/VATestprogram).

Mateusz Nalewajski has hunted down and fixed two bugs while working on
integrating the VIA gateware in
[icepi-zero-c64](https://github.com/m1nl/icepi-zero-c64).

André Fachat has tested the VIA and PIA implementations with his [PET PIA and
VIA test suite](https://github.com/fachat/pet_viapia_tests).

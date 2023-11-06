# reDIP CIA

## MOS 6520 PIA / MOS 6522 VIA / MOS 6526/8520/8521 CIA FPGA replacement
![Board](hardware/documentation/reDIP-CIA-board.png)

## Overview
The reDIP CIA is an open source FPGA board which combines the following in a DIP-40 size package:

* Lattice iCE5LP1K FPGA
* 1Mbit FLASH
* 5V tolerant I/O

The reDIP CIA provides an open source hardware platform for MOS 6520 PIA / MOS 6522 VIA / MOS 6526/8520/8521 CIA replacements.

Designs for the iCE5LP1K FPGA can be processed by [yosys](https://github.com/YosysHQ/yosys/) and [nextpnr](https://github.com/YosysHQ/nextpnr/).

## I/O interfaces

### DIP-40 header pins:

* 5V input
* 35 FPGA GPIO
* 3 FPGA open-drain I/O
* GND

All FPGA header I/O is 5V tolerant, and can drive 5V TTL.

### SPI / programming header:

A separate header footprint is provided for (Q)SPI flash programming, with pinout borrowed from the [iCEBreaker Bitsy](https://github.com/icebreaker-fpga/icebreaker).

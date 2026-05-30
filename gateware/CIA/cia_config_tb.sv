// ----------------------------------------------------------------------------
// This file is part of reDIP CIA, a MOS 6526/8520/8521 FPGA emulation platform.
// Copyright (C) 2026  Dag Lem <resid@nimrod.no>
//
// This source describes Open Hardware and is licensed under the CERN-OHL-S v2.
//
// You may redistribute and modify this source and make products using it under
// the terms of the CERN-OHL-S v2 (https://ohwr.org/cern_ohl_s_v2.txt).
//
// This source is distributed WITHOUT ANY EXPRESS OR IMPLIED WARRANTY,
// INCLUDING OF MERCHANTABILITY, SATISFACTORY QUALITY AND FITNESS FOR A
// PARTICULAR PURPOSE. Please see the CERN-OHL-S v2 for applicable conditions.
//
// Source location: https://github.com/daglem/reDIP-CIA
// ----------------------------------------------------------------------------

`default_nettype none

// A 24MHz clock implies a time step of 1/24MHz/2 = 20.833ns.
// We simulate a 25MHz clock by inverting ice40_init.clk24 every #20.
//
// `timescale 1ns/1ns

module cia_config_tb ();

    // Main signals
    wire PHI2, RES, CS, R_W;
    // Address inputs
    wire RS0, RS1, RS2, RS3;
    // Data bus inputs/outputs
    wire D0, D1, D2, D3, D4, D5, D6, D7;
    // I/O ports
    wire PA0, PA1, PA2, PA3, PA4, PA5, PA6, PA7;
    wire PB0, PB1, PB2, PB3, PB4, PB5, SPI_SIO1, SPI_SCLK;
    // Other signals
    wire SPI_SIO0, FLAG, TOD, CNT, SP, IRQ;
    // SPI CS
    wand SPI_CS;

    redip_cia redip_cia (
        PHI2, RES, CS, R_W,
        RS0, RS1, RS2, RS3,
        D0, D1, D2, D3, D4, D5, D6, D7,
        PA0, PA1, PA2, PA3, PA4, PA5, PA6, PA7,
        PB0, PB1, PB2, PB3, PB4, PB5, SPI_SIO1, SPI_SCLK,
        SPI_SIO0, FLAG, TOD, CNT, SP, IRQ,
        SPI_CS
    );

    logic phi2 = '0, cs_n = '1, r_w = '1;
    logic [3:0] addr;
    /* verilator lint_off UNUSEDSIGNAL */
    logic [7:0] data_i, data_o;
    /* verilator lint_on UNUSEDSIGNAL */

    assign PHI2 = phi2;
    assign RES = '1;
    assign CS = cs_n;
    assign R_W = r_w;
    assign { RS3, RS2, RS1, RS0 } = addr;
    assign { D7, D6, D5, D4, D3, D2, D1, D0 } = r_w ? 'z : data_o;
    assign data_i = { D7, D6, D5, D4, D3, D2, D1, D0 };

    logic spi_cs_n, spi_sclk, spi_si, spi_so;
    assign spi_cs_n = SPI_CS;
    assign spi_sclk = SPI_SCLK;
    assign spi_si = SPI_SIO0;
    assign SPI_SIO1 = spi_so;
    assign SPI_CS = '1;  // Pull-up

    logic [1:0] status;

    task read_status ();
        // @(posedge phi2);
        cs_n = '0;
        addr = 'hD;
        r_w = '1;
        @(negedge phi2);
        status = data_i[6:5];
        cs_n = '1;
    endtask

    task write_command (input string cmd);
        static byte c, b;

        @(posedge phi2);
        cs_n = '0;
        addr = 'hD;
        r_w = '0;

        for (int i = 0; i < cmd.len(); i++) begin
            c = cmd[i];
            b = (c >= 'h40 ? c - 'h40 : c - 'h30)*16;
            data_o = b;
            @(posedge phi2);
        end

        cs_n = '1;
        r_w = '1;
    endtask

    task flash_sample (output cia::reg8_t data);
        repeat (8) begin
            assert(~spi_cs_n);
            @(posedge spi_sclk);
            data = { data[6:0], spi_si };
        end
    endtask

    task flash_addr (output logic [23:0] addr);
        cia::reg8_t data;

        repeat (3) begin
            flash_sample(data);
            addr = { addr[15:0], data };
        end
    endtask

    task flash_shift (input cia::reg8_t data);
        repeat (8) begin
            assert(~spi_cs_n);
            @(negedge spi_sclk);
            { spi_so, data } = { data, 1'b0 };
        end
    endtask

    task flash ();
        cia::reg8_t cmd;
        logic [23:0] addr;
        cia::reg8_t model;
        cia::reg8_t status1;

        model = 'h55;  // Corrupt flash model byte.
        status1 = '0;   // Status register 1.

        forever begin
            @(negedge spi_cs_n);

            flash_sample(cmd);
            $write("Flash command: %02h", cmd);

            if (cmd == 'h02 || cmd == 'h03 || cmd == 'h20) begin
                flash_addr(addr);
                $write(" %06h", addr);
                assert(addr == 'h01f000);
            end

            case (cmd)
              'h02: begin
                  assert(status1[1]);  // Check WEL bit.
                  flash_sample(model);
                  status1[1] = '0;  // Clear WEL bit.
                  $write(" W %02h", model);
              end
              'h03: begin
                  flash_shift(model);
                  @(negedge spi_sclk);  // Extra cycle.
                  $write(" R %02h", model);
              end
              'h05: begin
                  status1[0] = '1;  // Set BUSY bit.
                  flash_shift(status1);
                  $write(" R %02h", status1);
                  status1[0] = '0;  // Clear BUSY bit.
                  flash_shift(status1);
                  $write(" %02h", status1);
                  @(negedge spi_sclk);  // Extra cycle.
              end
              'h06: begin
                  // Set WEL bit.
                  status1[1] = '1;
              end
              'h20: begin
                  assert(status1[1]);  // Check WEL bit.
                  model = '1;      // Erase (all 1s).
                  status1[1] = '0;  // Clear WEL bit.
                  $write(" E %02h", model);
              end
              default: begin
                  $error("Unknown command");
              end
            endcase

            $display;

            @(posedge spi_cs_n or posedge spi_sclk);
            assert(~spi_sclk);
            spi_so = '0;
        end
    endtask

    // A 1MHz clock implies a time step of 1/1MHz/2 = 500ns.
    always #500 phi2 = ~phi2;

    initial begin
        $dumpfile("cia_config.fst");
        $dumpvars;

        cs_n = '1;

        // Start flash chip emulation.
        fork
            flash();
        join_none;

        // Wait for release of reset.
        @(negedge redip_cia.rst_24);
        // Wait for initial read from flash to finish.
        repeat (4) @(negedge phi2);

        // Read CIA model (MOS8521).
        write_command("CFG0");
        read_status();
        $display("CIA model: %s", status == 1 ? "MOS6526" : status == 2 ? "MOS8521" : "MOS8520" );
        assert(status == 2);

        // Configure CIA model (MOS6526).
        write_command("CFG1");
        // Write to flash.
        write_command("CFG7");
        do read_status(); while (data_i[6:5] != '0);
        // Read from flash.
        write_command("CFG6");
        repeat (4) @(negedge phi2);
        read_status();
        $display("CIA model: %s", status == 1 ? "MOS6526" : status == 2 ? "MOS8521" : "MOS8520" );
        assert(status == 1);
        @(negedge phi2);

        $finish;
    end
endmodule

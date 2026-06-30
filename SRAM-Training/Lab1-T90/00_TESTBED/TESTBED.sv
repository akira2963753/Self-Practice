/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    TESTBED.sv
* Project:      SRAM-Training
* Module:       TESTBED.sv
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS, Verdi, Memory Compiler and Design Compiler
* Process:      TSMC 90nm
*
******************************************************************************/

module TESTBED();

    //=============================================================
    // ------------ Sim Mode & SDF Annotate & FSDB Dump -----------
    //=============================================================

    `ifdef GATE
        initial begin
            $display("======================================");
            $display("  [INFO] GATE-LEVEL SIMULATION START  ");
            $display("======================================");
            // 單獨測 SRAM 不用 SDF，他的時序資訊包含在 .v 檔裡面
        end
    `else
        initial begin
            $display("======================================");
            $display("  [INFO] BEHAVIORAL SIMULATION START  ");
            $display("======================================");
        end
    `endif

    initial begin
        $fsdbDumpfile("TESTBED.fsdb");
        $fsdbDumpvars(0, TESTBED, "+mda");
    end 

    //=============================================================
    // -------------------- Design & Pattern ----------------------
    //=============================================================
    
    parameter DEPTH = 256;
    parameter ADDR_W = $clog2(DEPTH);
    parameter DATA_W = 32;
    
    logic clk, en_w, en_r;
    logic [ADDR_W-1:0] addr_w, addr_r;
    logic [DATA_W-1:0] data_i, data_o;

    PATTERN #(
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W))
    u_PATTERN(
        .clk(clk),
        .en_w(en_w),
        .en_r(en_r),
        .addr_w(addr_w),
        .addr_r(addr_r),
        .data_i(data_i),
        .data_o(data_o));

    SRAM_DP_ADV u_SRAM(
        // Port A : Write
        .CLKA(clk),
        .CENA(~en_w), 
        .WENA(~en_w), 
        .AA(addr_w),
        .DA(data_i),
        .QA(),
        // Port B : Read
        .CLKB(clk),
        .CENB(~en_r), 
        .WENB(1'b1), 
        .AB(addr_r),
        .DB('b0),
        .QB(data_o),
        // Margin
        .EMAA(3'd0),
        .EMAB(3'd0));


endmodule

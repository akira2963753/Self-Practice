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
    
    parameter DEPTH = 128;
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
        .addr_w(addr_w),
        .en_r(en_r),
        .addr_r(addr_r),
        .data_i(data_i),
        .data_o(data_o));

    TS6N16ADFPCLLLVTA128X32M4FWSHOD u_SRAM(
        .CLKW(clk),
        .WEB(~en_w),
        .BWEB({DATA_W{~en_w}}),
        .AA(addr_w),
        .D(data_i),
        .CLKR(clk),
        .REB(~en_r),
        .AB(addr_r),
        .Q(data_o),
        .RCT(2'b01),
        .WCT(2'b01),
        .KP(3'b011),
        .SLP(1'd0),
        .DSLP(1'd0),
        .SD(1'd0),
        .PUDELAY());

endmodule

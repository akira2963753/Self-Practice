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
    parameter DATA_W = 64;
    
    logic clk, en_w, en_c;
    logic [ADDR_W-1:0] addr;
    logic [DATA_W-1:0] data_i, data_o;

    PATTERN #(
        .DEPTH(DEPTH),
        .ADDR_W(ADDR_W),
        .DATA_W(DATA_W))
    u_PATTERN(
        .clk(clk),
        .en_c(en_c),
        .en_w(en_w),
        .addr(addr),
        .data_i(data_i),
        .data_o(data_o));

    TS1N16ADFPCLLLVTA128X64M4SWSHOD u_SRAM(
        .CLK(clk),
        .CEB(en_c),
        .WEB(en_w),
        .A(addr),
        .D(data_i),
        .Q(data_o),
        .BWEB(64'hFFFF_FFFF_FFFF_FFFF),
        .SLP(1'd0),
        .DSLP(1'd0),
        .SD(1'd0),
        .PUDELAY(),
        .RTSEL(2'b01),
        .WTSEL(2'b01));

endmodule

/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    TESTBED.sv
* Project:      [Train] 2023 Spring IC LAB, Lab 7 - CDC
* Module:       TESTBED for CDC Design Verification
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/  

module TESTBED();

    parameter DSIZE = 8; 
    parameter ASIZE = 4;
    parameter WSIZE = $clog2(DSIZE);

    logic clk1, clk2, in_valid, out_valid, ready, rst_n;
    logic [4:0] doraemon_id;
    logic [DSIZE-1:0] size;
    logic [DSIZE-1:0] iq_score;
    logic [DSIZE-1:0] eq_score;
    logic [DSIZE-1:0] out;
    logic [WSIZE-1:0] size_weight, iq_weight, eq_weight;

    //=============================================================
    // ---------------- Sim Mode & SDF Annotate -------------------
    //=============================================================
    `ifdef GATE
        initial begin
            $display("======================================");
            $display("  [INFO] GATE-LEVEL SIMULATION START  ");
            $display("======================================");
            $sdf_annotate("../03_PT/CDC_SYN_pt.sdf", u_CDC, , ,"maximum");
        end
    `else
        initial begin
            $display("======================================");
            $display("  [INFO] BEHAVIORAL SIMULATION START  ");
            $display("======================================");
        end
    `endif

    //=============================================================
    // ------------------------ FSDB Dump -------------------------
    //=============================================================
    initial begin
        $fsdbDumpfile("TESTBED.fsdb");
        $fsdbDumpvars(0, TESTBED, "+mda");
    end 


    CDC u_CDC(
        .clk1(clk1),
        .clk2(clk2),
        .in_valid(in_valid),
        .rst_n(rst_n),
        .ready(ready),
        .out_valid(out_valid),
        .doraemon_id(doraemon_id),
        .size(size),
        .iq_score(iq_score),
        .eq_score(eq_score),
        .out(out),
        .size_weight(size_weight),
    	.iq_weight(iq_weight),
    	.eq_weight(eq_weight));
    
    PATTERN u_PATTERN(
        .clk1(clk1),
        .clk2(clk2),
        .in_valid(in_valid),
        .rst_n(rst_n),
        .ready(ready),
        .out_valid(out_valid),
        .doraemon_id(doraemon_id),
        .size(size),
        .iq_score(iq_score),
        .eq_score(eq_score),
        .out(out),
        .size_weight(size_weight),
    	.iq_weight(iq_weight),
    	.eq_weight(eq_weight));

endmodule
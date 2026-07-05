/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    TESTBED.sv
* Project:      Clock Domain Crossing
* Module:       TESTBED
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

module TESTBED();

    //=============================================================
    // ---------------- Sim Mode & SDF Annotate -------------------
    //=============================================================
    `ifdef GATE
        initial begin
            $display("======================================");
            $display("  [INFO] GATE-LEVEL SIMULATION START  ");
            $display("======================================");
            $sdf_annotate("../02_SYN/Netlist/Handshaker_syn.sdf", u_dut, , ,"maximum");
        end
    `else
        initial begin
            $display("======================================");
            $display("  [INFO] BEHAVIORAL SIMULATION START  ");
            $display("======================================");
        end
    `endif

    //=============================================================
    // ------------------------- FSDB Dump ------------------------
    //=============================================================
    initial begin
        $fsdbDumpfile("TESTBED.fsdb");
        $fsdbDumpvars(0, TESTBED, "+mda");
    end

    //=============================================================
    // --------------------- Desgin & Pattern ---------------------
    //=============================================================
    logic sclk, dclk, rst_n;
    logic [31:0] din;
    logic svalid;
    logic dbusy;
    logic sready;
    logic dvalid;
    logic [31:0] dout;

    PATTERN u_pattern (
        .sclk(sclk),
        .dclk(dclk),
        .rst_n(rst_n),
        .din(din),
        .svalid(svalid),
        .dbusy(dbusy),
        .sready(sready),
        .dvalid(dvalid),
        .dout(dout)
    );

    Handshaker u_dut (
        .sclk(sclk),
        .dclk(dclk),
        .rst_n(rst_n),
        .din(din),
        .svalid(svalid),
        .dbusy(dbusy),
        .sready(sready),
        .dvalid(dvalid),
        .dout(dout)
    );

	 //============================================================
    // ----------------------- CHECKER ----------------------------
    //=============================================================
    `ifdef SVA
        `ifdef GATE 
            // 用 bind 把 Handshaker 內部訊號送到 Checker 中
            bind Handshaker CHECKER u_checker (
                .sclk(sclk),
                .dclk(dclk),
                .rst_n(rst_n),
                .sready(sready),
                .dvalid(dvalid),
                .dbusy(dbusy),
                .dout(dout),
                .sreq(),
                .dreq(),
                .sack(),
                .dack());
        `else
            // 用 bind 把 Handshaker 內部訊號送到 Checker 中
            bind Handshaker CHECKER u_checker (
                .sclk(sclk),
                .dclk(dclk),
                .rst_n(rst_n),
                .sready(sready),
                .dvalid(dvalid),
                .dbusy(dbusy),
                .dout(dout),
                .sreq(sreq),
                .dreq(dreq),
                .sack(sack),
                .dack(dack));
        `endif
    `endif 

endmodule
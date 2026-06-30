/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    testfixture.sv
* Project:      SRAM-Training
* Module:       TESTBED
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS, Verdi, Memory Compiler and Design Compiler
* Process:      TSMC 90nm
*
******************************************************************************/
`define CLK_PERIOD  3.0


module PATTERN #(
    parameter DEPTH = 256,
    parameter ADDR_W = $clog2(DEPTH),
    parameter DATA_W = 32)(
    output logic clk,
    output logic en_w,
    output logic en_r,
    output logic [ADDR_W-1:0] addr_w,
    output logic [ADDR_W-1:0] addr_r,
    output logic [DATA_W-1:0] data_i,
    input [DATA_W-1:0] data_o);

    //=============================================================
    // ------------------- Clock Generate -------------------------
    //=============================================================
    
    always #(`CLK_PERIOD / 2.0) clk = ~clk;
    
    //=============================================================
    // ---------------- Parameters & Integers ---------------------
    //=============================================================
    
    int seed = 7;

    //=============================================================
    // --------------------- Internal Signals ---------------------
    //=============================================================
    
    logic [DATA_W-1:0] golden_mem [0:DEPTH]; 

    //=============================================================
    // ---------------------- Main Flow ---------------------------
    //=============================================================
    
    initial begin
        reset_task();
        test1_task();
        end_task();
    end

    //=============================================================
    // ------------------------ Tasks -----------------------------
    //=============================================================

    task reset_task;
        begin
           force clk = 0;
           en_w = 0;
           en_r = 0;
           addr_w = 0;
           addr_r = 0;
           data_i = 'dx;
           #20;
           release clk;
           $info("[RESET] Reset All Pattern Signal.");
        end
    endtask

    task test1_task;
        begin
            // Generate Input
            @(negedge clk);
            for(int i = 0; i < DEPTH; i++) begin
                data_i = $unsigned($random(seed)) % 32'd256;
                en_w = 1;
                golden_mem[addr_w] = data_i;
                @(negedge clk);
                addr_w = addr_w + 1;
            end
            data_i = 0;
            en_w = 0;
            addr_w = 0;
            $info("[TEST-CASE 01] Input Task Finish.");
            
            // Read Output and Check
            for(int i = 0; i < DEPTH; i++) begin
                en_r = 1;
                @(negedge clk);
                // Check Output Result
                CHECK_OUT_VALUE: assert (data_o===golden_mem[addr_r]) 
                else $fatal(1, "[TEST-CASE 01] Out mismatch. golden = %0d, read = %0d at address %0d"
                        , golden_mem[addr_r], data_o, addr_r);
                addr_r = addr_r + 1;
            end
            en_r = 0;
            addr_r = 0;
            $info("[TEST-CASE 01] Ouput Read Task Finish.");
        end
    endtask

    task end_task;
        begin
            #10;
            $display("====================================");
            $display("  [SUCCESS] ALL PATTERN PASS ! ! !  ");
            $display("====================================");
            #10 $finish; 
        end
    endtask

endmodule
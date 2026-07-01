/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      [Train] 2023 Spring IC LAB, Lab 7 - CDC
* Module:       PATTERN for CDC Design Verification
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

`ifdef GATE
	`define CLK_PERIOD_1 15.5
	`define CLK_PERIOD_2 18.3
`else
	`define CLK_PERIOD_1 15.5
	`define CLK_PERIOD_2 18.3
`endif

module PATTERN #(
    parameter DSIZE = 8,
    parameter ASIZE = 4,
    parameter WSIZE = $clog2(DSIZE))(
    
    // Output Port
    output logic rst_n,
    output logic clk1,
    output logic clk2,
    output logic in_valid,
    output logic [4:0] doraemon_id,
    output logic [DSIZE-1:0] size,
    output logic [DSIZE-1:0] iq_score,
    output logic [DSIZE-1:0] eq_score,
    output logic [WSIZE-1:0] size_weight,
    output logic [WSIZE-1:0] iq_weight,
    output logic [WSIZE-1:0] eq_weight,
    // Input Port
    input logic ready,
    input logic out_valid,
    input logic [DSIZE-1:0] out
);

    //=============================================================
    // ------------------- Clock & Reset --------------------------
    //=============================================================

    always #(`CLK_PERIOD_1 / 2.0) clk1 = ~clk1;
    always #(`CLK_PERIOD_2 / 2.0) clk2 = ~clk2;

    //=============================================================
    // ---------------- Parameters & Integers ---------------------
    //=============================================================
    int seed = 7;
    int PATNUM;
    
    int input_file;
    int output_file;
    int total_latency;
    int input_count;
    int output_count;
    int dummy_cycle;
    int start;
    int f;
    int r2i_done;
    int r2i_set;
    int r2i_delay; // delay from ready to in_valid

    //=============================================================
    // -------------------- Internal Signals --------------------
    //=============================================================
    
    logic [DSIZE-1:0] golden_out;

    //=============================================================
    // ------------------- Latency Monitor ----------------------
    //=============================================================
    always @(negedge clk2) begin
        if(start) begin 
            total_latency ++;
            LATENCY_MONITOR : assert (total_latency < 100000)
            else $fatal(1, "[ERROR] The total latency is over 100000.");
        end
    end

    //=============================================================
    // ------------------- Output Checker -------------------------
    //=============================================================
    CHECK_OUT_ZERO : assert property (
        @(posedge clk2) disable iff(!rst_n) 
        !out_valid |-> out === 'd0
    ) else $fatal(1, "[ERROR] out should be 0 when out_valid is deasserted.");

    always @(posedge clk2) begin
        if(out_valid) begin
            f = $fscanf(output_file, "%d", golden_out[7:5]);
            f = $fscanf(output_file, "%d", golden_out[4:0]);
            
            CHECK_OUT_VALUE : assert (out === golden_out) 
            $display("No. %0d pattern pass", output_count);
            else $fatal(1, "[FAIL] Out mismatch. golden = %0d, yours = %0d at pattern %0d",
                            golden_out, out, output_count);

            output_count ++;
            if(output_count === PATNUM) begin
                $display("====================================");
                $display("  [SUCCESS] ALL PATTERN PASS ! ! !  ");
                $display("====================================");
                #10 $finish;
            end
            else;  
        end
    end


    //=============================================================
    // ---------------------- Main Flow ---------------------------
    //=============================================================
    initial begin
        initial_task;
        reset_task;
        gen4in_task;
        genin_task;
    end
    //=============================================================
    // ------------------------ Tasks -----------------------------
    //=============================================================
    task initial_task;
        begin
           	input_file = $fopen("../00_TESTBED/input.txt", "r");
	        output_file = $fopen("../00_TESTBED/output.txt", "r"); 
            total_latency = 0;
            input_count = 0;
            output_count = 0;
            dummy_cycle = 0;
            start = 0;
            f = 0;
            r2i_done = 0;
            r2i_delay = 0;
            r2i_set = 0;
        end
    endtask
    
    task reset_task;
        begin
            rst_n = 'd1;
            in_valid 	= 'd0;
	        doraemon_id = 'dx;
	        size 		= 'dx;
	        iq_score 	= 'dx;
	        eq_score 	= 'dx;
	        size_weight = 'dx;
	        iq_weight 	= 'dx;
	        eq_weight 	= 'dx;

            force clk1 = 0;
            force clk2 = 0;

            #20; rst_n = 'd0;
            #20; rst_n = 'd1;

            assert (!ready&&!out_valid&&out==='d0)
            else $fatal(1, "[ERROR] Output signal should be 0 after RESET");

            release clk1;
            release clk2;


        end
    endtask

    task gen4in_task;
        begin
            f = $fscanf(input_file, "%d", PATNUM); // Get Number of Pattern
            dummy_cycle = $unsigned($random(seed)) % 'd3 + 'd3; // Wait 3 ~ 5 cycle
            repeat(dummy_cycle) @(negedge clk1);
            in_valid = 1;
            start = 1;
            for(int i = 0; i < 4; i++) begin
                f = $fscanf(input_file, "%d %d %d %d", doraemon_id, size, iq_score, eq_score);
                assert (!out_valid)
                else $fatal(1, "[ERROR] out_valid should be 0 in given first 4 input.");
                @(negedge clk1);
            end
        end
    endtask

    task genin_task;
        begin
            while(input_count < PATNUM) begin
                if(ready) begin
                    if(r2i_done) begin
                        in_valid = 1;
                        f = $fscanf(input_file, "%d %d %d %d", doraemon_id, size, iq_score, eq_score);
                        f = $fscanf(input_file, "%d %d %d", size_weight, iq_weight, eq_weight);
                        input_count++;
                        @(negedge clk1); 
                    end
                    else begin
                        // 0 ~ 150 Cycles (Random)
                        in_valid = 0; 
                        r2i_delay = (r2i_set)? r2i_delay - 'd1 : $unsigned($random(seed)) % 'd151;
                        r2i_set = 1; 
                        if(r2i_delay==='d0) r2i_done = 1;
                        else @(negedge clk1); 
                    end  
                end
                else begin
                    in_valid = 0;
                    r2i_done = 0;
                    r2i_set = 0;
                    r2i_delay = 0;
                    @(negedge clk1); 
                end
            end
        end
    endtask

endmodule

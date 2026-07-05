/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    PATTERN.sv
* Project:      Clock Domain Crossing
* Module:       PATTERN
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

`define SCLK_PERIOD 10
`define DCLK_PERIOD 7
`define TEST_NUM    100

module PATTERN(
    output logic sclk,
    output logic dclk,
    output logic rst_n,
    output logic [31:0] din,
    output logic svalid,
    output logic dbusy,
    input sready,
    input dvalid,
    input [31:0] dout);


    int dbusy_cycle;
    int seed;
    int input_data;
    //=============================================================
    // ------------------- Clock & Reset --------------------------
    //=============================================================

    always #(`SCLK_PERIOD/2.0) sclk = ~sclk;
    always #(`DCLK_PERIOD/2.0) dclk = ~dclk;

    //=============================================================
    // ------------------------- Reset Task -----------------------
    //=============================================================
    task automatic reset_dut();
        begin 
            force sclk = 0;
            force dclk = 0;
            rst_n = 1;
            din = 'dx;
            svalid = 0;
            dbusy = 0;
            #20 rst_n = 0;
            #20 rst_n = 1;
            release sclk;
            release dclk;
            @(negedge sclk);
        end
    endtask

    //=============================================================
    // ------------------------- Stimulus Task --------------------
    //=============================================================
    task automatic send_data(input [31:0] data);
        begin
            while (!sready) @(negedge sclk);
            din = data;
            svalid = 1;
            @(negedge sclk);
            svalid = 0;
            din = 0;
            random_busy(data);
        end

    endtask

    task automatic random_busy(input [31:0] data);
        begin
            wait(dvalid);
            @(negedge dclk);
            CHECK_OUT: assert (dout===data) 
            else $fatal(1, "[ERROR] : dout mismatch, correct = %d, yours = %d", data, dout);

            dbusy = $unsigned($random(seed)) % 'd2;
            if(dbusy) begin
                dbusy_cycle = $unsigned($random(seed)) % 'd5;
                repeat(dbusy_cycle) @(negedge sclk);
                dbusy = 0;
            end
        end
    endtask

    task end_task();
        begin
            $display("============================================");
            $display("  [SUCCESS] ALL PATTERN & ASSERTION PASS !  ");
            $display("============================================");
        end
    endtask

    //=============================================================
    // ------------------------- Timing Watchdog ------------------
    //=============================================================

    initial begin
        #(`SCLK_PERIOD*`TEST_NUM*100);
        $fatal(1, "[TIMEOUT] : Simulation Time is over 10000ns.");
    end

    //=============================================================
    // ------------------------- Main Flow ------------------------
    //=============================================================
    initial begin
        reset_dut();
        for(int i = 0; i < `TEST_NUM; i++) begin
            input_data = $unsigned($random(seed));
            send_data(input_data);
        end
        #100 end_task();
        $finish;
    end
    

endmodule

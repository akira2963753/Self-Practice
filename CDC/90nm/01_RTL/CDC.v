/******************************************************************************
* Copyright (C) 2026 Marco 
*
* File Name:    CDC.sv
* Project:      [Train] 2023 Spring IC LAB, Lab 7 - CDC
* Module:       CDC
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

module CDC #(
    parameter DSIZE = 8,
	parameter ASIZE = 4,
    parameter WSIZE = $clog2(DSIZE))(

	// Input Port
	input rst_n,
	input clk1, // write clock
    input clk2, // read clock
	input in_valid,
    input [4:0] doraemon_id,
    input [DSIZE-1:0] size,
    input [DSIZE-1:0] iq_score,
    input [DSIZE-1:0] eq_score,
    input [WSIZE-1:0] size_weight,
    input [WSIZE-1:0] iq_weight,
    input [WSIZE-1:0] eq_weight,

    // Output Port
	output reg ready,
    output reg out_valid,
	output reg [DSIZE-1:0] out);

    integer i;
    reg [2:0] in_cnt;

    // Door Register (5 Doors)
    reg [4:0] door_doraemon_id [0:4];
    reg [DSIZE-1:0] door_size [0:4];
    reg [DSIZE-1:0] door_iq_score [0:4];
    reg [DSIZE-1:0] door_eq_score [0:4];

    // Weight Register
    reg [WSIZE-1:0] size_weight_r;
    reg [WSIZE-1:0] iq_weight_r;
    reg [WSIZE-1:0] eq_weight_r;

    // Multiplier
    reg [DSIZE+WSIZE-1:0] size_mul [0:4];
    reg [DSIZE+WSIZE-1:0] iq_mul [0:4];   
    reg [DSIZE+WSIZE-1:0] eq_mul [0:4];
    reg [DSIZE+WSIZE:0] score [0:4];

    // AFIFO 
    reg winc; 
    reg rinc;
    wire wfull; 
    wire rempty;
    reg [7:0] wdata; 
    wire [7:0] rdata;

    reg [DSIZE+WSIZE:0] score_max;
    reg [2:0] idx_max;

    reg w_pending;

    always @(posedge clk1 or negedge rst_n) begin
        if(!rst_n) w_pending <= 0;
        else w_pending <= winc;  
    end

    always @(posedge clk1 or negedge rst_n) begin
        if(!rst_n) in_cnt <= 0;
        else if (in_valid && in_cnt != 3'd5) in_cnt <= in_cnt + 1;
    end

    always @(posedge clk1 or negedge rst_n) begin
        if(!rst_n) begin
            for(i = 0; i < 5; i = i + 1) begin 
                door_doraemon_id[i] <= 0;
                door_size[i] <= 0;
                door_iq_score[i] <= 0;
                door_eq_score[i] <= 0;
            end
        end
        else begin
            if(in_valid && in_cnt < 3'd5) begin // Extra Input (First 5)
                door_doraemon_id[in_cnt] <= doraemon_id;
                door_size[in_cnt] <= size;
                door_iq_score[in_cnt] <= iq_score;
                door_eq_score[in_cnt] <= eq_score;
            end
            else if(in_valid) begin // Replace the door with the new doraemon
                door_doraemon_id[idx_max] <= doraemon_id;
                door_size[idx_max] <= size;
                door_iq_score[idx_max] <= iq_score;
                door_eq_score[idx_max] <= eq_score;
            end
        end
    end
    
    always @(posedge clk1 or negedge rst_n) begin
        if(!rst_n) begin
            size_weight_r <= 0;
            iq_weight_r <= 0;
            eq_weight_r <= 0;
        end
        else if(in_valid) begin
            size_weight_r <= size_weight;
            iq_weight_r <= iq_weight;
            eq_weight_r <= eq_weight;
        end
    end

    always @(*) begin
        for(i = 0; i < 5; i = i + 1) begin
            size_mul[i] = door_size[i] * size_weight_r;
            iq_mul[i] = door_iq_score[i] * iq_weight_r;
            eq_mul[i] = door_eq_score[i] * eq_weight_r;
            score[i] = size_mul[i] + iq_mul[i] + eq_mul[i];
        end

        score_max = 0;
        idx_max = 0;

        for(i = 0; i < 5; i = i + 1) begin
            if(score[i] > score_max) begin
                score_max = score[i];
                idx_max = i;
            end
            else begin
                score_max = score_max;
                idx_max = idx_max;
            end            
        end
    end

    always @(*) begin
        winc = ((in_cnt == 3'd5) && (in_valid) || (w_pending && ~wfull)) && rst_n;
        wdata = {idx_max, door_doraemon_id[idx_max]};
        rinc = ~ rempty;
        ready = (~wfull) && rst_n;
    end

    AFIFO #(
        .DSIZE(DSIZE),
        .ASIZE(ASIZE)) 
    u_AFIF0 (
        .rst_n(rst_n),
        .rclk(clk2),
        .rinc(rinc),
        .wclk(clk1),
        .winc(winc),
        .wdata(wdata),
        .rempty(rempty),
        .rdata(rdata),
        .wfull(wfull));

    always @(posedge clk2 or negedge rst_n) begin
        if(!rst_n) begin
            out <= 0;
            out_valid <= 0;
        end
        else begin
            out <= (rinc)? rdata : 0;
            out_valid <= rinc;
        end
    end

endmodule
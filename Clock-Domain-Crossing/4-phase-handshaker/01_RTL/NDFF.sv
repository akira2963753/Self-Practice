/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    NDFF.sv
* Project:      Clock Domain Crossing
* Module:       NDFF Synchronizer
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

module NDFF(
    input clk,
    input rst_n,
    input D,
    output logic Q
    );

    logic T;

    always_ff @(posedge clk or negedge rst_n) begin : NDFF_BLOCK
        if(!rst_n) begin
            T <= 0;
            Q <= 0;
        end
        else begin
            T <= D;
            Q <= T;
        end
    end

endmodule
/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    Handshaker.sv
* Project:      Clock Domain Crossing
* Module:       4 Phase Handshaker
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

module Handshaker(
    input sclk,
    input dclk,
    input rst_n,
    input [31:0] din,
    input svalid,    
    input dbusy,  
    output sready,     
    output logic dvalid,     
    output logic [31:0] dout);

    typedef enum logic [1:0] {S_IDLE, S_REQ, S_WAIT} stype;
    typedef enum logic {D_IDLE, D_ACK} dtype;
    stype s_state, s_next_state;
    dtype d_state, d_next_state;

    logic sreq, dreq;   // Request
    logic sack, dack;   // Acknowledge
    logic [31:0] data;

    always_ff @(posedge sclk or negedge rst_n) begin : SRC_FSM
        if(!rst_n) s_state <= S_IDLE;
        else s_state <= s_next_state;
    end

    always_comb begin : SRC_FSM_CTRL
        case(s_state) 
            S_IDLE: s_next_state = (svalid)? S_REQ : S_IDLE;
            S_REQ: s_next_state = (sack)? S_WAIT : S_REQ;
            S_WAIT: s_next_state = (!sack)? S_IDLE : S_WAIT;
            default: s_next_state = S_IDLE;
        endcase
    end

    assign sreq = (s_state==S_REQ);
    assign sready = (s_state==S_IDLE);

    always_ff @(posedge sclk or negedge rst_n) begin : SRC_FF
        if(!rst_n) data <= 0;
        else data <= (s_state==S_IDLE && svalid)? din : data;
    end

    NDFF Src_Sync (
        .clk(dclk),
        .rst_n(rst_n),
        .D(sreq),
        .Q(dreq));

    always_ff @(posedge dclk or negedge rst_n) begin : DEST_FSM
        if(!rst_n) d_state <= D_IDLE;
        else d_state <= d_next_state;
    end

    always_comb begin : DEST_FSM_CTRL
        case(d_state) 
            D_IDLE: d_next_state = (dreq && !dbusy)? D_ACK : D_IDLE;
            D_ACK: d_next_state = (!dreq && !dbusy)? D_IDLE : D_ACK;
            default: d_next_state = D_IDLE;
        endcase
    end

    always_ff @(posedge dclk or negedge rst_n) begin : DRC_FF
        if(!rst_n) begin 
            dout <= 0;
            dvalid <= 0;
        end
        else begin
            if(d_state==D_ACK) begin
                dout <= data;
                dvalid <= 1;
            end
            else begin
                dout <= 0;
                dvalid <= 0;
            end
        end
    end

    assign dack = (d_state==D_ACK);

    NDFF Dest_Sync (
        .clk(sclk),
        .rst_n(rst_n),
        .D(dack),
        .Q(sack));

endmodule
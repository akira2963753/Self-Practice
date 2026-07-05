/******************************************************************************
* Copyright (C) 2026 Marco
*
* File Name:    CHECKER.sv
* Project:      Clock Domain Crossing
* Module:       CHECKER
* Author:       Marco <harry2963753@gmail.com>
* Student ID:   M11407439
* Tool:         VCS & Verdi
*
******************************************************************************/

module CHECKER(
    input sclk,
    input dclk,
    input rst_n,
    input sready,
    input dvalid,
    input dbusy,
    input [31:0] dout,
    input sreq,
    input dreq,
    input sack,
    input dack
);
    
    // Assertion 1 : dbusy 為高時, sready 應該為 0 (backpressure 期間不能接受新請求)
    CHECK_SREADY: assert property (
        @(posedge sclk) disable iff(!rst_n) dbusy |-> sready === 'd0)
        else $fatal(1, "[ERROR] : sready should be 0 when dbusy is high.");

    // Assertion 2 : dvalid 為低時, dout 應該為 0 (沒有有效資料就不該有殘留值)
    CHECK_OUT_ZERO: assert property (
        @(posedge dclk) disable iff(!rst_n) !dvalid |-> dout === 'd0)
        else $fatal(1, "[ERROR] : dout should be 0 when dvalid is low.");

    // Assertion 3 : dbusy 為高時, dout 應該保持穩定不變 (等下游讀走前資料不能被覆蓋)
    CHECK_OUT_STABLE: assert property (
        @(posedge dclk) disable iff(!rst_n) dbusy |=> $stable(dout))
        else $fatal(1, "[ERROR] : dout should be stable when dbusy is high.");

    // Assertion 4 : reset 釋放後, sready 應該立刻為高 (系統從 IDLE 開始)
    CHECK_RESET_IDLE: assert property(
        @(posedge sclk) disable iff(!rst_n) $fell(rst_n) |-> sready)
        else $fatal(1, "[ERROR] : sready should be high immediately after reset deassertion.");

    `ifdef GATE 
    `else 
        // Assertion 5: sreq -> dreq 應該在 2 個 dclk cycle 後同步到達
        CHECK_REQ: assert property(
            @(posedge dclk) disable iff(!rst_n) sreq |-> ##2 dreq)
            else $fatal(1, "[ERROR] : dreq should be high 2 dclk cycles after sreq.");

        // Assertion 6 : sreq 在收到 sack 前必須保持高電位, 不能提早放掉
        CHECK_SREQ_STABLE: assert property(
            @(posedge sclk) disable iff(!rst_n) (sreq && !sack) |=> sreq)
            else $fatal(1, "[ERROR] : sreq deasserted before sack was received.");

        // Assertion 7 : dack 在 dreq 還沒放掉前必須保持高電位, 不能提早放掉
        CHECK_DACK_STABLE: assert property(
            @(posedge dclk) disable iff(!rst_n) (dack && dreq) |=> dack)
            else $fatal(1, "[ERROR] : dack deasserted while dreq still high.");

        // Assertion 8 : dack -> sack 應該在 2 個 sclk cycle 後同步到達 (CHECK_REQ 的回程對稱版本)
        CHECK_ACK: assert property(
            @(posedge sclk) disable iff(!rst_n) dack |-> ##2 sack)
            else $fatal(1, "[ERROR] : sack should be high 2 sclk cycles after dack.");

        // Assertion 9 : dbusy 為高時, 不能新進入 D_ACK (dack 不能從低變高)
        CHECK_DBUSY_BLOCK: assert property(
            @(posedge dclk) disable iff(!rst_n) (!dack && dbusy) |=> !dack)
            else $fatal(1, "[ERROR] : dack should not assert while dbusy is high.");
    `endif

endmodule
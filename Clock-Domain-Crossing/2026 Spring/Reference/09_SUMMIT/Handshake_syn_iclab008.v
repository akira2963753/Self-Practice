module Handshake_syn #(parameter WIDTH=8) (
    sclk,
    dclk,
    rst_n,
    sready,
    din,
    dbusy,
    sidle,
    dvalid,
    dout,

    flag_handshake_to_clk1,
    flag_clk1_to_handshake,

    flag_handshake_to_clk2,
    flag_clk2_to_handshake
);

input sclk, dclk;
input rst_n;
input sready;
input [WIDTH-1:0] din;
input dbusy;
output sidle;
output reg dvalid;
output reg [WIDTH-1:0] dout;

// You can change the input / output of the custom flag ports
output reg flag_handshake_to_clk1;
input flag_clk1_to_handshake;

output flag_handshake_to_clk2;
input flag_clk2_to_handshake;

// Remember:
//   Don't modify the signal name
reg sreq;
wire dreq;
reg dack;
wire sack;

// ----------------------------------------------------------------------------
// Source-side FSM (sclk domain)
//   S_IDLE -> S_REQ  : on sready, raise sreq (parent holds din stable while ~sidle)
//   S_REQ  -> S_CLR  : on sack=1 (ack seen), drop sreq
//   S_CLR  -> S_IDLE : on sack=0 (ack removed), ready for next transfer
// ----------------------------------------------------------------------------
localparam S_IDLE = 2'd0;
localparam S_REQ  = 2'd1;
localparam S_CLR  = 2'd2;

reg [1:0] src_state;

always @(posedge sclk or negedge rst_n) begin
    if (!rst_n) begin
        src_state <= S_IDLE;
        sreq      <= 1'b0;
    end else begin
        case (src_state)
            S_IDLE: begin
                if (sready) begin
                    src_state <= S_REQ;
                    sreq      <= 1'b1;
                end
            end
            S_REQ: begin
                if (sack) begin
                    src_state <= S_CLR;
                    sreq      <= 1'b0;
                end
            end
            S_CLR: begin
                if (!sack) begin
                    src_state <= S_IDLE;
                end
            end
            default: begin
                src_state <= S_IDLE;
                sreq      <= 1'b0;
            end
        endcase
    end
end

assign sidle = (src_state == S_IDLE);

// ----------------------------------------------------------------------------
// Destination-side FSM (dclk domain)
//   D_IDLE -> D_ACK : on dreq & ~dbusy, latch dout, raise dack, pulse dvalid
//   D_ACK  -> D_IDLE: on ~dreq (source has dropped sreq), clear dack
// ----------------------------------------------------------------------------
localparam D_IDLE = 1'b0;
localparam D_ACK  = 1'b1;

reg dst_state;

always @(posedge dclk or negedge rst_n) begin
    if (!rst_n) begin
        dst_state <= D_IDLE;
        dack      <= 1'b0;
        dvalid    <= 1'b0;
        dout      <= {WIDTH{1'b0}};
    end else begin
        case (dst_state)
            D_IDLE: begin
                dvalid <= 1'b0;
                if (dreq && !dbusy) begin
                    dst_state <= D_ACK;
                    dack      <= 1'b1;
                    dout      <= din;
                    dvalid    <= 1'b1;
                end
            end
            D_ACK: begin
                dvalid <= 1'b0;
                if (!dreq) begin
                    dst_state <= D_IDLE;
                    dack      <= 1'b0;
                end
            end
            default: begin
                dst_state <= D_IDLE;
                dack      <= 1'b0;
                dvalid    <= 1'b0;
            end
        endcase
    end
end

// ----------------------------------------------------------------------------
// Cross-domain synchronizers (TA-provided NDFF_syn)
//   sreq (sclk) -> dreq (dclk)
//   dack (dclk) -> sack (sclk)
// ----------------------------------------------------------------------------
NDFF_syn u_sync_req (
    .D(sreq),
    .Q(dreq),
    .clk(dclk),
    .rst_n(rst_n)
);

NDFF_syn u_sync_ack (
    .D(dack),
    .Q(sack),
    .clk(sclk),
    .rst_n(rst_n)
);

// ----------------------------------------------------------------------------
// Custom flag ports: free-form sideband, tied off (no protocol requirement)
// ----------------------------------------------------------------------------
always @(posedge sclk or negedge rst_n) begin
    if (!rst_n) flag_handshake_to_clk1 <= 1'b0;
    else        flag_handshake_to_clk1 <= 1'b0;
end

assign flag_handshake_to_clk2 = 1'b0;

endmodule

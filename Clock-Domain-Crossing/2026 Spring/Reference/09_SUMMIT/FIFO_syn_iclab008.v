module FIFO_syn #(parameter WIDTH=32, parameter WORDS=64) (
    wclk,//clk2
    rclk,//clk1
    rst_n,
    winc,
    wdata,
    wfull,
    rinc,
    rdata,
    rempty,

    flag_fifo_to_clkw,
    flag_clkw_to_fifo,

    flag_fifo_to_clkr,
	flag_clkr_to_fifo
);

input wclk, rclk;
input rst_n;
input winc;
input [WIDTH-1:0] wdata;
output reg wfull;
input rinc;
output reg [WIDTH-1:0] rdata;
output reg rempty;

// You can change the input / output of the custom flag ports
output  flag_fifo_to_clkw;
input flag_clkw_to_fifo;

output flag_fifo_to_clkr;
input flag_clkr_to_fifo;

wire [WIDTH-1:0] rdata_q;

// Remember:
//   wptr and rptr should be gray coded
//   Don't modify the signal name
reg [$clog2(WORDS):0] wptr;
reg [$clog2(WORDS):0] rptr;

// ----------------------------------------------------------------------------
// Local parameters and internal signals
// ----------------------------------------------------------------------------
localparam PTR_W = $clog2(WORDS) + 1;   // 7 for WORDS=64
localparam ADDR_W = $clog2(WORDS);      // 6 for WORDS=64

reg  [PTR_W-1:0] wbin;                  // binary write pointer
reg  [PTR_W-1:0] rbin;                  // binary read pointer

wire [PTR_W-1:0] wbin_next;
wire [PTR_W-1:0] rbin_next;
wire [PTR_W-1:0] wgray_next;
wire [PTR_W-1:0] rgray_next;
wire [PTR_W-1:0] wptr_rclk;             // wptr synced into rclk domain
wire [PTR_W-1:0] rptr_wclk;             // rptr synced into wclk domain

wire             wen;                   // effective write
wire             ren;                   // effective read
wire             wfull_next;
wire             rempty_next;

assign wen        = winc & ~wfull;
assign ren        = rinc & ~rempty;

assign wbin_next  = wbin + {{(PTR_W-1){1'b0}}, wen};
assign rbin_next  = rbin + {{(PTR_W-1){1'b0}}, ren};

assign wgray_next = wbin_next ^ (wbin_next >> 1);
assign rgray_next = rbin_next ^ (rbin_next >> 1);

// Cummings-style full detect: top two gray bits inverted, low bits equal
assign wfull_next  = (wgray_next == { ~rptr_wclk[PTR_W-1:PTR_W-2], rptr_wclk[PTR_W-3:0] });
// Empty when read gray equals synced write gray
assign rempty_next = (rgray_next == wptr_rclk);

// ----------------------------------------------------------------------------
// Write side (wclk): advance binary pointer, register gray pointer and wfull
// ----------------------------------------------------------------------------
always @(posedge wclk or negedge rst_n) begin
    if (!rst_n) begin
        wbin  <= {PTR_W{1'b0}};
        wptr  <= {PTR_W{1'b0}};
        wfull <= 1'b0;
    end else begin
        wbin  <= wbin_next;
        wptr  <= wgray_next;
        wfull <= wfull_next;
    end
end

// ----------------------------------------------------------------------------
// Read side (rclk): advance binary pointer, register gray pointer and rempty
// ----------------------------------------------------------------------------
always @(posedge rclk or negedge rst_n) begin
    if (!rst_n) begin
        rbin   <= {PTR_W{1'b0}};
        rptr   <= {PTR_W{1'b0}};
        rempty <= 1'b1;
    end else begin
        rbin   <= rbin_next;
        rptr   <= rgray_next;
        rempty <= rempty_next;
    end
end

// rdata
//  Add one more register stage to rdata
always @(posedge rclk, negedge rst_n) begin
    if (!rst_n) begin
        rdata <= 0;
    end
    else begin
		if (ren) begin
			rdata <= rdata_q;
		end
    end
end

// ----------------------------------------------------------------------------
// Cross-domain pointer synchronizers (TA-provided NDFF_BUS_syn)
// ----------------------------------------------------------------------------
NDFF_BUS_syn #(.WIDTH(PTR_W)) u_sync_wptr (
    .D(wptr),
    .Q(wptr_rclk),
    .clk(rclk),
    .rst_n(rst_n)
);

NDFF_BUS_syn #(.WIDTH(PTR_W)) u_sync_rptr (
    .D(rptr),
    .Q(rptr_wclk),
    .clk(wclk),
    .rst_n(rst_n)
);

// ----------------------------------------------------------------------------
// Custom flag ports: free-form sideband, tied off
// ----------------------------------------------------------------------------
assign flag_fifo_to_clkw = 1'b0;
assign flag_fifo_to_clkr = 1'b0;

// ----------------------------------------------------------------------------
// Dual-port SRAM instance
//   Port A = write (wclk):  A0..A5 = wbin[5:0], WEAN = ~wen
//   Port B = read  (rclk):  B0..B5 = rbin_next[5:0], WEBN = 1 (never write)
//   OEB = 1 keeps DOB driven; OEA = 0 (DOA unused, unconnected)
// ----------------------------------------------------------------------------
DUAL_64X32X1BM1 u_dual_sram (
    .CKA(wclk),
    .CKB(rclk),
    .WEAN(~wen),
    .WEBN(1'b1),
    .CSA(1'b1),
    .CSB(1'b1),
    .OEA(1'b0),
    .OEB(1'b1),
    .A0(wbin[0]),
    .A1(wbin[1]),
    .A2(wbin[2]),
    .A3(wbin[3]),
    .A4(wbin[4]),
    .A5(wbin[5]),
    .B0(rbin_next[0]),
    .B1(rbin_next[1]),
    .B2(rbin_next[2]),
    .B3(rbin_next[3]),
    .B4(rbin_next[4]),
    .B5(rbin_next[5]),
    .DIA0(wdata[0]),
    .DIA1(wdata[1]),
    .DIA2(wdata[2]),
    .DIA3(wdata[3]),
    .DIA4(wdata[4]),
    .DIA5(wdata[5]),
    .DIA6(wdata[6]),
    .DIA7(wdata[7]),
    .DIA8(wdata[8]),
    .DIA9(wdata[9]),
    .DIA10(wdata[10]),
    .DIA11(wdata[11]),
    .DIA12(wdata[12]),
    .DIA13(wdata[13]),
    .DIA14(wdata[14]),
    .DIA15(wdata[15]),
    .DIA16(wdata[16]),
    .DIA17(wdata[17]),
    .DIA18(wdata[18]),
    .DIA19(wdata[19]),
    .DIA20(wdata[20]),
    .DIA21(wdata[21]),
    .DIA22(wdata[22]),
    .DIA23(wdata[23]),
    .DIA24(wdata[24]),
    .DIA25(wdata[25]),
    .DIA26(wdata[26]),
    .DIA27(wdata[27]),
    .DIA28(wdata[28]),
    .DIA29(wdata[29]),
    .DIA30(wdata[30]),
    .DIA31(wdata[31]),

    .DOB0(rdata_q[0]),
    .DOB1(rdata_q[1]),
    .DOB2(rdata_q[2]),
    .DOB3(rdata_q[3]),
    .DOB4(rdata_q[4]),
    .DOB5(rdata_q[5]),
    .DOB6(rdata_q[6]),
    .DOB7(rdata_q[7]),
    .DOB8(rdata_q[8]),
    .DOB9(rdata_q[9]),
    .DOB10(rdata_q[10]),
    .DOB11(rdata_q[11]),
    .DOB12(rdata_q[12]),
    .DOB13(rdata_q[13]),
    .DOB14(rdata_q[14]),
    .DOB15(rdata_q[15]),
    .DOB16(rdata_q[16]),
    .DOB17(rdata_q[17]),
    .DOB18(rdata_q[18]),
    .DOB19(rdata_q[19]),
    .DOB20(rdata_q[20]),
    .DOB21(rdata_q[21]),
    .DOB22(rdata_q[22]),
    .DOB23(rdata_q[23]),
    .DOB24(rdata_q[24]),
    .DOB25(rdata_q[25]),
    .DOB26(rdata_q[26]),
    .DOB27(rdata_q[27]),
    .DOB28(rdata_q[28]),
    .DOB29(rdata_q[29]),
    .DOB30(rdata_q[30]),
    .DOB31(rdata_q[31]),

    .DIB0(1'b0),
    .DIB1(1'b0),
    .DIB2(1'b0),
    .DIB3(1'b0),
    .DIB4(1'b0),
    .DIB5(1'b0),
    .DIB6(1'b0),
    .DIB7(1'b0),
    .DIB8(1'b0),
    .DIB9(1'b0),
    .DIB10(1'b0),
    .DIB11(1'b0),
    .DIB12(1'b0),
    .DIB13(1'b0),
    .DIB14(1'b0),
    .DIB15(1'b0),
    .DIB16(1'b0),
    .DIB17(1'b0),
    .DIB18(1'b0),
    .DIB19(1'b0),
    .DIB20(1'b0),
    .DIB21(1'b0),
    .DIB22(1'b0),
    .DIB23(1'b0),
    .DIB24(1'b0),
    .DIB25(1'b0),
    .DIB26(1'b0),
    .DIB27(1'b0),
    .DIB28(1'b0),
    .DIB29(1'b0),
    .DIB30(1'b0),
    .DIB31(1'b0)
);

endmodule

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

DUAL_64X32X1BM1 u_dual_sram (
    .CKA(wclk),
    .CKB(rclk),
    .WEAN(),
    .WEBN(),
    .CSA(),
    .CSB(),
    .OEA(),
    .OEB(),
    .A0(),
    .A1(),
    .A2(),
    .A3(),
    .A4(),
    .A5(),
    .B0(),
    .B1(),
    .B2(),
    .B3(),
    .B4(),
    .B5(),
    .DIA0(),
    .DIA1(),
    .DIA2(),
    .DIA3(),
    .DIA4(),
    .DIA5(),
    .DIA6(),
    .DIA7(),
    .DIA8(),
    .DIA9(),
    .DIA10(),
    .DIA11(),
    .DIA12(),
    .DIA13(),
    .DIA14(),
    .DIA15(),
    .DIA16(),
    .DIA17(),
    .DIA18(),
    .DIA19(),
    .DIA20(),
    .DIA21(),
    .DIA22(),
    .DIA23(),
    .DIA24(),
    .DIA25(),
    .DIA26(),
    .DIA27(),
    .DIA28(),
    .DIA29(),
    .DIA30(),
    .DIA31(),

    .DOB0(),
    .DOB1(),
    .DOB2(),
    .DOB3(),
    .DOB4(),
    .DOB5(),
    .DOB6(),
    .DOB7(),
    .DOB8(),
    .DOB9(),
    .DOB10(),
    .DOB11(),
    .DOB12(),
    .DOB13(),
    .DOB14(),
    .DOB15(),
    .DOB16(),
    .DOB17(),
    .DOB18(),
    .DOB19(),
    .DOB20(),
    .DOB21(),
    .DOB22(),
    .DOB23(),
    .DOB24(),
    .DOB25(),
    .DOB26(),
    .DOB27(),
    .DOB28(),
    .DOB29(),
    .DOB30(),
    .DOB31(),

    .DIB0(),
    .DIB1(),
    .DIB2(),
    .DIB3(),
    .DIB4(),
    .DIB5(),
    .DIB6(),
    .DIB7(),
    .DIB8(),
    .DIB9(),
    .DIB10(),
    .DIB11(),
    .DIB12(),
    .DIB13(),
    .DIB14(),
    .DIB15(),
    .DIB16(),
    .DIB17(),
    .DIB18(),
    .DIB19(),
    .DIB20(),
    .DIB21(),
    .DIB22(),
    .DIB23(),
    .DIB24(),
    .DIB25(),
    .DIB26(),
    .DIB27(),
    .DIB28(),
    .DIB29(),
    .DIB30(),
    .DIB31()
);

endmodule





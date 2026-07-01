module CLK_1_MODULE (
	input               clk, 
    input               rst_n,
    input               in_mode_valid,
    input       	    in_mode,
	
    input               in_valid,
    input       [1:0]   in_bank,
    input       [5:0]   in_src_row,

    output reg          out_valid,
    output reg  [63:0]  out_data,

	input out_idle,
	output reg handshake_sready,
	output reg [8:0] handshake_din,
	// You can use the the custom flag ports for your design
	input  flag_handshake_to_clk1,
	output flag_clk1_to_handshake,

	input fifo_empty,
	input [31:0] fifo_rdata,
	output fifo_rinc,
	// You can use the the custom flag ports for your design
	output flag_clk1_to_fifo,
	input flag_fifo_to_clk1

);

// =========================================================================
// CLK_1_MODULE - PATTERN bridge on clk1
// Two independent FSMs:
//   (1) Input capture buffer + dispatch FSM feeding Handshake_syn source.
//   (2) Output FIFO pop + 64-bit reassembly driving out_valid / out_data.
// Beat encoding on handshake_din (matches CLK_2 decoder):
//   [8]=1 => mode beat  ([0]=in_mode)
//   [8]=0 => data beat  ([7:6]=in_bank, [5:0]=in_src_row)
// =========================================================================

// -------------------------------------------------------------------------
// Input capture buffer (mode + 4 address beats per pattern)
// -------------------------------------------------------------------------
reg       mode_buf;
reg       mode_pending;
reg [1:0] bank_buf [0:3];
reg [5:0] row_buf  [0:3];
reg [2:0] data_wr_cnt;   // 0..4 data beats captured

// -------------------------------------------------------------------------
// Input dispatch FSM (drives Handshake_syn source port)
// -------------------------------------------------------------------------
localparam D_IDLE  = 2'd0;
localparam D_PULSE = 2'd1;
localparam D_WAIT  = 2'd2;

reg [1:0] disp_state;
reg [2:0] beat_idx;      // 0=mode, 1..4=data[0..3], 5=done

// -------------------------------------------------------------------------
// Output pop + 64-bit reassembly FSM
// -------------------------------------------------------------------------
localparam O_IDLE = 2'd0;
localparam O_POP0 = 2'd1;
localparam O_POP1 = 2'd2;
localparam O_EMIT = 2'd3;

reg [1:0]  out_state;
reg [31:0] lo_half;

integer bi;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_buf     <= 1'b0;
        mode_pending <= 1'b0;
        data_wr_cnt  <= 3'd0;
        for (bi = 0; bi < 4; bi = bi + 1) begin
            bank_buf[bi] <= 2'd0;
            row_buf[bi]  <= 6'd0;
        end
        disp_state       <= D_IDLE;
        beat_idx         <= 3'd0;
        handshake_sready <= 1'b0;
        handshake_din    <= 9'd0;
        out_state        <= O_IDLE;
        lo_half          <= 32'd0;
        out_valid        <= 1'b0;
        out_data         <= 64'd0;
    end else begin
        // -----------------------------------------------------------------
        // DISPATCH FSM
        // Runs first in procedural order; any clears can be overridden by
        // the capture block further down (guards against pattern-start
        // race when the clear cycle coincides with new in_mode_valid).
        // -----------------------------------------------------------------
        handshake_sready <= 1'b0;   // default; pulse high in D_IDLE when firing

        case (disp_state)
            D_IDLE: begin
                if (mode_pending && (data_wr_cnt == 3'd4) && out_idle &&
                    (beat_idx <= 3'd4)) begin
                    handshake_sready <= 1'b1;
                    if (beat_idx == 3'd0) begin
                        handshake_din <= {1'b1, 7'd0, mode_buf};
                    end else begin
                        handshake_din <= {1'b0,
                                          bank_buf[beat_idx - 3'd1],
                                          row_buf [beat_idx - 3'd1]};
                    end
                    disp_state <= D_PULSE;
                end else if (beat_idx == 3'd5) begin
                    // All five beats dispatched; clear buffer so the next
                    // pattern can start (capture block below overrides any
                    // simultaneous in_mode_valid / in_valid).
                    mode_pending <= 1'b0;
                    data_wr_cnt  <= 3'd0;
                    beat_idx     <= 3'd0;
                end
            end

            // sready was high for 1 cycle; drop it and move to wait.
            D_PULSE: disp_state <= D_WAIT;

            // Wait for Handshake_syn source FSM to complete the full cycle
            // (S_IDLE -> S_REQ -> S_CLR -> S_IDLE); out_idle returns to 1.
            D_WAIT: begin
                if (out_idle) begin
                    beat_idx   <= beat_idx + 3'd1;
                    disp_state <= D_IDLE;
                end
            end

            default: disp_state <= D_IDLE;
        endcase

        // -----------------------------------------------------------------
        // OUTPUT POP + 64-bit REASSEMBLY FSM
        // Two consecutive fifo_rinc cycles drain low then high half; on
        // the cycle after the second pop, fifo_rdata carries the high half
        // and we reassemble out_data = {hi, lo} (low-first convention
        // matches CLK_2 pusher's PS_LO then PS_HI).
        // -----------------------------------------------------------------
        case (out_state)
            O_IDLE: begin
                out_valid <= 1'b0;
                out_data  <= 64'd0;
                if (!fifo_empty) out_state <= O_POP0;
            end

            // Assert rinc combinationally only when ~fifo_empty so the FIFO
            // protocol invariant (no_read_on_empty) holds even during sync
            // lag between the two halves pushed by CLK_2.
            O_POP0: if (!fifo_empty) out_state <= O_POP1;

            O_POP1: if (!fifo_empty) begin
                lo_half   <= fifo_rdata;
                out_state <= O_EMIT;
            end

            // fifo_rdata now carries the high half; reassemble and emit.
            O_EMIT: begin
                out_data  <= {fifo_rdata, lo_half};
                out_valid <= 1'b1;
                out_state <= O_IDLE;
            end

            default: out_state <= O_IDLE;
        endcase

        // -----------------------------------------------------------------
        // CAPTURE BLOCK (ordered last so its writes win over dispatch
        // clears in a same-cycle race).
        //   in_mode_valid pulses for 1 clk1 cycle per pattern (spec p.13).
        //   in_valid stays high for 4 consecutive clk1 cycles carrying the
        //   4 (bank, row) pairs; each is latched into bank_buf / row_buf.
        // -----------------------------------------------------------------
        if (in_mode_valid) begin
            mode_buf     <= in_mode;
            mode_pending <= 1'b1;
        end
        if (in_valid && (data_wr_cnt < 3'd4)) begin
            bank_buf[data_wr_cnt[1:0]] <= in_bank;
            row_buf [data_wr_cnt[1:0]] <= in_src_row;
            data_wr_cnt <= data_wr_cnt + 3'd1;
        end
    end
end

// fifo_rinc combinational; gated with ~fifo_empty so we never assert rinc
// when the FIFO is empty (JG no_read_on_empty protocol check).
assign fifo_rinc = ((out_state == O_POP0) || (out_state == O_POP1)) & ~fifo_empty;

// Flag sidebands unused.
assign flag_clk1_to_handshake = 1'b0;
assign flag_clk1_to_fifo      = 1'b0;

endmodule

module CLK_2_MODULE (
    clk,
    rst_n,
    
	//INPUT
	busy,
    in_valid,
    in_data,
	flag_handshake_to_clk2,
    flag_clk2_to_handshake,

	//OUTPUT
    out_fifo_full,
    out_valid,
    out_data,
    flag_fifo_to_clk2,
    flag_clk2_to_fifo,

	//AR
    ar_fifo_full,
    ar_out_valid,
    ar_out_data,
    ar_flag_fifo_to_wclk,
    ar_flag_wclk_to_fifo,

    //R
	r_fifo_empty,
    r_fifo_rdata,
    r_fifo_rinc,
    r_flag_fifo_to_rclk,
    r_flag_rclk_to_fifo,

	ar_addr, 
    ar_valid, 
    ar_ready,
    r_data,  
    // r_resp, 
    r_valid, 
    r_ready
);
input clk;
input rst_n;

output  busy;
input in_valid;
input [8:0] in_data;
input  flag_handshake_to_clk2;
output flag_clk2_to_handshake;

input out_fifo_full;
output out_valid;
output [31:0] out_data;
input  flag_fifo_to_clk2;
output flag_clk2_to_fifo;

//AR
input    	ar_fifo_full;
output      ar_out_valid;
output [31:0]    ar_out_data;
input    	ar_flag_fifo_to_wclk;
output    	ar_flag_wclk_to_fifo;

//R
input	r_fifo_empty;
input [31:0]   r_fifo_rdata;
output    r_fifo_rinc;
input    r_flag_fifo_to_rclk;
output    r_flag_rclk_to_fifo;

output   [31:0]  ar_addr;
output           ar_valid;
output           ar_ready;
output reg  [63:0]  r_data;
// input       [1:0]   r_resp;
output reg       r_valid;
output           r_ready;

// =========================================================================
// Top-level FSM state encoding
// =========================================================================
localparam TS_IDLE         = 4'd0;
localparam TS_CAPTURE      = 4'd1;
localparam TS_DISPATCH     = 4'd2;
localparam TS_CALC         = 4'd3;
localparam TS_GUASS_P1     = 4'd4;
localparam TS_GUASS_THRESH = 4'd5;
localparam TS_GUASS_P3     = 4'd8;
localparam TS_DRAIN        = 4'd9;

reg [3:0] top_state, top_state_nxt;

// =========================================================================
// Ingress capture: 1 mode beat + 4 (bank,row) data beats via Handshake_syn
//   in_data[8] = tag bit: 1 = mode beat, 0 = data beat
//   mode beat payload: in_data[0]        = mode (0=CALC, 1=GUASS)
//   data beat payload: in_data[7:6] bank, in_data[5:0] row
// =========================================================================
reg       mode_reg;
reg       got_mode_reg;
reg [2:0] data_cnt;                 // 0..4 : data beats received so far
reg [1:0] bank_arr [0:3];
reg [5:0] row_arr  [0:3];

wire beat_accept  = in_valid;       // dvalid pulse from Handshake_syn
wire is_mode_beat = in_data[8];
wire capture_done = got_mode_reg && (data_cnt == 3'd4);

// =========================================================================
// Parameters
// =========================================================================
localparam OUTSTANDING_MAX = 4'd8;

// =========================================================================
// Engine activity gates (which engine owns the shared AR/R/pusher/ALU)
// =========================================================================
wire in_calc_state  = (top_state == TS_CALC);
wire in_guass_state = (top_state == TS_GUASS_P1) ||
                      (top_state == TS_GUASS_P3);

// =========================================================================
// CALC engine register-level outputs (forward; driven in CALC engine block)
// =========================================================================
reg         calc_issue_req;
reg  [15:0] calc_issue_addr;
reg         calc_push_req;
reg  [63:0] calc_push_data;
reg         calc_done_reg;

// =========================================================================
// GUASS engine register-level outputs (forward; driven in GUASS block)
// =========================================================================
reg         guass_issue_req;
reg  [15:0] guass_issue_addr;
reg         guass_push_req;
reg  [63:0] guass_push_data;
reg         guass_p1_done_reg;
reg         guass_p3_done_reg;
reg         thresh_done_reg;
reg         thresh_phase;
reg  [63:0] word_1023_reg;
reg         last_pushed;
reg         push_pending;
reg  [63:0] push_pending_data;
reg  [1:0]  p3_phase;

// =========================================================================
// Engine done signals to Top FSM
// =========================================================================
wire calc_done     = calc_done_reg;
wire guass_p1_done = guass_p1_done_reg;
wire thresh_done   = thresh_done_reg;
wire guass_p3_done = guass_p3_done_reg;

// Consumer stall: used by R consumer to hold word_valid production when
// GUASS Pass 3 has a filter-pass word buffered waiting for pusher drain.
wire consumer_stall = push_pending;

// =========================================================================
// Muxed engine-facing AR issue + output pusher interfaces
// =========================================================================
wire        issue_req  = in_calc_state  ? calc_issue_req  :
                         in_guass_state ? guass_issue_req : 1'b0;
wire [15:0] issue_addr = in_calc_state  ? calc_issue_addr :
                         in_guass_state ? guass_issue_addr : 16'd0;
wire        push_req   = in_calc_state  ? calc_push_req   :
                         in_guass_state ? guass_push_req  : 1'b0;
wire [63:0] push_data  = in_calc_state  ? calc_push_data  :
                         in_guass_state ? guass_push_data : 64'd0;

// =========================================================================
// Outstanding AR counter (forward declaration; register logic below)
// =========================================================================
reg  [3:0]  outstanding_cnt;

// =========================================================================
// Drain-complete interlock (pusher_idle forward-declared; driven below)
// =========================================================================
wire        pusher_idle;
wire        drain_complete  = pusher_idle && (outstanding_cnt == 4'd0);

// =========================================================================
// busy : drops to 0 only while CLK_2 is receiving handshake beats.
//         Handshake_syn.dbusy gate; high during compute/drain.
// =========================================================================
assign busy = (top_state != TS_IDLE) && (top_state != TS_CAPTURE);

// =========================================================================
// Top FSM : sequential + next-state
// =========================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) top_state <= TS_IDLE;
    else        top_state <= top_state_nxt;
end

always @(*) begin
    top_state_nxt = top_state;
    case (top_state)
        TS_IDLE       : if (beat_accept)    top_state_nxt = TS_CAPTURE;
        TS_CAPTURE    : if (capture_done)   top_state_nxt = TS_DISPATCH;
        TS_DISPATCH    :                     top_state_nxt = mode_reg ? TS_GUASS_P1 : TS_CALC;
        TS_CALC        : if (calc_done)      top_state_nxt = TS_DRAIN;
        TS_GUASS_P1    : if (guass_p1_done)  top_state_nxt = TS_GUASS_THRESH;
        TS_GUASS_THRESH: if (thresh_done)    top_state_nxt = TS_GUASS_P3;
        TS_GUASS_P3    : if (guass_p3_done)  top_state_nxt = TS_DRAIN;
        TS_DRAIN       : if (drain_complete) top_state_nxt = TS_IDLE;
        default       :                     top_state_nxt = TS_IDLE;
    endcase
end

// =========================================================================
// Ingress capture sequential
// =========================================================================
integer cap_i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        mode_reg     <= 1'b0;
        got_mode_reg <= 1'b0;
        data_cnt     <= 3'd0;
        for (cap_i = 0; cap_i < 4; cap_i = cap_i + 1) begin
            bank_arr[cap_i] <= 2'd0;
            row_arr[cap_i]  <= 6'd0;
        end
    end else begin
        // Reset capture bookkeeping when pattern dispatches (ready for next pattern)
        if (top_state == TS_DISPATCH) begin
            got_mode_reg <= 1'b0;
            data_cnt     <= 3'd0;
        end else if (beat_accept && (top_state == TS_IDLE || top_state == TS_CAPTURE)) begin
            if (is_mode_beat) begin
                mode_reg     <= in_data[0];
                got_mode_reg <= 1'b1;
            end else begin
                case (data_cnt[1:0])
                    2'd0: begin bank_arr[0] <= in_data[7:6]; row_arr[0] <= in_data[5:0]; end
                    2'd1: begin bank_arr[1] <= in_data[7:6]; row_arr[1] <= in_data[5:0]; end
                    2'd2: begin bank_arr[2] <= in_data[7:6]; row_arr[2] <= in_data[5:0]; end
                    2'd3: begin bank_arr[3] <= in_data[7:6]; row_arr[3] <= in_data[5:0]; end
                    default: ;
                endcase
                data_cnt <= data_cnt + 3'd1;
            end
        end
    end
end

// =========================================================================
// AR issuer
//   Latches engine's (issue_req, issue_addr) into AR FIFO push + AXI snoop.
//   Holds ar_valid_reg / ar_out_valid / ar_out_data stable until AR FIFO
//   accepts (~ar_fifo_full) -- satisfies AXI rule 2 (stability) and rule 5
//   (ar_addr = 0 when !ar_valid) via a combinational gate at the output.
// =========================================================================
localparam ARS_IDLE  = 1'b0;
localparam ARS_ISSUE = 1'b1;

reg        ar_state;
reg [15:0] ar_addr_reg_inner;
reg        ar_valid_reg;

wire ar_accepted = ar_valid_reg && ~ar_fifo_full;
wire issue_ack   = (ar_state == ARS_IDLE) && issue_req &&
                   (outstanding_cnt < OUTSTANDING_MAX);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ar_state          <= ARS_IDLE;
        ar_addr_reg_inner <= 16'd0;
        ar_valid_reg      <= 1'b0;
    end else begin
        case (ar_state)
            ARS_IDLE: begin
                if (issue_req && (outstanding_cnt < OUTSTANDING_MAX)) begin
                    ar_state          <= ARS_ISSUE;
                    ar_addr_reg_inner <= issue_addr;
                    ar_valid_reg      <= 1'b1;
                end
            end
            ARS_ISSUE: begin
                if (~ar_fifo_full) begin
                    ar_state     <= ARS_IDLE;
                    ar_valid_reg <= 1'b0;
                end
            end
            default: ar_state <= ARS_IDLE;
        endcase
    end
end

// Combinational winc/wdata for AR FIFO gated with ~ar_fifo_full.
assign ar_out_valid = (ar_state == ARS_ISSUE) & ~ar_fifo_full;
assign ar_out_data  = (ar_state == ARS_ISSUE) ? {16'd0, ar_addr_reg_inner} : 32'd0;

// =========================================================================
// R consumer
//   3-cycle FSM reassembling 64-bit AXI R beat from two 32-bit R FIFO halves.
//   Low-32 first (ordering convention), high-32 second.
//   Registered r_data / r_valid satisfy rule 9 (r_data = 0 when !r_valid).
// =========================================================================
localparam RS_POP_LO = 2'd0;
localparam RS_POP_HI = 2'd1;
localparam RS_EMIT   = 2'd2;

reg [1:0]  r_state;
reg [31:0] r_low_reg;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        r_state   <= RS_POP_LO;
        r_low_reg <= 32'd0;
        r_data    <= 64'd0;
        r_valid   <= 1'b0;
    end else begin
        case (r_state)
            RS_POP_LO: begin
                r_valid <= 1'b0;
                r_data  <= 64'd0;
                // Stall here (safe point -- no half-popped word) when the
                // downstream consumer (GUASS Pass 3 buffer) can't accept yet.
                if (~r_fifo_empty && !consumer_stall) begin
                    r_state <= RS_POP_HI;
                end
            end
            RS_POP_HI: begin
                if (~r_fifo_empty && !consumer_stall) begin
                    r_low_reg <= r_fifo_rdata;
                    r_state   <= RS_EMIT;
                end
                // else: stall here for high half OR for downstream consumer
            end
            RS_EMIT: begin
                r_valid <= 1'b1;
                r_data  <= {r_fifo_rdata, r_low_reg};
                r_state <= RS_POP_LO;
            end
            default: r_state <= RS_POP_LO;
        endcase
    end
end

// rinc is combinational -- FIFO_syn's `ren` samples it only at rclk edge.
// Gated at BOTH RS_POP_LO and RS_POP_HI by consumer_stall: stalling at
// RS_POP_HI prevents the in-flight word_valid pulse from overwriting the
// 1-deep push_pending buffer when downstream pusher back-pressures
// (Period_1 GUASS Pass 3 fix).
assign r_fifo_rinc = ((r_state == RS_POP_LO && !consumer_stall) ||
                      (r_state == RS_POP_HI && !consumer_stall)) && ~r_fifo_empty;

// Engine-facing reassembled word (alias of the AXI-snoop regs)
wire        word_valid = r_valid;
wire [63:0] word_out   = r_data;

// R handshake completes each cycle r_valid is high (since r_ready tied to 1).
wire r_accepted = r_valid;

// =========================================================================
// Outstanding AR counter
// =========================================================================
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        outstanding_cnt <= 4'd0;
    end else begin
        case ({ar_accepted, r_accepted})
            2'b10  : outstanding_cnt <= outstanding_cnt + 4'd1;
            2'b01  : outstanding_cnt <= outstanding_cnt - 4'd1;
            default: ;   // 2'b00 or 2'b11: unchanged
        endcase
    end
end

// =========================================================================
// Output pusher
//   Atomic 2-push of a 64-bit payload into the 32-bit output FIFO.
//   Low-32 first (ordering convention), high-32 second.
//   pusher_idle high when ready for a new push_req.
//   Engine usage: drive push_req=1 + push_data[63:0] when pusher_idle=1.
//   Pulse is captured in a single cycle; pusher then takes 3 cycles to
//   land both halves (unless out_fifo_full stalls).
// =========================================================================
localparam PS_IDLE = 2'd0;
localparam PS_LO   = 2'd1;
localparam PS_HI   = 2'd2;

reg  [1:0]  push_state;
reg  [63:0] push_payload;
reg         push_done;              // 1-cycle pulse when PS_HI -> PS_IDLE lands

assign pusher_idle = (push_state == PS_IDLE);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        push_state   <= PS_IDLE;
        push_payload <= 64'd0;
        push_done    <= 1'b0;
    end else begin
        push_done <= 1'b0;   // default; pulses only on PS_HI completion
        case (push_state)
            PS_IDLE: begin
                if (push_req) begin
                    push_payload <= push_data;
                    push_state   <= PS_LO;
                end
            end
            PS_LO: if (~out_fifo_full) push_state <= PS_HI;
            PS_HI: if (~out_fifo_full) begin
                push_state <= PS_IDLE;
                push_done  <= 1'b1;
            end
            default: push_state <= PS_IDLE;
        endcase
    end
end

// Combinational winc/wdata gated with ~out_fifo_full so JG's FIFO protocol
// invariant (no_write_on_full) holds trivially.
assign out_valid = ((push_state == PS_LO) || (push_state == PS_HI)) & ~out_fifo_full;
assign out_data  = (push_state == PS_LO) ? push_payload[31:0]  :
                   (push_state == PS_HI) ? push_payload[63:32] : 32'd0;

// =========================================================================
// CALC engine ALU operand registers (forward; driven in CALC block)
// =========================================================================
reg  [1:0]  calc_alu_op;
reg  [63:0] calc_alu_a;
reg  [63:0] calc_alu_b;
reg         calc_alu_start;

// =========================================================================
// ALU operand routing
//   Exact-form GUASS uses dedicated combinational multipliers for sum_sq
//   accumulation, threshold compute, and (N*x - S)^2 -- it does NOT use
//   the shared 64-bit ALU MULT. So the muxed operands below are CALC-only.
//   (Old GUASS ALU regs deleted along with the floor-form Pass 2 path.)
// =========================================================================
wire [1:0]  alu_op    = in_calc_state ? calc_alu_op    : 2'b00;
wire [63:0] alu_a_in  = in_calc_state ? calc_alu_a     : 64'd0;
wire [63:0] alu_b_in  = in_calc_state ? calc_alu_b     : 64'd0;
wire        alu_start = in_calc_state ? calc_alu_start : 1'b0;

// =========================================================================
// ALU
//   Uniform 2-cycle pipeline for ADD/SUB/MULT/ASR so the engine FSMs can
//   treat all ops with one latency. Stage 1 computes; stage 2 holds.
//   For MULT, DC can retime partial products into stage 1 so the 64x64
//   signed path meets clk2=11.3 ns without manual pipeline.
//   Opcodes (matching spec p.6):
//     2'b00 ADD, 2'b01 SUB, 2'b10 MULT (low 64 bits), 2'b11 ASR (shamt=b[5:0])
// =========================================================================
reg  [63:0] alu_result_s1;
reg  [63:0] alu_result_s2;
reg         alu_start_s1;
reg         alu_done;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        alu_result_s1 <= 64'd0;
        alu_result_s2 <= 64'd0;
        alu_start_s1  <= 1'b0;
        alu_done      <= 1'b0;
    end else begin
        alu_start_s1 <= alu_start;
        alu_done     <= alu_start_s1;
        case (alu_op)
            2'b00  : alu_result_s1 <= alu_a_in + alu_b_in;
            2'b01  : alu_result_s1 <= alu_a_in - alu_b_in;
            2'b10  : alu_result_s1 <= alu_a_in * alu_b_in;
            2'b11  : alu_result_s1 <= $signed(alu_a_in) >>> alu_b_in[5:0];
            default: alu_result_s1 <= 64'd0;
        endcase
        alu_result_s2 <= alu_result_s1;
    end
end

wire [63:0] alu_y = alu_result_s2;

// =========================================================================
// (Removed: sequential 72/11 divider and 36-bit sequential isqrt.
//  Both were used only by the old floor-form GUASS path (mu = S/N,
//  sigma = floor(sqrt(var_sum/N))) which has been replaced by the
//  exact-form filter (N*x-S)^2 <= N*Sum(x^2) - S^2 in TS_GUASS_THRESH.
//  Eliminates ~180 cycles of GUASS latency per pattern and removes the
//  clk2 critical-path pressure from the sqrt squaring.)
// =========================================================================

// =========================================================================
// CALC engine
//   Post-order DFS of 4 prefix expression trees (spec p.5).
//   Walker/reducer FSM + explicit stack (max depth 8, spec p.5 rule 2).
//   Each stack frame = {opcode[1:0], rptr[15:0], left_val[63:0], phase[1:0]}
//   Phase: PH_GOT_NONE = waiting for left child;
//          PH_GOT_LEFT = waiting for right child (left value latched).
//   Flow: root at {bank_arr[i], row_arr[i], 8'h00}; fetch, decode, descend
//   left; on return from left, descend right; on return from right, reduce
//   via ALU; propagate value up; at sp==0, emit tree result.
// =========================================================================

localparam C_IDLE      = 4'd0;
localparam C_INIT      = 4'd1;
localparam C_FETCH     = 4'd2;
localparam C_WAIT      = 4'd3;
localparam C_DECODE    = 4'd4;
localparam C_RETURN    = 4'd5;
localparam C_ALU_WAIT  = 4'd6;
localparam C_EMIT      = 4'd7;
localparam C_WAIT_PUSH = 4'd8;
localparam C_NEXT_TREE = 4'd9;

localparam PH_GOT_NONE = 2'd0;
localparam PH_GOT_LEFT = 2'd1;

reg [3:0]  calc_state;

// Stack (max depth 8)
reg [1:0]  stk_opcode [0:7];
reg [15:0] stk_rptr   [0:7];
reg [63:0] stk_left   [0:7];
reg [1:0]  stk_phase  [0:7];
reg [3:0]  sp;

// Current-node processing state
reg [15:0] cur_addr;
reg [63:0] cur_node_word;
reg [63:0] return_value;
reg [1:0]  tree_idx;

// Decoded fields of cur_node_word (spec p.5 Fig 2/3)
wire        node_is_operator = cur_node_word[63];
wire [63:0] node_num_value   = {{33{cur_node_word[62]}}, cur_node_word[62:32]};
wire [15:0] node_lptr        = cur_node_word[31:16];
wire [15:0] node_rptr        = cur_node_word[15:0];
wire [1:0]  node_opcode      = cur_node_word[33:32];

// Convenience: parent frame's phase (valid when sp > 0)
wire [1:0]  parent_phase  = (sp > 4'd0) ? stk_phase [sp - 4'd1] : 2'd0;
wire [1:0]  parent_opcode = (sp > 4'd0) ? stk_opcode[sp - 4'd1] : 2'd0;
wire [63:0] parent_left   = (sp > 4'd0) ? stk_left  [sp - 4'd1] : 64'd0;
wire [15:0] parent_rptr   = (sp > 4'd0) ? stk_rptr  [sp - 4'd1] : 16'd0;

integer stk_i;
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        calc_state      <= C_IDLE;
        sp              <= 4'd0;
        cur_addr        <= 16'd0;
        cur_node_word   <= 64'd0;
        return_value    <= 64'd0;
        tree_idx        <= 2'd0;
        calc_issue_req  <= 1'b0;
        calc_issue_addr <= 16'd0;
        calc_push_req   <= 1'b0;
        calc_push_data  <= 64'd0;
        calc_alu_op     <= 2'd0;
        calc_alu_a      <= 64'd0;
        calc_alu_b      <= 64'd0;
        calc_alu_start  <= 1'b0;
        calc_done_reg   <= 1'b0;
        for (stk_i = 0; stk_i < 8; stk_i = stk_i + 1) begin
            stk_opcode[stk_i] <= 2'd0;
            stk_rptr[stk_i]   <= 16'd0;
            stk_left[stk_i]   <= 64'd0;
            stk_phase[stk_i]  <= 2'd0;
        end
    end else if (!in_calc_state) begin
        // Top FSM is not in TS_CALC: freeze CALC engine at C_IDLE so that
        // spurious alu_done / word_valid pulses from GUASS passes can't
        // advance its FSM. (Otherwise CALC could enter a corrupted state
        // by the time the next CALC pattern starts.)
        calc_state      <= C_IDLE;
        sp              <= 4'd0;
        tree_idx        <= 2'd0;
        calc_issue_req  <= 1'b0;
        calc_push_req   <= 1'b0;
        calc_alu_start  <= 1'b0;
        calc_done_reg   <= 1'b0;
    end else begin
        // Default one-shot pulses
        calc_alu_start <= 1'b0;
        calc_done_reg  <= 1'b0;

        case (calc_state)
            C_IDLE: begin
                calc_issue_req <= 1'b0;
                calc_push_req  <= 1'b0;
                if (in_calc_state) begin
                    tree_idx   <= 2'd0;
                    sp         <= 4'd0;
                    calc_state <= C_INIT;
                end
            end

            C_INIT: begin
                // Start of a tree: root addr = {bank_arr[tree_idx], row_arr[tree_idx], 8'h00}
                cur_addr   <= {bank_arr[tree_idx], row_arr[tree_idx], 8'h00};
                sp         <= 4'd0;
                calc_state <= C_FETCH;
            end

            C_FETCH: begin
                // Issue AR; hold issue_req high until ar_issuer acknowledges.
                calc_issue_req  <= 1'b1;
                calc_issue_addr <= cur_addr;
                if (issue_ack) begin
                    calc_issue_req <= 1'b0;
                    calc_state     <= C_WAIT;
                end
            end

            C_WAIT: begin
                // Wait for the reassembled R word.
                if (word_valid) begin
                    cur_node_word <= word_out;
                    calc_state    <= C_DECODE;
                end
            end

            C_DECODE: begin
                if (node_is_operator) begin
                    // Push frame for this operator, then descend to LPtr.
                    stk_opcode[sp] <= node_opcode;
                    stk_rptr[sp]   <= node_rptr;
                    stk_left[sp]   <= 64'd0;
                    stk_phase[sp]  <= PH_GOT_NONE;
                    sp             <= sp + 4'd1;
                    cur_addr       <= node_lptr;
                    calc_state     <= C_FETCH;
                end else begin
                    // Number: its sign-extended value is returned to parent.
                    return_value <= node_num_value;
                    calc_state   <= C_RETURN;
                end
            end

            C_RETURN: begin
                if (sp == 4'd0) begin
                    // Root returned: emit this tree's result.
                    calc_state <= C_EMIT;
                end else begin
                    case (parent_phase)
                        PH_GOT_NONE: begin
                            // return_value is the left child's result.
                            stk_left[sp - 4'd1]  <= return_value;
                            stk_phase[sp - 4'd1] <= PH_GOT_LEFT;
                            cur_addr             <= parent_rptr;
                            calc_state           <= C_FETCH;
                        end
                        PH_GOT_LEFT: begin
                            // return_value is the right child's result. Run ALU.
                            calc_alu_op    <= parent_opcode;
                            calc_alu_a     <= parent_left;
                            calc_alu_b     <= return_value;
                            calc_alu_start <= 1'b1;
                            calc_state     <= C_ALU_WAIT;
                        end
                        default: calc_state <= C_IDLE;   // unreachable
                    endcase
                end
            end

            C_ALU_WAIT: begin
                if (alu_done) begin
                    return_value <= alu_y;
                    sp           <= sp - 4'd1;
                    calc_state   <= C_RETURN;
                end
            end

            C_EMIT: begin
                // Submit the tree result to the output pusher.
                if (pusher_idle) begin
                    calc_push_req  <= 1'b1;
                    calc_push_data <= return_value;
                    calc_state     <= C_WAIT_PUSH;
                end
            end

            C_WAIT_PUSH: begin
                calc_push_req <= 1'b0;
                if (push_done) begin
                    calc_state <= C_NEXT_TREE;
                end
            end

            C_NEXT_TREE: begin
                if (tree_idx == 2'd3) begin
                    // All four trees emitted.
                    calc_done_reg <= 1'b1;
                    calc_state    <= C_IDLE;
                end else begin
                    tree_idx   <= tree_idx + 2'd1;
                    calc_state <= C_INIT;
                end
            end

            default: calc_state <= C_IDLE;
        endcase
    end
end

// =========================================================================
// GUASS engine (exact-form filter, two scan passes)
//   Address map (bank-sequential, matches PATTERN.v scan order; supports
//   FAQ Q19/Q20/Q21 in_bank ordering and repeats):
//     scan_idx in [0..1023]
//       bank = bank_arr[scan_idx[9:8]]
//       row  = row_arr [scan_idx[9:8]]
//       col  = scan_idx[7:0]
//
//   Pipeline (3 GUASS states; 5 in old floor-form):
//     Pass 1 (TS_GUASS_P1): scan all 1024 words; accumulate
//       sum_x   = S  = Sum  (x)     over Type=0 entries
//       sum_sq  = SS = Sum  (x*x)   over Type=0 entries
//       n_count = N
//       Pulse guass_p1_done_reg when recv_idx == 1023.
//     Threshold (TS_GUASS_THRESH): 2-cycle compute of
//       thresh = N*SS - S*S = N^2 * sigma^2  (Cauchy-Schwarz: >= 0).
//     Pass 3 (TS_GUASS_P3): re-scan; for each Type=0 word x, keep iff
//       (N*x - S)^2 <= thresh   (== exact spec |x - mu| <= sigma).
//       Last position (cell 1023, FAQ Q21) force-emitted via P3_DRAIN /
//       P3_WAIT_TERM if not already pushed by the filter.
//
//   No division anywhere; no sqrt anywhere; no Verilog `$signed` mult.
// =========================================================================

reg  [10:0] issue_idx;       // next AR to issue      (0..1024)
reg  [10:0] recv_idx;        // next R to consume     (0..1024)
reg  [41:0] sum_x;           // S  = Sum  (x)        Pass 1
reg  [71:0] sum_sq;          // SS = Sum  (x*x)      Pass 1   (max 1024 * (2^31-1)^2 ~ 2^72)
reg  [10:0] n_count;         // N                   Pass 1

// Threshold compute (TS_GUASS_THRESH; replaces old mu/var/sigma divider+sqrt path)
reg  [82:0] N_sum_sq;        // N * SS              (11b * 72b -> 83b)
reg  [83:0] S_sq;            // S * S               (42b * 42b -> 84b)
reg  [83:0] thresh;          // sigma_sq_N2 = N*SS - S*S  (>=0 by Cauchy-Schwarz)
reg  [10:0] N_reg;           // snapshot of n_count for THRESH/P3 reuse
reg  [41:0] S_reg;           // snapshot of sum_x   for THRESH/P3 reuse

// Pass 3 phase encoding (drain + terminator management)
localparam P3_SCAN      = 2'd0;
localparam P3_DRAIN     = 2'd1;
localparam P3_WAIT_TERM = 2'd2;

// Edge detection on top_state so we can reset pass-local state on entry.
reg  [3:0]  top_state_d;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) top_state_d <= TS_IDLE;
    else        top_state_d <= top_state;
end

wire enter_p1     = (top_state == TS_GUASS_P1)     && (top_state_d != TS_GUASS_P1);
wire enter_thresh = (top_state == TS_GUASS_THRESH) && (top_state_d != TS_GUASS_THRESH);
wire enter_p3     = (top_state == TS_GUASS_P3)     && (top_state_d != TS_GUASS_P3);

// =========================================================================
// GUASS arithmetic helper wires (combinational, full-width context to
// avoid Verilog's self-determined width truncation inside concatenations).
//
// Pass 1 :  p1_x_sq = (word_out[62:32])^2     (62b, used by sum_sq accum)
// Pass 3 :  p3_N_x  = N_reg * word_out[62:32] (42b)
//           p3_delta_abs = |p3_N_x - S_reg|   (42b)
//           p3_delta_sq  = p3_delta_abs^2     (84b)
//           p3_keep      = Type==0 AND delta_sq <= thresh
// Spec p.6 + FAQ Q9: keep entry iff |x - mu| <= sigma.
// Algebraic equivalent: (N*x - S)^2 <= N*Sum(x^2) - S^2 = thresh.
// =========================================================================
wire [61:0] p1_x_sq      = word_out[62:32] * word_out[62:32];
wire [41:0] p3_N_x       = N_reg * word_out[62:32];
wire [41:0] p3_delta_abs = (p3_N_x >= S_reg) ? (p3_N_x - S_reg)
                                             : (S_reg - p3_N_x);
wire [83:0] p3_delta_sq  = p3_delta_abs * p3_delta_abs;
wire        p3_keep      = (word_out[63] == 1'b0) && (p3_delta_sq <= thresh);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        issue_idx         <= 11'd0;
        recv_idx          <= 11'd0;
        sum_x             <= 42'd0;
        sum_sq            <= 72'd0;
        n_count           <= 11'd0;
        N_sum_sq          <= 83'd0;
        S_sq              <= 84'd0;
        thresh            <= 84'd0;
        N_reg             <= 11'd0;
        S_reg             <= 42'd0;
        thresh_done_reg   <= 1'b0;
        thresh_phase      <= 1'b0;
        guass_p1_done_reg <= 1'b0;
        guass_p3_done_reg <= 1'b0;
        word_1023_reg     <= 64'd0;
        last_pushed       <= 1'b0;
        push_pending      <= 1'b0;
        push_pending_data <= 64'd0;
        p3_phase          <= P3_SCAN;
        guass_issue_req   <= 1'b0;
        guass_issue_addr  <= 16'd0;
        guass_push_req    <= 1'b0;
        guass_push_data   <= 64'd0;
    end else begin
        // Default one-shots
        guass_p1_done_reg <= 1'b0;
        guass_p3_done_reg <= 1'b0;
        thresh_done_reg   <= 1'b0;
        guass_push_req    <= 1'b0;

        // Reset pass-local state on entering Pass 1.
        if (enter_p1) begin
            issue_idx <= 11'd0;
            recv_idx  <= 11'd0;
            sum_x     <= 42'd0;
            sum_sq    <= 72'd0;
            n_count   <= 11'd0;
            guass_issue_req  <= 1'b0;
            guass_issue_addr <= 16'd0;
        end

        // Pass 1 work: issue + accumulate (skip the entry cycle).
        //   For each Type-0 word: accumulate sum_x (S = Sum x) AND sum_sq
        //   (SS = Sum x*x) in the same cycle. Combinational 31x31 squarer
        //   (62-bit product) zero-extends into the 72-bit sum_sq accumulator.
        //   Exact-form filter (TS_GUASS_THRESH + TS_GUASS_P3) needs both.
        if ((top_state == TS_GUASS_P1) && !enter_p1) begin
            // Issue side
            if ((issue_idx < 11'd1024) && (outstanding_cnt < OUTSTANDING_MAX)) begin
                guass_issue_req  <= 1'b1;
                guass_issue_addr <= {bank_arr[issue_idx[9:8]],
                                     row_arr [issue_idx[9:8]],
                                     issue_idx[7:0]};
            end else begin
                guass_issue_req  <= 1'b0;
            end
            if (issue_ack) begin
                issue_idx <= issue_idx + 11'd1;
            end

            // Receive side
            if (word_valid) begin
                if (word_out[63] == 1'b0) begin
                    sum_x   <= sum_x  + {11'd0, word_out[62:32]};
                    sum_sq  <= sum_sq + {10'd0, p1_x_sq};
                    n_count <= n_count + 11'd1;
                end
                recv_idx <= recv_idx + 11'd1;
                if (recv_idx == 11'd1023) begin
                    guass_p1_done_reg <= 1'b1;
                    guass_issue_req   <= 1'b0;
                end
            end
        end

        // Threshold compute (TS_GUASS_THRESH): exact-form filter prep.
        //   Cycle 0: snapshot N and S, launch two parallel multiplies in
        //            parallel: N_sum_sq = N*SS (11x72 -> 83b) and
        //            S_sq = S*S (42x42 -> 84b).
        //   Cycle 1: thresh = N_sum_sq - S_sq (84b unsigned, >=0 by
        //            Cauchy-Schwarz: (Sum 1*xi)^2 <= N * Sum xi^2).
        //            Pulse thresh_done_reg to advance Top FSM to TS_GUASS_P3.
        //   N=0 case: sum_x=0, sum_sq=0 -> thresh=0; P3 produces no Type-0
        //   filter pass (no Type-0 words exist), terminator path emits cell
        //   1023 once via the existing P3_DRAIN/WAIT_TERM logic.
        if (enter_thresh) begin
            N_reg        <= n_count;
            S_reg        <= sum_x;
            thresh_phase <= 1'b0;
        end else if (top_state == TS_GUASS_THRESH) begin
            case (thresh_phase)
                1'b0: begin
                    // Pad both operands to result width to guarantee no
                    // truncation under any Verilog interpretation.
                    N_sum_sq     <= {72'd0, N_reg} * {11'd0, sum_sq};   // 83b * 83b -> 83b
                    S_sq         <= {42'd0, S_reg} * {42'd0, S_reg};    // 84b * 84b -> 84b
                    thresh_phase <= 1'b1;
                end
                1'b1: begin
                    // {1'b0, N_sum_sq} widens 83b -> 84b for unsigned subtract.
                    // Result >= 0 by Cauchy-Schwarz: (Sum xi)^2 <= N * Sum xi^2.
                    thresh          <= {1'b0, N_sum_sq} - S_sq;
                    thresh_done_reg <= 1'b1;
                end
            endcase
        end

        // Reset pass-local state on entering Pass 3.
        if (enter_p3) begin
            issue_idx         <= 11'd0;
            recv_idx          <= 11'd0;
            last_pushed       <= 1'b0;
            push_pending      <= 1'b0;
            p3_phase          <= P3_SCAN;
            word_1023_reg     <= 64'd0;
            guass_issue_req   <= 1'b0;
        end

        // Pass 3 work: scan + filter + emit + terminator.
        //   Filter rule (matches PATTERN.v:491-506 Interpretation C):
        //     - For i in [0..1022] : emit if Type=0 AND lo <= v <= hi.
        //     - For i == 1023     : emit if filter-pass (sets last_pushed=1).
        //   Drain: after recv_idx=1024 and any in-flight push lands, if
        //   !last_pushed push word_1023_reg as terminator. Then pulse done.
        //   Stall: push_pending=1 freezes R consumer (consumer_stall=1) so
        //   the 1-deep buffer never overflows when pusher stalls on FIFO-full.
        if ((top_state == TS_GUASS_P3) && !enter_p3) begin
            // Buffer flush (fires whenever a buffered push can land).
            // Guard on !guass_push_req so we don't fire a second time in
            // the same cycle the pusher is accepting our previous push_req
            // (pusher_idle is still 1 pre-edge but state is transitioning
            // to PS_LO; the second push_req would be ignored by the pusher).
            if (push_pending && pusher_idle && !guass_push_req) begin
                guass_push_req    <= 1'b1;
                guass_push_data   <= push_pending_data;
                push_pending      <= 1'b0;
            end

            case (p3_phase)
                P3_SCAN: begin
                    // Issue side (bank-sequential, same as Pass 1/2)
                    if ((issue_idx < 11'd1024) && (outstanding_cnt < OUTSTANDING_MAX)) begin
                        guass_issue_req  <= 1'b1;
                        guass_issue_addr <= {bank_arr[issue_idx[9:8]],
                                             row_arr [issue_idx[9:8]],
                                             issue_idx[7:0]};
                    end else begin
                        guass_issue_req  <= 1'b0;
                    end
                    if (issue_ack) begin
                        issue_idx <= issue_idx + 11'd1;
                    end

                    // Receive side: filter + push decision
                    if (word_valid) begin
                        // Latch word 1023 for possible terminator use
                        if (recv_idx == 11'd1023) begin
                            word_1023_reg <= word_out;
                        end

                        // Filter-pass test (exact form): Type=0 AND
                        // (N*word_val - S)^2 <= thresh
                        if (p3_keep) begin
                            // Emit: direct-submit if pusher idle AND no
                            // push_req currently in flight (which would be
                            // accepted this cycle, moving pusher to PS_LO
                            // and silently dropping a second push_req).
                            if (pusher_idle && !push_pending && !guass_push_req) begin
                                guass_push_req  <= 1'b1;
                                guass_push_data <= word_out;
                            end else begin
                                push_pending      <= 1'b1;
                                push_pending_data <= word_out;
                            end
                            if (recv_idx == 11'd1023) begin
                                last_pushed <= 1'b1;
                            end
                        end

                        recv_idx <= recv_idx + 11'd1;
                        if (recv_idx == 11'd1023) begin
                            guass_issue_req <= 1'b0;
                            p3_phase        <= P3_DRAIN;
                        end
                    end
                end

                P3_DRAIN: begin
                    // Wait for any in-flight / buffered push to complete.
                    // !guass_push_req guard: prevents racing with a buffer-flush
                    // that fired the SAME cycle we entered DRAIN (last in-range
                    // filter-pass push was buffered, released by flush, and
                    // pusher is about to capture).  Without this guard, DRAIN
                    // would fire the terminator's push_req while the pusher is
                    // already grabbing the prior push's data from guass_push_data,
                    // and WAIT_TERM would then mis-observe that prior push's
                    // push_done pulse as the terminator's -- losing the terminator.
                    if (!push_pending && pusher_idle && !guass_push_req) begin
                        if (last_pushed) begin
                            guass_p3_done_reg <= 1'b1;
                            p3_phase          <= P3_SCAN;
                        end else begin
                            // Kick terminator push with the raw word at idx 1023
                            guass_push_req    <= 1'b1;
                            guass_push_data   <= word_1023_reg;
                            p3_phase          <= P3_WAIT_TERM;
                        end
                    end
                end

                P3_WAIT_TERM: begin
                    if (push_done) begin
                        guass_p3_done_reg <= 1'b1;
                        p3_phase          <= P3_SCAN;
                    end
                end

                default: p3_phase <= P3_SCAN;
            endcase
        end

        // Clamp guass_issue_req to 0 outside of active GUASS scan passes.
        if (!in_guass_state) begin
            guass_issue_req <= 1'b0;
        end
    end
end

// =========================================================================
// Flag sidebands: tied low (not used in this design)
// =========================================================================
assign flag_clk2_to_handshake = 1'b0;
assign flag_clk2_to_fifo      = 1'b0;
assign ar_flag_wclk_to_fifo   = 1'b0;
assign r_flag_rclk_to_fifo    = 1'b0;

// =========================================================================
// AXI snoop AR channel combinational outputs
//   Rule 5: ar_addr = 0 when ar_valid = 0 (masked).
// =========================================================================
assign ar_addr  = ar_valid_reg ? {16'd0, ar_addr_reg_inner} : 32'd0;
assign ar_valid = ar_valid_reg;
assign ar_ready = ~ar_fifo_full;    // slave-ready := AR FIFO not full
assign r_ready  = 1'b1;             // Phase A: always ready to accept R

endmodule

module CLK_3_MODULE (
    clk,
    rst_n,
    
    r_fifo_full,
    r_out_valid,
    r_out_data,

	ar_fifo_empty,
    ar_fifo_rdata,
    ar_fifo_rinc,

    ar_flag_fifo_to_rclk,
    ar_flag_rclk_to_fifo,

	r_flag_fifo_to_wclk,
    r_flag_wclk_to_fifo,

	ar_addr, 
    ar_valid, 
    ar_ready,
    r_data,  
    // r_resp, 
    r_valid, 
    r_ready,

	dram_cmd,  // {CS_n, RAS_n, CAS_n, WE_n}
    dram_ba,
    dram_addr,
    dram_wdata,
    dram_rdata,
    dram_valid
);
input 			clk;
input 			rst_n;

input  		ar_fifo_empty;
output      	ar_fifo_rinc;
input [31:0] 	ar_fifo_rdata;

input 			r_fifo_full;
output      	r_out_valid;
output [31:0] 	r_out_data;
// You can use the the custom flag ports for your design
input  			ar_flag_fifo_to_rclk,r_flag_fifo_to_wclk;
output 			ar_flag_rclk_to_fifo,r_flag_wclk_to_fifo;


output [31:0] ar_addr;
output reg    ar_valid;
output        ar_ready;
output [63:0] r_data;
output        r_valid;
output reg    r_ready;

output reg  [3:0]  dram_cmd;  // {CS_n, RAS_n, CAS_n, WE_n}
output reg  [1:0]  dram_ba;
output reg  [10:0] dram_addr;
output reg  [63:0] dram_wdata;
input [63:0] dram_rdata;
input        dram_valid;

// =========================================================================
// DRAM command encoding (spec p.10) = {CS_n, RAS_n, CAS_n, WE_n}
// =========================================================================
localparam CMD_NOP  = 4'b0111;
localparam CMD_ACT  = 4'b0011;
localparam CMD_READ = 4'b0101;
localparam CMD_PRE  = 4'b0010;

// =========================================================================
// Dual FSM design for 4-cycle-per-read steady-state cadence.
//   Issuer FSM: pops AR, handles ACT/RCD/PRE/RP, issues READ. Within a
//   same-row stream, runs at I_IDLE -> I_POP -> I_CAP -> I_READ -> I_IDLE
//   (4 cycles per read). No pre-pop: this guarantees any PRE we issue is
//   always at least t_RAS=5 cycles after its ACT and never collides with
//   a still-in-flight READ in pseudo_DRAM's t_CL pipeline.
//   Receiver FSM: watches dram_valid, captures the 64-bit word, pushes
//   low half then high half to the 32-bit R FIFO in 2 cycles, then pulses
//   the r_valid snoop (also on the push_hi cycle).
//   The two FSMs run concurrently; the issuer's READ cadence (4 cycles)
//   is slower than the receiver's push cadence (2 cycles per read plus
//   idle), so the R FIFO never overflows.
//   Throughput budget for GUASS: 2048 reads (P1+P2) x 4 cycles = 8192
//   clk3, ~14100 clk1 at clk3=34.7ns / clk1=20.1ns, under the 20000 cap.
// =========================================================================
localparam I_IDLE = 4'd0;
localparam I_POP  = 4'd1;
localparam I_CAP  = 4'd2;
localparam I_PRE  = 4'd3;
localparam I_RP1  = 4'd4;
localparam I_RP2  = 4'd5;
localparam I_RP3  = 4'd6;
localparam I_ACT  = 4'd7;
localparam I_RCD1 = 4'd8;
localparam I_RCD2 = 4'd9;
localparam I_READ = 4'd10;
localparam I_GAP  = 4'd11;  // NOP after READ; pre-pops next AR

reg [3:0]  iss_state;
reg        streaming;         // pre-pop raised rinc in I_READ

localparam R_WAIT = 2'd0;
localparam R_LO   = 2'd1;
localparam R_HI   = 2'd2;

reg [1:0]  recv_state;
reg [63:0] rdata_cap;          // 64-bit word being pushed to FIFO
reg [63:0] spill_buf;           // backup hold for a 2nd pending dram_valid
reg        spill_valid;

// Latched fields of current AR being processed by issuer
reg [1:0]  cur_bank;
reg [5:0]  cur_row;
reg [7:0]  cur_col;

// Per-bank row tracking (spec p.4: 4 banks, rows 0..63)
reg        bank_active [0:3];
reg [5:0]  open_row    [0:3];

// AR/R snoop registers (combinational mask below enforces rules 5/9)
reg [15:0] ar_addr_reg;
reg        r_valid_r;
reg [63:0] r_data_reg;

// In-flight read counter: READs issued minus deliveries from DRAM.
// complete_ev uses dram_valid (local clk3 signal from pseudo_DRAM) so
// inflight_cnt's update has only the ar_fifo_empty CDC fan-in (via
// iss_state). INFLIGHT_MAX=2 matches the 2-slot receive buffer capacity
// (rdata_cap + spill_buf); DRAM can never have more than 2 reads in
// flight so dram_valid always has room when captured.
reg [3:0]  inflight_cnt;
localparam INFLIGHT_MAX = 4'd2;

wire issue_ev    = (iss_state == I_READ) && (inflight_cnt < INFLIGHT_MAX);
wire complete_ev = dram_valid;

integer bi;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        iss_state    <= I_IDLE;
        streaming    <= 1'b0;
        cur_bank     <= 2'd0;
        cur_row      <= 6'd0;
        cur_col      <= 8'd0;
        for (bi = 0; bi < 4; bi = bi + 1) begin
            bank_active[bi] <= 1'b0;
            open_row[bi]    <= 6'd0;
        end
        dram_cmd     <= CMD_NOP;
        dram_ba      <= 2'd0;
        dram_addr    <= 11'd0;
        dram_wdata   <= 64'd0;
        ar_valid     <= 1'b0;
        ar_addr_reg  <= 16'd0;
        recv_state   <= R_WAIT;
        rdata_cap    <= 64'd0;
        spill_buf    <= 64'd0;
        spill_valid  <= 1'b0;
        r_valid_r    <= 1'b0;
        r_data_reg   <= 64'd0;
        r_ready      <= 1'b1;
        inflight_cnt <= 4'd0;
    end else begin
        // In-flight counter: simultaneous issue and complete cancel.
        case ({issue_ev, complete_ev})
            2'b10: inflight_cnt <= inflight_cnt + 4'd1;
            2'b01: inflight_cnt <= inflight_cnt - 4'd1;
            default: ;
        endcase

        // Per-cycle defaults
        ar_valid     <= 1'b0;
        r_valid_r    <= 1'b0;
        dram_cmd     <= CMD_NOP;
        dram_ba      <= 2'd0;
        dram_addr    <= 11'd0;
        dram_wdata   <= 64'd0;
        r_ready      <= 1'b1;

        // -----------------------------------------------------------------
        // ISSUER FSM
        // -----------------------------------------------------------------
        case (iss_state)
            I_IDLE: begin
                if (!ar_fifo_empty) iss_state <= I_POP;
            end

            // One wait cycle after rinc; fifo commits the pop at this edge.
            I_POP: iss_state <= I_CAP;

            // Capture popped AR, pulse ar_valid snoop for 1 cycle, branch.
            I_CAP: begin
                cur_bank    <= ar_fifo_rdata[15:14];
                cur_row     <= ar_fifo_rdata[13:8];
                cur_col     <= ar_fifo_rdata[7:0];
                ar_valid    <= 1'b1;
                ar_addr_reg <= ar_fifo_rdata[15:0];
                if (bank_active[ar_fifo_rdata[15:14]] &&
                    (open_row[ar_fifo_rdata[15:14]] == ar_fifo_rdata[13:8])) begin
                    iss_state <= I_READ;
                end else if (bank_active[ar_fifo_rdata[15:14]]) begin
                    iss_state <= I_PRE;
                end else begin
                    iss_state <= I_ACT;
                end
            end

            // Close the currently open row in cur_bank, wait t_RP = 3.
            I_PRE: begin
                dram_cmd              <= CMD_PRE;
                dram_ba               <= cur_bank;
                bank_active[cur_bank] <= 1'b0;
                iss_state             <= I_RP1;
            end
            I_RP1: iss_state <= I_RP2;
            I_RP2: iss_state <= I_RP3;
            I_RP3: iss_state <= I_ACT;

            // Open the target row, wait t_RCD = 2.
            I_ACT: begin
                dram_cmd              <= CMD_ACT;
                dram_ba               <= cur_bank;
                dram_addr             <= {5'd0, cur_row};
                bank_active[cur_bank] <= 1'b1;
                open_row[cur_bank]    <= cur_row;
                iss_state             <= I_RCD1;
            end
            I_RCD1: iss_state <= I_RCD2;
            I_RCD2: iss_state <= I_READ;

            // Issue READ and pre-pop next AR for 3-cycle-per-read
            // throughput. Gated on inflight_cnt < INFLIGHT_MAX to cap
            // pipeline depth. If the next AR targets a different row
            // (same bank), I_CAP will branch to I_PRE; t_RAS=5 is
            // naturally satisfied (ACT at X, PRE at >= X+6 cycles).
            I_READ: begin
                if (inflight_cnt < INFLIGHT_MAX) begin
                    dram_cmd  <= CMD_READ;
                    dram_ba   <= cur_bank;
                    dram_addr <= {3'd0, cur_col};
                    // Pre-pop next AR during the t_CL gap. streaming tracks
                    // whether the next pop should fire in I_GAP.
                    streaming <= !ar_fifo_empty;
                    iss_state <= I_GAP;
                end
                // else stall in I_READ
            end

            // NOP gap cycle; FIFO commits the pre-pop at this posedge
            // so fifo_rdata is ready when I_CAP samples it.
            I_GAP: iss_state <= streaming ? I_CAP : I_IDLE;

            default: iss_state <= I_IDLE;
        endcase

        // -----------------------------------------------------------------
        // RECEIVER FSM (reacts to dram_valid from pseudo_DRAM)
        //   3-state pipeline: R_WAIT latches dram_rdata into rdata_cap;
        //   R_LO pushes low half to R FIFO (stalls on r_fifo_full); R_HI
        //   pushes high half + pulses r_valid snoop (also stalls on full).
        //   A 1-entry spill_buf captures a 2nd dram_valid that arrives
        //   while the receiver is busy, so no pulse is ever missed.
        //   Combined with INFLIGHT_MAX=2 throttle, at most 2 reads are in
        //   flight at once so one spill slot suffices.
        // -----------------------------------------------------------------
        // Capture-always: dram_valid is never ignored.
        if (dram_valid) begin
            if (recv_state == R_WAIT) begin
                rdata_cap <= dram_rdata;
            end else if (!spill_valid) begin
                spill_buf   <= dram_rdata;
                spill_valid <= 1'b1;
            end
        end

        case (recv_state)
            R_WAIT: begin
                // New dram_valid this cycle is captured into rdata_cap by
                // the capture-always block above; just advance to R_LO.
                // Otherwise, if spill_buf already holds a prior pending
                // read, consume it and start pushing.
                if (dram_valid) begin
                    recv_state <= R_LO;
                end else if (spill_valid) begin
                    rdata_cap   <= spill_buf;
                    spill_valid <= 1'b0;
                    recv_state  <= R_LO;
                end
            end

            R_LO: if (!r_fifo_full) recv_state <= R_HI;

            R_HI: if (!r_fifo_full) begin
                r_valid_r  <= 1'b1;
                r_data_reg <= rdata_cap;
                // If a 2nd read is waiting in spill, chain into it.
                if (spill_valid) begin
                    rdata_cap   <= spill_buf;
                    spill_valid <= 1'b0;
                    recv_state  <= R_LO;
                end else begin
                    recv_state <= R_WAIT;
                end
            end

            default: recv_state <= R_WAIT;
        endcase
    end
end

// Combinational winc/wdata for R FIFO gated with ~r_fifo_full so JG's FIFO
// protocol invariant (no_write_on_full) holds trivially.
assign r_out_valid = ((recv_state == R_LO) || (recv_state == R_HI)) & ~r_fifo_full;
assign r_out_data  = (recv_state == R_LO) ? rdata_cap[31:0]  :
                     (recv_state == R_HI) ? rdata_cap[63:32] : 32'd0;

// Combinational AXI snoop outputs.
// ar_addr = 0 when ar_valid = 0 (spec p.9 rule 5).
// r_data  = 0 when r_valid  = 0 (spec p.9 rule 9).
assign ar_addr  = ar_valid ? {16'd0, ar_addr_reg} : 32'd0;
assign ar_ready = 1'b1;
assign r_data   = r_valid_r ? r_data_reg : 64'd0;
assign r_valid  = r_valid_r;

// Combinational AR FIFO rinc gated with ~ar_fifo_empty so JG's FIFO protocol
// invariant (no_read_on_empty) holds trivially. I_POP and I_GAP (when
// streaming) are the designated pop cycles; the empty check here also guards
// against any transient where the pop target has been drained.
assign ar_fifo_rinc = ((iss_state == I_POP) ||
                       ((iss_state == I_GAP) && streaming)) & ~ar_fifo_empty;

// Flag sidebands unused.
assign ar_flag_rclk_to_fifo = 1'b0;
assign r_flag_wclk_to_fifo  = 1'b0;

endmodule










































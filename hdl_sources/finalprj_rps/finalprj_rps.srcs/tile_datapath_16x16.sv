module tile_datapath_16x16 #(
    parameter int N            = 16,
    parameter int DATA_W       = 8,
    parameter int ACC_W        = 32,
    parameter int SCALE_W      = 32,
    parameter int SCALE_FRAC   = 24,
    parameter int INPUT_CYCLES = 16,
    parameter int FLUSH_CYCLES = 30,
    parameter int CLEAR_CYCLES = 16
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,

    input  logic                         start,
    input  logic                         en,

    input  logic signed [DATA_W-1:0]     raw_act_vec [0:N-1],
    input  logic signed [DATA_W-1:0]     raw_wgt_vec [0:N-1],
    input  logic [SCALE_W-1:0]           scale_q,

    output logic                         input_active,
    output logic                         drain_active,
    output logic                         busy,
    output logic                         done,

    output logic                         out_valid,
    output logic signed [DATA_W-1:0]     out_vec [0:N-1],
    output logic [$clog2(N)-1:0]         out_row_idx
);

localparam int OUT_W          = DATA_W;
localparam int STREAM_CYCLES  = INPUT_CYCLES + FLUSH_CYCLES;
localparam int CLEAR_CNT_W    = (CLEAR_CYCLES <= 1) ? 1 : $clog2(CLEAR_CYCLES);
localparam int STREAM_CNT_W   = (STREAM_CYCLES <= 1) ? 1 : $clog2(STREAM_CYCLES);
localparam int OUTPUT_CNT_W   = (N <= 1) ? 1 : $clog2(N + 1);

typedef enum logic [2:0] {
    ST_IDLE,
    ST_CLEAR,
    ST_STREAM,
    ST_DRAIN,
    ST_DONE
} state_t;

state_t state;

logic [CLEAR_CNT_W-1:0]  clear_count;
logic [STREAM_CNT_W-1:0] stream_count;
logic [OUTPUT_CNT_W-1:0] output_count;
logic                    drain_started;

logic block_clear;
logic array_en;
logic drain_en;
logic post_en;
logic drain_start;
logic array_rst_n;
logic stream_input_valid;

logic signed [DATA_W-1:0] skewer_act_in    [0:N-1];
logic signed [DATA_W-1:0] skewer_wgt_in    [0:N-1];
logic signed [DATA_W-1:0] act_vec_skewed   [0:N-1];
logic signed [DATA_W-1:0] wgt_vec_skewed   [0:N-1];
logic signed [DATA_W-1:0] act_last_vec     [0:N-1];
logic signed [DATA_W-1:0] wgt_last_vec     [0:N-1];
logic signed [ACC_W-1:0]  acc_mat          [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  row_vec          [0:N-1];
logic                    row_valid;
logic [$clog2(N)-1:0]    row_idx_out;
logic                    row_valid_d1;
logic [$clog2(N)-1:0]    row_idx_d1;
logic                    drain_busy;
logic                    drain_done;
logic                    post_out_valid;
logic signed [OUT_W-1:0] post_out_vec      [0:N-1];

assign input_active       = (state == ST_STREAM);
assign drain_active       = (state == ST_DRAIN);
assign busy               = (state != ST_IDLE) && (state != ST_DONE);
assign block_clear        = clear || (state == ST_CLEAR);
assign array_en           = en && ((state == ST_CLEAR) || (state == ST_STREAM));
assign drain_en           = en && ((state == ST_CLEAR) || (state == ST_DRAIN));
assign post_en            = en && ((state == ST_CLEAR) || (state == ST_DRAIN));
assign drain_start        = en && (state == ST_DRAIN) && !drain_started;
assign array_rst_n        = ~rst;
assign stream_input_valid = (state == ST_STREAM) && (stream_count < INPUT_CYCLES);
assign out_valid          = post_out_valid;
assign out_row_idx        = row_idx_d1;

generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_lane_connect
        assign skewer_act_in[g_lane] = stream_input_valid ? raw_act_vec[g_lane] : '0;
        assign skewer_wgt_in[g_lane] = stream_input_valid ? raw_wgt_vec[g_lane] : '0;
        assign out_vec[g_lane]       = post_out_vec[g_lane];
    end
endgenerate

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) act_skewer (
    .clk     (clk),
    .rst     (rst),
    .clear   (block_clear),
    .en      (array_en),
    .vec_in  (skewer_act_in),
    .vec_out (act_vec_skewed)
);

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) wgt_skewer (
    .clk     (clk),
    .rst     (rst),
    .clear   (block_clear),
    .en      (array_en),
    .vec_in  (skewer_wgt_in),
    .vec_out (wgt_vec_skewed)
);

PE_ARRAY_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) array_core (
    .i_clk          (clk),
    .i_rst_n        (array_rst_n),
    .i_clear        (block_clear),
    .i_en           (array_en),
    .i_act_vec      (act_vec_skewed),
    .i_wgt_vec      (wgt_vec_skewed),
    .o_act_last_vec (act_last_vec),
    .o_wgt_last_vec (wgt_last_vec),
    .o_acc_mat      (acc_mat)
);

acc_drain_16x16 #(
    .N    (N),
    .ACC_W(ACC_W)
) acc_drain (
    .clk         (clk),
    .rst         (rst),
    .clear       (block_clear),
    .en          (drain_en),
    .start       (drain_start),
    .acc_mat     (acc_mat),
    .row_vec     (row_vec),
    .row_valid   (row_valid),
    .row_idx_out (row_idx_out),
    .busy        (drain_busy),
    .done        (drain_done)
);

post_processor_16 #(
    .N         (N),
    .ACC_W     (ACC_W),
    .OUT_W     (OUT_W),
    .SCALE_W   (SCALE_W),
    .SCALE_FRAC(SCALE_FRAC)
) post_proc (
    .clk       (clk),
    .rst       (rst),
    .clear     (block_clear),
    .en        (post_en),
    .row_valid (row_valid),
    .row_vec   (row_vec),
    .scale_q   (scale_q),
    .out_valid (post_out_valid),
    .out_vec   (post_out_vec)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state         <= ST_IDLE;
        clear_count   <= '0;
        stream_count  <= '0;
        output_count  <= '0;
        drain_started <= 1'b0;
        row_valid_d1  <= 1'b0;
        row_idx_d1    <= '0;
        done          <= 1'b0;
    end
    else if (en) begin
        done <= 1'b0;

        case (state)
            // IDLE waits for a single-tile transaction request.
            ST_IDLE: begin
                clear_count   <= '0;
                stream_count  <= '0;
                output_count  <= '0;
                drain_started <= 1'b0;
                row_valid_d1  <= 1'b0;
                row_idx_d1    <= '0;

                if (start) begin
                    state <= ST_CLEAR;
                end
            end

            // CLEAR resets accumulators and shifts zero through PE forwarding regs.
            ST_CLEAR: begin
                stream_count  <= '0;
                output_count  <= '0;
                drain_started <= 1'b0;
                row_valid_d1  <= 1'b0;
                row_idx_d1    <= '0;

                if (clear_count == CLEAR_CYCLES-1) begin
                    clear_count <= '0;
                    state       <= ST_STREAM;
                end
                else begin
                    clear_count <= clear_count + 1'b1;
                end
            end

            // STREAM accepts 16 raw vectors, then masks input to zero for flush cycles.
            ST_STREAM: begin
                output_count  <= '0;
                drain_started <= 1'b0;
                row_valid_d1  <= 1'b0;
                row_idx_d1    <= '0;

                if (stream_count == STREAM_CYCLES-1) begin
                    stream_count <= '0;
                    state        <= ST_DRAIN;
                end
                else begin
                    stream_count <= stream_count + 1'b1;
                end
            end

            // DRAIN starts row readout once, then counts post-processed output rows.
            ST_DRAIN: begin
                row_valid_d1 <= row_valid;
                row_idx_d1   <= row_idx_out;

                if (!drain_started) begin
                    drain_started <= 1'b1;
                end

                if (post_out_valid) begin
                    if (output_count == N-1) begin
                        output_count <= '0;
                        done         <= 1'b1;
                        state        <= ST_DONE;
                    end
                    else begin
                        output_count <= output_count + 1'b1;
                    end
                end
            end

            // DONE holds the one-cycle done pulse state, then returns to IDLE.
            ST_DONE: begin
                row_valid_d1  <= 1'b0;
                row_idx_d1    <= '0;
                drain_started <= 1'b0;
                output_count  <= '0;
                state         <= ST_IDLE;
            end

            default: begin
                state         <= ST_IDLE;
                clear_count   <= '0;
                stream_count  <= '0;
                output_count  <= '0;
                drain_started <= 1'b0;
                row_valid_d1  <= 1'b0;
                row_idx_d1    <= '0;
                done          <= 1'b0;
            end
        endcase
    end
end

endmodule

`timescale 1ns / 1ps

// 16x16 engine that computes one output tile
// Reads K tiles in order, accumulates them in the PE array, then writes the output to BRAM
module output_tile_engine_feature_major_16x16 #(
    parameter int N = 16,
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14,
    parameter int SCALE_W = 32,
    parameter int SCALE_FRAC = 24,
    parameter int K_TILES_W = 8,
    parameter int CLEAR_CYCLES = 16,
    parameter int FLUSH_CYCLES = 30
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic start,
    input logic en,

    input logic [ADDR_W-1:0] act_base_addr,
    input logic [ADDR_W-1:0] wgt_base_addr,
    input logic [ADDR_W-1:0] out_base_addr,
    input logic act_layout_row_major,
    input logic out_layout_row_major,

    input logic [ADDR_W-1:0] act_k_stride,
    input logic [ADDR_W-1:0]  wgt_k_stride,
    input logic [K_TILES_W-1:0] num_k_tiles,

    input logic [SCALE_W-1:0] scale_q,

    output logic bram_act_en,
    output logic [ADDR_W-1:0] bram_act_addr,
    input logic [WORD_W-1:0] bram_act_rdata,

    output logic bram_wgt_en,
    output logic [ADDR_W-1:0] bram_wgt_addr,
    input logic [WORD_W-1:0] bram_wgt_rdata,

    output logic bram_out_wr,
    output logic [ADDR_W-1:0] bram_out_addr,
    output logic [WORD_W-1:0] bram_out_wdata,

    output logic busy,
    output logic done
);

// Widths for row indexes, counters, and address offsets
localparam int ROW_W = (N <= 1) ? 1 : $clog2(N);
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int CLEAR_CNT_W = (CLEAR_CYCLES <= 1) ? 1 : $clog2(CLEAR_CYCLES);
// One raw stream register stage is included in the flush count
localparam int STREAM_STAGE_CYCLES = 1;
localparam int EFFECTIVE_FLUSH_CYCLES = FLUSH_CYCLES + STREAM_STAGE_CYCLES;
localparam int FLUSH_CNT_W = (EFFECTIVE_FLUSH_CYCLES <= 1) ? 1 : $clog2(EFFECTIVE_FLUSH_CYCLES);
localparam int OFFSET_W = ADDR_W + K_TILES_W;

// FSM for the full output-tile flow: readers, PE array, drain, and writer
typedef enum logic [3:0] {
    ST_IDLE,
    ST_CLEAR_ARRAY,
    ST_START_READER,
    ST_CAPTURE_READER,
    ST_STREAM_TO_ARRAY,
    ST_FLUSH_ARRAY,
    ST_NEXT_K_TILE,
    ST_START_WRITER,
    ST_DRAIN_START,
    ST_DRAIN_AND_POST,
    ST_WRITE_WAIT,
    ST_DONE
} state_t;

state_t state;

logic reader_start;
logic act_reader_raw_valid;
logic act_reader_busy;
logic act_reader_done;
logic wgt_reader_raw_valid;
logic wgt_reader_busy;
logic wgt_reader_done;
logic reader_raw_valid;

logic signed [DATA_W-1:0] reader_raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] reader_raw_wgt_vec [0:N-1];

// Holds the 16 stream vectors from the readers before replaying them into the PE array
logic signed [DATA_W-1:0] act_buf [0:N-1][0:N-1];
logic signed [DATA_W-1:0] wgt_buf [0:N-1][0:N-1];

// Activation and weight streams before and after the skewers
logic signed [DATA_W-1:0] stream_act_vec [0:N-1];
logic signed [DATA_W-1:0] stream_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] act_vec_skewed [0:N-1];
logic signed [DATA_W-1:0] wgt_vec_skewed [0:N-1];

logic signed [DATA_W-1:0] array_act_last_vec [0:N-1];
logic signed [DATA_W-1:0] array_wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat [0:N-1][0:N-1];

// Signals for draining accumulated rows and sending them to the post processor
logic drain_start;
logic drain_row_valid;
logic [ROW_W-1:0] drain_row_idx;
logic [ROW_W-1:0] drain_row_idx_d1;
logic [ROW_W-1:0] drain_row_idx_d2;
logic drain_busy;
logic drain_done;
logic signed [ACC_W-1:0] drain_row_vec [0:N-1];

logic post_out_valid;
logic signed [DATA_W-1:0] post_out_vec [0:N-1];

// Only one writer starts, depending on the requested output layout
logic writer_start;
logic writer_busy;
logic writer_done;
logic writer_feature_start;
logic writer_feature_busy;
logic writer_feature_done;
logic writer_feature_bram_wr;
logic [ADDR_W-1:0] writer_feature_bram_addr;
logic [WORD_W-1:0] writer_feature_bram_wdata;
logic writer_row_start;
logic writer_row_busy;
logic writer_row_done;
logic writer_row_bram_wr;
logic [ADDR_W-1:0] writer_row_bram_addr;
logic [WORD_W-1:0] writer_row_bram_wdata;

logic [K_TILES_W-1:0] k_tile_idx;
logic [K_TILES_W-1:0] num_k_tiles_m1;
logic last_k_tile;

// Counters for reader capture, PE feed, clear cycles, and flush cycles
logic [COUNT_W-1:0] reader_valid_count;
logic [COUNT_W-1:0] feed_count;
logic [CLEAR_CNT_W-1:0] clear_count;
logic [FLUSH_CNT_W-1:0] flush_count;
logic [ROW_W-1:0] feed_index;

logic component_clear;
logic datapath_en;
logic [OFFSET_W-1:0] k_idx_ext;
logic [OFFSET_W-1:0] act_stride_ext;
logic [OFFSET_W-1:0] wgt_stride_ext;
logic [OFFSET_W-1:0] act_k_offset;
logic [OFFSET_W-1:0] wgt_k_offset;
logic [ADDR_W-1:0] current_act_base;
logic [ADDR_W-1:0] current_wgt_base;

assign busy = (state != ST_IDLE);

// Start pulses for submodules, generated from the FSM state
assign reader_start = en && (state == ST_START_READER);
assign writer_start = en && (state == ST_START_WRITER);
assign writer_feature_start = writer_start && !out_layout_row_major;
assign writer_row_start = writer_start && out_layout_row_major;
assign drain_start  = en && (state == ST_DRAIN_START);
assign reader_raw_valid = act_reader_raw_valid && wgt_reader_raw_valid;
// Select writer outputs based on the final storage layout
assign writer_busy = out_layout_row_major ? writer_row_busy : writer_feature_busy;
assign writer_done = out_layout_row_major ? writer_row_done : writer_feature_done;
assign bram_out_wr = out_layout_row_major ? writer_row_bram_wr : writer_feature_bram_wr;
assign bram_out_addr = out_layout_row_major ? writer_row_bram_addr : writer_feature_bram_addr;
assign bram_out_wdata = out_layout_row_major ? writer_row_bram_wdata : writer_feature_bram_wdata;

assign component_clear = clear || (en && (state == ST_CLEAR_ARRAY));
// PE-array datapath runs only during clear, stream, and flush phases
assign datapath_en = en && ((state == ST_CLEAR_ARRAY) || (state == ST_STREAM_TO_ARRAY) || (state == ST_FLUSH_ARRAY));

assign feed_index = feed_count[ROW_W-1:0];
assign num_k_tiles_m1 = num_k_tiles - 1'b1;
assign last_k_tile = (k_tile_idx == num_k_tiles_m1);

// Compute activation and weight base addresses from the current K tile and stride
assign k_idx_ext = {{ADDR_W{1'b0}}, k_tile_idx};
assign act_stride_ext = {{K_TILES_W{1'b0}}, act_k_stride};
assign wgt_stride_ext = {{K_TILES_W{1'b0}}, wgt_k_stride};
assign act_k_offset = k_idx_ext * act_stride_ext;
assign wgt_k_offset = k_idx_ext * wgt_stride_ext;
assign current_act_base = act_base_addr + act_k_offset[ADDR_W-1:0];
assign current_wgt_base = wgt_base_addr + wgt_k_offset[ADDR_W-1:0];

generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_stream_mux
        // Replay buffered values into the PE array only in the stream state
        assign stream_act_vec[g_lane] = (state == ST_STREAM_TO_ARRAY) ? act_buf[feed_index][g_lane] : '0;
        assign stream_wgt_vec[g_lane] = (state == ST_STREAM_TO_ARRAY) ? wgt_buf[feed_index][g_lane] : '0;
    end
endgenerate

always_ff @(posedge clk) begin
    if (rst || clear) begin
        for (int lane = 0; lane < N; lane++) begin
            raw_act_vec[lane] <= '0;
            raw_wgt_vec[lane] <= '0;
        end
    end
    else if (datapath_en) begin
        for (int lane = 0; lane < N; lane++) begin
            // Add one register stage before the skewers
            raw_act_vec[lane] <= stream_act_vec[lane];
            raw_wgt_vec[lane] <= stream_wgt_vec[lane];
        end
    end
end

// Reader for activation words in the current K tile
bram_activation_reader_16x16 #(
    .N (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) act_reader (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .start (reader_start),
    .en (en),
    .row_major_layout(act_layout_row_major),
    .act_base_addr (current_act_base),
    .bram_act_en (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata(bram_act_rdata),
    .raw_valid (act_reader_raw_valid),
    .raw_act_vec (reader_raw_act_vec),
    .busy (act_reader_busy),
    .done (act_reader_done)
);

// Reader for weight words in the current K tile, timed with activation reads
bram_weight_reader_16x16 #(
    .N (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) wgt_reader (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .start (reader_start),
    .en (en),
    .wgt_base_addr (current_wgt_base),
    .bram_wgt_en (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata(bram_wgt_rdata),
    .raw_valid (wgt_reader_raw_valid),
    .raw_wgt_vec (reader_raw_wgt_vec),
    .busy (wgt_reader_busy),
    .done (wgt_reader_done)
);

// Skew the activation stream per lane to match systolic timing
skewer_16 #(
    .N (N),
    .DATA_W(DATA_W)
) act_skewer (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (datapath_en),
    .vec_in (raw_act_vec),
    .vec_out (act_vec_skewed)
);

// Skew the weight stream the same way
skewer_16 #(
    .N (N),
    .DATA_W (DATA_W)
) wgt_skewer (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (datapath_en),
    .vec_in (raw_wgt_vec),
    .vec_out (wgt_vec_skewed)
);

// Feed the skew-aligned activation and weight streams into the 16x16 PE array
PE_ARRAY_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) array_core (
    .i_clk (clk),
    .i_rst_n (!rst),
    .i_clear (component_clear),
    .i_en (datapath_en),
    .i_act_vec (act_vec_skewed),
    .i_wgt_vec (wgt_vec_skewed),
    .o_act_last_vec (array_act_last_vec),
    .o_wgt_last_vec (array_wgt_last_vec),
    .o_acc_mat (acc_mat)
);

// Drain acc_mat row by row after all K tiles have accumulated
acc_drain_16x16 #(
    .N    (N),
    .ACC_W(ACC_W)
) acc_drain (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (en),
    .start (drain_start),
    .acc_mat (acc_mat),
    .row_vec (drain_row_vec),
    .row_valid (drain_row_valid),
    .row_idx_out(drain_row_idx),
    .busy (drain_busy),
    .done (drain_done)
);

// Apply ReLU, scale, rounding, and saturation to drained rows
post_processor_16 #(
    .N (N),
    .ACC_W (ACC_W),
    .OUT_W (DATA_W),
    .SCALE_W (SCALE_W),
    .SCALE_FRAC (SCALE_FRAC)
) post_proc (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (en),
    .row_valid(drain_row_valid),
    .row_vec (drain_row_vec),
    .scale_q (scale_q),
    .out_valid(post_out_valid),
    .out_vec (post_out_vec)
);

// Intermediate layer outputs are stored feature-major for the next layer reader
bram_output_writer_feature_major_16x16 #(
    .N (N),
    .DATA_W (DATA_W),
    .WORD_W (WORD_W),
    .ADDR_W (ADDR_W)
) feature_writer (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (en),
    .start (writer_feature_start),
    .out_base_addr (out_base_addr),
    .in_valid (post_out_valid),
    .in_row_idx (drain_row_idx_d2),
    .in_vec (post_out_vec),
    .bram_wr (writer_feature_bram_wr),
    .bram_addr (writer_feature_bram_addr),
    .bram_wdata (writer_feature_bram_wdata),
    .busy (writer_feature_busy),
    .done (writer_feature_done)
);

// Final layer output is stored row-major for PS/Vitis
bram_output_writer_16x16 #(
    .N (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) row_writer (
    .clk (clk),
    .rst (rst),
    .clear (component_clear),
    .en (en),
    .start (writer_row_start),
    .out_base_addr(out_base_addr),
    .in_valid (post_out_valid),
    .in_row_idx (drain_row_idx_d2),
    .in_vec (post_out_vec),
    .bram_wr (writer_row_bram_wr),
    .bram_addr (writer_row_bram_addr),
    .bram_wdata (writer_row_bram_wdata),
    .busy (writer_row_busy),
    .done (writer_row_done)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        k_tile_idx  <= '0;
        reader_valid_count <= '0;
        feed_count <= '0;
        clear_count <= '0;
        flush_count <= '0;
        drain_row_idx_d1 <= '0;
        drain_row_idx_d2 <= '0;
        done <= 1'b0;
        for (int stream = 0; stream < N; stream++) begin
            for (int lane = 0; lane < N; lane++) begin
                act_buf[stream][lane] <= '0;
                wgt_buf[stream][lane] <= '0;
            end
        end
    end
    else if (en) begin
        done <= 1'b0;
        drain_row_idx_d1 <= drain_row_idx;
        drain_row_idx_d2 <= drain_row_idx_d1;

        case (state)
            ST_IDLE: begin
                k_tile_idx <= '0;
                reader_valid_count <= '0;
                feed_count <= '0;
                clear_count <= '0;
                flush_count <= '0;
                drain_row_idx_d1 <= '0;
                drain_row_idx_d2 <= '0;

                if (start) begin
                    // Clear the PE accumulators only once at the start of an output tile
                    // Keep acc_mat partial sums when moving to the next K tile
                    state <= ST_CLEAR_ARRAY;
                end
            end

            ST_CLEAR_ARRAY: begin
                // Clear phase for PE accumulators and forwarding paths
                reader_valid_count <= '0;
                feed_count <= '0;
                flush_count <= '0;
                drain_row_idx_d1 <= '0;
                drain_row_idx_d2 <= '0;

                if (clear_count == CLEAR_CYCLES-1) begin
                    clear_count <= '0;
                    state <= ST_START_READER;
                end
                else begin
                    clear_count <= clear_count + 1'b1;
                end
            end

            ST_START_READER: begin
                // Raise one reader start pulse for the current K tile
                reader_valid_count <= '0;
                state <= ST_CAPTURE_READER;
            end

            ST_CAPTURE_READER: begin
                if (reader_raw_valid) begin
                    // Store into buffers only when activation and weight readers are both valid
                    for (int lane = 0; lane < N; lane++) begin
                        act_buf[reader_valid_count][lane] <= reader_raw_act_vec[lane];
                        wgt_buf[reader_valid_count][lane] <= reader_raw_wgt_vec[lane];
                    end

                    if (reader_valid_count == N-1) begin
                        reader_valid_count <= '0;
                        feed_count <= '0;
                        state <= ST_STREAM_TO_ARRAY;
                    end
                    else begin
                        reader_valid_count <= reader_valid_count + 1'b1;
                    end
                end
            end

            ST_STREAM_TO_ARRAY: begin
                // Replay the 16 buffered stream vectors into the PE array
                if (feed_count == N-1) begin
                    feed_count <= '0;
                    flush_count <= '0;
                    state <= ST_FLUSH_ARRAY;
                end
                else begin
                    feed_count <= feed_count + 1'b1;
                end
            end

            ST_FLUSH_ARRAY: begin
                // Push zeros through to flush the systolic forwarding paths
                // Keep acc_mat so the next K tile continues the partial sums
                if (flush_count == EFFECTIVE_FLUSH_CYCLES-1) begin
                    flush_count <= '0;
                    if (last_k_tile) begin
                        state <= ST_START_WRITER;
                    end
                    else begin
                        state <= ST_NEXT_K_TILE;
                    end
                end
                else begin
                    flush_count <= flush_count + 1'b1;
                end
            end

            ST_NEXT_K_TILE: begin
                // Advance only the K tile index and keep the PE accumulators
                k_tile_idx <= k_tile_idx + 1'b1;
                reader_valid_count <= '0;
                feed_count <= '0;
                clear_count <= '0;
                flush_count <= '0;
                drain_row_idx_d1 <= '0;
                drain_row_idx_d2 <= '0;
                state <= ST_START_READER;
            end

            ST_START_WRITER: begin
                // Start the writer before drain/post produce valid rows
                state <= ST_DRAIN_START;
            end

            ST_DRAIN_START: begin
                // Raise one drain_start pulse
                // post_processor takes one more cycle after acc_drain outputs row 0
                state <= ST_DRAIN_AND_POST;
            end

            ST_DRAIN_AND_POST: begin
                // Let the post processor and writer handle valid rows until acc_drain finishes
                if (drain_done) begin
                    state <= ST_WRITE_WAIT;
                end
            end

            ST_WRITE_WAIT: begin
                // Wait until the selected writer finishes the BRAM writes
                if (writer_done) begin
                    done  <= 1'b1;
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                // done is raised in ST_WRITE_WAIT, then this state returns to IDLE
                state <= ST_IDLE;
            end

            default: begin
                // Reset internal progress and return to IDLE on an unexpected state
                state <= ST_IDLE;
                k_tile_idx <= '0;
                reader_valid_count <= '0;
                feed_count <= '0;
                clear_count <= '0;
                flush_count <= '0;
                drain_row_idx_d1 <= '0;
                drain_row_idx_d2 <= '0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

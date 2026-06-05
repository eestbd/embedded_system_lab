module output_tile_engine_16x16 #(
    parameter int N            = 16,
    parameter int DATA_W       = 8,
    parameter int ACC_W        = 32,
    parameter int WORD_W       = 128,
    parameter int ADDR_W       = 14,
    parameter int SCALE_W      = 32,
    parameter int SCALE_FRAC   = 24,
    parameter int K_TILES_W    = 8,
    parameter int CLEAR_CYCLES = 16,
    parameter int FLUSH_CYCLES = 30
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         start,
    input  logic                         en,

    input  logic [ADDR_W-1:0]            act_base_addr,
    input  logic [ADDR_W-1:0]            wgt_base_addr,
    input  logic [ADDR_W-1:0]            out_base_addr,

    input  logic [ADDR_W-1:0]            act_k_stride,
    input  logic [ADDR_W-1:0]            wgt_k_stride,
    input  logic [K_TILES_W-1:0]         num_k_tiles,

    input  logic [SCALE_W-1:0]           scale_q,

    output logic                         bram_act_en,
    output logic [ADDR_W-1:0]            bram_act_addr,
    input  logic [WORD_W-1:0]            bram_act_rdata,

    output logic                         bram_wgt_en,
    output logic [ADDR_W-1:0]            bram_wgt_addr,
    input  logic [WORD_W-1:0]            bram_wgt_rdata,

    output logic                         bram_out_wr,
    output logic [ADDR_W-1:0]            bram_out_addr,
    output logic [WORD_W-1:0]            bram_out_wdata,

    output logic                         busy,
    output logic                         done
);

localparam int ROW_W       = (N <= 1) ? 1 : $clog2(N);
localparam int COUNT_W     = (N <= 1) ? 1 : $clog2(N + 1);
localparam int CLEAR_CNT_W = (CLEAR_CYCLES <= 1) ? 1 : $clog2(CLEAR_CYCLES);
localparam int FLUSH_CNT_W = (FLUSH_CYCLES <= 1) ? 1 : $clog2(FLUSH_CYCLES);
localparam int OFFSET_W    = ADDR_W + K_TILES_W;

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
logic reader_raw_valid;
logic reader_busy;
logic reader_done;

logic signed [DATA_W-1:0] reader_raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] reader_raw_wgt_vec [0:N-1];

logic signed [DATA_W-1:0] act_buf [0:N-1][0:N-1];
logic signed [DATA_W-1:0] wgt_buf [0:N-1][0:N-1];

logic signed [DATA_W-1:0] raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] act_vec_skewed [0:N-1];
logic signed [DATA_W-1:0] wgt_vec_skewed [0:N-1];

logic signed [DATA_W-1:0] array_act_last_vec [0:N-1];
logic signed [DATA_W-1:0] array_wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat [0:N-1][0:N-1];

logic drain_start;
logic drain_row_valid;
logic [ROW_W-1:0] drain_row_idx;
logic [ROW_W-1:0] drain_row_idx_d1;
logic drain_busy;
logic drain_done;
logic signed [ACC_W-1:0] drain_row_vec [0:N-1];

logic post_out_valid;
logic signed [DATA_W-1:0] post_out_vec [0:N-1];

logic writer_start;
logic writer_busy;
logic writer_done;

logic [K_TILES_W-1:0] k_tile_idx;
logic [K_TILES_W-1:0] num_k_tiles_m1;
logic                 last_k_tile;

logic [COUNT_W-1:0]     reader_valid_count;
logic [COUNT_W-1:0]     feed_count;
logic [CLEAR_CNT_W-1:0] clear_count;
logic [FLUSH_CNT_W-1:0] flush_count;
logic [ROW_W-1:0]       feed_index;

logic component_clear;
logic datapath_en;
logic [OFFSET_W-1:0] k_idx_ext;
logic [OFFSET_W-1:0] act_stride_ext;
logic [OFFSET_W-1:0] wgt_stride_ext;
logic [OFFSET_W-1:0] act_k_offset;
logic [OFFSET_W-1:0] wgt_k_offset;
logic [ADDR_W-1:0]   current_act_base;
logic [ADDR_W-1:0]   current_wgt_base;

assign busy = (state != ST_IDLE);

assign reader_start = en && (state == ST_START_READER);
assign writer_start = en && (state == ST_START_WRITER);
assign drain_start  = en && (state == ST_DRAIN_START);

assign component_clear = clear || (en && (state == ST_CLEAR_ARRAY));
assign datapath_en     = en && ((state == ST_CLEAR_ARRAY) ||
                                (state == ST_STREAM_TO_ARRAY) ||
                                (state == ST_FLUSH_ARRAY));

assign feed_index = feed_count[ROW_W-1:0];
assign num_k_tiles_m1 = num_k_tiles - 1'b1;
assign last_k_tile = (k_tile_idx == num_k_tiles_m1);

assign k_idx_ext     = {{ADDR_W{1'b0}}, k_tile_idx};
assign act_stride_ext = {{K_TILES_W{1'b0}}, act_k_stride};
assign wgt_stride_ext = {{K_TILES_W{1'b0}}, wgt_k_stride};
assign act_k_offset = k_idx_ext * act_stride_ext;
assign wgt_k_offset = k_idx_ext * wgt_stride_ext;
assign current_act_base = act_base_addr + act_k_offset[ADDR_W-1:0];
assign current_wgt_base = wgt_base_addr + wgt_k_offset[ADDR_W-1:0];

generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_stream_mux
        assign raw_act_vec[g_lane] =
            (state == ST_STREAM_TO_ARRAY) ? act_buf[feed_index][g_lane] : '0;
        assign raw_wgt_vec[g_lane] =
            (state == ST_STREAM_TO_ARRAY) ? wgt_buf[feed_index][g_lane] : '0;
    end
endgenerate

bram_stream_reader_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) reader (
    .clk           (clk),
    .rst           (rst),
    .clear         (component_clear),
    .start         (reader_start),
    .en            (en),
    .act_base_addr (current_act_base),
    .wgt_base_addr (current_wgt_base),
    .bram_act_en   (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata(bram_act_rdata),
    .bram_wgt_en   (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata(bram_wgt_rdata),
    .raw_valid     (reader_raw_valid),
    .raw_act_vec   (reader_raw_act_vec),
    .raw_wgt_vec   (reader_raw_wgt_vec),
    .busy          (reader_busy),
    .done          (reader_done)
);

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) act_skewer (
    .clk    (clk),
    .rst    (rst),
    .clear  (component_clear),
    .en     (datapath_en),
    .vec_in (raw_act_vec),
    .vec_out(act_vec_skewed)
);

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) wgt_skewer (
    .clk    (clk),
    .rst    (rst),
    .clear  (component_clear),
    .en     (datapath_en),
    .vec_in (raw_wgt_vec),
    .vec_out(wgt_vec_skewed)
);

PE_ARRAY_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) array_core (
    .i_clk          (clk),
    .i_rst_n        (!rst),
    .i_clear        (component_clear),
    .i_en           (datapath_en),
    .i_act_vec      (act_vec_skewed),
    .i_wgt_vec      (wgt_vec_skewed),
    .o_act_last_vec (array_act_last_vec),
    .o_wgt_last_vec (array_wgt_last_vec),
    .o_acc_mat      (acc_mat)
);

acc_drain_16x16 #(
    .N    (N),
    .ACC_W(ACC_W)
) acc_drain (
    .clk        (clk),
    .rst        (rst),
    .clear      (component_clear),
    .en         (en),
    .start      (drain_start),
    .acc_mat    (acc_mat),
    .row_vec    (drain_row_vec),
    .row_valid  (drain_row_valid),
    .row_idx_out(drain_row_idx),
    .busy       (drain_busy),
    .done       (drain_done)
);

post_processor_16 #(
    .N         (N),
    .ACC_W     (ACC_W),
    .OUT_W     (DATA_W),
    .SCALE_W   (SCALE_W),
    .SCALE_FRAC(SCALE_FRAC)
) post_proc (
    .clk      (clk),
    .rst      (rst),
    .clear    (component_clear),
    .en       (en),
    .row_valid(drain_row_valid),
    .row_vec  (drain_row_vec),
    .scale_q  (scale_q),
    .out_valid(post_out_valid),
    .out_vec  (post_out_vec)
);

bram_output_writer_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) writer (
    .clk          (clk),
    .rst          (rst),
    .clear        (component_clear),
    .en           (en),
    .start        (writer_start),
    .out_base_addr(out_base_addr),
    .in_valid     (post_out_valid),
    .in_row_idx   (drain_row_idx_d1),
    .in_vec       (post_out_vec),
    .bram_wr      (bram_out_wr),
    .bram_addr    (bram_out_addr),
    .bram_wdata   (bram_out_wdata),
    .busy         (writer_busy),
    .done         (writer_done)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state              <= ST_IDLE;
        k_tile_idx         <= '0;
        reader_valid_count <= '0;
        feed_count         <= '0;
        clear_count        <= '0;
        flush_count        <= '0;
        drain_row_idx_d1   <= '0;
        done               <= 1'b0;
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

        case (state)
            ST_IDLE: begin
                k_tile_idx         <= '0;
                reader_valid_count <= '0;
                feed_count         <= '0;
                clear_count        <= '0;
                flush_count        <= '0;
                drain_row_idx_d1   <= '0;

                if (start) begin
                    // Clear PE accumulators once per output tile. K tile
                    // changes intentionally do not clear acc_mat.
                    state <= ST_CLEAR_ARRAY;
                end
            end

            ST_CLEAR_ARRAY: begin
                reader_valid_count <= '0;
                feed_count         <= '0;
                flush_count        <= '0;
                drain_row_idx_d1   <= '0;

                if (clear_count == CLEAR_CYCLES-1) begin
                    clear_count <= '0;
                    state       <= ST_START_READER;
                end
                else begin
                    clear_count <= clear_count + 1'b1;
                end
            end

            ST_START_READER: begin
                // One-cycle pulse into the BRAM stream reader for this K tile.
                reader_valid_count <= '0;
                state              <= ST_CAPTURE_READER;
            end

            ST_CAPTURE_READER: begin
                if (reader_raw_valid) begin
                    for (int lane = 0; lane < N; lane++) begin
                        act_buf[reader_valid_count][lane] <= reader_raw_act_vec[lane];
                        wgt_buf[reader_valid_count][lane] <= reader_raw_wgt_vec[lane];
                    end

                    if (reader_valid_count == N-1) begin
                        reader_valid_count <= '0;
                        feed_count         <= '0;
                        state              <= ST_STREAM_TO_ARRAY;
                    end
                    else begin
                        reader_valid_count <= reader_valid_count + 1'b1;
                    end
                end
            end

            ST_STREAM_TO_ARRAY: begin
                // Replay the 16 buffered stream vectors into skewer+PE array.
                if (feed_count == N-1) begin
                    feed_count  <= '0;
                    flush_count <= '0;
                    state       <= ST_FLUSH_ARRAY;
                end
                else begin
                    feed_count <= feed_count + 1'b1;
                end
            end

            ST_FLUSH_ARRAY: begin
                // Push zeros through the systolic pipes so the next K tile
                // starts with clean forwarding paths while acc_mat is retained.
                if (flush_count == FLUSH_CYCLES-1) begin
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
                // Advance only the K tile pointer. The PE accumulators keep
                // the partial sum from all previous K tiles.
                k_tile_idx         <= k_tile_idx + 1'b1;
                reader_valid_count <= '0;
                feed_count         <= '0;
                clear_count        <= '0;
                flush_count        <= '0;
                drain_row_idx_d1   <= '0;
                state              <= ST_START_READER;
            end

            ST_START_WRITER: begin
                // Start writer before drain/post begin producing valid rows.
                state <= ST_DRAIN_START;
            end

            ST_DRAIN_START: begin
                // One-cycle drain_start pulse. acc_drain emits row 0 after
                // this clock; post_processor adds one registered latency.
                state <= ST_DRAIN_AND_POST;
            end

            ST_DRAIN_AND_POST: begin
                if (drain_done) begin
                    state <= ST_WRITE_WAIT;
                end
            end

            ST_WRITE_WAIT: begin
                if (writer_done) begin
                    done  <= 1'b1;
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                state <= ST_IDLE;
            end

            default: begin
                state              <= ST_IDLE;
                k_tile_idx         <= '0;
                reader_valid_count <= '0;
                feed_count         <= '0;
                clear_count        <= '0;
                flush_count        <= '0;
                drain_row_idx_d1   <= '0;
                done               <= 1'b0;
            end
        endcase
    end
end

endmodule

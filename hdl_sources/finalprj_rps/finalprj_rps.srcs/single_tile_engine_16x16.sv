`timescale 1ns / 1ps

module single_tile_engine_16x16 #(
    parameter int N            = 16,
    parameter int DATA_W       = 8,
    parameter int ACC_W        = 32,
    parameter int WORD_W       = 128,
    parameter int ADDR_W       = 14,
    parameter int SCALE_W      = 32,
    parameter int SCALE_FRAC   = 24,
    parameter int INPUT_CYCLES = 16,
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

localparam int STREAM_CYCLES = INPUT_CYCLES + FLUSH_CYCLES;
localparam int COUNT_W       = (N <= 1) ? 1 : $clog2(N + 1);
localparam int STREAM_CNT_W  = (STREAM_CYCLES <= 1) ? 1 : $clog2(STREAM_CYCLES);

typedef enum logic [2:0] {
    ST_IDLE,
    ST_START_READER,
    ST_CAPTURE_READER,
    ST_START_WRITER,
    ST_START_TILE,
    ST_FEED_TILE,
    ST_WAIT_DONE,
    ST_DONE
} state_t;

state_t state;

logic reader_start;
logic reader_raw_valid;
logic reader_busy;
logic reader_done;

logic tile_start;
logic tile_input_active;
logic tile_drain_active;
logic tile_busy;
logic tile_done;
logic tile_out_valid;
logic [$clog2(N)-1:0] tile_out_row_idx;
logic signed [DATA_W-1:0] tile_out_vec [0:N-1];

logic writer_start;
logic writer_busy;
logic writer_done;

logic signed [DATA_W-1:0] reader_raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] reader_raw_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] tile_raw_act_vec   [0:N-1];
logic signed [DATA_W-1:0] tile_raw_wgt_vec   [0:N-1];

logic signed [DATA_W-1:0] act_buf [0:N-1][0:N-1];
logic signed [DATA_W-1:0] wgt_buf [0:N-1][0:N-1];

logic [COUNT_W-1:0]      reader_valid_count;
logic [COUNT_W-1:0]      tile_feed_count;
logic [STREAM_CNT_W-1:0] tile_stream_count;
logic [$clog2(N)-1:0]    tile_feed_index;

assign busy         = (state != ST_IDLE);
assign reader_start = en && (state == ST_START_READER);
assign writer_start = en && (state == ST_START_WRITER);
assign tile_start   = en && (state == ST_START_TILE);
assign tile_feed_index = tile_feed_count[$clog2(N)-1:0];

generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_tile_input_mux
        assign tile_raw_act_vec[g_lane] =
            (tile_input_active && (tile_feed_count < N)) ? act_buf[tile_feed_index][g_lane] : '0;
        assign tile_raw_wgt_vec[g_lane] =
            (tile_input_active && (tile_feed_count < N)) ? wgt_buf[tile_feed_index][g_lane] : '0;
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
    .clear         (clear),
    .start         (reader_start),
    .en            (en),
    .act_base_addr (act_base_addr),
    .wgt_base_addr (wgt_base_addr),
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

tile_datapath_16x16 #(
    .N           (N),
    .DATA_W      (DATA_W),
    .ACC_W       (ACC_W),
    .SCALE_W     (SCALE_W),
    .SCALE_FRAC  (SCALE_FRAC),
    .INPUT_CYCLES(INPUT_CYCLES),
    .FLUSH_CYCLES(FLUSH_CYCLES),
    .CLEAR_CYCLES(N)
) tile (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .start        (tile_start),
    .en           (en),
    .raw_act_vec  (tile_raw_act_vec),
    .raw_wgt_vec  (tile_raw_wgt_vec),
    .scale_q      (scale_q),
    .input_active (tile_input_active),
    .drain_active (tile_drain_active),
    .busy         (tile_busy),
    .done         (tile_done),
    .out_valid    (tile_out_valid),
    .out_vec      (tile_out_vec),
    .out_row_idx  (tile_out_row_idx)
);

bram_output_writer_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) writer (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .en           (en),
    .start        (writer_start),
    .out_base_addr(out_base_addr),
    .in_valid     (tile_out_valid),
    .in_row_idx   (tile_out_row_idx),
    .in_vec       (tile_out_vec),
    .bram_wr      (bram_out_wr),
    .bram_addr    (bram_out_addr),
    .bram_wdata   (bram_out_wdata),
    .busy         (writer_busy),
    .done         (writer_done)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state              <= ST_IDLE;
        reader_valid_count <= '0;
        tile_feed_count    <= '0;
        tile_stream_count  <= '0;
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

        case (state)
            ST_IDLE: begin
                reader_valid_count <= '0;
                tile_feed_count    <= '0;
                tile_stream_count  <= '0;

                if (start) begin
                    state <= ST_START_READER;
                end
            end

            // One-cycle pulse into the BRAM stream reader.
            ST_START_READER: begin
                reader_valid_count <= '0;
                state              <= ST_CAPTURE_READER;
            end

            // Capture the 16 valid reader vectors into local stream buffers.
            ST_CAPTURE_READER: begin
                if (reader_raw_valid) begin
                    for (int lane = 0; lane < N; lane++) begin
                        act_buf[reader_valid_count][lane] <= reader_raw_act_vec[lane];
                        wgt_buf[reader_valid_count][lane] <= reader_raw_wgt_vec[lane];
                    end

                    if (reader_valid_count == N-1) begin
                        reader_valid_count <= '0;
                        state              <= ST_START_WRITER;
                    end
                    else begin
                        reader_valid_count <= reader_valid_count + 1'b1;
                    end
                end
            end

            // Start the writer before tile output rows appear.
            ST_START_WRITER: begin
                state <= ST_START_TILE;
            end

            // Start the tile datapath after the reader stream is buffered.
            ST_START_TILE: begin
                tile_feed_count   <= '0;
                tile_stream_count <= '0;
                state             <= ST_FEED_TILE;
            end

            // Replay the first 16 buffered stream vectors, then zeros for flush.
            ST_FEED_TILE: begin
                if (tile_input_active) begin
                    if (tile_feed_count < N) begin
                        tile_feed_count <= tile_feed_count + 1'b1;
                    end

                    if (tile_stream_count == STREAM_CYCLES-1) begin
                        tile_stream_count <= '0;
                        tile_feed_count   <= '0;
                        state             <= ST_WAIT_DONE;
                    end
                    else begin
                        tile_stream_count <= tile_stream_count + 1'b1;
                    end
                end
            end

            // Wait for writer completion after it has accepted all tile rows.
            ST_WAIT_DONE: begin
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
                reader_valid_count <= '0;
                tile_feed_count    <= '0;
                tile_stream_count  <= '0;
                done               <= 1'b0;
            end
        endcase
    end
end

endmodule

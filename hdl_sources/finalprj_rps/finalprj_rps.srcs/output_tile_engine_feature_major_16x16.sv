`timescale 1ns / 1ps

// output tile 하나를 계산하는 16x16 엔진
// K tile을 순서대로 읽어서 PE array에 누산하고, 마지막에 BRAM output으로 저장함
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

// row index, 카운터, 주소 offset에 필요한 폭 계산
localparam int ROW_W = (N <= 1) ? 1 : $clog2(N);
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int CLEAR_CNT_W = (CLEAR_CYCLES <= 1) ? 1 : $clog2(CLEAR_CYCLES);
// raw stream register가 한 단계 있어서 flush cycle에 같이 반영
localparam int STREAM_STAGE_CYCLES = 1;
localparam int EFFECTIVE_FLUSH_CYCLES = FLUSH_CYCLES + STREAM_STAGE_CYCLES;
localparam int FLUSH_CNT_W = (EFFECTIVE_FLUSH_CYCLES <= 1) ? 1 : $clog2(EFFECTIVE_FLUSH_CYCLES);
localparam int OFFSET_W = ADDR_W + K_TILES_W;

// reader, PE array, drain, writer까지 한 output tile 흐름을 관리하는 FSM
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

// reader에서 받은 16개 stream vector를 PE array에 다시 넣기 전 잠시 저장
logic signed [DATA_W-1:0] act_buf [0:N-1][0:N-1];
logic signed [DATA_W-1:0] wgt_buf [0:N-1][0:N-1];

// skewer 앞뒤로 지나가는 activation/weight stream
logic signed [DATA_W-1:0] stream_act_vec [0:N-1];
logic signed [DATA_W-1:0] stream_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] act_vec_skewed [0:N-1];
logic signed [DATA_W-1:0] wgt_vec_skewed [0:N-1];

logic signed [DATA_W-1:0] array_act_last_vec [0:N-1];
logic signed [DATA_W-1:0] array_wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat [0:N-1][0:N-1];

// 누산 결과를 row 단위로 빼고 post processor로 넘기기 위한 신호
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

// output layout에 따라 둘 중 하나의 writer만 start됨
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

// reader capture, PE feed, clear/flush cycle을 세는 카운터들
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

// FSM state에서 하위 모듈로 들어가는 start pulse 생성
assign reader_start = en && (state == ST_START_READER);
assign writer_start = en && (state == ST_START_WRITER);
assign writer_feature_start = writer_start && !out_layout_row_major;
assign writer_row_start = writer_start && out_layout_row_major;
assign drain_start  = en && (state == ST_DRAIN_START);
assign reader_raw_valid = act_reader_raw_valid && wgt_reader_raw_valid;
// 최종 저장 layout에 맞춰 writer 출력 mux 선택
assign writer_busy = out_layout_row_major ? writer_row_busy : writer_feature_busy;
assign writer_done = out_layout_row_major ? writer_row_done : writer_feature_done;
assign bram_out_wr = out_layout_row_major ? writer_row_bram_wr : writer_feature_bram_wr;
assign bram_out_addr = out_layout_row_major ? writer_row_bram_addr : writer_feature_bram_addr;
assign bram_out_wdata = out_layout_row_major ? writer_row_bram_wdata : writer_feature_bram_wdata;

assign component_clear = clear || (en && (state == ST_CLEAR_ARRAY));
// PE array 쪽 datapath는 clear, stream, flush 구간에서만 움직임
assign datapath_en = en && ((state == ST_CLEAR_ARRAY) || (state == ST_STREAM_TO_ARRAY) || (state == ST_FLUSH_ARRAY));

assign feed_index = feed_count[ROW_W-1:0];
assign num_k_tiles_m1 = num_k_tiles - 1'b1;
assign last_k_tile = (k_tile_idx == num_k_tiles_m1);

// 현재 K tile 번호에 stride를 곱해서 activation/weight base 주소 계산
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
        // stream 상태일 때만 buffer 값을 PE array 쪽으로 재생
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
            // skewer 앞에 한 stage를 두고 stream 값을 넘김
            raw_act_vec[lane] <= stream_act_vec[lane];
            raw_wgt_vec[lane] <= stream_wgt_vec[lane];
        end
    end
end

// 현재 K tile의 activation word들을 읽어 오는 reader
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

// 현재 K tile의 weight word들을 activation과 같은 타이밍으로 읽어 옴
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

// activation stream에 lane별 지연을 걸어 systolic 입력 타이밍을 맞춤
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

// weight stream도 같은 방식으로 skew를 줌
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

// skew가 맞춰진 activation/weight를 16x16 PE array에 입력
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

// 모든 K tile 누산이 끝난 뒤 acc_mat을 row 단위로 꺼냄
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

// drain된 row에 ReLU, scale, rounding, saturation 적용
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

// 중간 layer output은 다음 layer reader가 읽기 좋게 feature-major로 저장
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

// 마지막 layer output은 PS/Vitis가 보기 좋게 row-major로 저장
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
                    // output tile 시작할 때 PE accumulator를 한 번만 clear
                    // K tile이 바뀔 때는 acc_mat partial sum을 유지함
                    state <= ST_CLEAR_ARRAY;
                end
            end

            ST_CLEAR_ARRAY: begin
                // PE 내부 accumulator와 forwarding path 초기화 구간
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
                // 현재 K tile에 대해 reader start pulse 한 번 발생
                reader_valid_count <= '0;
                state <= ST_CAPTURE_READER;
            end

            ST_CAPTURE_READER: begin
                if (reader_raw_valid) begin
                    // activation과 weight reader가 같이 valid일 때만 buffer에 저장
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
                // buffer에 모아 둔 16개 stream vector를 PE array로 다시 흘림
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
                // 0을 흘려서 systolic forwarding path를 비우는 구간
                // acc_mat은 유지해서 다음 K tile partial sum과 이어짐
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
                // K tile index만 증가시키고 PE accumulator는 유지
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
                // drain/post가 valid row를 만들기 전에 writer를 먼저 대기시킴
                state <= ST_DRAIN_START;
            end

            ST_DRAIN_START: begin
                // drain_start pulse 한 번 발생
                // acc_drain row 0 출력 뒤 post_processor에서 한 cycle 더 걸림
                state <= ST_DRAIN_AND_POST;
            end

            ST_DRAIN_AND_POST: begin
                // acc_drain이 끝날 때까지 post_processor와 writer가 valid row를 처리
                if (drain_done) begin
                    state <= ST_WRITE_WAIT;
                end
            end

            ST_WRITE_WAIT: begin
                // 선택된 writer가 BRAM write를 마칠 때까지 대기
                if (writer_done) begin
                    done  <= 1'b1;
                    state <= ST_DONE;
                end
            end

            ST_DONE: begin
                // done은 ST_WRITE_WAIT에서 올리고 여기서 IDLE로 복귀
                state <= ST_IDLE;
            end

            default: begin
                // 이상 상태에서는 내부 진행 상태를 초기화하고 IDLE로 복귀
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

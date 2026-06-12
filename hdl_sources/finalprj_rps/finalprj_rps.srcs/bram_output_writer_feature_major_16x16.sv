`timescale 1ns / 1ps

// post processor에서 나온 row 단위 결과를 feature-major layout으로 BRAM에 저장하는 모듈
// 다음 layer activation reader가 feature 기준으로 읽을 수 있게 row/col 방향을 바꿔서 씀
module bram_output_writer_feature_major_16x16 #(
    parameter int N = 16,
    parameter int DATA_W = 8,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic en,
    input logic start,

    input logic [ADDR_W-1:0] out_base_addr,

    input logic in_valid,
    input logic [$clog2(N)-1:0] in_row_idx,
    input logic signed [DATA_W-1:0] in_vec [0:N-1],

    output logic bram_wr,
    output logic [ADDR_W-1:0] bram_addr,
    output logic [WORD_W-1:0] bram_wdata,

    output logic busy,
    output logic done
);

// N개 row를 받고 N개 feature word를 쓰기 위한 카운터 폭
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int IDX_W = (N <= 1) ? 1 : $clog2(N);

// row 캡처 후 feature-major write로 넘어가는 FSM
typedef enum logic [1:0] {
    ST_IDLE,
    ST_CAPTURE,
    ST_WRITE,
    ST_DONE
} state_t;

state_t state;

logic [COUNT_W-1:0] capture_count;
logic [IDX_W-1:0] write_col_idx;
logic [ADDR_W-1:0] col_addr_offset;

// row 단위로 들어온 16x16 결과를 잠시 저장해 두는 타일 버퍼
logic signed [DATA_W-1:0] tile_buf [0:N-1][0:N-1];

assign busy = (state != ST_IDLE);

always_comb begin
    // write_col_idx를 BRAM 주소 offset으로 사용
    col_addr_offset = '0;
    col_addr_offset[IDX_W-1:0] = write_col_idx;
end

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        capture_count <= '0;
        write_col_idx <= '0;
        bram_wr <= 1'b0;
        bram_addr <= '0;
        bram_wdata <= '0;
        done <= 1'b0;
        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                tile_buf[row][col] <= '0;
            end
        end
    end
    else if (!en) begin
        // 내부 상태와 버퍼는 유지하고, 1 cycle pulse 출력만 막음
        bram_wr <= 1'b0;
        done <= 1'b0;
    end
    else begin
        bram_wr <= 1'b0;
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                capture_count <= '0;
                write_col_idx <= '0;

                if (start) begin
                    state <= ST_CAPTURE;
                end
            end

            ST_CAPTURE: begin
                // post_processor 출력은 row 단위로 들어옴
                // in_vec[col] = C[in_row_idx][col]
                if (in_valid) begin
                    for (int col = 0; col < N; col++) begin
                        tile_buf[in_row_idx][col] <= in_vec[col];
                    end

                    if (capture_count == N-1) begin
                        capture_count <= '0;
                        write_col_idx <= '0;
                        state <= ST_WRITE;
                    end
                    else begin
                        capture_count <= capture_count + 1'b1;
                    end
                end
            end

            ST_WRITE: begin
                // 다음 layer reader를 위해 feature-major 형태로 저장
                // bram_wdata[8*row +: 8] = C[row][write_col_idx]
                bram_wr <= 1'b1;
                bram_addr <= out_base_addr + col_addr_offset;
                for (int row = 0; row < N; row++) begin
                    bram_wdata[DATA_W*row +: DATA_W] <= tile_buf[row][write_col_idx];
                end

                if (write_col_idx == N-1) begin
                    write_col_idx <= '0;
                    state <= ST_DONE;
                end
                else begin
                    write_col_idx <= write_col_idx + 1'b1;
                end
            end

            ST_DONE: begin
                // 모든 feature word를 쓴 뒤 done pulse 한 번 발생
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                // 이상 상태에서는 초기 상태로 복귀
                state <= ST_IDLE;
                capture_count <= '0;
                write_col_idx <= '0;
                bram_wr <= 1'b0;
                bram_addr <= '0;
                bram_wdata <= '0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

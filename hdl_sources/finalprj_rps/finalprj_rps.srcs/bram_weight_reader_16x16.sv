`timescale 1ns / 1ps

// weight 16x16 타일을 BRAM에서 읽어서 PE array 입력 순서로 풀어주는 모듈
// BRAM word 16개를 먼저 받아 두고, k 방향으로 한 줄씩 내보냄
module bram_weight_reader_16x16 #(
    parameter int N = 16,
    parameter int DATA_W = 8,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic start,
    input logic en,

    input logic [ADDR_W-1:0] wgt_base_addr,

    output logic bram_wgt_en,
    output logic [ADDR_W-1:0] bram_wgt_addr,
    input  logic [WORD_W-1:0] bram_wgt_rdata,

    output logic raw_valid,
    output logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1],

    output logic busy,
    output logic done
);

// N번 읽고 N번 내보내기 위한 카운터 폭
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int IDX_W = (N <= 1) ? 1 : $clog2(N);

// BRAM 주소 요청, 대기, 캡처, 출력 순서로 도는 FSM
typedef enum logic [2:0] {
    ST_IDLE,
    ST_READ_ADDR_SET,
    ST_READ_WAIT,
    ST_READ_CAPTURE,
    ST_EMIT,
    ST_DONE
} state_t;

state_t state;

logic [COUNT_W-1:0] read_count;
logic [COUNT_W-1:0] emit_count;
logic [IDX_W-1:0] read_index;
logic [IDX_W-1:0] emit_index;

// BRAM에서 읽은 16x16 weight 타일을 잠시 저장하는 버퍼
logic signed [DATA_W-1:0] tile_buf [0:N-1][0:N-1];

// done 상태는 한 사이클만 따로 보고, 나머지 작업 중인 상태를 busy로 봄
assign busy = (state != ST_IDLE) && (state != ST_DONE);
assign read_index = read_count[IDX_W-1:0];
assign emit_index = emit_count[IDX_W-1:0];

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        read_count <= '0;
        emit_count <= '0;
        bram_wgt_en <= 1'b0;
        bram_wgt_addr <= '0;
        raw_valid <= 1'b0;
        done <= 1'b0;
        for (int row = 0; row < N; row++) begin
            raw_wgt_vec[row] <= '0;
            for (int lane = 0; lane < N; lane++) begin
                tile_buf[row][lane] <= '0;
            end
        end
    end
    else if (en) begin
        bram_wgt_en <= 1'b0;
        raw_valid   <= 1'b0;
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                read_count <= '0;
                emit_count <= '0;

                if (start) begin
                    state <= ST_READ_ADDR_SET;
                end
            end

            ST_READ_ADDR_SET: begin
                // BRAM 주소만 먼저 걸어 주는 단계
                // 데이터는 다음 클럭 이후에 들어와서 여기서는 잡지 않음
                bram_wgt_en <= 1'b1;
                bram_wgt_addr <= wgt_base_addr + read_count;
                state <= ST_READ_WAIT;
            end

            ST_READ_WAIT: begin
                // 동기 BRAM 지연 맞추려고 한 사이클 기다림
                state <= ST_READ_CAPTURE;
            end

            ST_READ_CAPTURE: begin
                // 한 word 안의 16개 lane을 현재 read_index 줄에 저장
                for (int lane = 0; lane < N; lane++) begin
                    tile_buf[read_index][lane] <= bram_wgt_rdata[DATA_W*lane +: DATA_W];
                end

                if (read_count == N-1) begin
                    read_count <= '0;
                    emit_count <= '0;
                    state <= ST_EMIT;
                end
                else begin
                    read_count <= read_count + 1'b1;
                    state <= ST_READ_ADDR_SET;
                end
            end

            ST_EMIT: begin
                raw_valid <= 1'b1;
                for (int lane = 0; lane < N; lane++) begin
                    // weight word 하나는 output 쪽 한 줄이고, k_inner 기준으로 세로로 꺼냄
                    raw_wgt_vec[lane] <= tile_buf[lane][emit_index];
                end

                if (emit_count == N-1) begin
                    emit_count <= '0;
                    state <= ST_DONE;
                end
                else begin
                    emit_count <= emit_count + 1'b1;
                end
            end

            ST_DONE: begin
                // done을 한 사이클 올리고 다시 대기 상태로 감
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                // 이상 상태로 들어오면 안전하게 초기 상태로 복귀
                state <= ST_IDLE;
                read_count <= '0;
                emit_count <= '0;
                bram_wgt_en <= 1'b0;
                bram_wgt_addr <= '0;
                raw_valid <= 1'b0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

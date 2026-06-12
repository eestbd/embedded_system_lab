`timescale 1ns / 1ps

// post processor에서 나온 row 단위 결과를 그대로 BRAM에 저장하는 모듈
// row 하나를 128bit word 하나로 pack해서 최종 output 영역에 씀
module bram_output_writer_16x16 #(
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

// N개 row write를 세기 위한 카운터 폭
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int ROW_W = (N <= 1) ? 1 : $clog2(N);

// start 이후 valid row를 받아 쓰고, 마지막에 done을 내는 FSM
typedef enum logic [1:0] {
    ST_IDLE,
    ST_ACTIVE,
    ST_DONE
} state_t;

state_t state;
logic [COUNT_W-1:0] write_count;
logic [ADDR_W-1:0] row_addr_offset;

assign busy = (state == ST_ACTIVE);

always_comb begin
    // in_row_idx를 BRAM 주소 offset으로 사용
    row_addr_offset = '0;
    row_addr_offset[ROW_W-1:0] = in_row_idx;
end

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        write_count <= '0;
        bram_wr <= 1'b0;
        bram_addr <= '0;
        bram_wdata <= '0;
        done <= 1'b0;
    end
    else if (!en) begin
        // 상태와 count는 유지하고, write/done pulse만 막음
        bram_wr <= 1'b0;
        done <= 1'b0;
    end
    else begin
        bram_wr <= 1'b0;
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                write_count <= '0;

                if (start) begin
                    state <= ST_ACTIVE;
                end
            end

            ST_ACTIVE: begin
                if (in_valid) begin
                    // int8 lane 16개를 128bit BRAM word 하나로 묶음
                    // lane 0은 [7:0], lane 15는 [127:120] 위치
                    bram_wr   <= 1'b1;
                    bram_addr <= out_base_addr + row_addr_offset;
                    for (int lane = 0; lane < N; lane++) begin
                        bram_wdata[DATA_W*lane +: DATA_W] <= in_vec[lane];
                    end

                    // 주소는 in_row_idx를 쓰고, done은 valid row를 N개 받은 기준으로 판단
                    if (write_count == N-1) begin
                        write_count <= '0;
                        state <= ST_DONE;
                    end
                    else begin
                        write_count <= write_count + 1'b1;
                    end
                end
            end

            ST_DONE: begin
                // 마지막 row write 이후 done pulse 한 번 발생
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                // 이상 상태에서는 초기 상태로 복귀
                state <= ST_IDLE;
                write_count <= '0;
                bram_wr <= 1'b0;
                bram_addr <= '0;
                bram_wdata <= '0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

`timescale 1ns / 1ps

// PE array에 쌓인 accumulator matrix를 row 단위로 꺼내는 모듈
// start 이후 row 0부터 N-1까지 한 cycle에 한 줄씩 내보냄
module acc_drain_16x16 #(
    parameter int N = 16,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic en,
    input logic start,

    input logic signed [ACC_W-1:0] acc_mat [0:N-1][0:N-1],

    output logic signed [ACC_W-1:0] row_vec [0:N-1],
    output logic row_valid,
    output logic [$clog2(N)-1:0] row_idx_out,
    output logic busy,
    output logic done
);

// 대기, row 출력, done pulse 순서로 도는 간단한 FSM
typedef enum logic [1:0] {
    ST_IDLE,
    ST_DRAIN,
    ST_DONE
} state_t;

state_t state;
logic [$clog2(N)-1:0] next_row_idx;

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        row_valid <= 1'b0;
        row_idx_out <= '0;
        busy <= 1'b0;
        done <= 1'b0;
        next_row_idx <= '0;
        for (int col = 0; col < N; col++) begin
            row_vec[col] <= '0;
        end
    end
    else begin
        done <= 1'b0;

        if (en) begin
            case (state)
                // start는 IDLE에서만 받고, 받는 순간 row 0을 바로 출력
                ST_IDLE: begin
                    row_valid <= 1'b0;
                    busy <= 1'b0;

                    if (start) begin
                        row_valid <= 1'b1;
                        row_idx_out <= '0;
                        busy <= 1'b1;
                        for (int col = 0; col < N; col++) begin
                            row_vec[col] <= acc_mat[0][col];
                        end

                        // N이 1이면 이미 마지막 row라 바로 DONE으로 이동
                        if (N == 1) begin
                            state <= ST_DONE;
                            next_row_idx <= '0;
                        end
                        else begin
                            state <= ST_DRAIN;
                            next_row_idx <= 1'b1;
                        end
                    end
                end

                // enable된 cycle마다 accumulator row 하나씩 출력
                ST_DRAIN: begin
                    row_valid <= 1'b1;
                    row_idx_out <= next_row_idx;
                    busy <= 1'b1;
                    for (int col = 0; col < N; col++) begin
                        row_vec[col] <= acc_mat[next_row_idx][col];
                    end

                    // 마지막 row까지 내보내면 다음 cycle에 done pulse 발생
                    if (next_row_idx == N-1) begin
                        state <= ST_DONE;
                    end
                    else begin
                        next_row_idx <= next_row_idx + 1'b1;
                    end
                end

                // 마지막 valid row 다음 cycle에 done을 한 번만 올림
                ST_DONE: begin
                    row_valid <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    // 혹시 모를 이상 상태에서는 대기 상태로 복귀
                    state <= ST_IDLE;
                    row_valid <= 1'b0;
                    row_idx_out <= '0;
                    busy <= 1'b0;
                    next_row_idx <= '0;
                    for (int col = 0; col < N; col++) begin
                        row_vec[col] <= '0;
                    end
                end
            endcase
        end
    end
end

endmodule

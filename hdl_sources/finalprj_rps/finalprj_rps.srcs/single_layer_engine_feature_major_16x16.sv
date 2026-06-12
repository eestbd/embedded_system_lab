`timescale 1ns / 1ps

// 한 layer 안에서 output tile들을 순서대로 계산하는 모듈
// activation은 재사용하고, weight/output base만 tile마다 바꿔 줌
module single_layer_engine_feature_major_16x16 #(
    parameter int N  = 16,
    parameter int DATA_W = 8,
    parameter int ACC_W = 32,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14,
    parameter int SCALE_W = 32,
    parameter int SCALE_FRAC = 24,
    parameter int K_TILES_W = 8,
    parameter int OUT_TILES_W = 8
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
    input logic [ADDR_W-1:0] wgt_k_stride,
    input logic [ADDR_W-1:0] wgt_out_stride,
    input logic [ADDR_W-1:0] out_tile_stride,

    input logic [K_TILES_W-1:0] num_k_tiles,
    input logic [OUT_TILES_W-1:0] num_out_tiles,

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

// output column tile 하나씩 시작하고 완료를 기다리는 FSM
typedef enum logic [2:0] {
    ST_IDLE,
    ST_START_TILE,
    ST_WAIT_TILE_DONE,
    ST_NEXT_OUT_TILE,
    ST_DONE
} state_t;

state_t state;

logic tile_start;
logic tile_busy;
logic tile_done;

logic [OUT_TILES_W-1:0] out_tile_idx;
logic [OUT_TILES_W-1:0] num_out_tiles_m1;
logic last_out_tile;

// 현재 처리 중인 output tile의 weight/output 시작 주소
logic [ADDR_W-1:0] current_wgt_base;
logic [ADDR_W-1:0] current_out_base;

assign busy = (state != ST_IDLE);
// output_tile_engine에는 한 cycle start pulse만 넘김
assign tile_start = en && (state == ST_START_TILE);

assign num_out_tiles_m1 = num_out_tiles - 1'b1;
assign last_out_tile = (out_tile_idx == num_out_tiles_m1);

// 실제 16x16 output tile 계산은 하위 엔진이 담당
output_tile_engine_feature_major_16x16 #(
    .N (N),
    .DATA_W (DATA_W),
    .ACC_W (ACC_W),
    .WORD_W (WORD_W),
    .ADDR_W (ADDR_W),
    .SCALE_W (SCALE_W),
    .SCALE_FRAC(SCALE_FRAC),
    .K_TILES_W (K_TILES_W)
) output_tile (
    .clk (clk),
    .rst (rst),
    .clear (clear),
    .start (tile_start),
    .en (en),
    // activation A[16][K]는 output column tile마다 재사용
    .act_base_addr (act_base_addr),
    // weight/output base가 현재 16-column output tile을 가리킴
    .wgt_base_addr (current_wgt_base),
    .out_base_addr (current_out_base),
    .act_layout_row_major (act_layout_row_major),
    .out_layout_row_major (out_layout_row_major),
    .act_k_stride (act_k_stride),
    .wgt_k_stride (wgt_k_stride),
    .num_k_tiles (num_k_tiles),
    .scale_q (scale_q),
    .bram_act_en (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata (bram_act_rdata),
    .bram_wgt_en (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata (bram_wgt_rdata),
    .bram_out_wr (bram_out_wr),
    .bram_out_addr (bram_out_addr),
    .bram_out_wdata (bram_out_wdata),
    .busy (tile_busy),
    .done (tile_done)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        out_tile_idx <= '0;
        current_wgt_base <= '0;
        current_out_base <= '0;
        done <= 1'b0;
    end
    else if (en) begin
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                out_tile_idx <= '0;
                current_wgt_base <= wgt_base_addr;
                current_out_base <= out_base_addr;

                if (start) begin
                    state <= ST_START_TILE;
                end
            end

            ST_START_TILE: begin
                // 현재 output column tile에 start pulse 한 번 발생
                state <= ST_WAIT_TILE_DONE;
            end

            ST_WAIT_TILE_DONE: begin
                // 하위 output tile 엔진이 끝날 때까지 대기
                if (tile_done) begin
                    if (last_out_tile) begin
                        state <= ST_DONE;
                    end
                    else begin
                        state <= ST_NEXT_OUT_TILE;
                    end
                end
            end

            ST_NEXT_OUT_TILE: begin
                // 다음 output column tile로 이동
                // out_tile_stride가 16이면 out_base+0, +16, +32 순서로 저장
                out_tile_idx <= out_tile_idx + 1'b1;
                current_wgt_base <= current_wgt_base + wgt_out_stride;
                current_out_base <= current_out_base + out_tile_stride;
                state <= ST_START_TILE;
            end

            ST_DONE: begin
                // layer 하나가 끝났다는 done pulse 발생
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                // 이상 상태에서는 layer 진행 상태 초기화
                state <= ST_IDLE;
                out_tile_idx <= '0;
                current_wgt_base <= '0;
                current_out_base <= '0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

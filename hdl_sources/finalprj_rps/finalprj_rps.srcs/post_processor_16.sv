`timescale 1ns / 1ps

// PE 누산 결과 한 row를 받아서 ReLU, scale, rounding, saturation까지 처리하는 모듈
// 다음 layer로 넘길 8bit activation vector를 만듦
module post_processor_16 #(
    parameter int N = 16,
    parameter int ACC_W = 32,
    parameter int OUT_W = 8,
    parameter int SCALE_W = 32,
    parameter int SCALE_FRAC = 24
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic en,

    input logic row_valid,
    input logic signed [ACC_W-1:0] row_vec [0:N-1],
    input logic [SCALE_W-1:0] scale_q,

    output logic out_valid,
    output logic signed [OUT_W-1:0] out_vec [0:N-1]
);

// accumulator와 scale을 곱하면 두 폭을 더한 만큼의 product 폭이 필요함
localparam int PRODUCT_W = ACC_W + SCALE_W;

logic [PRODUCT_W-1:0] product_reg [0:N-1];
logic stage1_valid;

// 음수는 0으로 만든 뒤 scale_q를 곱하는 함수
function automatic logic [PRODUCT_W-1:0] relu_scale_product(
    input logic signed [ACC_W-1:0] in_value,
    input logic [SCALE_W-1:0] in_scale_q
);
    logic [ACC_W-1:0] relu_val;
    logic [PRODUCT_W-1:0] relu_ext;
    logic [PRODUCT_W-1:0] scale_ext;
begin
    // ReLU라서 accumulator가 음수면 0으로 처리
    if (in_value[ACC_W-1]) begin
        relu_val = '0;
    end
    else begin
        relu_val = in_value[ACC_W-1:0];
    end

    // scale_q는 SCALE_FRAC만큼 fractional bit를 가진 fixed-point 값
    relu_ext = {{SCALE_W{1'b0}}, relu_val};
    scale_ext = {{ACC_W{1'b0}}, in_scale_q};
    relu_scale_product = relu_ext * scale_ext;
end
endfunction

// scale 곱 결과를 반올림하고 8bit 범위로 잘라 주는 함수
function automatic logic signed [OUT_W-1:0] round_saturate_product(
    input logic [PRODUCT_W-1:0] in_product
);
    logic [PRODUCT_W-1:0] round_bias;
    logic [PRODUCT_W-1:0] rounded;
begin
    // fixed-point shift 전에 bias를 더해서 반올림 처리
    round_bias = '0;
    round_bias[SCALE_FRAC-1] = 1'b1;
    rounded = (in_product + round_bias) >> SCALE_FRAC;

    // 다음 layer activation 범위가 0..127이라 넘치면 127로 고정
    if (rounded > 127) begin
        round_saturate_product = 8'sd127;
    end
    else begin
        round_saturate_product = rounded[OUT_W-1:0];
    end
end
endfunction

always_ff @(posedge clk) begin
    if (rst) begin
        stage1_valid <= 1'b0;
        out_valid <= 1'b0;
        for (int lane = 0; lane < N; lane++) begin
            product_reg[lane] <= '0;
            out_vec[lane] <= '0;
        end
    end
    else if (en) begin
        if (clear) begin
            stage1_valid <= 1'b0;
            out_valid <= 1'b0;
            for (int lane = 0; lane < N; lane++) begin
                product_reg[lane] <= '0;
                out_vec[lane] <= '0;
            end
        end
        else begin
            stage1_valid <= row_valid;
            out_valid <= stage1_valid;

            if (row_valid) begin
                // stage1에서 ReLU와 scale 곱까지 먼저 계산
                for (int lane = 0; lane < N; lane++) begin
                    product_reg[lane] <= relu_scale_product(row_vec[lane], scale_q);
                end
            end
            else begin
                for (int lane = 0; lane < N; lane++) begin
                    product_reg[lane] <= '0;
                end
            end

            if (stage1_valid) begin
                // stage2에서 반올림과 saturation을 적용해서 최종 출력 생성
                for (int lane = 0; lane < N; lane++) begin
                    out_vec[lane] <= round_saturate_product(product_reg[lane]);
                end
            end
            else begin
                for (int lane = 0; lane < N; lane++) begin
                    out_vec[lane] <= '0;
                end
            end
        end
    end
end

endmodule

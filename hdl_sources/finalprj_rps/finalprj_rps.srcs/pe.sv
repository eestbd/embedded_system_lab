`timescale 1ns / 1ps

// 한 칸짜리 PE
// act는 오른쪽으로, weight는 아래쪽으로 넘기면서 현재 자리의 곱을 누산함
module PE #(
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_clear,
    input logic i_en,
    input logic signed [DATA_W-1:0] i_act,
    input logic signed [DATA_W-1:0] i_wgt,
    output logic signed [DATA_W-1:0] o_act,
    output logic signed [DATA_W-1:0] o_wgt,
    output logic signed [ACC_W-1:0] o_acc
);

// DATA_W 두 개를 곱한 값이라 곱 결과 폭은 먼저 2배로 잡음
localparam int PRODUCT_W = DATA_W * 2;

logic signed [PRODUCT_W-1:0] product;
logic signed [ACC_W-1:0] product_ext;

// 현재 PE에 들어온 activation과 weight의 곱
assign product = $signed(i_act) * $signed(i_wgt);

// 누산기 폭에 맞게 곱셈 결과를 맞추고, 폭이 넓으면 부호 확장해서 넣음
generate
    if (ACC_W > PRODUCT_W) begin : g_product_sign_extend
        assign product_ext = {{(ACC_W-PRODUCT_W){product[PRODUCT_W-1]}}, product};
    end
    else begin : g_product_fit_or_truncate
        assign product_ext = product[ACC_W-1:0];
    end
endgenerate

// enable된 사이클에만 값이 한 칸 이동하고 누산됨
always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_act <= '0;
        o_wgt <= '0;
        o_acc <= '0;
    end
    else begin
        if (i_clear) begin
            // 새 계산을 시작할 때는 누산값만 비움
            o_acc <= '0;
        end
        else if (i_en) begin
            // 현재 자리의 곱을 기존 partial sum에 더함
            o_acc <= o_acc + product_ext;
        end

        if (i_en) begin
            // act와 weight는 다음 PE로 넘겨 주는 파이프라인 값
            o_act <= i_act;
            o_wgt <= i_wgt;
        end
    end
end

endmodule

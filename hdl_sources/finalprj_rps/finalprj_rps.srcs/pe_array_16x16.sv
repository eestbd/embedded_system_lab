`timescale 1ns / 1ps

// N x N PE 배열
// activation은 오른쪽으로, weight는 아래쪽으로 흘리면서 각 PE가 자기 위치의 합을 만듦
module PE_ARRAY_16x16 #(
    parameter int N = 16,
    parameter int DATA_W = 8,
    parameter int ACC_W = 32
)(
    input logic i_clk,
    input logic i_rst_n,
    input logic i_clear,
    input logic i_en,

    input logic signed [DATA_W-1:0] i_act_vec [0:N-1],
    input logic signed [DATA_W-1:0] i_wgt_vec [0:N-1],

    output logic signed [DATA_W-1:0] o_act_last_vec [0:N-1],
    output logic signed [DATA_W-1:0] o_wgt_last_vec [0:N-1],
    output logic signed [ACC_W-1:0] o_acc_mat [0:N-1][0:N-1]
);

// PE 사이를 이어 주는 내부 배선, act는 행 방향, weight는 열 방향으로 한 칸씩 이동함
logic signed [DATA_W-1:0] act_pipe [0:N-1][0:N];
logic signed [DATA_W-1:0] wgt_pipe [0:N][0:N-1];

genvar g_row;
genvar g_col;

generate
    // 왼쪽 경계로 activation을 넣고, 오른쪽 끝 값을 밖으로 뺌
    for (g_row = 0; g_row < N; g_row++) begin : g_act_boundary
        assign act_pipe[g_row][0] = i_act_vec[g_row];
        assign o_act_last_vec[g_row] = act_pipe[g_row][N];
    end

    // 위쪽 경계로 weight를 넣고, 아래쪽 끝 값을 밖으로 뺌
    for (g_col = 0; g_col < N; g_col++) begin : g_wgt_boundary
        assign wgt_pipe[0][g_col] = i_wgt_vec[g_col];
        assign o_wgt_last_vec[g_col] = wgt_pipe[N][g_col];
    end

    // 실제 PE 배열 본체, 각 좌표에 PE 하나씩 배치
    for (g_row = 0; g_row < N; g_row++) begin : g_pe_row
        for (g_col = 0; g_col < N; g_col++) begin : g_pe_col
            PE #(
                .DATA_W (DATA_W),
                .ACC_W (ACC_W)
            ) u_pe (
                .i_clk (i_clk),
                .i_rst_n (i_rst_n),
                .i_clear (i_clear),
                .i_en (i_en),
                .i_act (act_pipe[g_row][g_col]),
                .i_wgt (wgt_pipe[g_row][g_col]),
                // PE 출력이 바로 오른쪽/아래쪽 PE의 입력으로 이어짐
                .o_act (act_pipe[g_row][g_col+1]),
                .o_wgt (wgt_pipe[g_row+1][g_col]),
                .o_acc (o_acc_mat[g_row][g_col])
            );
        end
    end
endgenerate

endmodule

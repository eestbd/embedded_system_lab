module PE_ARRAY_16x16 #(
    parameter int N      = 16,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  logic                         i_clk,
    input  logic                         i_rst_n,
    input  logic                         i_clear,
    input  logic                         i_en,

    input  logic signed [DATA_W-1:0]     i_act_vec [0:N-1],
    input  logic signed [DATA_W-1:0]     i_wgt_vec [0:N-1],

    output logic signed [DATA_W-1:0]     o_act_last_vec [0:N-1],
    output logic signed [DATA_W-1:0]     o_wgt_last_vec [0:N-1],
    output logic signed [ACC_W-1:0]      o_acc_mat [0:N-1][0:N-1]
);

logic signed [DATA_W-1:0] act_pipe [0:N-1][0:N];
logic signed [DATA_W-1:0] wgt_pipe [0:N][0:N-1];

genvar g_row;
genvar g_col;

generate
    for (g_row = 0; g_row < N; g_row++) begin : g_act_boundary
        assign act_pipe[g_row][0]   = i_act_vec[g_row];
        assign o_act_last_vec[g_row] = act_pipe[g_row][N];
    end

    for (g_col = 0; g_col < N; g_col++) begin : g_wgt_boundary
        assign wgt_pipe[0][g_col]   = i_wgt_vec[g_col];
        assign o_wgt_last_vec[g_col] = wgt_pipe[N][g_col];
    end

    for (g_row = 0; g_row < N; g_row++) begin : g_pe_row
        for (g_col = 0; g_col < N; g_col++) begin : g_pe_col
            PE #(
                .DATA_W(DATA_W),
                .ACC_W (ACC_W)
            ) u_pe (
                .i_clk   (i_clk),
                .i_rst_n (i_rst_n),
                .i_clear (i_clear),
                .i_en    (i_en),
                .i_act   (act_pipe[g_row][g_col]),
                .i_wgt   (wgt_pipe[g_row][g_col]),
                .o_act   (act_pipe[g_row][g_col+1]),
                .o_wgt   (wgt_pipe[g_row+1][g_col]),
                .o_acc   (o_acc_mat[g_row][g_col])
            );
        end
    end
endgenerate

endmodule

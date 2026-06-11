`timescale 1ns / 1ps

module PE_ROW #(
    parameter int N      = 16,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  logic                         i_clk,
    input  logic                         i_rst_n,
    input  logic                         i_clear,
    input  logic                         i_en,
    input  logic signed [DATA_W-1:0]     i_act,
    input  logic signed [DATA_W-1:0]     i_wgt_vec [0:N-1],
    output logic signed [DATA_W-1:0]     o_act_last,
    output logic signed [ACC_W-1:0]      o_acc_vec [0:N-1]
);

logic signed [DATA_W-1:0] act_chain [0:N];
logic signed [DATA_W-1:0] wgt_chain [0:N-1];

assign act_chain[0] = i_act;
assign o_act_last   = act_chain[N];

genvar g_pe;
generate
    for (g_pe = 0; g_pe < N; g_pe++) begin : g_pe_row
        PE #(
            .DATA_W(DATA_W),
            .ACC_W (ACC_W)
        ) u_pe (
            .i_clk   (i_clk),
            .i_rst_n (i_rst_n),
            .i_clear (i_clear),
            .i_en    (i_en),
            .i_act   (act_chain[g_pe]),
            .i_wgt   (i_wgt_vec[g_pe]),
            .o_act   (act_chain[g_pe+1]),
            .o_wgt   (wgt_chain[g_pe]),
            .o_acc   (o_acc_vec[g_pe])
        );
    end
endgenerate

endmodule

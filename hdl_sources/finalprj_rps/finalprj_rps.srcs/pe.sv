module PE #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  logic                         i_clk,
    input  logic                         i_rst_n,
    input  logic                         i_clear,
    input  logic                         i_en,
    input  logic signed [DATA_W-1:0]     i_act,
    input  logic signed [DATA_W-1:0]     i_wgt,
    output logic signed [DATA_W-1:0]     o_act,
    output logic signed [DATA_W-1:0]     o_wgt,
    output logic signed [ACC_W-1:0]      o_acc
);

localparam int PRODUCT_W = DATA_W * 2;

logic signed [PRODUCT_W-1:0] product;
logic signed [ACC_W-1:0]     product_ext;

assign product = $signed(i_act) * $signed(i_wgt);

generate
    if (ACC_W > PRODUCT_W) begin : g_product_sign_extend
        assign product_ext = {{(ACC_W-PRODUCT_W){product[PRODUCT_W-1]}}, product};
    end
    else begin : g_product_fit_or_truncate
        assign product_ext = product[ACC_W-1:0];
    end
endgenerate

always_ff @(posedge i_clk or negedge i_rst_n) begin
    if (!i_rst_n) begin
        o_act <= '0;
        o_wgt <= '0;
        o_acc <= '0;
    end
    else begin
        if (i_clear) begin
            o_acc <= '0;
        end
        else if (i_en) begin
            o_acc <= o_acc + product_ext;
        end

        if (i_en) begin
            o_act <= i_act;
            o_wgt <= i_wgt;
        end
    end
end

endmodule

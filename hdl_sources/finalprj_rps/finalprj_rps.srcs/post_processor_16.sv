module post_processor_16 #(
    parameter int N          = 16,
    parameter int ACC_W      = 32,
    parameter int OUT_W      = 8,
    parameter int SCALE_W    = 32,
    parameter int SCALE_FRAC = 24
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         en,

    input  logic                         row_valid,
    input  logic signed [ACC_W-1:0]      row_vec [0:N-1],
    input  logic [SCALE_W-1:0]           scale_q,

    output logic                         out_valid,
    output logic signed [OUT_W-1:0]      out_vec [0:N-1]
);

localparam int PRODUCT_W = ACC_W + SCALE_W;

function automatic logic signed [OUT_W-1:0] process_lane(
    input logic signed [ACC_W-1:0] in_value,
    input logic [SCALE_W-1:0]      in_scale_q
);
    logic [ACC_W-1:0]     relu_val;
    logic [PRODUCT_W-1:0] relu_ext;
    logic [PRODUCT_W-1:0] scale_ext;
    logic [PRODUCT_W-1:0] product;
    logic [PRODUCT_W-1:0] round_bias;
    logic [PRODUCT_W-1:0] rounded;
begin
    // ReLU: negative accumulator values become zero.
    if (in_value[ACC_W-1]) begin
        relu_val = '0;
    end
    else begin
        relu_val = in_value[ACC_W-1:0];
    end

    // Fixed-point scaling: scale_q represents scale_q / 2^SCALE_FRAC.
    relu_ext  = {{SCALE_W{1'b0}}, relu_val};
    scale_ext = {{ACC_W{1'b0}}, in_scale_q};
    product   = relu_ext * scale_ext;

    // Round-to-nearest before the fixed-point right shift.
    round_bias = '0;
    round_bias[SCALE_FRAC-1] = 1'b1;
    rounded = (product + round_bias) >> SCALE_FRAC;

    // Saturation to int8 activation range used by the next layer: 0..127.
    if (rounded > 127) begin
        process_lane = 8'sd127;
    end
    else begin
        process_lane = rounded[OUT_W-1:0];
    end
end
endfunction

always_ff @(posedge clk) begin
    if (rst || clear) begin
        out_valid <= 1'b0;
        for (int lane = 0; lane < N; lane++) begin
            out_vec[lane] <= '0;
        end
    end
    else if (en) begin
        if (row_valid) begin
            out_valid <= 1'b1;
            for (int lane = 0; lane < N; lane++) begin
                out_vec[lane] <= process_lane(row_vec[lane], scale_q);
            end
        end
        else begin
            out_valid <= 1'b0;
        end
    end
end

endmodule

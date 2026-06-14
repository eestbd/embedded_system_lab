`timescale 1ns / 1ps

// Takes one accumulated PE row and runs ReLU, scale, rounding, and saturation
// Produces the 8-bit activation vector for the next layer
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

// Multiplying accumulator and scale needs a product width equal to both widths added
localparam int PRODUCT_W = ACC_W + SCALE_W;

logic [PRODUCT_W-1:0] product_reg [0:N-1];
logic stage1_valid;

// Turns negatives into zero before multiplying by scale_q
function automatic logic [PRODUCT_W-1:0] relu_scale_product(
    input logic signed [ACC_W-1:0] in_value,
    input logic [SCALE_W-1:0] in_scale_q
);
    logic [ACC_W-1:0] relu_val;
    logic [PRODUCT_W-1:0] relu_ext;
    logic [PRODUCT_W-1:0] scale_ext;
begin
    // ReLU clamps negative accumulator values to zero
    if (in_value[ACC_W-1]) begin
        relu_val = '0;
    end
    else begin
        relu_val = in_value[ACC_W-1:0];
    end

    // scale_q is fixed-point with SCALE_FRAC fractional bits
    relu_ext = {{SCALE_W{1'b0}}, relu_val};
    scale_ext = {{ACC_W{1'b0}}, in_scale_q};
    relu_scale_product = relu_ext * scale_ext;
end
endfunction

// Rounds the scaled product and clamps it to the 8-bit range
function automatic logic signed [OUT_W-1:0] round_saturate_product(
    input logic [PRODUCT_W-1:0] in_product
);
    logic [PRODUCT_W-1:0] round_bias;
    logic [PRODUCT_W-1:0] rounded;
begin
    // Add bias before the fixed-point shift to round the result
    round_bias = '0;
    round_bias[SCALE_FRAC-1] = 1'b1;
    rounded = (in_product + round_bias) >> SCALE_FRAC;

    // Next-layer activations use 0..127, so clamp overflow to 127
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
                // Stage 1 handles ReLU and scale multiplication
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
                // Stage 2 applies rounding and saturation for the final output
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

`timescale 1ns / 1ps

module post_processor_16_tb;

localparam int N          = 16;
localparam int ACC_W      = 32;
localparam int OUT_W      = 8;
localparam int SCALE_W    = 32;
localparam int SCALE_FRAC = 24;
localparam int PRODUCT_W  = ACC_W + SCALE_W;

localparam logic [SCALE_W-1:0] SCALE_M1 = 32'd6073;
localparam logic [SCALE_W-1:0] SCALE_M2 = 32'd24139;
localparam logic [SCALE_W-1:0] SCALE_M3 = 32'd328223;
localparam logic [SCALE_W-1:0] SCALE_M4 = 32'd16777216;

logic clk;
logic rst;
logic clear;
logic en;
logic row_valid;
logic signed [ACC_W-1:0] row_vec [0:N-1];
logic [SCALE_W-1:0] scale_q;
logic out_valid;
logic signed [OUT_W-1:0] out_vec [0:N-1];

post_processor_16 #(
    .N         (N),
    .ACC_W     (ACC_W),
    .OUT_W     (OUT_W),
    .SCALE_W   (SCALE_W),
    .SCALE_FRAC(SCALE_FRAC)
) u_dut (
    .clk       (clk),
    .rst       (rst),
    .clear     (clear),
    .en        (en),
    .row_valid (row_valid),
    .row_vec   (row_vec),
    .scale_q   (scale_q),
    .out_valid (out_valid),
    .out_vec   (out_vec)
);

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic logic signed [OUT_W-1:0] golden_lane(
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
    if (in_value[ACC_W-1]) begin
        relu_val = '0;
    end
    else begin
        relu_val = in_value[ACC_W-1:0];
    end

    relu_ext  = {{SCALE_W{1'b0}}, relu_val};
    scale_ext = {{ACC_W{1'b0}}, in_scale_q};
    product   = relu_ext * scale_ext;
    round_bias = '0;
    round_bias[SCALE_FRAC-1] = 1'b1;
    rounded = (product + round_bias) >> SCALE_FRAC;

    if (rounded > 127) begin
        golden_lane = 8'sd127;
    end
    else begin
        golden_lane = rounded[OUT_W-1:0];
    end
end
endfunction

task automatic drive_zero_row();
begin
    for (int lane = 0; lane < N; lane++) begin
        row_vec[lane] = '0;
    end
end
endtask

task automatic drive_base_pattern();
begin
    row_vec[ 0] = -32'sd1000;
    row_vec[ 1] =  32'sd0;
    row_vec[ 2] =  32'sd1;
    row_vec[ 3] =  32'sd2;
    row_vec[ 4] =  32'sd10;
    row_vec[ 5] =  32'sd127;
    row_vec[ 6] =  32'sd128;
    row_vec[ 7] =  32'sd255;
    row_vec[ 8] =  32'sd1000;
    row_vec[ 9] = -32'sd1;
    row_vec[10] =  32'sd4096;
    row_vec[11] =  32'sd10000;
    row_vec[12] =  32'sd100000;
    row_vec[13] =  32'sd350000;
    row_vec[14] =  32'sd1000000;
    row_vec[15] =  32'sd20000000;
end
endtask

task automatic check_outputs(input string test_name, input logic [SCALE_W-1:0] expected_scale);
    logic signed [OUT_W-1:0] expected;
begin
    if (out_valid !== 1'b1) begin
        $display("%s: expected out_valid=1, got %0b", test_name, out_valid);
        $fatal(1);
    end

    for (int lane = 0; lane < N; lane++) begin
        expected = golden_lane(row_vec[lane], expected_scale);
        if (out_vec[lane] !== expected) begin
            $display("%s lane %0d mismatch: input=%0d scale_q=%0d expected=%0d got=%0d",
                     test_name, lane, row_vec[lane], expected_scale, expected, out_vec[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_zero_outputs(input string test_name);
begin
    if (out_valid !== 1'b0) begin
        $display("%s: expected out_valid=0, got %0b", test_name, out_valid);
        $fatal(1);
    end

    for (int lane = 0; lane < N; lane++) begin
        if (out_vec[lane] !== '0) begin
            $display("%s lane %0d mismatch: expected 0, got %0d",
                     test_name, lane, out_vec[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic run_valid_case(input string test_name, input logic [SCALE_W-1:0] test_scale);
begin
    @(negedge clk);
    clear     = 1'b0;
    en        = 1'b1;
    row_valid = 1'b1;
    scale_q   = test_scale;
    drive_base_pattern();

    @(posedge clk);
    #1;
    check_outputs(test_name, test_scale);
end
endtask

task automatic check_row_valid_low();
begin
    @(negedge clk);
    en        = 1'b1;
    row_valid = 1'b0;
    scale_q   = SCALE_M4;
    drive_base_pattern();

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
        $display("row_valid low: expected out_valid=0, got %0b", out_valid);
        $fatal(1);
    end
end
endtask

task automatic check_clear();
begin
    @(negedge clk);
    clear     = 1'b1;
    en        = 1'b1;
    row_valid = 1'b1;
    scale_q   = SCALE_M4;
    drive_base_pattern();

    @(posedge clk);
    #1;
    check_zero_outputs("clear");

    @(negedge clk);
    clear = 1'b0;
end
endtask

task automatic check_enable_hold();
    logic held_valid;
    logic signed [OUT_W-1:0] held_vec [0:N-1];
begin
    run_valid_case("en hold setup", SCALE_M4);

    held_valid = out_valid;
    for (int lane = 0; lane < N; lane++) begin
        held_vec[lane] = out_vec[lane];
    end

    @(negedge clk);
    en        = 1'b0;
    row_valid = 1'b0;
    scale_q   = SCALE_M1;
    drive_zero_row();

    repeat (2) begin
        @(posedge clk);
        #1;
        if (out_valid !== held_valid) begin
            $display("en hold: expected out_valid=%0b, got %0b", held_valid, out_valid);
            $fatal(1);
        end
        for (int lane = 0; lane < N; lane++) begin
            if (out_vec[lane] !== held_vec[lane]) begin
                $display("en hold lane %0d mismatch: expected %0d, got %0d",
                         lane, held_vec[lane], out_vec[lane]);
                $fatal(1);
            end
        end
    end

    @(negedge clk);
    en = 1'b1;
end
endtask

task automatic apply_reset();
begin
    @(negedge clk);
    rst       = 1'b1;
    clear     = 1'b0;
    en        = 1'b1;
    row_valid = 1'b0;
    scale_q   = '0;
    drive_zero_row();

    repeat (2) @(posedge clk);
    #1;
    check_zero_outputs("reset");

    @(negedge clk);
    rst = 1'b0;
end
endtask

initial begin
    rst       = 1'b0;
    clear     = 1'b0;
    en        = 1'b0;
    row_valid = 1'b0;
    scale_q   = '0;
    drive_zero_row();

    apply_reset();
    run_valid_case("SCALE_M1", SCALE_M1);
    run_valid_case("SCALE_M2", SCALE_M2);
    run_valid_case("SCALE_M3", SCALE_M3);
    run_valid_case("SCALE_M4", SCALE_M4);
    check_row_valid_low();
    check_clear();
    check_enable_hold();

    $display("POST_PROCESSOR_16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

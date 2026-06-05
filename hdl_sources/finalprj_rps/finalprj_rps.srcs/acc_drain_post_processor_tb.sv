`timescale 1ns / 1ps

module acc_drain_post_processor_tb;

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
logic drain_start;

logic signed [ACC_W-1:0] acc_mat [0:N-1][0:N-1];
logic signed [ACC_W-1:0] row_vec [0:N-1];
logic row_valid;
logic [$clog2(N)-1:0] row_idx_out;
logic drain_busy;
logic drain_done;

logic [SCALE_W-1:0] scale_q;
logic out_valid;
logic signed [OUT_W-1:0] out_vec [0:N-1];
logic signed [OUT_W-1:0] expected_out [0:N-1];

acc_drain_16x16 #(
    .N    (N),
    .ACC_W(ACC_W)
) dut_drain (
    .clk         (clk),
    .rst         (rst),
    .clear       (clear),
    .en          (en),
    .start       (drain_start),
    .acc_mat     (acc_mat),
    .row_vec     (row_vec),
    .row_valid   (row_valid),
    .row_idx_out (row_idx_out),
    .busy        (drain_busy),
    .done        (drain_done)
);

post_processor_16 #(
    .N         (N),
    .ACC_W     (ACC_W),
    .OUT_W     (OUT_W),
    .SCALE_W   (SCALE_W),
    .SCALE_FRAC(SCALE_FRAC)
) dut_post (
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

function automatic logic signed [OUT_W-1:0] golden_post_lane(
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

    relu_ext   = {{SCALE_W{1'b0}}, relu_val};
    scale_ext  = {{ACC_W{1'b0}}, in_scale_q};
    product    = relu_ext * scale_ext;
    round_bias = '0;
    round_bias[SCALE_FRAC-1] = 1'b1;
    rounded = (product + round_bias) >> SCALE_FRAC;

    if (rounded > 127) begin
        golden_post_lane = 8'sd127;
    end
    else begin
        golden_post_lane = rounded[OUT_W-1:0];
    end
end
endfunction

task automatic init_acc_mat();
    int signed value;
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            value = (row - 8) * 5000 + (col - 8) * 777;
            acc_mat[row][col] = value;
        end
    end

    acc_mat[ 0][15] = -32'sd200000;
    acc_mat[ 8][ 8] =  32'sd0;
    acc_mat[ 9][ 3] =  32'sd1;
    acc_mat[10][ 5] =  32'sd127;
    acc_mat[11][ 7] =  32'sd4096;
    acc_mat[14][ 0] =  32'sd1000000;
    acc_mat[15][15] =  32'sd20000000;
end
endtask

task automatic fill_expected_out(input int row, input logic [SCALE_W-1:0] test_scale);
begin
    for (int col = 0; col < N; col++) begin
        expected_out[col] = golden_post_lane(acc_mat[row][col], test_scale);
    end
end
endtask

task automatic check_idle(input string label);
begin
    if (row_valid !== 1'b0) begin
        $display("%s: expected row_valid=0, got %0b", label, row_valid);
        $fatal(1);
    end
    if (out_valid !== 1'b0) begin
        $display("%s: expected out_valid=0, got %0b", label, out_valid);
        $fatal(1);
    end
end
endtask

task automatic check_drain_row(input int expected_row, input string scale_name);
    logic [$clog2(N)-1:0] expected_idx;
begin
    expected_idx = expected_row;

    if (row_valid !== 1'b1) begin
        $display("%s DRAIN: row %0d expected row_valid=1, got %0b",
                 scale_name, expected_row, row_valid);
        $fatal(1);
    end
    if (row_idx_out !== expected_idx) begin
        $display("%s DRAIN: expected row_idx=%0d, got %0d",
                 scale_name, expected_row, row_idx_out);
        $fatal(1);
    end
    for (int col = 0; col < N; col++) begin
        if (row_vec[col] !== acc_mat[expected_row][col]) begin
            $display("%s DRAIN row_vec mismatch row %0d col %0d: expected %0d, got %0d",
                     scale_name, expected_row, col, acc_mat[expected_row][col], row_vec[col]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_post_row(
    input string scale_name,
    input logic [SCALE_W-1:0] test_scale,
    input int expected_row
);
begin
    if (out_valid !== 1'b1) begin
        $display("%s POST: row %0d expected out_valid=1, got %0b",
                 scale_name, expected_row, out_valid);
        $fatal(1);
    end

    fill_expected_out(expected_row, test_scale);
    for (int col = 0; col < N; col++) begin
        if (out_vec[col] !== expected_out[col]) begin
            $display("%s POST mismatch row %0d col %0d: input=%0d scale_q=%0d expected=%0d got=%0d",
                     scale_name, expected_row, col, acc_mat[expected_row][col],
                     test_scale, expected_out[col], out_vec[col]);
            $fatal(1);
        end
    end
end
endtask

task automatic apply_reset();
begin
    @(negedge clk);
    rst         = 1'b1;
    clear       = 1'b0;
    en          = 1'b1;
    drain_start = 1'b0;
    scale_q     = '0;

    repeat (2) @(posedge clk);
    #1;
    check_idle("reset");

    @(negedge clk);
    rst = 1'b0;
end
endtask

task automatic apply_clear(input string label);
begin
    @(negedge clk);
    clear       = 1'b1;
    en          = 1'b1;
    drain_start = 1'b0;

    @(posedge clk);
    #1;
    check_idle(label);

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
end
endtask

task automatic run_scale_case(
    input string scale_name,
    input logic [SCALE_W-1:0] test_scale
);
    int row_count;
    int out_count;
begin
    row_count = 0;
    out_count = 0;

    scale_q = test_scale;
    apply_clear(scale_name);

    @(negedge clk);
    en          = 1'b1;
    drain_start = 1'b1;

    @(posedge clk);
    #1;
    check_drain_row(0, scale_name);
    row_count = row_count + 1;
    if (out_valid !== 1'b0) begin
        $display("%s POST: expected first drain cycle out_valid=0, got %0b",
                 scale_name, out_valid);
        $fatal(1);
    end

    @(negedge clk);
    drain_start = 1'b0;

    for (int row = 1; row < N; row++) begin
        @(posedge clk);
        #1;
        check_drain_row(row, scale_name);
        row_count = row_count + 1;
        check_post_row(scale_name, test_scale, row - 1);
        out_count = out_count + 1;
    end

    @(posedge clk);
    #1;
    if (row_valid !== 1'b0) begin
        $display("%s DRAIN: expected row_valid=0 during done, got %0b",
                 scale_name, row_valid);
        $fatal(1);
    end
    if (drain_done !== 1'b1) begin
        $display("%s DRAIN: expected drain_done=1 after row15, got %0b",
                 scale_name, drain_done);
        $fatal(1);
    end
    check_post_row(scale_name, test_scale, N - 1);
    out_count = out_count + 1;

    @(posedge clk);
    #1;
    if (row_valid !== 1'b0) begin
        $display("%s DRAIN: expected row_valid=0 after done, got %0b",
                 scale_name, row_valid);
        $fatal(1);
    end
    if (out_valid !== 1'b0) begin
        $display("%s POST: expected out_valid=0 after final output, got %0b",
                 scale_name, out_valid);
        $fatal(1);
    end

    if (row_count != N) begin
        $display("%s DRAIN: expected 16 row_valid cycles, got %0d",
                 scale_name, row_count);
        $fatal(1);
    end
    if (out_count != N) begin
        $display("%s POST: expected 16 out_valid cycles, got %0d",
                 scale_name, out_count);
        $fatal(1);
    end

    @(negedge clk);
    en = 1'b0;
end
endtask

initial begin
    rst         = 1'b0;
    clear       = 1'b0;
    en          = 1'b0;
    drain_start = 1'b0;
    scale_q     = '0;
    init_acc_mat();
    for (int col = 0; col < N; col++) begin
        expected_out[col] = '0;
    end

    apply_reset();
    run_scale_case("SCALE_M1", SCALE_M1);
    run_scale_case("SCALE_M2", SCALE_M2);
    run_scale_case("SCALE_M3", SCALE_M3);
    run_scale_case("SCALE_M4", SCALE_M4);

    $display("ACC_DRAIN_POST_PROCESSOR test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

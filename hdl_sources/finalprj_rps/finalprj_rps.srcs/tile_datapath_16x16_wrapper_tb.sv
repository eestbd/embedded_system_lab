`timescale 1ns / 1ps

module tile_datapath_16x16_wrapper_tb;

localparam int N             = 16;
localparam int DATA_W        = 8;
localparam int ACC_W         = 32;
localparam int SCALE_W       = 32;
localparam int SCALE_FRAC    = 24;
localparam int PRODUCT_W     = ACC_W + SCALE_W;
localparam int INPUT_CYCLES  = 16;
localparam int FLUSH_CYCLES  = 30;
localparam int STREAM_CYCLES = INPUT_CYCLES + FLUSH_CYCLES;
localparam int TIMEOUT_CYCLES = 200;

localparam logic [SCALE_W-1:0] SCALE_M4 = 32'd16777216;

logic clk;
logic rst;
logic clear;
logic start;
logic en;

logic signed [DATA_W-1:0] raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1];
logic [SCALE_W-1:0] scale_q;

logic input_active;
logic drain_active;
logic busy;
logic done;
logic out_valid;
logic signed [DATA_W-1:0] out_vec [0:N-1];
logic [$clog2(N)-1:0] out_row_idx;

logic signed [DATA_W-1:0] A [0:N-1][0:N-1];
logic signed [DATA_W-1:0] B [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  golden_C   [0:N-1][0:N-1];
logic signed [DATA_W-1:0] golden_out [0:N-1][0:N-1];

tile_datapath_16x16 #(
    .N           (N),
    .DATA_W      (DATA_W),
    .ACC_W       (ACC_W),
    .SCALE_W     (SCALE_W),
    .SCALE_FRAC  (SCALE_FRAC),
    .INPUT_CYCLES(INPUT_CYCLES),
    .FLUSH_CYCLES(FLUSH_CYCLES),
    .CLEAR_CYCLES(N)
) dut (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .start        (start),
    .en           (en),
    .raw_act_vec  (raw_act_vec),
    .raw_wgt_vec  (raw_wgt_vec),
    .scale_q      (scale_q),
    .input_active (input_active),
    .drain_active (drain_active),
    .busy         (busy),
    .done         (done),
    .out_valid    (out_valid),
    .out_vec      (out_vec),
    .out_row_idx  (out_row_idx)
);

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

function automatic logic signed [ACC_W-1:0] mul_i8_to_i32(
    input logic signed [DATA_W-1:0] lhs,
    input logic signed [DATA_W-1:0] rhs
);
    int signed lhs_i;
    int signed rhs_i;
begin
    lhs_i = lhs;
    rhs_i = rhs;
    mul_i8_to_i32 = lhs_i * rhs_i;
end
endfunction

function automatic logic signed [DATA_W-1:0] golden_post_lane(
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
        golden_post_lane = rounded[DATA_W-1:0];
    end
end
endfunction

task automatic drive_zero_raw_inputs();
begin
    for (int lane = 0; lane < N; lane++) begin
        raw_act_vec[lane] = '0;
        raw_wgt_vec[lane] = '0;
    end
end
endtask

task automatic init_matrices();
    int signed a_val;
    int signed b_val;
begin
    for (int i = 0; i < N; i++) begin
        for (int k = 0; k < N; k++) begin
            a_val = ((i * 3 + k * 2 + 1) % 9) - 4;
            A[i][k] = to_data(a_val);
        end
    end

    for (int k = 0; k < N; k++) begin
        for (int j = 0; j < N; j++) begin
            b_val = ((k * 5 + j * 2 + 3) % 9) - 4;
            B[k][j] = to_data(b_val);
        end
    end

    // These rows/columns force easy-to-see positive, negative, zero, and saturation cases.
    for (int k = 0; k < N; k++) begin
        A[0][k] = 8'sd4;
        A[1][k] = -8'sd4;
        A[2][k] = 8'sd0;
        B[k][0] = 8'sd4;
        B[k][1] = 8'sd4;
        B[k][2] = 8'sd0;
    end
end
endtask

task automatic compute_golden(input logic [SCALE_W-1:0] test_scale);
begin
    for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
            golden_C[i][j] = '0;
            for (int k = 0; k < N; k++) begin
                golden_C[i][j] = golden_C[i][j] + mul_i8_to_i32(A[i][k], B[k][j]);
            end
            golden_out[i][j] = golden_post_lane(golden_C[i][j], test_scale);
        end
    end
end
endtask

task automatic drive_raw_stream_cycle(input int stream_count);
begin
    for (int row = 0; row < N; row++) begin
        if (stream_count < INPUT_CYCLES) begin
            raw_act_vec[row] = A[row][stream_count];
        end
        else begin
            raw_act_vec[row] = '0;
        end
    end

    for (int col = 0; col < N; col++) begin
        if (stream_count < INPUT_CYCLES) begin
            raw_wgt_vec[col] = B[stream_count][col];
        end
        else begin
            raw_wgt_vec[col] = '0;
        end
    end
end
endtask

task automatic pulse_start();
begin
    @(negedge clk);
    start = 1'b1;
    en    = 1'b1;

    @(negedge clk);
    start = 1'b0;
end
endtask

task automatic run_input_stream();
begin
    wait (input_active === 1'b1);

    for (int t = 0; t < STREAM_CYCLES; t++) begin
        @(negedge clk);
        if (input_active !== 1'b1) begin
            $display("INPUT_STREAM: expected input_active=1 at stream cycle %0d, got %0b",
                     t, input_active);
            $fatal(1);
        end
        drive_raw_stream_cycle(t);

        @(posedge clk);
        #1;
    end

    drive_zero_raw_inputs();
    if (input_active !== 1'b0) begin
        $display("INPUT_STREAM: expected input_active=0 after %0d cycles, got %0b",
                 STREAM_CYCLES, input_active);
        $fatal(1);
    end
end
endtask

task automatic check_output_row(input int expected_row);
    logic [$clog2(N)-1:0] expected_idx;
begin
    expected_idx = expected_row;

    if (out_row_idx !== expected_idx) begin
        $display("OUTPUT_CHECK row order mismatch: expected row %0d, got %0d",
                 expected_row, out_row_idx);
        $fatal(1);
    end

    for (int col = 0; col < N; col++) begin
        if (out_vec[col] !== golden_out[expected_row][col]) begin
            $display("OUTPUT_CHECK mismatch row %0d col %0d: golden_C=%0d expected=%0d got=%0d",
                     expected_row, col, golden_C[expected_row][col],
                     golden_out[expected_row][col], out_vec[col]);
            $fatal(1);
        end
    end
end
endtask

task automatic wait_for_outputs_and_done();
    int output_count;
    int timeout_count;
    bit done_seen;
begin
    output_count  = 0;
    timeout_count = 0;
    done_seen     = 1'b0;

    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (out_valid) begin
            if (output_count >= N) begin
                $display("OUTPUT_CHECK: received more than %0d output rows", N);
                $fatal(1);
            end

            check_output_row(output_count);
            output_count = output_count + 1;
        end

        if (done) begin
            done_seen = 1'b1;
            if (out_valid !== 1'b0) begin
                $display("DONE_CHECK: expected out_valid=0 when done=1, got %0b",
                         out_valid);
                $fatal(1);
            end
            if (output_count != N) begin
                $display("DONE_CHECK: done asserted after %0d output rows, expected %0d",
                         output_count, N);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("DONE_CHECK: timeout waiting for done");
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (out_valid !== 1'b0) begin
        $display("DONE_CHECK: expected out_valid=0 after done, got %0b", out_valid);
        $fatal(1);
    end
    if (output_count != N) begin
        $display("OUTPUT_CHECK: expected %0d output rows, got %0d", N, output_count);
        $fatal(1);
    end
end
endtask

initial begin
    rst     = 1'b1;
    clear   = 1'b0;
    start   = 1'b0;
    en      = 1'b0;
    scale_q = SCALE_M4;
    drive_zero_raw_inputs();
    init_matrices();
    compute_golden(SCALE_M4);

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    pulse_start();
    run_input_stream();
    wait_for_outputs_and_done();

    $display("TILE_DATAPATH_16x16 WRAPPER test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

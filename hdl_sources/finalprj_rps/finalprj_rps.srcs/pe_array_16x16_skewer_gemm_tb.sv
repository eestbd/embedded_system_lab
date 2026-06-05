`timescale 1ns / 1ps

module pe_array_16x16_skewer_gemm_tb;

localparam int N             = 16;
localparam int DATA_W        = 8;
localparam int ACC_W         = 32;
localparam int INPUT_CYCLES  = 16;
localparam int FLUSH_CYCLES  = 30;
localparam int TOTAL_CYCLES  = INPUT_CYCLES + FLUSH_CYCLES;
localparam int EXTRA_WAIT    = 3;

logic clk;
logic rst;
logic rst_n;
logic clear;
logic en;

logic signed [DATA_W-1:0] raw_act_vec    [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec    [0:N-1];
logic signed [DATA_W-1:0] act_vec_skewed [0:N-1];
logic signed [DATA_W-1:0] wgt_vec_skewed [0:N-1];

logic signed [DATA_W-1:0] act_last_vec [0:N-1];
logic signed [DATA_W-1:0] wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat      [0:N-1][0:N-1];

logic signed [DATA_W-1:0] A [0:N-1][0:N-1];
logic signed [DATA_W-1:0] B [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  golden_C [0:N-1][0:N-1];

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) act_skewer (
    .clk     (clk),
    .rst     (rst),
    .clear   (clear),
    .en      (en),
    .vec_in  (raw_act_vec),
    .vec_out (act_vec_skewed)
);

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) wgt_skewer (
    .clk     (clk),
    .rst     (rst),
    .clear   (clear),
    .en      (en),
    .vec_in  (raw_wgt_vec),
    .vec_out (wgt_vec_skewed)
);

PE_ARRAY_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) dut (
    .i_clk          (clk),
    .i_rst_n        (rst_n),
    .i_clear        (clear),
    .i_en           (en),
    .i_act_vec      (act_vec_skewed),
    .i_wgt_vec      (wgt_vec_skewed),
    .o_act_last_vec (act_last_vec),
    .o_wgt_last_vec (wgt_last_vec),
    .o_acc_mat      (acc_mat)
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
end
endtask

task automatic compute_golden();
begin
    for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
            golden_C[i][j] = '0;
            for (int k = 0; k < N; k++) begin
                golden_C[i][j] = golden_C[i][j] + mul_i8_to_i32(A[i][k], B[k][j]);
            end
        end
    end
end
endtask

task automatic drive_raw_gemm_cycle(input int t);
begin
    for (int i = 0; i < N; i++) begin
        if (t < INPUT_CYCLES) begin
            raw_act_vec[i] = A[i][t];
        end
        else begin
            raw_act_vec[i] = '0;
        end
    end

    for (int j = 0; j < N; j++) begin
        if (t < INPUT_CYCLES) begin
            raw_wgt_vec[j] = B[t][j];
        end
        else begin
            raw_wgt_vec[j] = '0;
        end
    end
end
endtask

function automatic logic signed [DATA_W-1:0] expected_skewed_act(
    input int row,
    input int t
);
    int k_idx;
begin
    k_idx = t - row;
    if ((k_idx >= 0) && (k_idx < INPUT_CYCLES)) begin
        expected_skewed_act = A[row][k_idx];
    end
    else begin
        expected_skewed_act = '0;
    end
end
endfunction

function automatic logic signed [DATA_W-1:0] expected_skewed_wgt(
    input int col,
    input int t
);
    int k_idx;
begin
    k_idx = t - col;
    if ((k_idx >= 0) && (k_idx < INPUT_CYCLES)) begin
        expected_skewed_wgt = B[k_idx][col];
    end
    else begin
        expected_skewed_wgt = '0;
    end
end
endfunction

task automatic check_skewed_inputs(input int t);
    logic signed [DATA_W-1:0] expected_act;
    logic signed [DATA_W-1:0] expected_wgt;
begin
    for (int lane = 0; lane < N; lane++) begin
        expected_act = expected_skewed_act(lane, t);
        expected_wgt = expected_skewed_wgt(lane, t);

        if (act_vec_skewed[lane] !== expected_act) begin
            $display("act skewer mismatch at cycle %0d lane %0d: expected %0d, got %0d",
                     t, lane, expected_act, act_vec_skewed[lane]);
            $fatal(1);
        end

        if (wgt_vec_skewed[lane] !== expected_wgt) begin
            $display("wgt skewer mismatch at cycle %0d lane %0d: expected %0d, got %0d",
                     t, lane, expected_wgt, wgt_vec_skewed[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_all_acc_zero(input string label);
begin
    for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
            if (acc_mat[i][j] !== '0) begin
                $display("%s mismatch at PE[%0d][%0d]: expected 0, got %0d",
                         label, i, j, acc_mat[i][j]);
                $fatal(1);
            end
        end
    end
end
endtask

task automatic clear_skewer_and_array();
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;
    drive_zero_raw_inputs();

    repeat (N) @(posedge clk);
    #1;
    check_all_acc_zero("clear");

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_raw_inputs();
end
endtask

task automatic run_raw_skewer_gemm_stream();
begin
    for (int t = 0; t < TOTAL_CYCLES; t++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        drive_raw_gemm_cycle(t);
        #1;
        check_skewed_inputs(t);

        @(posedge clk);
        #1;
    end

    @(negedge clk);
    en = 1'b0;
    drive_zero_raw_inputs();

    repeat (EXTRA_WAIT) @(posedge clk);
    #1;
end
endtask

task automatic check_gemm_result();
begin
    for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
            if (acc_mat[i][j] !== golden_C[i][j]) begin
                $display("SKEWER GEMM mismatch at C[%0d][%0d]: expected %0d, got %0d",
                         i, j, golden_C[i][j], acc_mat[i][j]);
                $fatal(1);
            end
        end
    end
end
endtask

initial begin
    rst   = 1'b1;
    rst_n = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_raw_inputs();
    init_matrices();
    compute_golden();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst   = 1'b0;
    rst_n = 1'b1;

    @(posedge clk);
    #1;
    check_all_acc_zero("reset");

    clear_skewer_and_array();
    run_raw_skewer_gemm_stream();
    check_gemm_result();

    $display("PE_ARRAY_16x16 SKEWER GEMM test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

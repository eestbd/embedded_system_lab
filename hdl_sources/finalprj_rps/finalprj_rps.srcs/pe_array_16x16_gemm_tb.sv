`timescale 1ns / 1ps

module pe_array_16x16_gemm_tb;

localparam int N             = 16;
localparam int DATA_W        = 8;
localparam int ACC_W         = 32;
localparam int STREAM_CYCLES = N + (N - 1) + (N - 1);
localparam int EXTRA_WAIT    = 3;

logic clk;
logic rst_n;
logic clear;
logic en;

logic signed [DATA_W-1:0] act_vec [0:N-1];
logic signed [DATA_W-1:0] wgt_vec [0:N-1];

logic signed [DATA_W-1:0] act_last_vec [0:N-1];
logic signed [DATA_W-1:0] wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat [0:N-1][0:N-1];

logic signed [DATA_W-1:0] A [0:N-1][0:N-1];
logic signed [DATA_W-1:0] B [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  golden_C [0:N-1][0:N-1];

PE_ARRAY_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) u_dut (
    .i_clk          (clk),
    .i_rst_n        (rst_n),
    .i_clear        (clear),
    .i_en           (en),
    .i_act_vec      (act_vec),
    .i_wgt_vec      (wgt_vec),
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

task automatic drive_zero_inputs();
begin
    for (int i = 0; i < N; i++) begin
        act_vec[i] = '0;
        wgt_vec[i] = '0;
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

task automatic clear_accumulators_and_pipeline();
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;
    drive_zero_inputs();

    repeat (N) @(posedge clk);
    #1;
    check_all_acc_zero("clear");

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_inputs();
end
endtask

task automatic drive_gemm_cycle(input int t);
    int k_idx;
begin
    for (int i = 0; i < N; i++) begin
        k_idx = t - i;
        if ((k_idx >= 0) && (k_idx < N)) begin
            act_vec[i] = A[i][k_idx];
        end
        else begin
            act_vec[i] = '0;
        end
    end

    for (int j = 0; j < N; j++) begin
        k_idx = t - j;
        if ((k_idx >= 0) && (k_idx < N)) begin
            wgt_vec[j] = B[k_idx][j];
        end
        else begin
            wgt_vec[j] = '0;
        end
    end
end
endtask

task automatic run_gemm_stream();
begin
    for (int t = 0; t < STREAM_CYCLES; t++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        drive_gemm_cycle(t);

        @(posedge clk);
        #1;
    end

    @(negedge clk);
    en = 1'b0;
    drive_zero_inputs();

    repeat (EXTRA_WAIT) @(posedge clk);
    #1;
end
endtask

task automatic check_gemm_result();
begin
    for (int i = 0; i < N; i++) begin
        for (int j = 0; j < N; j++) begin
            if (acc_mat[i][j] !== golden_C[i][j]) begin
                $display("GEMM mismatch at C[%0d][%0d]: expected %0d, got %0d",
                         i, j, golden_C[i][j], acc_mat[i][j]);
                $fatal(1);
            end
        end
    end
end
endtask

initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_inputs();
    init_matrices();
    compute_golden();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_all_acc_zero("reset");

    clear_accumulators_and_pipeline();
    run_gemm_stream();
    check_gemm_result();

    $display("PE_ARRAY_16x16 GEMM test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

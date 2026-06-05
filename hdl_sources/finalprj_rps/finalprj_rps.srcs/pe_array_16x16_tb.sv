`timescale 1ns / 1ps

module pe_array_16x16_tb;

localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int ACC_W          = 32;
localparam int COMPUTE_CYCLES = 4;
localparam int SKEW_CYCLES    = 2 * (N - 1);
localparam int TOTAL_CYCLES   = COMPUTE_CYCLES + SKEW_CYCLES;

logic clk;
logic rst_n;
logic clear;
logic en;

logic signed [DATA_W-1:0] act_vec [0:N-1];
logic signed [DATA_W-1:0] wgt_vec [0:N-1];

logic signed [DATA_W-1:0] act_last_vec [0:N-1];
logic signed [DATA_W-1:0] wgt_last_vec [0:N-1];
logic signed [ACC_W-1:0]  acc_mat [0:N-1][0:N-1];

logic signed [DATA_W-1:0] act_row0_tap [0:N];
logic signed [DATA_W-1:0] wgt_col0_tap [0:N];

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

genvar g_tap;
generate
    for (g_tap = 0; g_tap <= N; g_tap++) begin : g_wave_tap
        assign act_row0_tap[g_tap] = u_dut.act_pipe[0][g_tap];
        assign wgt_col0_tap[g_tap] = u_dut.wgt_pipe[g_tap][0];
    end
endgenerate

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic int signed act_value(input int row, input bit signed_pattern);
begin
    if (signed_pattern && (row % 2)) begin
        act_value = -(row + 1);
    end
    else begin
        act_value = row + 1;
    end
end
endfunction

function automatic int signed wgt_value(input int col, input bit signed_pattern);
begin
    if (signed_pattern && (col % 2)) begin
        wgt_value = -(col + 1);
    end
    else begin
        wgt_value = col + 1;
    end
end
endfunction

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

function automatic logic signed [ACC_W-1:0] to_acc(input int signed value);
begin
    to_acc = value;
end
endfunction

function automatic logic signed [DATA_W-1:0] forwarding_act_value(input int cycle_idx);
begin
    case (cycle_idx)
        0: forwarding_act_value = 8'sd1;
        1: forwarding_act_value = 8'sd2;
        2: forwarding_act_value = 8'sd3;
        3: forwarding_act_value = 8'sd4;
        default: forwarding_act_value = '0;
    endcase
end
endfunction

function automatic logic signed [DATA_W-1:0] forwarding_wgt_value(input int cycle_idx);
begin
    if ((cycle_idx >= 0) && (cycle_idx < COMPUTE_CYCLES)) begin
        forwarding_wgt_value = 8'sd1;
    end
    else begin
        forwarding_wgt_value = '0;
    end
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

task automatic check_all_acc_zero(input string label);
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            if (acc_mat[row][col] !== '0) begin
                $error("%s: PE[%0d][%0d] expected acc=0, got acc=%0d",
                       label, row, col, acc_mat[row][col]);
                $fatal(1);
            end
        end
    end
end
endtask

task automatic apply_clear(input string label);
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;
    drive_zero_inputs();

    repeat (N) @(posedge clk);
    #1;
    check_all_acc_zero(label);

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
end
endtask

task automatic run_warmup_activity();
begin
    @(negedge clk);
    clear = 1'b0;
    en    = 1'b1;
    for (int i = 0; i < N; i++) begin
        act_vec[i] = to_data(i + 1);
        wgt_vec[i] = to_data(i + 1);
    end

    repeat (3) @(posedge clk);

    @(negedge clk);
    en = 1'b0;
    drive_zero_inputs();
end
endtask

task automatic check_forwarding_taps(input int cycle_idx);
    logic signed [DATA_W-1:0] expected_act;
    logic signed [DATA_W-1:0] expected_wgt;
    int source_idx;
begin
    for (int tap = 1; tap <= N; tap++) begin
        source_idx   = cycle_idx - (tap - 1);
        expected_act = forwarding_act_value(source_idx);
        expected_wgt = forwarding_wgt_value(source_idx);

        if (act_row0_tap[tap] !== expected_act) begin
            $error("forwarding act tap[%0d] cycle %0d expected=%0d actual=%0d",
                   tap, cycle_idx, expected_act, act_row0_tap[tap]);
            $fatal(1);
        end

        if (wgt_col0_tap[tap] !== expected_wgt) begin
            $error("forwarding wgt tap[%0d] cycle %0d expected=%0d actual=%0d",
                   tap, cycle_idx, expected_wgt, wgt_col0_tap[tap]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_forwarding_accumulators();
    logic signed [ACC_W-1:0] expected;
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            if ((row == 0) && (col == 0)) begin
                expected = 32'sd10;
            end
            else begin
                expected = '0;
            end

            if (acc_mat[row][col] !== expected) begin
                $error("forwarding acc PE[%0d][%0d] expected=%0d actual=%0d",
                       row, col, expected, acc_mat[row][col]);
                $fatal(1);
            end
        end
    end
end
endtask

task automatic run_forwarding_test();
begin
    apply_clear("clear before forwarding test");
    $display("forwarding test start");

    for (int cycle_idx = 0; cycle_idx < TOTAL_CYCLES; cycle_idx++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        drive_zero_inputs();
        act_vec[0] = forwarding_act_value(cycle_idx);
        wgt_vec[0] = forwarding_wgt_value(cycle_idx);

        @(posedge clk);
        #1;
        check_forwarding_taps(cycle_idx);
    end

    @(negedge clk);
    en = 1'b0;
    drive_zero_inputs();
    #1;
    check_forwarding_accumulators();
    $display("forwarding test OK");
end
endtask

task automatic drive_skewed_pattern(input int cycle_idx, input bit signed_pattern);
begin
    for (int row = 0; row < N; row++) begin
        if ((cycle_idx >= row) && (cycle_idx < (row + COMPUTE_CYCLES))) begin
            act_vec[row] = to_data(act_value(row, signed_pattern));
        end
        else begin
            act_vec[row] = '0;
        end
    end

    for (int col = 0; col < N; col++) begin
        if ((cycle_idx >= col) && (cycle_idx < (col + COMPUTE_CYCLES))) begin
            wgt_vec[col] = to_data(wgt_value(col, signed_pattern));
        end
        else begin
            wgt_vec[col] = '0;
        end
    end
end
endtask

task automatic check_pattern_accumulators(input string label, input bit signed_pattern);
    logic signed [ACC_W-1:0] expected;
    int signed expected_int;
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            expected_int = COMPUTE_CYCLES
                         * act_value(row, signed_pattern)
                         * wgt_value(col, signed_pattern);
            expected = to_acc(expected_int);

            if (acc_mat[row][col] !== expected) begin
                $error("%s: PE[%0d][%0d] expected=%0d actual=%0d",
                       label, row, col, expected, acc_mat[row][col]);
                $fatal(1);
            end
        end
    end
    $display("%s OK", label);
end
endtask

task automatic run_skewed_constant_test(input string label, input bit signed_pattern);
begin
    apply_clear(label);
    $display("%s start", label);

    for (int cycle_idx = 0; cycle_idx < TOTAL_CYCLES; cycle_idx++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        drive_skewed_pattern(cycle_idx, signed_pattern);

        @(posedge clk);
        #1;
    end

    @(negedge clk);
    en = 1'b0;
    drive_zero_inputs();
    #1;
    check_pattern_accumulators(label, signed_pattern);
end
endtask

initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_inputs();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_all_acc_zero("reset");

    run_warmup_activity();
    apply_clear("clear after warmup activity");

    run_forwarding_test();
    run_skewed_constant_test("constant positive pattern", 1'b0);
    run_skewed_constant_test("constant signed pattern", 1'b1);

    $display("PE_ARRAY_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

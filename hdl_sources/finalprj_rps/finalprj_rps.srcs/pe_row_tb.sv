`timescale 1ns / 1ps

module pe_row_tb;

localparam int N            = 16;
localparam int DATA_W       = 8;
localparam int ACC_W        = 32;
localparam int SEQ_LEN      = 4;
localparam int FLUSH_CYCLES = N;
localparam int TOTAL_CYCLES = SEQ_LEN + FLUSH_CYCLES;

logic clk;
logic rst_n;
logic clear;
logic en;
logic signed [DATA_W-1:0] act;
logic signed [DATA_W-1:0] wgt_vec [0:N-1];
logic signed [DATA_W-1:0] act_last;
logic signed [ACC_W-1:0]  acc_vec [0:N-1];

logic signed [DATA_W-1:0] act_seq [0:TOTAL_CYCLES-1];

PE_ROW #(
    .N     (N),
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) u_dut (
    .i_clk      (clk),
    .i_rst_n    (rst_n),
    .i_clear    (clear),
    .i_en       (en),
    .i_act      (act),
    .i_wgt_vec  (wgt_vec),
    .o_act_last (act_last),
    .o_acc_vec  (acc_vec)
);

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic logic signed [ACC_W-1:0] extend_data(
    input logic signed [DATA_W-1:0] value
);
begin
    extend_data = {{(ACC_W-DATA_W){value[DATA_W-1]}}, value};
end
endfunction

function automatic logic signed [DATA_W-1:0] expected_last_act(input int cycle_idx);
    int source_idx;
begin
    source_idx = cycle_idx - (N - 1);
    if ((source_idx >= 0) && (source_idx < TOTAL_CYCLES)) begin
        expected_last_act = act_seq[source_idx];
    end
    else begin
        expected_last_act = '0;
    end
end
endfunction

function automatic logic signed [ACC_W-1:0] sequence_sum();
    logic signed [ACC_W-1:0] sum;
begin
    sum = '0;
    for (int i = 0; i < SEQ_LEN; i++) begin
        sum = sum + extend_data(act_seq[i]);
    end
    sequence_sum = sum;
end
endfunction

function automatic logic signed [ACC_W-1:0] expected_acc_for_weight(
    input logic signed [DATA_W-1:0] weight
);
begin
    expected_acc_for_weight = sequence_sum() * extend_data(weight);
end
endfunction

task automatic fatal_mismatch(input string label);
begin
    $error("%s", label);
    $fatal(1);
end
endtask

task automatic check_all_acc_zero(input string label);
begin
    for (int j = 0; j < N; j++) begin
        if (acc_vec[j] !== '0) begin
            $error("%s: PE%0d expected acc=0, got acc=%0d", label, j, acc_vec[j]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_accumulators(input string label);
    logic signed [ACC_W-1:0] expected;
begin
    for (int j = 0; j < N; j++) begin
        expected = expected_acc_for_weight(wgt_vec[j]);
        if (acc_vec[j] !== expected) begin
            $error("%s: PE%0d expected acc=%0d, got acc=%0d",
                   label, j, expected, acc_vec[j]);
            $fatal(1);
        end
    end
    $display("%s: accumulators OK", label);
end
endtask

task automatic apply_clear(input string label);
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b0;
    act   = '0;

    @(posedge clk);
    #1;
    check_all_acc_zero(label);

    @(negedge clk);
    clear = 1'b0;
end
endtask

task automatic set_all_weights(input logic signed [DATA_W-1:0] value);
begin
    for (int j = 0; j < N; j++) begin
        wgt_vec[j] = value;
    end
end
endtask

task automatic set_index_weights();
begin
    for (int j = 0; j < N; j++) begin
        wgt_vec[j] = j + 1;
    end
end
endtask

task automatic set_signed_weights();
begin
    for (int j = 0; j < N; j++) begin
        if (j < (N/2)) begin
            wgt_vec[j] = -(j + 1);
        end
        else begin
            wgt_vec[j] = j - (N/2) + 1;
        end
    end
end
endtask

task automatic load_positive_sequence();
begin
    for (int i = 0; i < TOTAL_CYCLES; i++) begin
        act_seq[i] = '0;
    end
    act_seq[0] = 8'sd1;
    act_seq[1] = 8'sd2;
    act_seq[2] = 8'sd3;
    act_seq[3] = 8'sd4;
end
endtask

task automatic load_signed_sequence();
begin
    for (int i = 0; i < TOTAL_CYCLES; i++) begin
        act_seq[i] = '0;
    end
    act_seq[0] = -8'sd1;
    act_seq[1] =  8'sd2;
    act_seq[2] = -8'sd3;
    act_seq[3] =  8'sd4;
end
endtask

task automatic run_sequence_and_check_forwarding(input string label);
    logic signed [DATA_W-1:0] expected_last;
begin
    $display("%s: forwarding run start", label);

    for (int cycle_idx = 0; cycle_idx < TOTAL_CYCLES; cycle_idx++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        act   = act_seq[cycle_idx];

        @(posedge clk);
        #1;
        expected_last = expected_last_act(cycle_idx);
        if (act_last !== expected_last) begin
            $error("%s: cycle %0d expected o_act_last=%0d, got o_act_last=%0d",
                   label, cycle_idx, expected_last, act_last);
            $fatal(1);
        end
    end

    @(negedge clk);
    en  = 1'b0;
    act = '0;
end
endtask

task automatic check_enable_hold();
begin
    set_all_weights(8'sd1);

    for (int i = 0; i < 3; i++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b0;
        act   = 8'sd7;

        @(posedge clk);
        #1;
        check_all_acc_zero("enable low hold");
        if (act_last !== '0) begin
            fatal_mismatch("enable low hold: o_act_last changed while i_en=0");
        end
    end

    @(negedge clk);
    act = '0;
end
endtask

initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    act   = '0;
    set_all_weights(8'sd0);
    load_positive_sequence();

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_all_acc_zero("reset");
    if (act_last !== '0) begin
        fatal_mismatch("reset: o_act_last is not zero");
    end

    check_enable_hold();

    apply_clear("clear before all-one weight test");
    set_all_weights(8'sd1);
    load_positive_sequence();
    run_sequence_and_check_forwarding("all weights = 1, act = 1,2,3,4");
    check_accumulators("all weights = 1, act = 1,2,3,4");

    apply_clear("clear before index weight test");
    set_index_weights();
    load_positive_sequence();
    run_sequence_and_check_forwarding("weights = j+1, act = 1,2,3,4");
    check_accumulators("weights = j+1, act = 1,2,3,4");

    apply_clear("clear before signed test");
    set_signed_weights();
    load_signed_sequence();
    run_sequence_and_check_forwarding("signed weights, act = -1,2,-3,4");
    check_accumulators("signed weights, act = -1,2,-3,4");

    $display("PE_ROW test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

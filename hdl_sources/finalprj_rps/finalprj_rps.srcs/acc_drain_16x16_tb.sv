`timescale 1ns / 1ps

module acc_drain_16x16_tb;

localparam int N     = 16;
localparam int ACC_W = 32;

logic clk;
logic rst;
logic clear;
logic en;
logic start;

logic signed [ACC_W-1:0] acc_mat [0:N-1][0:N-1];
logic signed [ACC_W-1:0] row_vec [0:N-1];
logic row_valid;
logic [$clog2(N)-1:0] row_idx_out;
logic busy;
logic done;

acc_drain_16x16 #(
    .N    (N),
    .ACC_W(ACC_W)
) u_dut (
    .clk         (clk),
    .rst         (rst),
    .clear       (clear),
    .en          (en),
    .start       (start),
    .acc_mat     (acc_mat),
    .row_vec     (row_vec),
    .row_valid   (row_valid),
    .row_idx_out (row_idx_out),
    .busy        (busy),
    .done        (done)
);

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic logic signed [ACC_W-1:0] acc_value(
    input int row,
    input int col
);
    int signed value;
begin
    value = (row - 8) * 100 + (col - 8);
    acc_value = value;
end
endfunction

task automatic init_acc_mat();
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            acc_mat[row][col] = acc_value(row, col);
        end
    end
end
endtask

task automatic check_idle(input string label);
begin
    if (row_valid !== 1'b0) begin
        $display("%s: expected row_valid=0, got %0b", label, row_valid);
        $fatal(1);
    end
    if (busy !== 1'b0) begin
        $display("%s: expected busy=0, got %0b", label, busy);
        $fatal(1);
    end
    if (done !== 1'b0) begin
        $display("%s: expected done=0, got %0b", label, done);
        $fatal(1);
    end
end
endtask

task automatic check_row(input int expected_row, input string label);
    logic [$clog2(N)-1:0] expected_idx;
begin
    expected_idx = expected_row;

    if (row_valid !== 1'b1) begin
        $display("%s: row %0d expected row_valid=1, got %0b",
                 label, expected_row, row_valid);
        $fatal(1);
    end
    if (busy !== 1'b1) begin
        $display("%s: row %0d expected busy=1, got %0b",
                 label, expected_row, busy);
        $fatal(1);
    end
    if (row_idx_out !== expected_idx) begin
        $display("%s: expected row_idx=%0d, got %0d",
                 label, expected_row, row_idx_out);
        $fatal(1);
    end

    for (int col = 0; col < N; col++) begin
        if (row_vec[col] !== acc_mat[expected_row][col]) begin
            $display("%s mismatch row %0d col %0d: expected %0d, got %0d",
                     label, expected_row, col, acc_mat[expected_row][col], row_vec[col]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_done_pulse(input string label);
begin
    if (row_valid !== 1'b0) begin
        $display("%s: expected row_valid=0 during done, got %0b", label, row_valid);
        $fatal(1);
    end
    if (busy !== 1'b0) begin
        $display("%s: expected busy=0 during done, got %0b", label, busy);
        $fatal(1);
    end
    if (done !== 1'b1) begin
        $display("%s: expected done=1, got %0b", label, done);
        $fatal(1);
    end
end
endtask

task automatic apply_reset();
begin
    @(negedge clk);
    rst   = 1'b1;
    clear = 1'b0;
    en    = 1'b0;
    start = 1'b0;

    repeat (2) @(posedge clk);
    #1;
    check_idle("reset");

    @(negedge clk);
    rst = 1'b0;
end
endtask

task automatic apply_clear_while_active();
begin
    @(negedge clk);
    en    = 1'b1;
    start = 1'b1;

    @(posedge clk);
    #1;
    check_row(0, "clear setup row0");

    @(negedge clk);
    start = 1'b0;

    @(posedge clk);
    #1;
    check_row(1, "clear setup row1");

    @(negedge clk);
    clear = 1'b1;

    @(posedge clk);
    #1;
    check_idle("clear active drain");

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
end
endtask

task automatic hold_enable_low(input int held_row);
begin
    for (int hold_cycle = 0; hold_cycle < 2; hold_cycle++) begin
        @(negedge clk);
        en    = 1'b0;
        start = 1'b1; // start must be ignored while drain state is held

        @(posedge clk);
        #1;
        check_row(held_row, "en hold");
    end

    @(negedge clk);
    en    = 1'b1;
    start = 1'b0;
end
endtask

task automatic run_full_drain_with_hold();
begin
    @(negedge clk);
    en    = 1'b1;
    start = 1'b1;

    @(posedge clk);
    #1;
    check_row(0, "full drain");

    @(negedge clk);
    start = 1'b0;

    for (int row = 1; row < N; row++) begin
        if (row == 5) begin
            hold_enable_low(row - 1);
        end

        @(posedge clk);
        #1;
        check_row(row, "full drain");

        // A start pulse during DRAIN must not restart at row 0.
        if (row == 8) begin
            @(negedge clk);
            start = 1'b1;
            @(posedge clk);
            #1;
            check_row(row + 1, "start ignored during drain");
            @(negedge clk);
            start = 1'b0;
            row = row + 1;
        end
    end

    @(posedge clk);
    #1;
    check_done_pulse("done after row15");

    @(posedge clk);
    #1;
    check_idle("idle after done");
end
endtask

initial begin
    rst   = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    start = 1'b0;
    init_acc_mat();

    apply_reset();
    apply_clear_while_active();
    run_full_drain_with_hold();

    $display("ACC_DRAIN_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

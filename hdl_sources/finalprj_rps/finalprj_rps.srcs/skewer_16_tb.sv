`timescale 1ns / 1ps

module skewer_16_tb;

localparam int N            = 16;
localparam int DATA_W       = 8;
localparam int INPUT_CYCLES = 20;
localparam int FLUSH_CYCLES = N;
localparam int TOTAL_CYCLES = INPUT_CYCLES + FLUSH_CYCLES;

logic clk;
logic rst;
logic clear;
logic en;

logic signed [DATA_W-1:0] vec_in  [0:N-1];
logic signed [DATA_W-1:0] vec_out [0:N-1];

logic signed [DATA_W-1:0] vec_in_0;
logic signed [DATA_W-1:0] vec_in_1;
logic signed [DATA_W-1:0] vec_in_2;
logic signed [DATA_W-1:0] vec_out_0;
logic signed [DATA_W-1:0] vec_out_1;
logic signed [DATA_W-1:0] vec_out_2;

assign vec_in_0  = vec_in[0];
assign vec_in_1  = vec_in[1];
assign vec_in_2  = vec_in[2];
assign vec_out_0 = vec_out[0];
assign vec_out_1 = vec_out[1];
assign vec_out_2 = vec_out[2];

skewer_16 #(
    .N     (N),
    .DATA_W(DATA_W)
) u_dut (
    .clk     (clk),
    .rst     (rst),
    .clear   (clear),
    .en      (en),
    .vec_in  (vec_in),
    .vec_out (vec_out)
);

initial clk = 1'b0;
always #5 clk = ~clk;

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

function automatic logic signed [DATA_W-1:0] input_pattern(
    input int lane,
    input int cycle_idx
);
    int signed value;
begin
    value = ((lane * 3 + cycle_idx * 5 + 2) % 17) - 8;
    input_pattern = to_data(value);
end
endfunction

function automatic logic signed [DATA_W-1:0] expected_output(
    input int lane,
    input int cycle_idx
);
    int source_cycle;
begin
    source_cycle = cycle_idx - lane;
    if ((source_cycle >= 0) && (source_cycle < INPUT_CYCLES)) begin
        expected_output = input_pattern(lane, source_cycle);
    end
    else begin
        expected_output = '0;
    end
end
endfunction

task automatic drive_zero_inputs();
begin
    for (int lane = 0; lane < N; lane++) begin
        vec_in[lane] = '0;
    end
end
endtask

task automatic drive_pattern_cycle(input int cycle_idx);
begin
    for (int lane = 0; lane < N; lane++) begin
        if (cycle_idx < INPUT_CYCLES) begin
            vec_in[lane] = input_pattern(lane, cycle_idx);
        end
        else begin
            vec_in[lane] = '0;
        end
    end
end
endtask

task automatic check_all_outputs_zero(input string label);
begin
    for (int lane = 0; lane < N; lane++) begin
        if (vec_out[lane] !== '0) begin
            $display("%s mismatch lane %0d: expected 0, got %0d",
                     label, lane, vec_out[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_cycle_outputs(input int cycle_idx);
    logic signed [DATA_W-1:0] expected;
begin
    for (int lane = 0; lane < N; lane++) begin
        expected = expected_output(lane, cycle_idx);
        if (vec_out[lane] !== expected) begin
            $display("cycle %0d lane %0d mismatch: expected %0d, got %0d",
                     cycle_idx, lane, expected, vec_out[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_first_three_lanes(input int cycle_idx);
    logic signed [DATA_W-1:0] expected0;
    logic signed [DATA_W-1:0] expected1;
    logic signed [DATA_W-1:0] expected2;
begin
    expected0 = expected_output(0, cycle_idx);
    expected1 = expected_output(1, cycle_idx);
    expected2 = expected_output(2, cycle_idx);

    if (vec_out_0 !== expected0) begin
        $display("lane0 delay-0 mismatch at cycle %0d: expected %0d, got %0d",
                 cycle_idx, expected0, vec_out_0);
        $fatal(1);
    end

    if (vec_out_1 !== expected1) begin
        $display("lane1 delay-1 mismatch at cycle %0d: expected %0d, got %0d",
                 cycle_idx, expected1, vec_out_1);
        $fatal(1);
    end

    if (vec_out_2 !== expected2) begin
        $display("lane2 delay-2 mismatch at cycle %0d: expected %0d, got %0d",
                 cycle_idx, expected2, vec_out_2);
        $fatal(1);
    end
end
endtask

task automatic apply_reset();
begin
    @(negedge clk);
    rst   = 1'b1;
    clear = 1'b0;
    en    = 1'b1;
    drive_zero_inputs();

    repeat (2) @(posedge clk);
    #1;
    check_all_outputs_zero("reset");

    @(negedge clk);
    rst = 1'b0;
    en  = 1'b0;
end
endtask

task automatic apply_clear();
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;
    drive_zero_inputs();

    @(posedge clk);
    #1;
    check_all_outputs_zero("clear");

    @(negedge clk);
    clear = 1'b0;
    en    = 1'b0;
end
endtask

task automatic run_delay_check();
begin
    for (int cycle_idx = 0; cycle_idx < TOTAL_CYCLES; cycle_idx++) begin
        @(negedge clk);
        clear = 1'b0;
        en    = 1'b1;
        drive_pattern_cycle(cycle_idx);

        @(posedge clk);
        #1;
        check_cycle_outputs(cycle_idx);
        check_first_three_lanes(cycle_idx);
    end

    @(negedge clk);
    en = 1'b0;
    drive_zero_inputs();
end
endtask

task automatic check_enable_hold();
    logic signed [DATA_W-1:0] held [0:N-1];
begin
    for (int lane = 0; lane < N; lane++) begin
        held[lane] = vec_out[lane];
    end

    for (int hold_cycle = 0; hold_cycle < 3; hold_cycle++) begin
        @(negedge clk);
        en    = 1'b0;
        clear = 1'b0;
        for (int lane = 0; lane < N; lane++) begin
            vec_in[lane] = input_pattern(lane, INPUT_CYCLES + hold_cycle + 4);
        end

        @(posedge clk);
        #1;
        for (int lane = 1; lane < N; lane++) begin
            if (vec_out[lane] !== held[lane]) begin
                $display("enable hold mismatch lane %0d: expected %0d, got %0d",
                         lane, held[lane], vec_out[lane]);
                $fatal(1);
            end
        end

        if (vec_out[0] !== vec_in[0]) begin
            $display("enable hold lane0 mismatch: expected combinational %0d, got %0d",
                     vec_in[0], vec_out[0]);
            $fatal(1);
        end
    end

    @(negedge clk);
    drive_zero_inputs();
end
endtask

initial begin
    rst   = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    drive_zero_inputs();

    apply_reset();
    run_delay_check();
    check_enable_hold();
    apply_clear();

    $display("SKEWER_16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

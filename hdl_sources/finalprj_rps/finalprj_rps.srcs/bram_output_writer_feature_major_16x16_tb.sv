`timescale 1ns / 1ps

module bram_output_writer_feature_major_16x16_tb;

localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int WORD_W         = 128;
localparam int ADDR_W         = 14;
localparam int MEM_AW         = 12;
localparam int MEM_DEPTH      = 1 << MEM_AW;
localparam int TIMEOUT_CYCLES = 160;

localparam logic [ADDR_W-1:0] OUT_BASE_ADDR = 14'h0300;

logic clk;
logic rst;
logic clear;
logic en;
logic start;

logic [ADDR_W-1:0] out_base_addr;
logic in_valid;
logic [$clog2(N)-1:0] in_row_idx;
logic signed [DATA_W-1:0] in_vec [0:N-1];

logic bram_wr;
logic [ADDR_W-1:0] bram_addr;
logic [WORD_W-1:0] bram_wdata;
logic busy;
logic done;

logic [WORD_W-1:0] out_mem [0:MEM_DEPTH-1];
logic signed [DATA_W-1:0] C [0:N-1][0:N-1];
logic [WORD_W-1:0] expected_word [0:N-1];

bram_output_writer_feature_major_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) dut (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .en           (en),
    .start        (start),
    .out_base_addr(out_base_addr),
    .in_valid     (in_valid),
    .in_row_idx   (in_row_idx),
    .in_vec       (in_vec),
    .bram_wr      (bram_wr),
    .bram_addr    (bram_addr),
    .bram_wdata   (bram_wdata),
    .busy         (busy),
    .done         (done)
);

initial clk = 1'b0;
always #5 clk = ~clk;

always_ff @(posedge clk) begin
    if (bram_wr) begin
        out_mem[bram_addr[MEM_AW-1:0]] <= bram_wdata;
    end
end

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

task automatic drive_zero_input();
begin
    in_valid   = 1'b0;
    in_row_idx = '0;
    for (int lane = 0; lane < N; lane++) begin
        in_vec[lane] = '0;
    end
end
endtask

task automatic init_tile();
    int value;
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            value = (row * 7 + col * 11 + 3) % 128;
            C[row][col] = to_data(value);
        end
    end
end
endtask

task automatic init_expected();
begin
    for (int col = 0; col < N; col++) begin
        expected_word[col] = '0;
        for (int row = 0; row < N; row++) begin
            expected_word[col][DATA_W*row +: DATA_W] = C[row][col];
        end
    end
end
endtask

task automatic init_mock_memory();
begin
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        out_mem[idx] = '0;
    end
end
endtask

task automatic pulse_start();
begin
    @(negedge clk);
    start = 1'b1;

    @(negedge clk);
    start = 1'b0;
end
endtask

task automatic drive_row(input int row);
begin
    in_valid   = 1'b1;
    in_row_idx = row[$clog2(N)-1:0];
    for (int col = 0; col < N; col++) begin
        in_vec[col] = C[row][col];
    end
end
endtask

task automatic check_no_pulse(input string stage);
begin
    if (bram_wr !== 1'b0) begin
        $display("%s: expected bram_wr=0 while held, got %0b", stage, bram_wr);
        $fatal(1);
    end
    if (done !== 1'b0) begin
        $display("%s: expected done=0 while held, got %0b", stage, done);
        $fatal(1);
    end
end
endtask

task automatic check_write(input int col);
    logic [ADDR_W-1:0] expected_addr;
begin
    expected_addr = OUT_BASE_ADDR + col;

    if (bram_addr !== expected_addr) begin
        $display("WRITE_CHECK col %0d: expected addr=0x%0h, got 0x%0h",
                 col, expected_addr, bram_addr);
        $fatal(1);
    end

    if (bram_wdata !== expected_word[col]) begin
        $display("WRITE_CHECK col %0d: expected word 0x%032h, got 0x%032h",
                 col, expected_word[col], bram_wdata);
        for (int row = 0; row < N; row++) begin
            $display("  row %0d expected=%0d got=%0d",
                     row, C[row][col],
                     $signed(bram_wdata[DATA_W*row +: DATA_W]));
        end
        $fatal(1);
    end
end
endtask

task automatic check_output_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int col = 0; col < N; col++) begin
        got_word = out_mem[(OUT_BASE_ADDR + col) & (MEM_DEPTH-1)];

        if (got_word !== expected_word[col]) begin
            $display("MEMORY_CHECK col %0d: expected word 0x%032h, got 0x%032h",
                     col, expected_word[col], got_word);
            for (int row = 0; row < N; row++) begin
                $display("  row %0d expected=%0d got=%0d",
                         row, C[row][col],
                         $signed(got_word[DATA_W*row +: DATA_W]));
            end
            $fatal(1);
        end
    end
end
endtask

task automatic exercise_clear_path();
begin
    pulse_start();

    @(negedge clk);
    drive_row(0);
    @(negedge clk);
    drive_zero_input();

    @(negedge clk);
    clear = 1'b1;
    @(posedge clk);
    #1;
    if (busy !== 1'b0 || bram_wr !== 1'b0 || done !== 1'b0) begin
        $display("CLEAR_CHECK: expected idle/no pulse after clear, busy=%0b bram_wr=%0b done=%0b",
                 busy, bram_wr, done);
        $fatal(1);
    end
    @(negedge clk);
    clear = 1'b0;
end
endtask

task automatic run_writer_check();
    int write_count;
    int timeout_count;
    bit done_seen;
    bit write_hold_done;
begin
    write_count   = 0;
    timeout_count = 0;
    done_seen     = 1'b0;
    write_hold_done = 1'b0;

    pulse_start();

    for (int row = 0; row < N; row++) begin
        if (row == 6) begin
            @(negedge clk);
            en = 1'b0;
            drive_zero_input();
            repeat (2) begin
                @(posedge clk);
                #1;
                check_no_pulse("CAPTURE_HOLD_CHECK");
            end
            @(negedge clk);
            en = 1'b1;
        end

        @(negedge clk);
        drive_row(row);
    end

    @(negedge clk);
    drive_zero_input();

    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (bram_wr) begin
            if (write_count >= N) begin
                $display("WRITE_CHECK: extra write after %0d columns", N);
                $fatal(1);
            end

            check_write(write_count);
            write_count = write_count + 1;

            if ((write_count == 5) && !write_hold_done) begin
                write_hold_done = 1'b1;
                @(negedge clk);
                en = 1'b0;
                repeat (2) begin
                    @(posedge clk);
                    #1;
                    check_no_pulse("WRITE_HOLD_CHECK");
                end
                @(negedge clk);
                en = 1'b1;
            end
        end

        if (done) begin
            done_seen = 1'b1;
            if (write_count != N) begin
                $display("DONE_CHECK: done after %0d writes, expected %0d", write_count, N);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("WRITER_CHECK: timeout waiting for done");
        $fatal(1);
    end
    if (write_count != N) begin
        $display("WRITE_CHECK: expected %0d writes, got %0d", N, write_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
        $display("DONE_CHECK: expected done pulse to clear, got %0b", done);
        $fatal(1);
    end
    if (busy !== 1'b0) begin
        $display("DONE_CHECK: expected busy=0 after DONE, got %0b", busy);
        $fatal(1);
    end
end
endtask

initial begin
    rst           = 1'b1;
    clear         = 1'b0;
    en            = 1'b0;
    start         = 1'b0;
    out_base_addr = OUT_BASE_ADDR;
    drive_zero_input();
    init_tile();
    init_expected();
    init_mock_memory();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    exercise_clear_path();
    run_writer_check();

    repeat (2) @(posedge clk);
    #1;
    check_output_memory();

    $display("BRAM_OUTPUT_WRITER_FEATURE_MAJOR_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

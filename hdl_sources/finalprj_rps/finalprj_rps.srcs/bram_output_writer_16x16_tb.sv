`timescale 1ns / 1ps

module bram_output_writer_16x16_tb;

localparam int N       = 16;
localparam int DATA_W  = 8;
localparam int WORD_W  = 128;
localparam int ADDR_W  = 14;
localparam int MEM_AW  = 12;
localparam int MEM_DEPTH = 1 << MEM_AW;

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
logic signed [DATA_W-1:0] out_matrix [0:N-1][0:N-1];

bram_output_writer_16x16 #(
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

// Mock BRAM write port. Because DUT outputs are registered, this memory sees
// bram_wr/bram_addr/bram_wdata on the following clock edge and stores them then.
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

function automatic logic [WORD_W-1:0] expected_packed_word(input int row);
    logic [WORD_W-1:0] packed_word;
begin
    packed_word = '0;
    for (int lane = 0; lane < N; lane++) begin
        packed_word[DATA_W*lane +: DATA_W] = out_matrix[row][lane];
    end
    expected_packed_word = packed_word;
end
endfunction

task automatic init_out_matrix();
    int unsigned value;
begin
    for (int row = 0; row < N; row++) begin
        for (int lane = 0; lane < N; lane++) begin
            value = (row * 7 + lane * 11 + 3) % 128;
            out_matrix[row][lane] = to_data(value);
        end
    end

    out_matrix[ 0][ 0] = 8'sd0;
    out_matrix[ 0][ 1] = 8'sd1;
    out_matrix[ 0][ 2] = 8'sd2;
    out_matrix[ 3][ 5] = 8'sd15;
    out_matrix[ 7][ 9] = 8'sd64;
    out_matrix[15][15] = 8'sd127;
end
endtask

task automatic init_out_mem();
begin
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        out_mem[idx] = '0;
    end
end
endtask

task automatic drive_zero_input();
begin
    in_valid   = 1'b0;
    in_row_idx = '0;
    for (int lane = 0; lane < N; lane++) begin
        in_vec[lane] = '0;
    end
end
endtask

task automatic drive_row_input(input int row);
begin
    in_valid   = 1'b1;
    in_row_idx = row;
    for (int lane = 0; lane < N; lane++) begin
        in_vec[lane] = out_matrix[row][lane];
    end
end
endtask

task automatic check_idle_state(input string label);
begin
    if (bram_wr !== 1'b0) begin
        $display("%s: expected bram_wr=0, got %0b", label, bram_wr);
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

task automatic apply_clear_check();
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;
    start = 1'b0;
    drive_zero_input();

    @(posedge clk);
    #1;
    check_idle_state("CLEAR_CHECK");

    @(negedge clk);
    clear = 1'b0;
end
endtask

task automatic pulse_start_and_check_active();
begin
    @(negedge clk);
    start = 1'b1;
    en    = 1'b1;
    drive_zero_input();

    @(posedge clk);
    #1;
    if (busy !== 1'b1) begin
        $display("START_CHECK: expected busy=1 after start, got %0b", busy);
        $fatal(1);
    end
    if (bram_wr !== 1'b0) begin
        $display("START_CHECK: expected no write on start-only cycle, got %0b", bram_wr);
        $fatal(1);
    end

    @(negedge clk);
    start = 1'b0;
end
endtask

task automatic check_en_hold();
begin
    @(negedge clk);
    en = 1'b0;
    drive_row_input(0);

    repeat (2) begin
        @(posedge clk);
        #1;
        if (bram_wr !== 1'b0) begin
            $display("EN_HOLD_CHECK: expected bram_wr=0 while en=0, got %0b", bram_wr);
            $fatal(1);
        end
        if (done !== 1'b0) begin
            $display("EN_HOLD_CHECK: expected done=0 while en=0, got %0b", done);
            $fatal(1);
        end
    end

    @(negedge clk);
    en = 1'b1;
    drive_zero_input();
end
endtask

task automatic check_write_pulse(input int row, input int write_count);
    logic [ADDR_W-1:0] expected_addr;
    logic [WORD_W-1:0] expected_word;
begin
    expected_addr = OUT_BASE_ADDR + row;
    expected_word = expected_packed_word(row);

    if (bram_wr !== 1'b1) begin
        $display("WRITE_CHECK row %0d count %0d: expected bram_wr=1, got %0b",
                 row, write_count, bram_wr);
        $fatal(1);
    end
    if (bram_addr !== expected_addr) begin
        $display("WRITE_CHECK row %0d count %0d: expected addr=0x%0h, got 0x%0h",
                 row, write_count, expected_addr, bram_addr);
        $fatal(1);
    end
    if (bram_wdata !== expected_word) begin
        $display("WRITE_CHECK row %0d count %0d: expected packed word 0x%032h, got 0x%032h",
                 row, write_count, expected_word, bram_wdata);
        for (int lane = 0; lane < N; lane++) begin
            $display("  lane %0d expected=%0d got=%0d",
                     lane, out_matrix[row][lane],
                     $signed(bram_wdata[DATA_W*lane +: DATA_W]));
        end
        $fatal(1);
    end
end
endtask

task automatic run_write_rows();
    int write_count;
begin
    write_count = 0;

    for (int row = 0; row < N; row++) begin
        @(negedge clk);
        en = 1'b1;
        drive_row_input(row);

        @(posedge clk);
        #1;
        check_write_pulse(row, write_count);
        write_count = write_count + 1;
    end

    @(negedge clk);
    drive_zero_input();

    @(posedge clk);
    #1;
    if (bram_wr !== 1'b0) begin
        $display("DONE_CHECK: expected bram_wr=0 after final write, got %0b", bram_wr);
        $fatal(1);
    end
    if (done !== 1'b1) begin
        $display("DONE_CHECK: expected done=1 after 16 writes, got %0b", done);
        $fatal(1);
    end
    if (write_count != N) begin
        $display("WRITE_CHECK: expected %0d write pulses, got %0d", N, write_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
        $display("DONE_CHECK: expected done pulse to clear, got %0b", done);
        $fatal(1);
    end
end
endtask

task automatic check_output_memory();
    logic [WORD_W-1:0] expected_word;
    logic [WORD_W-1:0] got_word;
begin
    for (int row = 0; row < N; row++) begin
        expected_word = expected_packed_word(row);
        got_word = out_mem[(OUT_BASE_ADDR + row) & (MEM_DEPTH-1)];

        if (got_word !== expected_word) begin
            $display("MEM_CHECK row %0d: expected packed word 0x%032h, got 0x%032h",
                     row, expected_word, got_word);
            for (int lane = 0; lane < N; lane++) begin
                $display("  lane %0d expected=%0d got=%0d",
                         lane, out_matrix[row][lane],
                         $signed(got_word[DATA_W*lane +: DATA_W]));
            end
            $fatal(1);
        end
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
    init_out_matrix();
    init_out_mem();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    apply_clear_check();
    pulse_start_and_check_active();
    check_en_hold();
    run_write_rows();
    check_output_memory();

    $display("BRAM_OUTPUT_WRITER_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

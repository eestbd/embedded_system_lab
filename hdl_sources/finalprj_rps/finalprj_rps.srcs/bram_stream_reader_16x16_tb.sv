`timescale 1ns / 1ps

module bram_stream_reader_16x16_tb;

localparam int N       = 16;
localparam int DATA_W  = 8;
localparam int WORD_W  = 128;
localparam int ADDR_W  = 14;
localparam int MEM_AW  = 10;
localparam int MEM_DEPTH = 1 << MEM_AW;
localparam int TIMEOUT_CYCLES = 80;

localparam logic [ADDR_W-1:0] ACT_BASE_ADDR = 14'h0100;
localparam logic [ADDR_W-1:0] WGT_BASE_ADDR = 14'h0200;

logic clk;
logic rst;
logic clear;
logic start;
logic en;

logic [ADDR_W-1:0] act_base_addr;
logic [ADDR_W-1:0] wgt_base_addr;

logic bram_act_en;
logic [ADDR_W-1:0] bram_act_addr;
logic [WORD_W-1:0] bram_act_rdata;

logic bram_wgt_en;
logic [ADDR_W-1:0] bram_wgt_addr;
logic [WORD_W-1:0] bram_wgt_rdata;

logic raw_valid;
logic signed [DATA_W-1:0] raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec [0:N-1];
logic busy;
logic done;

logic [WORD_W-1:0] act_mem [0:MEM_DEPTH-1];
logic [WORD_W-1:0] wgt_mem [0:MEM_DEPTH-1];

bram_stream_reader_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) dut (
    .clk           (clk),
    .rst           (rst),
    .clear         (clear),
    .start         (start),
    .en            (en),
    .act_base_addr (act_base_addr),
    .wgt_base_addr (wgt_base_addr),
    .bram_act_en   (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata(bram_act_rdata),
    .bram_wgt_en   (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata(bram_wgt_rdata),
    .raw_valid     (raw_valid),
    .raw_act_vec   (raw_act_vec),
    .raw_wgt_vec   (raw_wgt_vec),
    .busy          (busy),
    .done          (done)
);

initial clk = 1'b0;
always #5 clk = ~clk;

// Mock synchronous BRAM: address/en are sampled on the clock edge, and rdata
// updates after that edge. If the BRAM enable is low, rdata holds its value.
always_ff @(posedge clk) begin
    if (rst) begin
        bram_act_rdata <= '0;
        bram_wgt_rdata <= '0;
    end
    else begin
        if (bram_act_en) begin
            bram_act_rdata <= act_mem[bram_act_addr[MEM_AW-1:0]];
        end
        if (bram_wgt_en) begin
            bram_wgt_rdata <= wgt_mem[bram_wgt_addr[MEM_AW-1:0]];
        end
    end
end

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

function automatic int signed expected_act_value(input int stream_idx, input int lane);
begin
    expected_act_value = ((stream_idx * 3 + lane * 2 + 1) % 9) - 4;
end
endfunction

function automatic int signed expected_wgt_value(input int stream_idx, input int lane);
begin
    expected_wgt_value = ((stream_idx * 5 + lane * 2 + 3) % 9) - 4;
end
endfunction

function automatic logic [WORD_W-1:0] pack_act_word(input int stream_idx);
    logic [WORD_W-1:0] packed_word;
begin
    packed_word = '0;
    for (int lane = 0; lane < N; lane++) begin
        packed_word[DATA_W*lane +: DATA_W] = to_data(expected_act_value(stream_idx, lane));
    end
    pack_act_word = packed_word;
end
endfunction

function automatic logic [WORD_W-1:0] pack_wgt_word(input int stream_idx);
    logic [WORD_W-1:0] packed_word;
begin
    packed_word = '0;
    for (int lane = 0; lane < N; lane++) begin
        packed_word[DATA_W*lane +: DATA_W] = to_data(expected_wgt_value(stream_idx, lane));
    end
    pack_wgt_word = packed_word;
end
endfunction

task automatic init_mock_mem();
begin
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        act_mem[idx] = '0;
        wgt_mem[idx] = '0;
    end

    for (int stream_idx = 0; stream_idx < N; stream_idx++) begin
        act_mem[(ACT_BASE_ADDR + stream_idx) & (MEM_DEPTH-1)] = pack_act_word(stream_idx);
        wgt_mem[(WGT_BASE_ADDR + stream_idx) & (MEM_DEPTH-1)] = pack_wgt_word(stream_idx);
    end
end
endtask

task automatic check_reset_state(input string label);
begin
    if (bram_act_en !== 1'b0) begin
        $display("%s: expected bram_act_en=0, got %0b", label, bram_act_en);
        $fatal(1);
    end
    if (bram_wgt_en !== 1'b0) begin
        $display("%s: expected bram_wgt_en=0, got %0b", label, bram_wgt_en);
        $fatal(1);
    end
    if (raw_valid !== 1'b0) begin
        $display("%s: expected raw_valid=0, got %0b", label, raw_valid);
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

task automatic check_addr(input int stream_idx);
    logic [ADDR_W-1:0] expected_act_addr;
    logic [ADDR_W-1:0] expected_wgt_addr;
begin
    expected_act_addr = ACT_BASE_ADDR + stream_idx;
    expected_wgt_addr = WGT_BASE_ADDR + stream_idx;

    if (bram_act_en !== 1'b1) begin
        $display("ADDR_CHECK stream %0d: expected bram_act_en=1, got %0b",
                 stream_idx, bram_act_en);
        $fatal(1);
    end
    if (bram_wgt_en !== 1'b1) begin
        $display("ADDR_CHECK stream %0d: expected bram_wgt_en=1, got %0b",
                 stream_idx, bram_wgt_en);
        $fatal(1);
    end
    if (bram_act_addr !== expected_act_addr) begin
        $display("ADDR_CHECK stream %0d: expected act_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_act_addr, bram_act_addr);
        $fatal(1);
    end
    if (bram_wgt_addr !== expected_wgt_addr) begin
        $display("ADDR_CHECK stream %0d: expected wgt_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_wgt_addr, bram_wgt_addr);
        $fatal(1);
    end
end
endtask

task automatic check_raw_output(input int stream_idx, input int cycle_idx);
    logic signed [DATA_W-1:0] expected_act;
    logic signed [DATA_W-1:0] expected_wgt;
begin
    for (int lane = 0; lane < N; lane++) begin
        expected_act = to_data(expected_act_value(stream_idx, lane));
        expected_wgt = to_data(expected_wgt_value(stream_idx, lane));

        if (raw_act_vec[lane] !== expected_act) begin
            $display("RAW_CHECK cycle %0d stream %0d lane %0d ACT mismatch: expected %0d, got %0d",
                     cycle_idx, stream_idx, lane, expected_act, raw_act_vec[lane]);
            $fatal(1);
        end
        if (raw_wgt_vec[lane] !== expected_wgt) begin
            $display("RAW_CHECK cycle %0d stream %0d lane %0d WGT mismatch: expected %0d, got %0d",
                     cycle_idx, stream_idx, lane, expected_wgt, raw_wgt_vec[lane]);
            $fatal(1);
        end
    end
end
endtask

task automatic apply_clear_check();
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b1;

    @(posedge clk);
    #1;
    check_reset_state("CLEAR_CHECK");

    @(negedge clk);
    clear = 1'b0;
end
endtask

task automatic start_with_en_hold_check();
begin
    @(negedge clk);
    start = 1'b1;
    en    = 1'b1;

    @(posedge clk);
    #1;
    check_addr(0);
    if (raw_valid !== 1'b0) begin
        $display("HOLD_CHECK: expected raw_valid=0 on first address issue, got %0b",
                 raw_valid);
        $fatal(1);
    end

    @(negedge clk);
    start = 1'b0;
    en    = 1'b0;

    repeat (2) begin
        @(posedge clk);
        #1;
        check_addr(0);
        if (raw_valid !== 1'b0) begin
            $display("HOLD_CHECK: expected raw_valid hold at 0 while en=0, got %0b",
                     raw_valid);
            $fatal(1);
        end
    end

    @(negedge clk);
    en = 1'b1;
end
endtask

task automatic run_reader_check();
    int addr_count;
    int valid_count;
    int cycle_count;
    bit done_seen;
begin
    addr_count  = 1;
    valid_count = 0;
    cycle_count = 0;
    done_seen   = 1'b0;

    while (!done_seen && (cycle_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        cycle_count = cycle_count + 1;

        if (bram_act_en || bram_wgt_en) begin
            if (addr_count >= N) begin
                $display("ADDR_CHECK: received extra address after stream %0d", N-1);
                $fatal(1);
            end
            check_addr(addr_count);
            addr_count = addr_count + 1;
        end

        if (raw_valid) begin
            if (valid_count >= N) begin
                $display("RAW_CHECK: received more than %0d valid outputs", N);
                $fatal(1);
            end
            check_raw_output(valid_count, cycle_count);
            valid_count = valid_count + 1;
        end

        if (done) begin
            done_seen = 1'b1;
            if (raw_valid !== 1'b0) begin
                $display("DONE_CHECK: expected raw_valid=0 when done=1, got %0b",
                         raw_valid);
                $fatal(1);
            end
            if (valid_count != N) begin
                $display("DONE_CHECK: done asserted after %0d valid outputs, expected %0d",
                         valid_count, N);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("DONE_CHECK: timeout waiting for done");
        $fatal(1);
    end
    if (addr_count != N) begin
        $display("ADDR_CHECK: expected %0d addresses, got %0d", N, addr_count);
        $fatal(1);
    end
    if (valid_count != N) begin
        $display("RAW_CHECK: expected %0d raw_valid outputs, got %0d", N, valid_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
        $display("DONE_CHECK: expected done pulse to clear, got %0b", done);
        $fatal(1);
    end
    if (raw_valid !== 1'b0) begin
        $display("RAW_CHECK: expected raw_valid=0 after done, got %0b", raw_valid);
        $fatal(1);
    end
end
endtask

initial begin
    rst           = 1'b1;
    clear         = 1'b0;
    start         = 1'b0;
    en            = 1'b0;
    act_base_addr = ACT_BASE_ADDR;
    wgt_base_addr = WGT_BASE_ADDR;
    init_mock_mem();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    apply_clear_check();
    start_with_en_hold_check();
    run_reader_check();

    $display("BRAM_STREAM_READER_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

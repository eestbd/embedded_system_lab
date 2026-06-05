`timescale 1ns / 1ps

module bram_reader_tile_writer_tb;

localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int ACC_W          = 32;
localparam int WORD_W         = 128;
localparam int ADDR_W         = 14;
localparam int SCALE_W        = 32;
localparam int SCALE_FRAC     = 24;
localparam int PRODUCT_W      = ACC_W + SCALE_W;
localparam int INPUT_CYCLES   = 16;
localparam int FLUSH_CYCLES   = 30;
localparam int STREAM_CYCLES  = INPUT_CYCLES + FLUSH_CYCLES;
localparam int MEM_AW         = 12;
localparam int MEM_DEPTH      = 1 << MEM_AW;
localparam int TIMEOUT_CYCLES = 260;

localparam logic [ADDR_W-1:0] ACT_BASE_ADDR = 14'h0100;
localparam logic [ADDR_W-1:0] WGT_BASE_ADDR = 14'h0200;
localparam logic [ADDR_W-1:0] OUT_BASE_ADDR = 14'h0300;
localparam logic [SCALE_W-1:0] SCALE_M4 = 32'd16777216;

logic clk;
logic rst;
logic clear;
logic en;

logic reader_start;
logic reader_raw_valid;
logic reader_done;
logic reader_busy;

logic [ADDR_W-1:0] act_base_addr;
logic [ADDR_W-1:0] wgt_base_addr;
logic bram_act_en;
logic [ADDR_W-1:0] bram_act_addr;
logic [WORD_W-1:0] bram_act_rdata;
logic bram_wgt_en;
logic [ADDR_W-1:0] bram_wgt_addr;
logic [WORD_W-1:0] bram_wgt_rdata;

logic signed [DATA_W-1:0] reader_raw_act_vec [0:N-1];
logic signed [DATA_W-1:0] reader_raw_wgt_vec [0:N-1];
logic signed [DATA_W-1:0] raw_act_vec        [0:N-1];
logic signed [DATA_W-1:0] raw_wgt_vec        [0:N-1];

logic tile_start;
logic tile_input_active;
logic tile_drain_active;
logic tile_busy;
logic tile_done;
logic tile_out_valid;
logic [$clog2(N)-1:0] tile_out_row_idx;
logic signed [DATA_W-1:0] tile_out_vec [0:N-1];

logic writer_start;
logic writer_busy;
logic writer_done;
logic writer_bram_wr;
logic [ADDR_W-1:0] writer_bram_addr;
logic [WORD_W-1:0] writer_bram_wdata;

logic [WORD_W-1:0] act_mem [0:MEM_DEPTH-1];
logic [WORD_W-1:0] wgt_mem [0:MEM_DEPTH-1];
logic [WORD_W-1:0] out_mem [0:MEM_DEPTH-1];

logic signed [DATA_W-1:0] A [0:N-1][0:N-1];
logic signed [DATA_W-1:0] B [0:N-1][0:N-1];
logic signed [DATA_W-1:0] act_stream_buf [0:N-1][0:N-1];
logic signed [DATA_W-1:0] wgt_stream_buf [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  golden_C [0:N-1][0:N-1];
logic signed [DATA_W-1:0] golden_out [0:N-1][0:N-1];
logic [WORD_W-1:0] expected_out_word [0:N-1];

bram_stream_reader_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) dut_reader (
    .clk           (clk),
    .rst           (rst),
    .clear         (clear),
    .start         (reader_start),
    .en            (en),
    .act_base_addr (act_base_addr),
    .wgt_base_addr (wgt_base_addr),
    .bram_act_en   (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata(bram_act_rdata),
    .bram_wgt_en   (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata(bram_wgt_rdata),
    .raw_valid     (reader_raw_valid),
    .raw_act_vec   (reader_raw_act_vec),
    .raw_wgt_vec   (reader_raw_wgt_vec),
    .busy          (reader_busy),
    .done          (reader_done)
);

tile_datapath_16x16 #(
    .N           (N),
    .DATA_W      (DATA_W),
    .ACC_W       (ACC_W),
    .SCALE_W     (SCALE_W),
    .SCALE_FRAC  (SCALE_FRAC),
    .INPUT_CYCLES(INPUT_CYCLES),
    .FLUSH_CYCLES(FLUSH_CYCLES),
    .CLEAR_CYCLES(N)
) dut_tile (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .start        (tile_start),
    .en           (en),
    .raw_act_vec  (raw_act_vec),
    .raw_wgt_vec  (raw_wgt_vec),
    .scale_q      (SCALE_M4),
    .input_active (tile_input_active),
    .drain_active (tile_drain_active),
    .busy         (tile_busy),
    .done         (tile_done),
    .out_valid    (tile_out_valid),
    .out_vec      (tile_out_vec),
    .out_row_idx  (tile_out_row_idx)
);

bram_output_writer_16x16 #(
    .N     (N),
    .DATA_W(DATA_W),
    .WORD_W(WORD_W),
    .ADDR_W(ADDR_W)
) dut_writer (
    .clk          (clk),
    .rst          (rst),
    .clear        (clear),
    .en           (en),
    .start        (writer_start),
    .out_base_addr(OUT_BASE_ADDR),
    .in_valid     (tile_out_valid),
    .in_row_idx   (tile_out_row_idx),
    .in_vec       (tile_out_vec),
    .bram_wr      (writer_bram_wr),
    .bram_addr    (writer_bram_addr),
    .bram_wdata   (writer_bram_wdata),
    .busy         (writer_busy),
    .done         (writer_done)
);

initial clk = 1'b0;
always #5 clk = ~clk;

// Mock synchronous input BRAMs.
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

// Mock output BRAM write port.
always_ff @(posedge clk) begin
    if (writer_bram_wr) begin
        out_mem[writer_bram_addr[MEM_AW-1:0]] <= writer_bram_wdata;
    end
end

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

task automatic drive_zero_tile_inputs();
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
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < N; col++) begin
            a_val = ((row * 3 + col * 2 + 1) % 9) - 4;
            b_val = ((row * 5 + col * 2 + 3) % 9) - 4;
            A[row][col] = to_data(a_val);
            B[row][col] = to_data(b_val);
        end
    end

    // Waveform landmarks: positive, negative, zero, and saturation after ReLU.
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

task automatic init_mock_memories();
    logic [WORD_W-1:0] act_word;
    logic [WORD_W-1:0] wgt_word;
begin
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        act_mem[idx] = '0;
        wgt_mem[idx] = '0;
        out_mem[idx] = '0;
    end

    for (int t = 0; t < N; t++) begin
        act_word = '0;
        wgt_word = '0;
        for (int lane = 0; lane < N; lane++) begin
            act_word[DATA_W*lane +: DATA_W] = A[lane][t];
            wgt_word[DATA_W*lane +: DATA_W] = B[t][lane];
        end
        act_mem[ACT_BASE_ADDR + t] = act_word;
        wgt_mem[WGT_BASE_ADDR + t] = wgt_word;
    end
end
endtask

task automatic clear_stream_buffers();
begin
    for (int t = 0; t < N; t++) begin
        expected_out_word[t] = '0;
        for (int lane = 0; lane < N; lane++) begin
            act_stream_buf[t][lane] = '0;
            wgt_stream_buf[t][lane] = '0;
        end
    end
end
endtask

task automatic compute_golden();
begin
    for (int row = 0; row < N; row++) begin
        expected_out_word[row] = '0;
        for (int col = 0; col < N; col++) begin
            golden_C[row][col] = '0;
            for (int k = 0; k < N; k++) begin
                golden_C[row][col] = golden_C[row][col] + mul_i8_to_i32(A[row][k], B[k][col]);
            end

            golden_out[row][col] = golden_post_lane(golden_C[row][col], SCALE_M4);
            expected_out_word[row][DATA_W*col +: DATA_W] = golden_out[row][col];
        end
    end
end
endtask

task automatic check_reader_addr(input int stream_idx);
    logic [ADDR_W-1:0] expected_act_addr;
    logic [ADDR_W-1:0] expected_wgt_addr;
begin
    expected_act_addr = ACT_BASE_ADDR + stream_idx;
    expected_wgt_addr = WGT_BASE_ADDR + stream_idx;

    if (bram_act_en !== 1'b1) begin
        $display("READER_CHECK addr stream %0d: expected bram_act_en=1, got %0b",
                 stream_idx, bram_act_en);
        $fatal(1);
    end
    if (bram_wgt_en !== 1'b1) begin
        $display("READER_CHECK addr stream %0d: expected bram_wgt_en=1, got %0b",
                 stream_idx, bram_wgt_en);
        $fatal(1);
    end
    if (bram_act_addr !== expected_act_addr) begin
        $display("READER_CHECK addr stream %0d: expected act_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_act_addr, bram_act_addr);
        $fatal(1);
    end
    if (bram_wgt_addr !== expected_wgt_addr) begin
        $display("READER_CHECK addr stream %0d: expected wgt_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_wgt_addr, bram_wgt_addr);
        $fatal(1);
    end
end
endtask

task automatic check_reader_data(input int stream_idx, input int reader_valid_count);
    logic signed [DATA_W-1:0] expected_act;
    logic signed [DATA_W-1:0] expected_wgt;
begin
    for (int lane = 0; lane < N; lane++) begin
        expected_act = A[lane][stream_idx];
        expected_wgt = B[stream_idx][lane];

        if (reader_raw_act_vec[lane] !== expected_act) begin
            $display("READER_CHECK data count %0d stream %0d lane %0d ACT expected=%0d got=%0d",
                     reader_valid_count, stream_idx, lane, expected_act, reader_raw_act_vec[lane]);
            $fatal(1);
        end
        if (reader_raw_wgt_vec[lane] !== expected_wgt) begin
            $display("READER_CHECK data count %0d stream %0d lane %0d WGT expected=%0d got=%0d",
                     reader_valid_count, stream_idx, lane, expected_wgt, reader_raw_wgt_vec[lane]);
            $fatal(1);
        end

        act_stream_buf[stream_idx][lane] = reader_raw_act_vec[lane];
        wgt_stream_buf[stream_idx][lane] = reader_raw_wgt_vec[lane];
    end
end
endtask

task automatic run_reader_capture();
    int addr_count;
    int valid_count;
    int timeout_count;
    bit reader_done_seen;
begin
    addr_count       = 1;
    valid_count      = 0;
    timeout_count    = 0;
    reader_done_seen = 1'b0;

    @(negedge clk);
    reader_start = 1'b1;

    @(posedge clk);
    #1;
    check_reader_addr(0);
    if (reader_raw_valid !== 1'b0) begin
        $display("READER_CHECK: expected raw_valid=0 on first address issue, got %0b",
                 reader_raw_valid);
        $fatal(1);
    end

    @(negedge clk);
    reader_start = 1'b0;

    while (!reader_done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (bram_act_en || bram_wgt_en) begin
            if (addr_count >= N) begin
                $display("READER_CHECK: extra address issue after %0d addresses", N);
                $fatal(1);
            end
            check_reader_addr(addr_count);
            addr_count = addr_count + 1;
        end

        if (reader_raw_valid) begin
            if (valid_count >= N) begin
                $display("READER_CHECK: extra raw_valid after %0d valid vectors", N);
                $fatal(1);
            end
            check_reader_data(valid_count, valid_count);
            valid_count = valid_count + 1;
        end

        if (reader_done) begin
            reader_done_seen = 1'b1;
            if (reader_raw_valid !== 1'b0) begin
                $display("READER_CHECK: expected raw_valid=0 when reader_done=1, got %0b",
                         reader_raw_valid);
                $fatal(1);
            end
        end
    end

    if (!reader_done_seen) begin
        $display("READER_CHECK: timeout waiting for reader_done");
        $fatal(1);
    end
    if (addr_count != N) begin
        $display("READER_CHECK: expected %0d addresses, got %0d", N, addr_count);
        $fatal(1);
    end
    if (valid_count != N) begin
        $display("READER_CHECK: expected %0d valid vectors, got %0d", N, valid_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (reader_done !== 1'b0) begin
        $display("READER_CHECK: expected reader_done pulse to clear, got %0b", reader_done);
        $fatal(1);
    end
end
endtask

task automatic pulse_writer_start();
begin
    @(negedge clk);
    writer_start = 1'b1;

    @(posedge clk);
    #1;
    if (writer_busy !== 1'b1) begin
        $display("WRITER_CHECK: expected writer_busy=1 after writer_start, got %0b",
                 writer_busy);
        $fatal(1);
    end

    @(negedge clk);
    writer_start = 1'b0;
end
endtask

task automatic pulse_tile_start();
begin
    @(negedge clk);
    tile_start = 1'b1;

    @(negedge clk);
    tile_start = 1'b0;
end
endtask

task automatic drive_buffered_tile_cycle(input int stream_idx);
begin
    for (int lane = 0; lane < N; lane++) begin
        if (stream_idx < INPUT_CYCLES) begin
            raw_act_vec[lane] = act_stream_buf[stream_idx][lane];
            raw_wgt_vec[lane] = wgt_stream_buf[stream_idx][lane];
        end
        else begin
            raw_act_vec[lane] = '0;
            raw_wgt_vec[lane] = '0;
        end
    end
end
endtask

task automatic run_tile_input_stream();
begin
    pulse_tile_start();
    wait (tile_input_active === 1'b1);

    for (int t = 0; t < STREAM_CYCLES; t++) begin
        @(negedge clk);
        if (tile_input_active !== 1'b1) begin
            $display("TILE_OUTPUT_CHECK input stream %0d: expected tile_input_active=1, got %0b",
                     t, tile_input_active);
            $fatal(1);
        end
        drive_buffered_tile_cycle(t);

        @(posedge clk);
        #1;
    end

    drive_zero_tile_inputs();
end
endtask

task automatic check_tile_output_row(input int expected_row, input int tile_out_count);
    logic [$clog2(N)-1:0] expected_idx;
begin
    expected_idx = expected_row;

    if (tile_out_row_idx !== expected_idx) begin
        $display("TILE_OUTPUT_CHECK count %0d: expected row_idx=%0d, got %0d",
                 tile_out_count, expected_row, tile_out_row_idx);
        $fatal(1);
    end

    for (int col = 0; col < N; col++) begin
        if (tile_out_vec[col] !== golden_out[expected_row][col]) begin
            $display("TILE_OUTPUT_CHECK row %0d col %0d count %0d: golden_C=%0d expected=%0d got=%0d",
                     expected_row, col, tile_out_count, golden_C[expected_row][col],
                     golden_out[expected_row][col], tile_out_vec[col]);
            $fatal(1);
        end
    end
end
endtask

task automatic check_writer_write(input int expected_row, input int writer_count);
    logic [ADDR_W-1:0] expected_addr;
begin
    expected_addr = OUT_BASE_ADDR + expected_row;

    if (writer_bram_addr !== expected_addr) begin
        $display("WRITER_CHECK count %0d row %0d: expected addr=0x%0h, got 0x%0h",
                 writer_count, expected_row, expected_addr, writer_bram_addr);
        $fatal(1);
    end
    if (writer_bram_wdata !== expected_out_word[expected_row]) begin
        $display("WRITER_CHECK count %0d row %0d: expected word 0x%032h, got 0x%032h",
                 writer_count, expected_row, expected_out_word[expected_row], writer_bram_wdata);
        for (int lane = 0; lane < N; lane++) begin
            $display("  lane %0d expected=%0d got=%0d",
                     lane, golden_out[expected_row][lane],
                     $signed(writer_bram_wdata[DATA_W*lane +: DATA_W]));
        end
        $fatal(1);
    end
end
endtask

task automatic wait_for_tile_writer_completion();
    int tile_out_count;
    int writer_count;
    int timeout_count;
    bit tile_done_seen;
    bit writer_done_seen;
begin
    tile_out_count   = 0;
    writer_count     = 0;
    timeout_count    = 0;
    tile_done_seen   = 1'b0;
    writer_done_seen = 1'b0;

    while (!writer_done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (tile_out_valid) begin
            if (tile_out_count >= N) begin
                $display("TILE_OUTPUT_CHECK: extra out_valid after %0d output rows", N);
                $fatal(1);
            end
            check_tile_output_row(tile_out_count, tile_out_count);
            tile_out_count = tile_out_count + 1;
        end

        if (writer_bram_wr) begin
            if (writer_count >= N) begin
                $display("WRITER_CHECK: extra bram_wr after %0d writes", N);
                $fatal(1);
            end
            check_writer_write(writer_count, writer_count);
            writer_count = writer_count + 1;
        end

        if (tile_done) begin
            tile_done_seen = 1'b1;
            if (tile_out_valid !== 1'b0) begin
                $display("TILE_OUTPUT_CHECK: expected tile_out_valid=0 when tile_done=1, got %0b",
                         tile_out_valid);
                $fatal(1);
            end
            if (tile_out_count != N) begin
                $display("TILE_OUTPUT_CHECK: tile_done after %0d outputs, expected %0d",
                         tile_out_count, N);
                $fatal(1);
            end
        end

        if (writer_done) begin
            writer_done_seen = 1'b1;
            if (!tile_done_seen) begin
                $display("WRITER_CHECK: writer_done asserted before tile_done");
                $fatal(1);
            end
            if (writer_count != N) begin
                $display("WRITER_CHECK: writer_done after %0d writes, expected %0d",
                         writer_count, N);
                $fatal(1);
            end
        end
    end

    if (!writer_done_seen) begin
        $display("WRITER_CHECK: timeout waiting for writer_done");
        $fatal(1);
    end
    if (!tile_done_seen) begin
        $display("TILE_OUTPUT_CHECK: writer_done seen but tile_done was never seen");
        $fatal(1);
    end
    if (tile_out_count != N) begin
        $display("TILE_OUTPUT_CHECK: expected %0d output rows, got %0d", N, tile_out_count);
        $fatal(1);
    end
    if (writer_count != N) begin
        $display("WRITER_CHECK: expected %0d writes, got %0d", N, writer_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (writer_done !== 1'b0) begin
        $display("WRITER_CHECK: expected writer_done pulse to clear, got %0b", writer_done);
        $fatal(1);
    end
end
endtask

task automatic check_output_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int row = 0; row < N; row++) begin
        got_word = out_mem[(OUT_BASE_ADDR + row) & (MEM_DEPTH-1)];
        if (got_word !== expected_out_word[row]) begin
            $display("MEMORY_CHECK row %0d: expected word 0x%032h, got 0x%032h",
                     row, expected_out_word[row], got_word);
            for (int lane = 0; lane < N; lane++) begin
                $display("  lane %0d expected=%0d got=%0d",
                         lane, golden_out[row][lane],
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
    reader_start  = 1'b0;
    tile_start    = 1'b0;
    writer_start  = 1'b0;
    act_base_addr = ACT_BASE_ADDR;
    wgt_base_addr = WGT_BASE_ADDR;
    drive_zero_tile_inputs();
    clear_stream_buffers();
    init_matrices();
    init_mock_memories();
    compute_golden();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    @(negedge clk);
    clear = 1'b1;
    @(negedge clk);
    clear = 1'b0;

    run_reader_capture();
    pulse_writer_start();
    run_tile_input_stream();
    wait_for_tile_writer_completion();
    check_output_memory();

    $display("BRAM_READER_TILE_WRITER test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

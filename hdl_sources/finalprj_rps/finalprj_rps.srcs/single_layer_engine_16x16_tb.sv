`timescale 1ns / 1ps

module single_layer_engine_16x16_tb;

localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int ACC_W          = 32;
localparam int WORD_W         = 128;
localparam int ADDR_W         = 14;
localparam int SCALE_W        = 32;
localparam int SCALE_FRAC     = 24;
localparam int PRODUCT_W      = ACC_W + SCALE_W;
localparam int K_TILES_W      = 8;
localparam int OUT_TILES_W    = 8;
localparam int NUM_K_TILES    = 3;
localparam int NUM_OUT_TILES  = 4;
localparam int TOTAL_K        = N * NUM_K_TILES;
localparam int OUT_DIM        = N * NUM_OUT_TILES;
localparam int TOTAL_READS    = TOTAL_K * NUM_OUT_TILES;
localparam int TOTAL_WRITES   = N * NUM_OUT_TILES;
localparam int MEM_AW         = 12;
localparam int MEM_DEPTH      = 1 << MEM_AW;
localparam int TIMEOUT_CYCLES = 3200;

localparam logic [K_TILES_W-1:0] NUM_K_TILES_CFG = 8'd3;
localparam logic [OUT_TILES_W-1:0] NUM_OUT_TILES_CFG = 8'd4;
localparam logic [ADDR_W-1:0] ACT_BASE_ADDR = 14'h0100;
localparam logic [ADDR_W-1:0] WGT_BASE_ADDR = 14'h0200;
localparam logic [ADDR_W-1:0] OUT_BASE_ADDR = 14'h0800;
localparam logic [ADDR_W-1:0] K_STRIDE = 14'd16;
localparam logic [ADDR_W-1:0] WGT_OUT_STRIDE = NUM_K_TILES * N;
localparam logic [ADDR_W-1:0] OUT_TILE_STRIDE = 14'd16;
localparam logic [SCALE_W-1:0] SCALE_M4 = 32'd16777216;

logic clk;
logic rst;
logic clear;
logic start;
logic en;

logic [ADDR_W-1:0] act_base_addr;
logic [ADDR_W-1:0] wgt_base_addr;
logic [ADDR_W-1:0] out_base_addr;
logic [ADDR_W-1:0] act_k_stride;
logic [ADDR_W-1:0] wgt_k_stride;
logic [ADDR_W-1:0] wgt_out_stride;
logic [ADDR_W-1:0] out_tile_stride;
logic [K_TILES_W-1:0] num_k_tiles;
logic [OUT_TILES_W-1:0] num_out_tiles;
logic [SCALE_W-1:0] scale_q;

logic bram_act_en;
logic [ADDR_W-1:0] bram_act_addr;
logic [WORD_W-1:0] bram_act_rdata;
logic bram_wgt_en;
logic [ADDR_W-1:0] bram_wgt_addr;
logic [WORD_W-1:0] bram_wgt_rdata;
logic bram_out_wr;
logic [ADDR_W-1:0] bram_out_addr;
logic [WORD_W-1:0] bram_out_wdata;
logic busy;
logic done;

logic [WORD_W-1:0] act_mem [0:MEM_DEPTH-1];
logic [WORD_W-1:0] wgt_mem [0:MEM_DEPTH-1];
logic [WORD_W-1:0] out_mem [0:MEM_DEPTH-1];

logic signed [DATA_W-1:0] A_full [0:N-1][0:TOTAL_K-1];
logic signed [DATA_W-1:0] B_full [0:TOTAL_K-1][0:OUT_DIM-1];
logic signed [ACC_W-1:0]  golden_C [0:N-1][0:OUT_DIM-1];
logic signed [DATA_W-1:0] golden_out [0:N-1][0:OUT_DIM-1];
logic [WORD_W-1:0] expected_out_word [0:NUM_OUT_TILES-1][0:N-1];

wire [OUT_TILES_W-1:0] out_tile_idx;

single_layer_engine_16x16 #(
    .N          (N),
    .DATA_W     (DATA_W),
    .ACC_W      (ACC_W),
    .WORD_W     (WORD_W),
    .ADDR_W     (ADDR_W),
    .SCALE_W    (SCALE_W),
    .SCALE_FRAC (SCALE_FRAC),
    .K_TILES_W  (K_TILES_W),
    .OUT_TILES_W(OUT_TILES_W)
) dut (
    .clk           (clk),
    .rst           (rst),
    .clear         (clear),
    .start         (start),
    .en            (en),
    .act_base_addr (act_base_addr),
    .wgt_base_addr (wgt_base_addr),
    .out_base_addr (out_base_addr),
    .act_k_stride  (act_k_stride),
    .wgt_k_stride  (wgt_k_stride),
    .wgt_out_stride(wgt_out_stride),
    .out_tile_stride(out_tile_stride),
    .num_k_tiles   (num_k_tiles),
    .num_out_tiles (num_out_tiles),
    .scale_q       (scale_q),
    .bram_act_en   (bram_act_en),
    .bram_act_addr (bram_act_addr),
    .bram_act_rdata(bram_act_rdata),
    .bram_wgt_en   (bram_wgt_en),
    .bram_wgt_addr (bram_wgt_addr),
    .bram_wgt_rdata(bram_wgt_rdata),
    .bram_out_wr   (bram_out_wr),
    .bram_out_addr (bram_out_addr),
    .bram_out_wdata(bram_out_wdata),
    .busy          (busy),
    .done          (done)
);

assign out_tile_idx = dut.out_tile_idx;

initial clk = 1'b0;
always #5 clk = ~clk;

// Mock synchronous input BRAMs with one-cycle read latency.
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

// Mock synchronous output BRAM write port.
always_ff @(posedge clk) begin
    if (bram_out_wr) begin
        out_mem[bram_out_addr[MEM_AW-1:0]] <= bram_out_wdata;
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

task automatic init_full_matrices();
    int signed a_val;
    int signed b_val;
begin
    for (int row = 0; row < N; row++) begin
        for (int k = 0; k < TOTAL_K; k++) begin
            a_val = ((row * 5 + k * 3 + 2) % 9) - 4;
            A_full[row][k] = to_data(a_val);
        end
    end

    for (int k = 0; k < TOTAL_K; k++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            b_val = ((k * 7 + col * 2 + 1) % 9) - 4;
            B_full[k][col] = to_data(b_val);
        end
    end

    // Repeat visible positive, ReLU-zero, and zero-output landmarks per output tile.
    for (int k = 0; k < TOTAL_K; k++) begin
        A_full[0][k] = 8'sd4;
        A_full[1][k] = -8'sd4;
        A_full[2][k] = 8'sd0;
        for (int ot = 0; ot < NUM_OUT_TILES; ot++) begin
            B_full[k][ot*N + 0] = 8'sd4;
            B_full[k][ot*N + 1] = 8'sd4;
            B_full[k][ot*N + 2] = 8'sd0;
        end
    end
end
endtask

task automatic init_mock_memories();
    logic [WORD_W-1:0] act_word;
    logic [WORD_W-1:0] wgt_word;
    int full_k;
begin
    for (int idx = 0; idx < MEM_DEPTH; idx++) begin
        act_mem[idx] = '0;
        wgt_mem[idx] = '0;
        out_mem[idx] = '0;
    end

    // Activation is shared across every output column tile.
    for (int kt = 0; kt < NUM_K_TILES; kt++) begin
        for (int t = 0; t < N; t++) begin
            full_k = kt * N + t;
            act_word = '0;
            for (int lane = 0; lane < N; lane++) begin
                act_word[DATA_W*lane +: DATA_W] = A_full[lane][full_k];
            end
            act_mem[ACT_BASE_ADDR + kt * N + t] = act_word;
        end
    end

    // Weight layout: output tile major, then K tile, then 16 stream words.
    for (int ot = 0; ot < NUM_OUT_TILES; ot++) begin
        for (int kt = 0; kt < NUM_K_TILES; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                wgt_word = '0;
                for (int lane = 0; lane < N; lane++) begin
                    wgt_word[DATA_W*lane +: DATA_W] = B_full[full_k][ot*N + lane];
                end
                wgt_mem[WGT_BASE_ADDR + ot * (NUM_K_TILES * N) + kt * N + t] = wgt_word;
            end
        end
    end
end
endtask

task automatic compute_golden();
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            golden_C[row][col] = '0;
            for (int k = 0; k < TOTAL_K; k++) begin
                golden_C[row][col] = golden_C[row][col] + mul_i8_to_i32(A_full[row][k], B_full[k][col]);
            end
            golden_out[row][col] = golden_post_lane(golden_C[row][col], SCALE_M4);
        end
    end

    for (int ot = 0; ot < NUM_OUT_TILES; ot++) begin
        for (int row = 0; row < N; row++) begin
            expected_out_word[ot][row] = '0;
            for (int lane = 0; lane < N; lane++) begin
                expected_out_word[ot][row][DATA_W*lane +: DATA_W] =
                    golden_out[row][ot*N + lane];
            end
        end
    end
end
endtask

task automatic check_read_addr(input int read_count);
    int expected_ot;
    int read_in_tile;
    int expected_kt;
    int expected_t;
    logic [ADDR_W-1:0] expected_act_addr;
    logic [ADDR_W-1:0] expected_wgt_addr;
begin
    expected_ot = read_count / TOTAL_K;
    read_in_tile = read_count % TOTAL_K;
    expected_kt = read_in_tile / N;
    expected_t = read_in_tile % N;

    expected_act_addr = ACT_BASE_ADDR + expected_kt * N + expected_t;
    expected_wgt_addr = WGT_BASE_ADDR + expected_ot * (NUM_K_TILES * N) +
                        expected_kt * N + expected_t;

    if (bram_act_en !== 1'b1) begin
        $display("READ_ADDR_CHECK ot %0d kt %0d t %0d: expected bram_act_en=1, got %0b",
                 expected_ot, expected_kt, expected_t, bram_act_en);
        $fatal(1);
    end
    if (bram_wgt_en !== 1'b1) begin
        $display("READ_ADDR_CHECK ot %0d kt %0d t %0d: expected bram_wgt_en=1, got %0b",
                 expected_ot, expected_kt, expected_t, bram_wgt_en);
        $fatal(1);
    end
    if (bram_act_addr !== expected_act_addr) begin
        $display("READ_ADDR_CHECK ot %0d kt %0d t %0d: expected act_addr=0x%0h, got 0x%0h",
                 expected_ot, expected_kt, expected_t, expected_act_addr, bram_act_addr);
        $fatal(1);
    end
    if (bram_wgt_addr !== expected_wgt_addr) begin
        $display("READ_ADDR_CHECK ot %0d kt %0d t %0d: expected wgt_addr=0x%0h, got 0x%0h",
                 expected_ot, expected_kt, expected_t, expected_wgt_addr, bram_wgt_addr);
        $fatal(1);
    end
end
endtask

task automatic check_write(input int write_count);
    int expected_ot;
    int expected_row;
    logic [ADDR_W-1:0] expected_addr;
begin
    expected_ot = write_count / N;
    expected_row = write_count % N;
    expected_addr = OUT_BASE_ADDR + expected_ot * N + expected_row;

    if (bram_out_addr !== expected_addr) begin
        $display("WRITE_CHECK ot %0d row %0d: expected addr=0x%0h, got 0x%0h",
                 expected_ot, expected_row, expected_addr, bram_out_addr);
        $fatal(1);
    end

    if (bram_out_wdata !== expected_out_word[expected_ot][expected_row]) begin
        $display("WRITE_CHECK ot %0d row %0d: expected word 0x%032h, got 0x%032h",
                 expected_ot, expected_row,
                 expected_out_word[expected_ot][expected_row], bram_out_wdata);
        for (int lane = 0; lane < N; lane++) begin
            $display("  lane %0d col %0d golden_C=%0d expected=%0d got=%0d",
                     lane, expected_ot*N + lane,
                     golden_C[expected_row][expected_ot*N + lane],
                     golden_out[expected_row][expected_ot*N + lane],
                     $signed(bram_out_wdata[DATA_W*lane +: DATA_W]));
        end
        $fatal(1);
    end
end
endtask

task automatic check_output_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int ot = 0; ot < NUM_OUT_TILES; ot++) begin
        for (int row = 0; row < N; row++) begin
            got_word = out_mem[(OUT_BASE_ADDR + ot * N + row) & (MEM_DEPTH-1)];

            if (got_word !== expected_out_word[ot][row]) begin
                $display("MEMORY_CHECK ot %0d row %0d: expected word 0x%032h, got 0x%032h",
                         ot, row, expected_out_word[ot][row], got_word);
                for (int lane = 0; lane < N; lane++) begin
                    $display("  lane %0d col %0d golden_C=%0d expected=%0d got=%0d",
                             lane, ot*N + lane,
                             golden_C[row][ot*N + lane],
                             golden_out[row][ot*N + lane],
                             $signed(got_word[DATA_W*lane +: DATA_W]));
                end
                $fatal(1);
            end
        end
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

task automatic run_layer_check();
    int read_count;
    int write_count;
    int timeout_count;
    bit done_seen;
begin
    read_count = 0;
    write_count = 0;
    timeout_count = 0;
    done_seen = 1'b0;

    pulse_start();

    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (bram_act_en || bram_wgt_en) begin
            if (read_count >= TOTAL_READS) begin
                $display("READ_ADDR_CHECK: extra read after %0d words", TOTAL_READS);
                $fatal(1);
            end
            check_read_addr(read_count);
            read_count = read_count + 1;
        end

        if (bram_out_wr) begin
            if (write_count >= TOTAL_WRITES) begin
                $display("WRITE_CHECK: extra write after %0d words", TOTAL_WRITES);
                $fatal(1);
            end
            check_write(write_count);
            write_count = write_count + 1;
        end

        if (done) begin
            done_seen = 1'b1;
            if (write_count != TOTAL_WRITES) begin
                $display("DONE_CHECK: done after %0d writes, expected %0d",
                         write_count, TOTAL_WRITES);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("SINGLE_LAYER_ENGINE: timeout waiting for done, out_tile_idx=%0d",
                 out_tile_idx);
        $fatal(1);
    end
    if (read_count != TOTAL_READS) begin
        $display("READ_ADDR_CHECK: expected %0d reads, got %0d",
                 TOTAL_READS, read_count);
        $fatal(1);
    end
    if (write_count != TOTAL_WRITES) begin
        $display("WRITE_CHECK: expected %0d writes, got %0d",
                 TOTAL_WRITES, write_count);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
        $display("DONE_CHECK: expected done pulse to clear, got %0b", done);
        $fatal(1);
    end
    if (busy !== 1'b0) begin
        $display("DONE_CHECK: expected busy=0 after returning to IDLE, got %0b", busy);
        $fatal(1);
    end
end
endtask

initial begin
    rst             = 1'b1;
    clear           = 1'b0;
    start           = 1'b0;
    en              = 1'b0;
    act_base_addr   = ACT_BASE_ADDR;
    wgt_base_addr   = WGT_BASE_ADDR;
    out_base_addr   = OUT_BASE_ADDR;
    act_k_stride    = K_STRIDE;
    wgt_k_stride    = K_STRIDE;
    wgt_out_stride  = WGT_OUT_STRIDE;
    out_tile_stride = OUT_TILE_STRIDE;
    num_k_tiles     = NUM_K_TILES_CFG;
    num_out_tiles   = NUM_OUT_TILES_CFG;
    scale_q         = SCALE_M4;

    init_full_matrices();
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

    run_layer_check();

    repeat (2) @(posedge clk);
    #1;
    check_output_memory();

    $display("SINGLE_LAYER_ENGINE_16x16 test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

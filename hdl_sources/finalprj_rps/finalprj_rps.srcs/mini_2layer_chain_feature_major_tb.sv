`timescale 1ns / 1ps

module mini_2layer_chain_feature_major_tb;

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

localparam int L1_K           = 48;
localparam int L1_OUT_DIM     = 64;
localparam int L2_K           = 64;
localparam int L2_OUT_DIM     = 32;
localparam int L1_K_TILES     = 3;
localparam int L1_OUT_TILES   = 4;
localparam int L2_K_TILES     = 4;
localparam int L2_OUT_TILES   = 2;

localparam int MEM_DEPTH      = 1 << ADDR_W;
localparam int TIMEOUT_CYCLES = 4200;

localparam logic [ADDR_W-1:0] L1_ACT_BASE = 14'h0100;
localparam logic [ADDR_W-1:0] L1_WGT_BASE = 14'h0200;
localparam logic [ADDR_W-1:0] L1_OUT_BASE = 14'h0800;
localparam logic [ADDR_W-1:0] L2_WGT_BASE = 14'h1000;
localparam logic [ADDR_W-1:0] L2_OUT_BASE = 14'h1800;

localparam logic [ADDR_W-1:0] K_STRIDE = 14'd16;
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

logic [WORD_W-1:0] mem [0:MEM_DEPTH-1];

logic signed [DATA_W-1:0] A0 [0:N-1][0:L1_K-1];
logic signed [DATA_W-1:0] W1 [0:L1_K-1][0:L1_OUT_DIM-1];
logic signed [DATA_W-1:0] W2 [0:L2_K-1][0:L2_OUT_DIM-1];

logic signed [ACC_W-1:0] Y1_int32 [0:N-1][0:L1_OUT_DIM-1];
logic signed [DATA_W-1:0] X1 [0:N-1][0:L1_OUT_DIM-1];
logic signed [ACC_W-1:0] Y2_int32 [0:N-1][0:L2_OUT_DIM-1];
logic signed [DATA_W-1:0] X2 [0:N-1][0:L2_OUT_DIM-1];

logic [WORD_W-1:0] expected_L1_word [0:L1_OUT_DIM-1];
logic [WORD_W-1:0] expected_L2_word [0:L2_OUT_DIM-1];

wire [OUT_TILES_W-1:0] out_tile_idx;

single_layer_engine_feature_major_16x16 #(
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
    .clk            (clk),
    .rst            (rst),
    .clear          (clear),
    .start          (start),
    .en             (en),
    .act_base_addr  (act_base_addr),
    .wgt_base_addr  (wgt_base_addr),
    .out_base_addr  (out_base_addr),
    .act_layout_row_major(1'b0),
    .act_k_stride   (act_k_stride),
    .wgt_k_stride   (wgt_k_stride),
    .wgt_out_stride (wgt_out_stride),
    .out_tile_stride(out_tile_stride),
    .num_k_tiles    (num_k_tiles),
    .num_out_tiles  (num_out_tiles),
    .scale_q        (scale_q),
    .bram_act_en    (bram_act_en),
    .bram_act_addr  (bram_act_addr),
    .bram_act_rdata (bram_act_rdata),
    .bram_wgt_en    (bram_wgt_en),
    .bram_wgt_addr  (bram_wgt_addr),
    .bram_wgt_rdata (bram_wgt_rdata),
    .bram_out_wr    (bram_out_wr),
    .bram_out_addr  (bram_out_addr),
    .bram_out_wdata (bram_out_wdata),
    .busy           (busy),
    .done           (done)
);

assign out_tile_idx = dut.out_tile_idx;

initial clk = 1'b0;
always #5 clk = ~clk;

// Unified mock BRAM with separate logical activation, weight, and output ports.
always_ff @(posedge clk) begin
    if (rst) begin
        bram_act_rdata <= '0;
        bram_wgt_rdata <= '0;
    end
    else begin
        if (bram_act_en) begin
            bram_act_rdata <= mem[bram_act_addr];
        end
        if (bram_wgt_en) begin
            bram_wgt_rdata <= mem[bram_wgt_addr];
        end
    end

    if (bram_out_wr) begin
        mem[bram_out_addr] <= bram_out_wdata;
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

task automatic init_matrices();
    int signed value;
begin
    for (int row = 0; row < N; row++) begin
        for (int k = 0; k < L1_K; k++) begin
            value = ((row * 5 + k * 3 + 2) % 9) - 4;
            A0[row][k] = to_data(value);
        end
    end

    for (int k = 0; k < L1_K; k++) begin
        for (int col = 0; col < L1_OUT_DIM; col++) begin
            value = ((k * 7 + col * 2 + 1) % 9) - 4;
            W1[k][col] = to_data(value);
        end
    end

    for (int k = 0; k < L2_K; k++) begin
        for (int col = 0; col < L2_OUT_DIM; col++) begin
            value = ((k * 5 + col * 3 + 4) % 9) - 4;
            W2[k][col] = to_data(value);
        end
    end

    // Deterministic landmarks that exercise saturation, ReLU zero, and zeros.
    for (int k = 0; k < L1_K; k++) begin
        A0[0][k] = 8'sd4;
        A0[1][k] = -8'sd4;
        A0[2][k] = 8'sd0;
        for (int col = 0; col < L1_OUT_DIM; col += N) begin
            W1[k][col + 0] = 8'sd4;
            W1[k][col + 1] = 8'sd4;
            W1[k][col + 2] = 8'sd0;
        end
    end

    for (int k = 0; k < L2_K; k++) begin
        for (int col = 0; col < L2_OUT_DIM; col += N) begin
            W2[k][col + 0] = 8'sd4;
            W2[k][col + 1] = -8'sd4;
            W2[k][col + 2] = 8'sd0;
        end
    end
end
endtask

task automatic compute_golden();
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < L1_OUT_DIM; col++) begin
            Y1_int32[row][col] = '0;
            for (int k = 0; k < L1_K; k++) begin
                Y1_int32[row][col] = Y1_int32[row][col] + mul_i8_to_i32(A0[row][k], W1[k][col]);
            end
            X1[row][col] = golden_post_lane(Y1_int32[row][col], SCALE_M4);
        end
    end

    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < L2_OUT_DIM; col++) begin
            Y2_int32[row][col] = '0;
            for (int k = 0; k < L2_K; k++) begin
                Y2_int32[row][col] = Y2_int32[row][col] + mul_i8_to_i32(X1[row][k], W2[k][col]);
            end
            X2[row][col] = golden_post_lane(Y2_int32[row][col], SCALE_M4);
        end
    end

    for (int feature = 0; feature < L1_OUT_DIM; feature++) begin
        expected_L1_word[feature] = '0;
        for (int row = 0; row < N; row++) begin
            expected_L1_word[feature][DATA_W*row +: DATA_W] = X1[row][feature];
        end
    end

    for (int feature = 0; feature < L2_OUT_DIM; feature++) begin
        expected_L2_word[feature] = '0;
        for (int row = 0; row < N; row++) begin
            expected_L2_word[feature][DATA_W*row +: DATA_W] = X2[row][feature];
        end
    end
end
endtask

task automatic init_mock_bram();
    logic [WORD_W-1:0] word;
    int full_k;
begin
    for (int addr = 0; addr < MEM_DEPTH; addr++) begin
        mem[addr] = '0;
    end

    for (int kt = 0; kt < L1_K_TILES; kt++) begin
        for (int t = 0; t < N; t++) begin
            full_k = kt * N + t;
            word = '0;
            for (int row = 0; row < N; row++) begin
                word[DATA_W*row +: DATA_W] = A0[row][full_k];
            end
            mem[L1_ACT_BASE + kt*N + t] = word;
        end
    end

    for (int ot = 0; ot < L1_OUT_TILES; ot++) begin
        for (int kt = 0; kt < L1_K_TILES; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                word = '0;
                for (int col = 0; col < N; col++) begin
                    word[DATA_W*col +: DATA_W] = W1[full_k][ot*N + col];
                end
                mem[L1_WGT_BASE + ot*(L1_K_TILES*N) + kt*N + t] = word;
            end
        end
    end

    for (int ot = 0; ot < L2_OUT_TILES; ot++) begin
        for (int kt = 0; kt < L2_K_TILES; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                word = '0;
                for (int col = 0; col < N; col++) begin
                    word[DATA_W*col +: DATA_W] = W2[full_k][ot*N + col];
                end
                mem[L2_WGT_BASE + ot*(L2_K_TILES*N) + kt*N + t] = word;
            end
        end
    end
end
endtask

task automatic configure_layer1();
begin
    act_base_addr   = L1_ACT_BASE;
    wgt_base_addr   = L1_WGT_BASE;
    out_base_addr   = L1_OUT_BASE;
    act_k_stride    = K_STRIDE;
    wgt_k_stride    = K_STRIDE;
    wgt_out_stride  = L1_K_TILES * N;
    out_tile_stride = OUT_TILE_STRIDE;
    num_k_tiles     = L1_K_TILES;
    num_out_tiles   = L1_OUT_TILES;
    scale_q         = SCALE_M4;
end
endtask

task automatic configure_layer2();
begin
    act_base_addr   = L1_OUT_BASE;
    wgt_base_addr   = L2_WGT_BASE;
    out_base_addr   = L2_OUT_BASE;
    act_k_stride    = K_STRIDE;
    wgt_k_stride    = K_STRIDE;
    wgt_out_stride  = L2_K_TILES * N;
    out_tile_stride = OUT_TILE_STRIDE;
    num_k_tiles     = L2_K_TILES;
    num_out_tiles   = L2_OUT_TILES;
    scale_q         = SCALE_M4;
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

task automatic check_write_word(
    input string stage,
    input int write_count
);
    logic [ADDR_W-1:0] expected_addr;
    logic [WORD_W-1:0] expected_word;
    int feature;
begin
    if (stage == "L1") begin
        expected_addr = L1_OUT_BASE + write_count;
        expected_word = expected_L1_word[write_count];
    end
    else begin
        expected_addr = L2_OUT_BASE + write_count;
        expected_word = expected_L2_word[write_count];
    end

    if (bram_out_addr !== expected_addr) begin
        $display("%s_WRITE_CHECK feature %0d: expected addr=0x%0h, got 0x%0h",
                 stage, write_count, expected_addr, bram_out_addr);
        $fatal(1);
    end

    if (bram_out_wdata !== expected_word) begin
        feature = write_count;
        $display("%s_WRITE_CHECK feature %0d: expected word 0x%032h, got 0x%032h",
                 stage, feature, expected_word, bram_out_wdata);
        for (int row = 0; row < N; row++) begin
            if (stage == "L1") begin
                $display("  row %0d expected=%0d got=%0d",
                         row, X1[row][feature],
                         $signed(bram_out_wdata[DATA_W*row +: DATA_W]));
            end
            else begin
                $display("  row %0d expected=%0d got=%0d",
                         row, X2[row][feature],
                         $signed(bram_out_wdata[DATA_W*row +: DATA_W]));
            end
        end
        $fatal(1);
    end
end
endtask

task automatic run_layer(
    input string stage,
    input int expected_writes
);
    int write_count;
    int timeout_count;
    bit done_seen;
begin
    write_count = 0;
    timeout_count = 0;
    done_seen = 1'b0;

    pulse_start();

    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (bram_out_wr) begin
            if (write_count >= expected_writes) begin
                $display("%s_WRITE_CHECK: extra write after %0d feature words",
                         stage, expected_writes);
                $fatal(1);
            end

            check_write_word(stage, write_count);
            write_count = write_count + 1;
        end

        if (done) begin
            done_seen = 1'b1;
            if (write_count != expected_writes) begin
                $display("%s_DONE_CHECK: done after %0d writes, expected %0d",
                         stage, write_count, expected_writes);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("%s_DONE_CHECK: timeout waiting for done, out_tile_idx=%0d",
                 stage, out_tile_idx);
        $fatal(1);
    end

    @(posedge clk);
    #1;
    if (done !== 1'b0) begin
        $display("%s_DONE_CHECK: expected done pulse to clear, got %0b",
                 stage, done);
        $fatal(1);
    end
end
endtask

task automatic check_l1_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int feature = 0; feature < L1_OUT_DIM; feature++) begin
        got_word = mem[L1_OUT_BASE + feature];

        if (got_word !== expected_L1_word[feature]) begin
            $display("L1_MEMORY_CHECK feature %0d: expected word 0x%032h, got 0x%032h",
                     feature, expected_L1_word[feature], got_word);
            for (int row = 0; row < N; row++) begin
                $display("  row %0d expected=%0d got=%0d",
                         row, X1[row][feature],
                         $signed(got_word[DATA_W*row +: DATA_W]));
            end
            $fatal(1);
        end
    end
end
endtask

task automatic check_l2_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int feature = 0; feature < L2_OUT_DIM; feature++) begin
        got_word = mem[L2_OUT_BASE + feature];

        if (got_word !== expected_L2_word[feature]) begin
            $display("L2_MEMORY_CHECK feature %0d: expected word 0x%032h, got 0x%032h",
                     feature, expected_L2_word[feature], got_word);
            for (int row = 0; row < N; row++) begin
                $display("  row %0d expected=%0d got=%0d",
                         row, X2[row][feature],
                         $signed(got_word[DATA_W*row +: DATA_W]));
            end
            $fatal(1);
        end
    end
end
endtask

initial begin
    rst             = 1'b1;
    clear           = 1'b0;
    start           = 1'b0;
    en              = 1'b0;
    act_base_addr   = '0;
    wgt_base_addr   = '0;
    out_base_addr   = '0;
    act_k_stride    = K_STRIDE;
    wgt_k_stride    = K_STRIDE;
    wgt_out_stride  = '0;
    out_tile_stride = OUT_TILE_STRIDE;
    num_k_tiles     = '0;
    num_out_tiles   = '0;
    scale_q         = SCALE_M4;

    init_matrices();
    compute_golden();
    init_mock_bram();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst = 1'b0;
    en  = 1'b1;

    configure_layer1();
    run_layer("L1", L1_OUT_DIM);
    repeat (2) @(posedge clk);
    #1;
    check_l1_memory();

    repeat (4) @(posedge clk);
    configure_layer2();
    run_layer("L2", L2_OUT_DIM);
    repeat (2) @(posedge clk);
    #1;
    check_l2_memory();

    $display("MINI_2LAYER_CHAIN_FEATURE_MAJOR test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

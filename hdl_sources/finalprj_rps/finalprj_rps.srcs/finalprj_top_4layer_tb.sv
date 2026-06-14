`timescale 1ns / 1ps

// Testbench for the 4-layer MLP top
module finalprj_top_4layer_tb;

// Common sizes and timeout value used by the testbench
localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int ACC_W          = 32;
localparam int WORD_W         = 128;
localparam int ADDR_W         = 14;
localparam int SCALE_W        = 32;
localparam int SCALE_FRAC     = 24;
localparam int PRODUCT_W      = ACC_W + SCALE_W;
localparam int TIMEOUT_CYCLES = 160000;

localparam int IN_DIM  = 768;
localparam int H_DIM   = 128;
localparam int OUT_DIM = 16;

// Base addresses for input, weights, scratch buffers, and final output in BRAM
localparam logic [ADDR_W-1:0] INPUT_BASE = 14'h2400;
localparam logic [ADDR_W-1:0] W1_BASE    = 14'h0000;
localparam logic [ADDR_W-1:0] W2_BASE    = 14'h1800;
localparam logic [ADDR_W-1:0] W3_BASE    = 14'h1C00;
localparam logic [ADDR_W-1:0] W4_BASE    = 14'h2000;
localparam logic [ADDR_W-1:0] BUF0_BASE  = 14'h2700;
localparam logic [ADDR_W-1:0] BUF1_BASE  = 14'h2780;
localparam logic [ADDR_W-1:0] FINAL_BASE = 14'h2880;

// Per-layer post-processing scale values
localparam logic [SCALE_W-1:0] M1_Q24 = 32'd6073;
localparam logic [SCALE_W-1:0] M2_Q24 = 32'd24139;
localparam logic [SCALE_W-1:0] M3_Q24 = 32'd328223;
localparam logic [SCALE_W-1:0] M4_Q24 = 32'd16777216;

// Input and weight binary files generated from numpy_reference/weights
localparam string INPUT_BIN_FILE = "input_spectrogram.bin";
localparam string W1_BIN_FILE    = "layer1_weights.bin";
localparam string W2_BIN_FILE    = "layer2_weights.bin";
localparam string W3_BIN_FILE    = "layer3_weights.bin";
localparam string W4_BIN_FILE    = "layer4_weights.bin";

logic clk;
logic rst_n;
logic proc_start;
logic proc_done;

// Signals used to tie off the AXI-lite style top ports in the testbench
logic [31:0] s_axi_awaddr;
logic        s_axi_awvalid;
logic        s_axi_awready;
logic [31:0] s_axi_wdata;
logic [3:0]  s_axi_wstrb;
logic        s_axi_wvalid;
logic        s_axi_wready;
logic [1:0]  s_axi_bresp;
logic        s_axi_bvalid;
logic        s_axi_bready;
logic [31:0] s_axi_araddr;
logic        s_axi_arvalid;
logic        s_axi_arready;
logic [31:0] s_axi_rdata;
logic [1:0]  s_axi_rresp;
logic        s_axi_rvalid;
logic        s_axi_rready;

// Input/weight matrices loaded from binary files, plus matrices for golden calculation
logic signed [DATA_W-1:0] X0 [0:N-1][0:IN_DIM-1];
logic signed [DATA_W-1:0] W1 [0:IN_DIM-1][0:H_DIM-1];
logic signed [DATA_W-1:0] W2 [0:H_DIM-1][0:H_DIM-1];
logic signed [DATA_W-1:0] W3 [0:H_DIM-1][0:H_DIM-1];
logic signed [DATA_W-1:0] W4 [0:H_DIM-1][0:OUT_DIM-1];

logic signed [ACC_W-1:0]  Y1 [0:N-1][0:H_DIM-1];
logic signed [DATA_W-1:0] X1 [0:N-1][0:H_DIM-1];
logic signed [ACC_W-1:0]  Y2 [0:N-1][0:H_DIM-1];
logic signed [DATA_W-1:0] X2 [0:N-1][0:H_DIM-1];
logic signed [ACC_W-1:0]  Y3 [0:N-1][0:H_DIM-1];
logic signed [DATA_W-1:0] X3 [0:N-1][0:H_DIM-1];
logic signed [ACC_W-1:0]  Y4 [0:N-1][0:OUT_DIM-1];
logic signed [DATA_W-1:0] X4 [0:N-1][0:OUT_DIM-1];

// Expected 128-bit words used for direct comparison with the BRAM final area
logic [WORD_W-1:0] expected_final_word [0:OUT_DIM-1];

// Raw byte buffers filled by $fread
byte signed x0_bin [0:N*IN_DIM-1];
byte signed w1_bin [0:H_DIM*IN_DIM-1];
byte signed w2_bin [0:H_DIM*H_DIM-1];
byte signed w3_bin [0:H_DIM*H_DIM-1];
byte signed w4_bin [0:OUT_DIM*H_DIM-1];

// Final output values checked earlier against the numpy reference
localparam logic signed [DATA_W-1:0] expected_numpy [0:N-1][0:OUT_DIM-1] = '{
    '{8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd7,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd5,  8'sd0,  8'sd5,  8'sd5,  8'sd15, 8'sd2,  8'sd6,  8'sd5,  8'sd12, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd7,  8'sd1,  8'sd0,  8'sd0,  8'sd7,  8'sd0,  8'sd5,  8'sd0,  8'sd14, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd10, 8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd6,  8'sd0,  8'sd6,  8'sd6,  8'sd18, 8'sd1,  8'sd3,  8'sd6,  8'sd13, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd12, 8'sd21, 8'sd0,  8'sd10, 8'sd6,  8'sd6,  8'sd15, 8'sd12, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd0,  8'sd2,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd5,  8'sd9,  8'sd0,  8'sd1,  8'sd4,  8'sd0,  8'sd11, 8'sd4,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd4,  8'sd2,  8'sd18, 8'sd9,  8'sd11, 8'sd4,  8'sd5,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd3,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd14, 8'sd0,  8'sd0,  8'sd2,  8'sd6,  8'sd0,  8'sd0,  8'sd0,  8'sd14, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0},
    '{8'sd0,  8'sd0,  8'sd6,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0,  8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0, 8'sd0}
};

// Probes for watching the internal sequencer and BRAM accesses
wire [1:0] seq_layer_idx;
wire       seq_busy;
wire       seq_done;
wire [ADDR_W-1:0] bram_pa_addr;
wire              bram_pa_wr;
wire [WORD_W-1:0] bram_pa_wdata;
wire [ADDR_W-1:0] bram_pb_addr;

// Top module under test
finalprj_top u_dut (
    .i_CLK         (clk),
    .i_RST_n       (rst_n),
    .i_PROC_START  (proc_start),
    .o_PROC_DONE   (proc_done),
    .S_AXI_ARESETN (rst_n),
    .S_AXI_AWADDR  (s_axi_awaddr),
    .S_AXI_AWVALID (s_axi_awvalid),
    .S_AXI_AWREADY (s_axi_awready),
    .S_AXI_WDATA   (s_axi_wdata),
    .S_AXI_WSTRB   (s_axi_wstrb),
    .S_AXI_WVALID  (s_axi_wvalid),
    .S_AXI_WREADY  (s_axi_wready),
    .S_AXI_BRESP   (s_axi_bresp),
    .S_AXI_BVALID  (s_axi_bvalid),
    .S_AXI_BREADY  (s_axi_bready),
    .S_AXI_ARADDR  (s_axi_araddr),
    .S_AXI_ARVALID (s_axi_arvalid),
    .S_AXI_ARREADY (s_axi_arready),
    .S_AXI_RDATA   (s_axi_rdata),
    .S_AXI_RRESP   (s_axi_rresp),
    .S_AXI_RVALID  (s_axi_rvalid),
    .S_AXI_RREADY  (s_axi_rready)
);

assign seq_layer_idx = u_dut.u_ctrl.u_mlp_seq.layer_idx;
assign seq_busy      = u_dut.u_ctrl.seq_busy;
assign seq_done      = u_dut.u_ctrl.seq_done;
assign bram_pa_addr  = u_dut.ctrl_pa_addr;
assign bram_pa_wr    = u_dut.ctrl_pa_wr;
assign bram_pa_wdata = u_dut.ctrl_pa_wdata;
assign bram_pb_addr  = u_dut.ctrl_pb_addr;

// 100 MHz clock
initial clk = 1'b0;
always #5 clk = ~clk;

task automatic try_weight_path(
    input  string dir_name,
    input  string filename,
    inout  int    fd,
    output string path
);
begin
    if (fd == 0) begin
        path = {dir_name, filename};
        fd = $fopen(path, "rb");
    end
end
endtask

task automatic open_weight_bin(
    input  string label_name,
    input  string filename,
    output int    fd,
    output string path
);
    string weights_dir;
begin
    fd = 0;
    path = "";

    if ($value$plusargs("WEIGHTS_DIR=%s", weights_dir)) begin
        path = {weights_dir, "/", filename};
        fd = $fopen(path, "rb");
    end

    try_weight_path("../../../../../../numpy_reference/weights/", filename, fd, path);
    try_weight_path("../../numpy_reference/weights/", filename, fd, path);
    try_weight_path("numpy_reference/weights/", filename, fd, path);
    try_weight_path("../numpy_reference/weights/", filename, fd, path);
    try_weight_path("../../../numpy_reference/weights/", filename, fd, path);
    try_weight_path("../../../../numpy_reference/weights/", filename, fd, path);
    try_weight_path("../../../../../numpy_reference/weights/", filename, fd, path);

    if (fd == 0) begin
        $display("%s_BIN_OPEN_FAILED: %s", label_name, filename);
        $display("Set +WEIGHTS_DIR=<path-to-numpy_reference/weights> or keep the full Embedded_System_Lab folder layout.");
        $fatal(1);
    end

    $display("%s_BIN_PATH: %s", label_name, path);
end
endtask

function automatic logic signed [DATA_W-1:0] to_data(input int signed value);
begin
    to_data = value;
end
endfunction

// Signed 8-bit multiply widened to 32 bits for the golden model
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

// Golden version of the RTL post_processor path: ReLU, scale, round, and saturate
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
    int fd;
    int nread;
    string bin_path;
begin
    // Open the input spectrogram binary before loading it into X0
    open_weight_bin("INPUT", INPUT_BIN_FILE, fd, bin_path);
    nread = $fread(x0_bin, fd);
    $fclose(fd);
    if (nread != N*IN_DIM) begin
        $display("INPUT_BIN_SIZE_MISMATCH: %s expected %0d bytes, got %0d", bin_path, N*IN_DIM, nread);
        $fatal(1);
    end

    // Read layer 1 weights
    open_weight_bin("W1", W1_BIN_FILE, fd, bin_path);
    nread = $fread(w1_bin, fd);
    $fclose(fd);
    if (nread != H_DIM*IN_DIM) begin
        $display("W1_BIN_SIZE_MISMATCH: %s expected %0d bytes, got %0d", bin_path, H_DIM*IN_DIM, nread);
        $fatal(1);
    end

    // Read layer 2 weights
    open_weight_bin("W2", W2_BIN_FILE, fd, bin_path);
    nread = $fread(w2_bin, fd);
    $fclose(fd);
    if (nread != H_DIM*H_DIM) begin
        $display("W2_BIN_SIZE_MISMATCH: %s expected %0d bytes, got %0d", bin_path, H_DIM*H_DIM, nread);
        $fatal(1);
    end

    // Read layer 3 weights
    open_weight_bin("W3", W3_BIN_FILE, fd, bin_path);
    nread = $fread(w3_bin, fd);
    $fclose(fd);
    if (nread != H_DIM*H_DIM) begin
        $display("W3_BIN_SIZE_MISMATCH: %s expected %0d bytes, got %0d", bin_path, H_DIM*H_DIM, nread);
        $fatal(1);
    end

    // Read layer 4 weights
    open_weight_bin("W4", W4_BIN_FILE, fd, bin_path);
    nread = $fread(w4_bin, fd);
    $fclose(fd);
    if (nread != OUT_DIM*H_DIM) begin
        $display("W4_BIN_SIZE_MISMATCH: %s expected %0d bytes, got %0d", bin_path, OUT_DIM*H_DIM, nread);
        $fatal(1);
    end

    // Unpack the byte buffers back into row/column indexed matrices
    for (int row = 0; row < N; row++) begin
        for (int k = 0; k < IN_DIM; k++) begin
            X0[row][k] = x0_bin[row*IN_DIM + k];
        end
    end

    for (int k = 0; k < IN_DIM; k++) begin
        for (int col = 0; col < H_DIM; col++) begin
            W1[k][col] = w1_bin[col*IN_DIM + k];
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        for (int col = 0; col < H_DIM; col++) begin
            W2[k][col] = w2_bin[col*H_DIM + k];
            W3[k][col] = w3_bin[col*H_DIM + k];
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            W4[k][col] = w4_bin[col*H_DIM + k];
        end
    end
end
endtask

// Compute the software golden output from binary inputs and weights
task automatic compute_golden();
begin
    // Layer 1
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y1[row][col] = '0;
            for (int k = 0; k < IN_DIM; k++) begin
                Y1[row][col] = Y1[row][col] + mul_i8_to_i32(X0[row][k], W1[k][col]);
            end
            X1[row][col] = golden_post_lane(Y1[row][col], M1_Q24);
        end
    end

    // Layer 2
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y2[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y2[row][col] = Y2[row][col] + mul_i8_to_i32(X1[row][k], W2[k][col]);
            end
            X2[row][col] = golden_post_lane(Y2[row][col], M2_Q24);
        end
    end

    // Layer 3
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y3[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y3[row][col] = Y3[row][col] + mul_i8_to_i32(X2[row][k], W3[k][col]);
            end
            X3[row][col] = golden_post_lane(Y3[row][col], M3_Q24);
        end
    end

    // Layer 4
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            Y4[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y4[row][col] = Y4[row][col] + mul_i8_to_i32(X3[row][k], W4[k][col]);
            end
            X4[row][col] = golden_post_lane(Y4[row][col], M4_Q24);
        end
    end

    // Pack the final 16 features into one BRAM word
    for (int row = 0; row < N; row++) begin
        expected_final_word[row] = '0;
        for (int feature = 0; feature < OUT_DIM; feature++) begin
            expected_final_word[row][DATA_W*feature +: DATA_W] = X4[row][feature];
        end
    end
end
endtask

// Pack the numpy reference values used as the submission check
task automatic pack_expected_final_word_from_numpy();
begin
    for (int row = 0; row < N; row++) begin
        expected_final_word[row] = '0;
        for (int feature = 0; feature < OUT_DIM; feature++) begin
            expected_final_word[row][DATA_W*feature +: DATA_W] = expected_numpy[row][feature];
            X4[row][feature] = expected_numpy[row][feature];
        end
    end
end
endtask

// Clear only the scratch/final regions inside the DUT BRAM
task automatic init_dut_bram();
begin
    // input/weight data is already loaded from bram_init.txt, so do not overwrite it here
    // Only clear the intermediate buffers and final output area
    for (int offset = 0; offset < H_DIM; offset++) begin
        u_dut.u_bram.mem[BUF0_BASE + offset] = '0;
        u_dut.u_bram.mem[BUF1_BASE + offset] = '0;
    end

    for (int row = 0; row < N; row++) begin
        u_dut.u_bram.mem[FINAL_BASE + row] = '0;
    end
end
endtask

// Pulse proc_start for one cycle to begin the run
task automatic pulse_proc_start();
begin
    @(negedge clk);
    proc_start = 1'b1;

    @(negedge clk);
    proc_start = 1'b0;
end
endtask

// Wait for proc_done while also counting final writes
task automatic wait_for_done();
    int timeout_count;
    int final_write_count;
    bit done_seen;
begin
    timeout_count = 0;
    final_write_count = 0;
    done_seen = 1'b0;

    pulse_proc_start();

    // Watch done and final writes until timeout
    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (bram_pa_wr &&
            (bram_pa_addr >= FINAL_BASE) &&
            (bram_pa_addr < FINAL_BASE + OUT_DIM)) begin
            final_write_count = final_write_count + 1;
        end

        if (proc_done) begin
            done_seen = 1'b1;
            if (seq_busy !== 1'b0) begin
                $display("TOP_DONE_CHECK: expected seq_busy=0 when proc_done=1, got %0b",
                         seq_busy);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("FINALPRJ_TOP_4LAYER: timeout waiting for done, layer_idx=%0d PA=0x%0h PB=0x%0h",
                 seq_layer_idx, bram_pa_addr, bram_pb_addr);
        $fatal(1);
    end
    if (final_write_count != OUT_DIM) begin
        $display("FINAL_WRITE_CHECK: expected %0d final writes, got %0d",
                 OUT_DIM, final_write_count);
        $fatal(1);
    end
end
endtask

// Compare 128-bit words in the BRAM final area against expected values
task automatic check_final_memory();
    logic [WORD_W-1:0] got_word;
    int mismatch_count;
begin
    mismatch_count = 0;

    for (int row = 0; row < N; row++) begin
        got_word = u_dut.u_bram.mem[FINAL_BASE + row];

        if (got_word !== expected_final_word[row]) begin
            mismatch_count++;
            $display("FINAL_MEMORY_CHECK row %0d: expected word 0x%032h, got 0x%032h",
                     row, expected_final_word[row], got_word);
            for (int feature = 0; feature < OUT_DIM; feature++) begin
                $display("  feature %0d expected=%0d got=%0d",
                         feature, X4[row][feature],
                         $signed(got_word[DATA_W*feature +: DATA_W]));
            end
        end
    end

    if (mismatch_count != 0) begin
        $display("FINAL_MEMORY_CHECK_FAILED mismatch_count=%0d", mismatch_count);
        $fatal(1);
    end
end
endtask

// Compare one more time against the numpy reference, feature by feature
task automatic check_numpy_reference_output();
    logic signed [DATA_W-1:0] got_value;
    int mismatch_count;
begin
    mismatch_count = 0;

    for (int row = 0; row < N; row++) begin
        for (int feature = 0; feature < OUT_DIM; feature++) begin
            got_value = $signed(u_dut.u_bram.mem[FINAL_BASE + row][DATA_W*feature +: DATA_W]);

            if (got_value !== expected_numpy[row][feature]) begin
                mismatch_count++;
                $display("NUMPY_REFERENCE_OUTPUT_MISMATCH row=%0d feature=%0d expected=%0d got=%0d",
                         row, feature, expected_numpy[row][feature], got_value);
            end
        end
    end

    if (mismatch_count != 0) begin
        $display("NUMPY_REFERENCE_OUTPUT_FAILED mismatch_count=%0d", mismatch_count);
        $fatal(1);
    end

end
endtask

// Print the final output matrix and predicted class for each row
task automatic print_final_matrix();
    logic signed [DATA_W-1:0] final_value;
    int signed current_value;
    int signed best_value;
    int        best_feature;
begin
    $display("=== RTL FINAL OUTPUT MATRIX ===");
    for (int row = 0; row < N; row++) begin
        if (row == 0) begin
            $write("[[");
        end
        else begin
            $write(" [");
        end

        for (int feature = 0; feature < OUT_DIM; feature++) begin
            final_value = $signed(u_dut.u_bram.mem[FINAL_BASE + row][DATA_W*feature +: DATA_W]);
            $write("%4d", final_value);
            if (feature != OUT_DIM-1) begin
                $write(" ");
            end
        end

        if (row == N-1) begin
            $display("]]");
        end
        else begin
            $display("]");
        end
    end

    $display("--- RTL Final Batch Predictions ---");
    for (int row = 0; row < N; row++) begin
        best_feature = 0;
        best_value   = -129;

        for (int feature = 0; feature < 9; feature++) begin
            final_value = $signed(u_dut.u_bram.mem[FINAL_BASE + row][DATA_W*feature +: DATA_W]);
            current_value = final_value;

            if ((feature == 0) || (current_value > best_value)) begin
                best_value   = current_value;
                best_feature = feature;
            end
        end

        $display("Audio Clip %02d: Predicted Class ID = %0d", row + 1, best_feature);
    end
end
endtask

initial begin
    // Initialize top input signals while reset is active
    rst_n         = 1'b0;
    proc_start    = 1'b0;
    s_axi_awaddr  = 32'd0;
    s_axi_awvalid = 1'b0;
    s_axi_wdata   = 32'd0;
    s_axi_wstrb   = 4'h0;
    s_axi_wvalid  = 1'b0;
    s_axi_bready  = 1'b1;
    s_axi_araddr  = 32'd0;
    s_axi_arvalid = 1'b0;
    s_axi_rready  = 1'b1;

    // Prepare the golden calculation and DUT BRAM initialization
    init_matrices();
    compute_golden();
    pack_expected_final_word_from_numpy();

    #1;
    init_dut_bram();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    repeat (2) @(posedge clk);
    wait_for_done();

    // After the run, compare final memory against the numpy reference
    repeat (4) @(posedge clk);
    #1;
    check_final_memory();
    check_numpy_reference_output();
    print_final_matrix();

    $display("FINALPRJ_TOP 4LAYER MLP test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

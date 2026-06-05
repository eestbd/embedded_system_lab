`timescale 1ns / 1ps

module finalprj_top_4layer_tb;

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

localparam logic [ADDR_W-1:0] INPUT_BASE = 14'h0000;
localparam logic [ADDR_W-1:0] W1_BASE    = 14'h0300;
localparam logic [ADDR_W-1:0] W2_BASE    = 14'h1B00;
localparam logic [ADDR_W-1:0] W3_BASE    = 14'h1F00;
localparam logic [ADDR_W-1:0] W4_BASE    = 14'h2300;
localparam logic [ADDR_W-1:0] BUF0_BASE  = 14'h2700;
localparam logic [ADDR_W-1:0] BUF1_BASE  = 14'h2780;
localparam logic [ADDR_W-1:0] FINAL_BASE = 14'h2880;

localparam logic [SCALE_W-1:0] M1_Q24 = 32'd6073;
localparam logic [SCALE_W-1:0] M2_Q24 = 32'd24139;
localparam logic [SCALE_W-1:0] M3_Q24 = 32'd328223;
localparam logic [SCALE_W-1:0] M4_Q24 = 32'd16777216;

logic clk;
logic rst_n;
logic proc_start;
logic proc_done;

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

logic [WORD_W-1:0] expected_final_word [0:OUT_DIM-1];

wire [1:0] seq_layer_idx;
wire       seq_busy;
wire       seq_done;
wire [ADDR_W-1:0] bram_pa_addr;
wire              bram_pa_wr;
wire [WORD_W-1:0] bram_pa_wdata;
wire [ADDR_W-1:0] bram_pb_addr;

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

initial clk = 1'b0;
always #5 clk = ~clk;

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
        for (int k = 0; k < IN_DIM; k++) begin
            value = ((row * 5 + k * 3 + 2) % 9) - 4;
            X0[row][k] = to_data(value);
        end
    end

    for (int k = 0; k < IN_DIM; k++) begin
        for (int col = 0; col < H_DIM; col++) begin
            value = ((k * 7 + col * 2 + 1) % 9) - 4;
            W1[k][col] = to_data(value);
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        for (int col = 0; col < H_DIM; col++) begin
            value = ((k * 5 + col * 3 + 4) % 9) - 4;
            W2[k][col] = to_data(value);
            value = ((k * 3 + col * 4 + 5) % 9) - 4;
            W3[k][col] = to_data(value);
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            value = ((k * 7 + col * 5 + 6) % 9) - 4;
            W4[k][col] = to_data(value);
        end
    end

    // Landmarks with nonzero positive paths after all scales.
    for (int k = 0; k < IN_DIM; k++) begin
        X0[0][k] = 8'sd4;
        X0[1][k] = -8'sd4;
        X0[2][k] = 8'sd0;
        for (int col = 0; col < H_DIM; col += N) begin
            W1[k][col + 0] = 8'sd4;
            W1[k][col + 1] = 8'sd4;
            W1[k][col + 2] = 8'sd0;
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        for (int col = 0; col < H_DIM; col += N) begin
            W2[k][col + 0] = 8'sd4;
            W2[k][col + 1] = -8'sd4;
            W2[k][col + 2] = 8'sd0;
            W3[k][col + 0] = 8'sd4;
            W3[k][col + 1] = 8'sd4;
            W3[k][col + 2] = 8'sd0;
        end
    end

    for (int k = 0; k < H_DIM; k++) begin
        W4[k][0] = 8'sd4;
        W4[k][1] = -8'sd4;
        W4[k][2] = 8'sd0;
    end
end
endtask

task automatic compute_golden();
begin
    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y1[row][col] = '0;
            for (int k = 0; k < IN_DIM; k++) begin
                Y1[row][col] = Y1[row][col] + mul_i8_to_i32(X0[row][k], W1[k][col]);
            end
            X1[row][col] = golden_post_lane(Y1[row][col], M1_Q24);
        end
    end

    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y2[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y2[row][col] = Y2[row][col] + mul_i8_to_i32(X1[row][k], W2[k][col]);
            end
            X2[row][col] = golden_post_lane(Y2[row][col], M2_Q24);
        end
    end

    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < H_DIM; col++) begin
            Y3[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y3[row][col] = Y3[row][col] + mul_i8_to_i32(X2[row][k], W3[k][col]);
            end
            X3[row][col] = golden_post_lane(Y3[row][col], M3_Q24);
        end
    end

    for (int row = 0; row < N; row++) begin
        for (int col = 0; col < OUT_DIM; col++) begin
            Y4[row][col] = '0;
            for (int k = 0; k < H_DIM; k++) begin
                Y4[row][col] = Y4[row][col] + mul_i8_to_i32(X3[row][k], W4[k][col]);
            end
            X4[row][col] = golden_post_lane(Y4[row][col], M4_Q24);
        end
    end

    for (int feature = 0; feature < OUT_DIM; feature++) begin
        expected_final_word[feature] = '0;
        for (int row = 0; row < N; row++) begin
            expected_final_word[feature][DATA_W*row +: DATA_W] = X4[row][feature];
        end
    end
end
endtask

task automatic init_dut_bram();
    logic [WORD_W-1:0] word;
    int full_k;
begin
    for (int k = 0; k < IN_DIM; k++) begin
        word = '0;
        for (int row = 0; row < N; row++) begin
            word[DATA_W*row +: DATA_W] = X0[row][k];
        end
        u_dut.u_bram.mem[INPUT_BASE + k] = word;
    end

    for (int ot = 0; ot < 8; ot++) begin
        for (int kt = 0; kt < 48; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                word = '0;
                for (int col = 0; col < N; col++) begin
                    word[DATA_W*col +: DATA_W] = W1[full_k][ot*N + col];
                end
                u_dut.u_bram.mem[W1_BASE + ot*(48*N) + kt*N + t] = word;
            end
        end
    end

    for (int ot = 0; ot < 8; ot++) begin
        for (int kt = 0; kt < 8; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                word = '0;
                for (int col = 0; col < N; col++) begin
                    word[DATA_W*col +: DATA_W] = W2[full_k][ot*N + col];
                end
                u_dut.u_bram.mem[W2_BASE + ot*(8*N) + kt*N + t] = word;
            end
        end
    end

    for (int ot = 0; ot < 8; ot++) begin
        for (int kt = 0; kt < 8; kt++) begin
            for (int t = 0; t < N; t++) begin
                full_k = kt * N + t;
                word = '0;
                for (int col = 0; col < N; col++) begin
                    word[DATA_W*col +: DATA_W] = W3[full_k][ot*N + col];
                end
                u_dut.u_bram.mem[W3_BASE + ot*(8*N) + kt*N + t] = word;
            end
        end
    end

    for (int kt = 0; kt < 8; kt++) begin
        for (int t = 0; t < N; t++) begin
            full_k = kt * N + t;
            word = '0;
            for (int col = 0; col < OUT_DIM; col++) begin
                word[DATA_W*col +: DATA_W] = W4[full_k][col];
            end
            u_dut.u_bram.mem[W4_BASE + kt*N + t] = word;
        end
    end

    for (int offset = 0; offset < H_DIM; offset++) begin
        u_dut.u_bram.mem[BUF0_BASE + offset] = '0;
        u_dut.u_bram.mem[BUF1_BASE + offset] = '0;
    end

    for (int feature = 0; feature < OUT_DIM; feature++) begin
        u_dut.u_bram.mem[FINAL_BASE + feature] = '0;
    end
end
endtask

task automatic pulse_proc_start();
begin
    @(negedge clk);
    proc_start = 1'b1;

    @(negedge clk);
    proc_start = 1'b0;
end
endtask

task automatic wait_for_done();
    int timeout_count;
    int final_write_count;
    bit done_seen;
begin
    timeout_count = 0;
    final_write_count = 0;
    done_seen = 1'b0;

    pulse_proc_start();

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

task automatic check_final_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int feature = 0; feature < OUT_DIM; feature++) begin
        got_word = u_dut.u_bram.mem[FINAL_BASE + feature];

        if (got_word !== expected_final_word[feature]) begin
            $display("FINAL_MEMORY_CHECK feature %0d: expected word 0x%032h, got 0x%032h",
                     feature, expected_final_word[feature], got_word);
            for (int row = 0; row < N; row++) begin
                $display("  row %0d expected=%0d got=%0d",
                         row, X4[row][feature],
                         $signed(got_word[DATA_W*row +: DATA_W]));
            end
            $fatal(1);
        end
    end
end
endtask

initial begin
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

    init_matrices();
    compute_golden();

    #1;
    init_dut_bram();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    repeat (2) @(posedge clk);
    wait_for_done();

    repeat (4) @(posedge clk);
    #1;
    check_final_memory();

    $display("FINALPRJ_TOP 4LAYER MLP test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

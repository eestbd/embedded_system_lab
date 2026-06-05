`timescale 1ns / 1ps

module finalprj_top_single_tile_tb;

localparam int N              = 16;
localparam int DATA_W         = 8;
localparam int ACC_W          = 32;
localparam int WORD_W         = 128;
localparam int ADDR_W         = 14;
localparam int SCALE_W        = 32;
localparam int SCALE_FRAC     = 24;
localparam int PRODUCT_W      = ACC_W + SCALE_W;
localparam int TIMEOUT_CYCLES = 600;

localparam logic [ADDR_W-1:0] ACT_BASE_ADDR = 14'h0100;
localparam logic [ADDR_W-1:0] WGT_BASE_ADDR = 14'h0200;
localparam logic [ADDR_W-1:0] OUT_BASE_ADDR = 14'h2880;
localparam logic [SCALE_W-1:0] SCALE_M4 = 32'd16777216;

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

logic signed [DATA_W-1:0] A [0:N-1][0:N-1];
logic signed [DATA_W-1:0] B [0:N-1][0:N-1];
logic signed [ACC_W-1:0]  golden_C [0:N-1][0:N-1];
logic signed [DATA_W-1:0] golden_out [0:N-1][0:N-1];
logic [WORD_W-1:0] expected_out_word [0:N-1];

wire [ADDR_W-1:0] bram_pa_addr;
wire              bram_pa_wr;
wire [WORD_W-1:0] bram_pa_wdata;
wire [ADDR_W-1:0] bram_pb_addr;
wire              bram_pb_wr;
wire [WORD_W-1:0] bram_pb_wdata;

wire              engine_busy;
wire              engine_done;
wire              engine_bram_act_en;
wire [ADDR_W-1:0] engine_bram_act_addr;
wire              engine_bram_wgt_en;
wire [ADDR_W-1:0] engine_bram_wgt_addr;
wire              engine_bram_out_wr;
wire [ADDR_W-1:0] engine_bram_out_addr;
wire [WORD_W-1:0] engine_bram_out_wdata;

finalprj_top u_dut (
    .i_CLK          (clk),
    .i_RST_n        (rst_n),
    .i_PROC_START   (proc_start),
    .o_PROC_DONE    (proc_done),
    .S_AXI_ARESETN  (rst_n),
    .S_AXI_AWADDR   (s_axi_awaddr),
    .S_AXI_AWVALID  (s_axi_awvalid),
    .S_AXI_AWREADY  (s_axi_awready),
    .S_AXI_WDATA    (s_axi_wdata),
    .S_AXI_WSTRB    (s_axi_wstrb),
    .S_AXI_WVALID   (s_axi_wvalid),
    .S_AXI_WREADY   (s_axi_wready),
    .S_AXI_BRESP    (s_axi_bresp),
    .S_AXI_BVALID   (s_axi_bvalid),
    .S_AXI_BREADY   (s_axi_bready),
    .S_AXI_ARADDR   (s_axi_araddr),
    .S_AXI_ARVALID  (s_axi_arvalid),
    .S_AXI_ARREADY  (s_axi_arready),
    .S_AXI_RDATA    (s_axi_rdata),
    .S_AXI_RRESP    (s_axi_rresp),
    .S_AXI_RVALID   (s_axi_rvalid),
    .S_AXI_RREADY   (s_axi_rready)
);

assign bram_pa_addr = u_dut.ctrl_pa_addr;
assign bram_pa_wr = u_dut.ctrl_pa_wr;
assign bram_pa_wdata = u_dut.ctrl_pa_wdata;
assign bram_pb_addr = u_dut.ctrl_pb_addr;
assign bram_pb_wr = u_dut.ctrl_pb_wr;
assign bram_pb_wdata = u_dut.ctrl_pb_wdata;

assign engine_busy = u_dut.u_ctrl.engine_busy;
assign engine_done = u_dut.u_ctrl.engine_done;
assign engine_bram_act_en = u_dut.u_ctrl.engine_bram_act_en;
assign engine_bram_act_addr = u_dut.u_ctrl.engine_bram_act_addr;
assign engine_bram_wgt_en = u_dut.u_ctrl.engine_bram_wgt_en;
assign engine_bram_wgt_addr = u_dut.u_ctrl.engine_bram_wgt_addr;
assign engine_bram_out_wr = u_dut.u_ctrl.engine_bram_out_wr;
assign engine_bram_out_addr = u_dut.u_ctrl.engine_bram_out_addr;
assign engine_bram_out_wdata = u_dut.u_ctrl.engine_bram_out_wdata;

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

    // Visible corner cases in the final output: positive, ReLU zero, and saturation.
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

task automatic init_dut_bram();
    logic [WORD_W-1:0] act_word;
    logic [WORD_W-1:0] wgt_word;
begin
    for (int t = 0; t < N; t++) begin
        act_word = '0;
        wgt_word = '0;
        for (int lane = 0; lane < N; lane++) begin
            act_word[DATA_W*lane +: DATA_W] = A[lane][t];
            wgt_word[DATA_W*lane +: DATA_W] = B[t][lane];
        end
        u_dut.u_bram.mem[ACT_BASE_ADDR + t] = act_word;
        u_dut.u_bram.mem[WGT_BASE_ADDR + t] = wgt_word;
    end

    for (int row = 0; row < N; row++) begin
        u_dut.u_bram.mem[OUT_BASE_ADDR + row] = '0;
    end
end
endtask

task automatic check_read_addr(input int stream_idx);
    logic [ADDR_W-1:0] expected_act_addr;
    logic [ADDR_W-1:0] expected_wgt_addr;
begin
    expected_act_addr = ACT_BASE_ADDR + stream_idx;
    expected_wgt_addr = WGT_BASE_ADDR + stream_idx;

    if (engine_bram_act_en !== 1'b1) begin
        $display("READ_ADDR_CHECK stream %0d: expected engine_bram_act_en=1, got %0b",
                 stream_idx, engine_bram_act_en);
        $fatal(1);
    end
    if (engine_bram_wgt_en !== 1'b1) begin
        $display("READ_ADDR_CHECK stream %0d: expected engine_bram_wgt_en=1, got %0b",
                 stream_idx, engine_bram_wgt_en);
        $fatal(1);
    end
    if (engine_bram_act_addr !== expected_act_addr) begin
        $display("READ_ADDR_CHECK stream %0d: expected act_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_act_addr, engine_bram_act_addr);
        $fatal(1);
    end
    if (engine_bram_wgt_addr !== expected_wgt_addr) begin
        $display("READ_ADDR_CHECK stream %0d: expected wgt_addr=0x%0h, got 0x%0h",
                 stream_idx, expected_wgt_addr, engine_bram_wgt_addr);
        $fatal(1);
    end

    if (bram_pa_wr !== 1'b0) begin
        $display("READ_ADDR_CHECK stream %0d: expected Port A write disabled during read, got %0b",
                 stream_idx, bram_pa_wr);
        $fatal(1);
    end
    if (bram_pa_addr !== expected_act_addr) begin
        $display("READ_ADDR_CHECK stream %0d: expected Port A addr=0x%0h, got 0x%0h",
                 stream_idx, expected_act_addr, bram_pa_addr);
        $fatal(1);
    end
    if (bram_pb_addr !== expected_wgt_addr) begin
        $display("READ_ADDR_CHECK stream %0d: expected Port B addr=0x%0h, got 0x%0h",
                 stream_idx, expected_wgt_addr, bram_pb_addr);
        $fatal(1);
    end
    if (bram_pb_wr !== 1'b0 || bram_pb_wdata !== '0) begin
        $display("READ_ADDR_CHECK stream %0d: expected Port B read-only, wr=%0b wdata=0x%032h",
                 stream_idx, bram_pb_wr, bram_pb_wdata);
        $fatal(1);
    end
end
endtask

task automatic check_write(input int expected_row, input int write_count);
    logic [ADDR_W-1:0] expected_addr;
begin
    expected_addr = OUT_BASE_ADDR + expected_row;

    if (engine_bram_out_wr !== 1'b1) begin
        $display("WRITE_CHECK count %0d row %0d: expected engine_bram_out_wr=1, got %0b",
                 write_count, expected_row, engine_bram_out_wr);
        $fatal(1);
    end
    if (engine_bram_out_addr !== expected_addr) begin
        $display("WRITE_CHECK count %0d row %0d: expected engine addr=0x%0h, got 0x%0h",
                 write_count, expected_row, expected_addr, engine_bram_out_addr);
        $fatal(1);
    end
    if (bram_pa_wr !== 1'b1) begin
        $display("WRITE_CHECK count %0d row %0d: expected Port A write enabled, got %0b",
                 write_count, expected_row, bram_pa_wr);
        $fatal(1);
    end
    if (bram_pa_addr !== expected_addr) begin
        $display("WRITE_CHECK count %0d row %0d: expected Port A addr=0x%0h, got 0x%0h",
                 write_count, expected_row, expected_addr, bram_pa_addr);
        $fatal(1);
    end
    if (bram_pa_wdata !== expected_out_word[expected_row]) begin
        $display("WRITE_CHECK count %0d row %0d: expected word 0x%032h, got 0x%032h",
                 write_count, expected_row, expected_out_word[expected_row], bram_pa_wdata);
        for (int lane = 0; lane < N; lane++) begin
            $display("  lane %0d expected=%0d got=%0d",
                     lane, golden_out[expected_row][lane],
                     $signed(bram_pa_wdata[DATA_W*lane +: DATA_W]));
        end
        $fatal(1);
    end
    if (engine_bram_out_wdata !== expected_out_word[expected_row]) begin
        $display("WRITE_CHECK count %0d row %0d: engine word mismatch expected 0x%032h got 0x%032h",
                 write_count, expected_row, expected_out_word[expected_row], engine_bram_out_wdata);
        $fatal(1);
    end
end
endtask

task automatic check_output_memory();
    logic [WORD_W-1:0] got_word;
begin
    for (int row = 0; row < N; row++) begin
        got_word = u_dut.u_bram.mem[OUT_BASE_ADDR + row];

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

task automatic pulse_proc_start();
begin
    @(negedge clk);
    proc_start = 1'b1;

    @(negedge clk);
    proc_start = 1'b0;
end
endtask

task automatic run_top_check();
    int read_count;
    int write_count;
    int timeout_count;
    bit done_seen;
begin
    read_count    = 0;
    write_count   = 0;
    timeout_count = 0;
    done_seen     = 1'b0;

    pulse_proc_start();

    while (!done_seen && (timeout_count < TIMEOUT_CYCLES)) begin
        @(posedge clk);
        #1;
        timeout_count = timeout_count + 1;

        if (engine_bram_out_wr && (engine_bram_act_en || engine_bram_wgt_en)) begin
            $display("PORT_CONFLICT_CHECK: output write overlapped with read phase, act_en=%0b wgt_en=%0b",
                     engine_bram_act_en, engine_bram_wgt_en);
            $fatal(1);
        end

        if (engine_bram_act_en || engine_bram_wgt_en) begin
            if (read_count >= N) begin
                $display("READ_ADDR_CHECK: extra read address after %0d streams", N);
                $fatal(1);
            end
            check_read_addr(read_count);
            read_count = read_count + 1;
        end

        if (bram_pa_wr) begin
            if (write_count >= N) begin
                $display("WRITE_CHECK: extra write after %0d rows", N);
                $fatal(1);
            end
            check_write(write_count, write_count);
            write_count = write_count + 1;
        end

        if (proc_done) begin
            done_seen = 1'b1;
            if (engine_busy !== 1'b0) begin
                $display("TOP_DONE_CHECK: expected engine_busy=0 when proc_done=1, got %0b",
                         engine_busy);
                $fatal(1);
            end
            if (write_count != N) begin
                $display("TOP_DONE_CHECK: proc_done after %0d writes, expected %0d",
                         write_count, N);
                $fatal(1);
            end
            if (bram_pa_wr !== 1'b0) begin
                $display("TOP_DONE_CHECK: expected Port A write disabled when proc_done=1, got %0b",
                         bram_pa_wr);
                $fatal(1);
            end
        end
    end

    if (!done_seen) begin
        $display("FINALPRJ_TOP: timeout waiting for o_PROC_DONE");
        $fatal(1);
    end
    if (read_count != N) begin
        $display("READ_ADDR_CHECK: expected %0d read addresses, got %0d", N, read_count);
        $fatal(1);
    end
    if (write_count != N) begin
        $display("WRITE_CHECK: expected %0d writes, got %0d", N, write_count);
        $fatal(1);
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

    // Let BRAM_TDP finish its $readmemh initial block, then override this
    // single-tile test region through simulation-only hierarchical access.
    #1;
    init_dut_bram();

    repeat (4) @(posedge clk);
    @(negedge clk);
    rst_n = 1'b1;

    repeat (2) @(posedge clk);
    run_top_check();

    // The final Port A write is visible one cycle before the BRAM write edge.
    repeat (2) @(posedge clk);
    #1;
    check_output_memory();

    $display("FINALPRJ_TOP SINGLE TILE test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

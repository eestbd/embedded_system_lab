`timescale 1ns / 1ns

module finalprj_tb;

logic clk, rst_n, proc_start, proc_done;

// Clock: 2ns period
initial clk = 0;
always #1 clk = ~clk;

// Bring-up taps for BRAM read timing.
wire [2:0]   ctrl_state_tap         = u_dut.u_ctrl.r_state;
wire [13:0]  ctrl_pa_addr_tap       = u_dut.u_ctrl.o_PA_ADDR;
wire [127:0] ctrl_pa_rdata_tap      = u_dut.u_ctrl.i_PA_RDATA;
wire [127:0] ctrl_pa_capture_tap    = u_dut.u_ctrl.r_pa_read_data_capture;
wire         ctrl_pa_capture_valid  = u_dut.u_ctrl.r_pa_read_data_valid;

// Instantiate finalprj top module
finalprj_top u_dut (
    .i_CLK           (clk),
    .i_RST_n         (rst_n),

    .i_PROC_START    (proc_start),
    .o_PROC_DONE     (proc_done),

    // Set AXI bus as idle (do not modify)
    .S_AXI_ARESETN  (rst_n),
    .S_AXI_AWADDR   (32'd0),
    .S_AXI_AWVALID  (1'b0),
    .S_AXI_AWREADY  (),
    .S_AXI_WDATA    (32'd0),
    .S_AXI_WSTRB    (4'd0),
    .S_AXI_WVALID   (1'b0),
    .S_AXI_WREADY   (),
    .S_AXI_BRESP    (),
    .S_AXI_BVALID   (),
    .S_AXI_BREADY   (1'b1),
    .S_AXI_ARADDR   (32'd0),
    .S_AXI_ARVALID  (1'b0),
    .S_AXI_ARREADY  (),
    .S_AXI_RDATA    (),
    .S_AXI_RRESP    (),
    .S_AXI_RVALID   (),
    .S_AXI_RREADY   (1'b1)
);

initial begin
    rst_n      = 1'b0;
    proc_start = 1'b0;

    repeat (32) @(posedge clk);
    rst_n = 1'b1;

    @(posedge clk);
    proc_start = 1'b1;
    @(posedge clk);
    proc_start = 1'b0;

    // Wait for completion
    wait (proc_done);
    $display("CONTROL BRAM read addr    = 0x%04h", ctrl_pa_addr_tap);
    $display("CONTROL BRAM read capture = 0x%032h", ctrl_pa_capture_tap);

    repeat (16) @(posedge clk);
    $finish;

end

endmodule

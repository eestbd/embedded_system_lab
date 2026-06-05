`timescale 1ns / 1ns

module finalprj_tb;

logic clk, rst_n, proc_start, proc_done;

// Clock: 10ns period
initial clk = 0;
always #1 clk = ~clk;

// You can observe internal signals like this:
wire signed [31:0] pe_acc_tap [0:15][0:15];

genvar gr, gc;
generate
    for (gr = 0; gr < 16; gr++) begin : g_tap_row
        for (gc = 0; gc < 16; gc++) begin : g_tap_col
            assign pe_acc_tap[gr][gc] =
                u_dut.u_systolic.u_pe_arr.g_row[gr].g_col[gc].u_pe.acc;
        end
    end
endgenerate

// Instantiate finalprj top module
finalprj_top u_dut (
    .i_CLK           (clk),
    .i_RST_n         (rst_n),

    .i_PROC_START    (proc_start),
    .o_PROC_DONE     (proc_done),

    // Set AXI bus as idle (do not modify)
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
    //wait (proc_done);
    //repeat (16) @(posedge clk);

end

endmodule
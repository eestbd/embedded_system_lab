`timescale 1ns / 1ps

module pe_tb;

localparam int DATA_W = 8;
localparam int ACC_W  = 32;

logic clk;
logic rst_n;
logic clear;
logic en;
logic signed [DATA_W-1:0] act;
logic signed [DATA_W-1:0] wgt;
logic signed [DATA_W-1:0] act_out;
logic signed [DATA_W-1:0] wgt_out;
logic signed [ACC_W-1:0]  acc;

PE #(
    .DATA_W(DATA_W),
    .ACC_W (ACC_W)
) u_pe (
    .i_clk   (clk),
    .i_rst_n (rst_n),
    .i_clear (clear),
    .i_en    (en),
    .i_act   (act),
    .i_wgt   (wgt),
    .o_act   (act_out),
    .o_wgt   (wgt_out),
    .o_acc   (acc)
);

initial clk = 1'b0;
always #5 clk = ~clk;

task automatic check_acc(
    input logic signed [ACC_W-1:0] expected,
    input string                   label
);
begin
    if (acc !== expected) begin
        $error("%s: expected acc=%0d, got acc=%0d", label, expected, acc);
        $fatal(1);
    end
    else begin
        $display("%s: acc=%0d OK", label, acc);
    end
end
endtask

task automatic check_pipe_outputs(
    input logic signed [DATA_W-1:0] expected_act,
    input logic signed [DATA_W-1:0] expected_wgt,
    input string                    label
);
begin
    if ((act_out !== expected_act) || (wgt_out !== expected_wgt)) begin
        $error("%s: expected o_act=%0d o_wgt=%0d, got o_act=%0d o_wgt=%0d",
               label, expected_act, expected_wgt, act_out, wgt_out);
        $fatal(1);
    end
end
endtask

task automatic apply_mac(
    input logic signed [DATA_W-1:0] in_act,
    input logic signed [DATA_W-1:0] in_wgt,
    input logic signed [ACC_W-1:0]  expected_acc,
    input string                    label
);
begin
    @(negedge clk);
    clear = 1'b0;
    en    = 1'b1;
    act   = in_act;
    wgt   = in_wgt;

    @(posedge clk);
    #1;
    check_acc(expected_acc, label);
    check_pipe_outputs(in_act, in_wgt, label);

    @(negedge clk);
    en  = 1'b0;
    act = '0;
    wgt = '0;
end
endtask

task automatic apply_clear(input string label);
begin
    @(negedge clk);
    clear = 1'b1;
    en    = 1'b0;
    act   = '0;
    wgt   = '0;

    @(posedge clk);
    #1;
    check_acc('0, label);

    @(negedge clk);
    clear = 1'b0;
end
endtask

initial begin
    rst_n = 1'b0;
    clear = 1'b0;
    en    = 1'b0;
    act   = '0;
    wgt   = '0;

    repeat (4) @(posedge clk);
    rst_n = 1'b1;
    @(posedge clk);
    #1;
    check_acc(32'sd0, "reset");

    apply_mac( 8'sd3,   8'sd4,   32'sd12,    "3 * 4");

    apply_clear("clear after 3 * 4");
    apply_mac(-8'sd3,   8'sd4,  -32'sd12,    "-3 * 4");

    apply_clear("clear after -3 * 4");
    apply_mac(-8'sd3,  -8'sd4,   32'sd12,    "-3 * -4");

    apply_clear("clear before multi-cycle accumulation");
    apply_mac( 8'sd3,   8'sd4,   32'sd12,    "multi 1: 3 * 4");
    apply_mac(-8'sd3,   8'sd4,   32'sd0,     "multi 2: + (-3 * 4)");
    apply_mac(-8'sd3,  -8'sd4,   32'sd12,    "multi 3: + (-3 * -4)");

    apply_clear("clear after multi-cycle accumulation");

    apply_mac( 8'sd127, 8'sd127, 32'sd16129, "boundary 127 * 127");
    apply_mac($signed(8'h80), 8'sd127, -32'sd127,
              "boundary accumulate + (-128 * 127)");

    apply_clear("clear before -128 * -128");
    apply_mac($signed(8'h80), $signed(8'h80), 32'sd16384,
              "boundary -128 * -128");

    $display("PE test PASSED");
    repeat (4) @(posedge clk);
    $finish;
end

endmodule

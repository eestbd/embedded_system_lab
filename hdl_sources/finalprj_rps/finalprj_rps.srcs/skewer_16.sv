`timescale 1ns / 1ps

module skewer_16 #(
    parameter int N      = 16,
    parameter int DATA_W = 8
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         en,
    input  logic signed [DATA_W-1:0]     vec_in  [0:N-1],
    output logic signed [DATA_W-1:0]     vec_out [0:N-1]
);

// Lane 0 is combinational delay 0.
// Lane L>0 uses exactly L registers, so vec_out[L] is vec_in[L]
// delayed by L enabled cycles.
logic signed [DATA_W-1:0] delay_pipe [0:N-1][0:N-1];

always_ff @(posedge clk) begin
    if (rst || clear) begin
        for (int lane = 0; lane < N; lane++) begin
            for (int stage = 0; stage < N; stage++) begin
                delay_pipe[lane][stage] <= '0;
            end
        end
    end
    else if (en) begin
        for (int lane = 0; lane < N; lane++) begin
            if (lane > 0) begin
                delay_pipe[lane][0] <= vec_in[lane];
            end

            for (int stage = 1; stage < N; stage++) begin
                if (stage < lane) begin
                    delay_pipe[lane][stage] <= delay_pipe[lane][stage-1];
                end
            end
        end
    end
end

generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_output
        if (g_lane == 0) begin : g_lane0
            assign vec_out[g_lane] = vec_in[g_lane];
        end
        else begin : g_delayed_lane
            assign vec_out[g_lane] = delay_pipe[g_lane][g_lane-1];
        end
    end
endgenerate

endmodule

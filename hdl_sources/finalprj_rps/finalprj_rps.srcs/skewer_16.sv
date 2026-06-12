`timescale 1ns / 1ps

// lane마다 지연을 다르게 줘서 PE array에 들어가는 타이밍을 맞추는 모듈
// lane 번호가 클수록 더 늦게 나가도록 skew를 만들어 줌
module skewer_16 #(
    parameter int N  = 16,
    parameter int DATA_W = 8
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic  en,
    input logic signed [DATA_W-1:0] vec_in  [0:N-1],
    output logic signed [DATA_W-1:0] vec_out [0:N-1]
);

// lane 0은 지연 없이 바로 나가고, lane L은 L cycle만큼 지연됨
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
                // 각 lane의 첫 지연 stage에 새 입력을 넣음
                delay_pipe[lane][0] <= vec_in[lane];
            end

            for (int stage = 1; stage < N; stage++) begin
                if (stage < lane) begin
                    // 필요한 stage까지만 한 칸씩 밀어 줌
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
            // 첫 lane은 skew가 필요 없어서 그대로 출력
            assign vec_out[g_lane] = vec_in[g_lane];
        end
        else begin : g_delayed_lane
            // 마지막으로 필요한 지연 stage를 출력으로 사용
            assign vec_out[g_lane] = delay_pipe[g_lane][g_lane-1];
        end
    end
endgenerate

endmodule

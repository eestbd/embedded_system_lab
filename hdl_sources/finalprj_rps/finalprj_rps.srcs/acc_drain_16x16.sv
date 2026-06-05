module acc_drain_16x16 #(
    parameter int N     = 16,
    parameter int ACC_W = 32
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         en,
    input  logic                         start,

    input  logic signed [ACC_W-1:0]      acc_mat [0:N-1][0:N-1],

    output logic signed [ACC_W-1:0]      row_vec [0:N-1],
    output logic                         row_valid,
    output logic [$clog2(N)-1:0]         row_idx_out,
    output logic                         busy,
    output logic                         done
);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_DRAIN,
    ST_DONE
} state_t;

state_t state;
logic [$clog2(N)-1:0] next_row_idx;

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state        <= ST_IDLE;
        row_valid    <= 1'b0;
        row_idx_out  <= '0;
        busy         <= 1'b0;
        done         <= 1'b0;
        next_row_idx <= '0;
        for (int col = 0; col < N; col++) begin
            row_vec[col] <= '0;
        end
    end
    else begin
        done <= 1'b0;

        if (en) begin
            case (state)
                // IDLE accepts start only here. A valid start immediately emits row 0.
                ST_IDLE: begin
                    row_valid <= 1'b0;
                    busy      <= 1'b0;

                    if (start) begin
                        row_valid   <= 1'b1;
                        row_idx_out <= '0;
                        busy        <= 1'b1;
                        for (int col = 0; col < N; col++) begin
                            row_vec[col] <= acc_mat[0][col];
                        end

                        if (N == 1) begin
                            state        <= ST_DONE;
                            next_row_idx <= '0;
                        end
                        else begin
                            state        <= ST_DRAIN;
                            next_row_idx <= 1'b1;
                        end
                    end
                end

                // DRAIN emits one accumulator row per enabled cycle.
                ST_DRAIN: begin
                    row_valid   <= 1'b1;
                    row_idx_out <= next_row_idx;
                    busy        <= 1'b1;
                    for (int col = 0; col < N; col++) begin
                        row_vec[col] <= acc_mat[next_row_idx][col];
                    end

                    if (next_row_idx == N-1) begin
                        state <= ST_DONE;
                    end
                    else begin
                        next_row_idx <= next_row_idx + 1'b1;
                    end
                end

                // DONE produces a one-cycle done pulse after the final valid row.
                ST_DONE: begin
                    row_valid <= 1'b0;
                    busy      <= 1'b0;
                    done      <= 1'b1;
                    state     <= ST_IDLE;
                end

                default: begin
                    state        <= ST_IDLE;
                    row_valid    <= 1'b0;
                    row_idx_out  <= '0;
                    busy         <= 1'b0;
                    next_row_idx <= '0;
                    for (int col = 0; col < N; col++) begin
                        row_vec[col] <= '0;
                    end
                end
            endcase
        end
    end
end

endmodule

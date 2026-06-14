`timescale 1ns / 1ps

// Drains the accumulator matrix from the PE array one row at a time
// After start, rows 0 through N-1 come out one per cycle
module acc_drain_16x16 #(
    parameter int N = 16,
    parameter int ACC_W = 32
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic en,
    input logic start,

    input logic signed [ACC_W-1:0] acc_mat [0:N-1][0:N-1],

    output logic signed [ACC_W-1:0] row_vec [0:N-1],
    output logic row_valid,
    output logic [$clog2(N)-1:0] row_idx_out,
    output logic busy,
    output logic done
);

// Small FSM for idle, row output, and done pulse
typedef enum logic [1:0] {
    ST_IDLE,
    ST_DRAIN,
    ST_DONE
} state_t;

state_t state;
logic [$clog2(N)-1:0] next_row_idx;

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        row_valid <= 1'b0;
        row_idx_out <= '0;
        busy <= 1'b0;
        done <= 1'b0;
        next_row_idx <= '0;
        for (int col = 0; col < N; col++) begin
            row_vec[col] <= '0;
        end
    end
    else begin
        done <= 1'b0;

        if (en) begin
            case (state)
                // Accept start only in IDLE and output row 0 right away
                ST_IDLE: begin
                    row_valid <= 1'b0;
                    busy <= 1'b0;

                    if (start) begin
                        row_valid <= 1'b1;
                        row_idx_out <= '0;
                        busy <= 1'b1;
                        for (int col = 0; col < N; col++) begin
                            row_vec[col] <= acc_mat[0][col];
                        end

                        // If N is 1, row 0 is already the last row
                        if (N == 1) begin
                            state <= ST_DONE;
                            next_row_idx <= '0;
                        end
                        else begin
                            state <= ST_DRAIN;
                            next_row_idx <= 1'b1;
                        end
                    end
                end

                // Output one accumulator row on each enabled cycle
                ST_DRAIN: begin
                    row_valid <= 1'b1;
                    row_idx_out <= next_row_idx;
                    busy <= 1'b1;
                    for (int col = 0; col < N; col++) begin
                        row_vec[col] <= acc_mat[next_row_idx][col];
                    end

                    // After the last row, the next cycle raises done
                    if (next_row_idx == N-1) begin
                        state <= ST_DONE;
                    end
                    else begin
                        next_row_idx <= next_row_idx + 1'b1;
                    end
                end

                // Raise done once, one cycle after the last valid row
                ST_DONE: begin
                    row_valid <= 1'b0;
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= ST_IDLE;
                end

                default: begin
                    // Fall back to IDLE if the state ever gets out of range
                    state <= ST_IDLE;
                    row_valid <= 1'b0;
                    row_idx_out <= '0;
                    busy <= 1'b0;
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

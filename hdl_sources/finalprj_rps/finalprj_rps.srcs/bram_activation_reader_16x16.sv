`timescale 1ns / 1ps

// Reads a 16x16 activation tile from BRAM and feeds it in PE-array order
// Caches 16 BRAM words first, then emits one k step at a time
module bram_activation_reader_16x16 #(
    parameter int N = 16,
    parameter int DATA_W = 8,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14
)(
    input logic clk,
    input logic rst,
    input logic clear,
    input logic start,
    input logic en,

    // 1 means the input tile is row-major from bram_init
    // 0 means an intermediate feature-major tile
    input logic row_major_layout,
    input logic [ADDR_W-1:0] act_base_addr,

    output logic bram_act_en,
    output logic [ADDR_W-1:0] bram_act_addr,
    input logic [WORD_W-1:0] bram_act_rdata,

    output logic raw_valid,
    output logic signed [DATA_W-1:0] raw_act_vec [0:N-1],

    output logic busy,
    output logic done
);

// Counter widths for N reads and N emits
localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int IDX_W = (N <= 1) ? 1 : $clog2(N);

// FSM order: request BRAM address, wait, capture, then emit
typedef enum logic [2:0] {
    ST_IDLE,
    ST_READ_ADDR_SET,
    ST_READ_WAIT,
    ST_READ_CAPTURE,
    ST_EMIT,
    ST_DONE
} state_t;

state_t state;

logic [COUNT_W-1:0] read_count;
logic [COUNT_W-1:0] emit_count;
logic [IDX_W-1:0] read_index;
logic [IDX_W-1:0] emit_index;

// Temporary buffer for the 16x16 activation tile read from BRAM
logic signed [DATA_W-1:0] tile_buf [0:N-1][0:N-1];

// DONE is a one-cycle state, and the other non-idle states count as busy
assign busy = (state != ST_IDLE) && (state != ST_DONE);
assign read_index = read_count[IDX_W-1:0];
assign emit_index = emit_count[IDX_W-1:0];

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state <= ST_IDLE;
        read_count <= '0;
        emit_count <= '0;
        bram_act_en <= 1'b0;
        bram_act_addr <= '0;
        raw_valid <= 1'b0;
        done <= 1'b0;
        for (int row = 0; row < N; row++) begin
            raw_act_vec[row] <= '0;
            for (int lane = 0; lane < N; lane++) begin
                tile_buf[row][lane] <= '0;
            end
        end
    end
    else if (en) begin
        bram_act_en <= 1'b0;
        raw_valid <= 1'b0;
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                read_count <= '0;
                emit_count <= '0;

                if (start) begin
                    state <= ST_READ_ADDR_SET;
                end
            end

            ST_READ_ADDR_SET: begin
                // Put only the BRAM address out in this stage
                // Data arrives after the next clock, so nothing is captured here
                bram_act_en <= 1'b1;
                bram_act_addr <= act_base_addr + read_count;
                state <= ST_READ_WAIT;
            end

            ST_READ_WAIT: begin
                // Wait one cycle to match synchronous BRAM latency
                state <= ST_READ_CAPTURE;
            end

            ST_READ_CAPTURE: begin
                // Store the 16 lanes from one word into the current read_index row
                for (int lane = 0; lane < N; lane++) begin
                    tile_buf[read_index][lane] <= bram_act_rdata[DATA_W*lane +: DATA_W];
                end

                if (read_count == N-1) begin
                    read_count <= '0;
                    emit_count <= '0;
                    state <= ST_EMIT;
                end
                else begin
                    read_count <= read_count + 1'b1;
                    state <= ST_READ_ADDR_SET;
                end
            end

            ST_EMIT: begin
                raw_valid <= 1'b1;
                for (int lane = 0; lane < N; lane++) begin
                    if (row_major_layout) begin
                        // For the input layer, each word is a row, so pull by k_inner vertically
                        raw_act_vec[lane] <= tile_buf[lane][emit_index];
                    end
                    else begin
                        // Intermediate layers are already feature-major, so use the stored row directly
                        raw_act_vec[lane] <= tile_buf[emit_index][lane];
                    end
                end

                if (emit_count == N-1) begin
                    emit_count <= '0;
                    state <= ST_DONE;
                end
                else begin
                    emit_count <= emit_count + 1'b1;
                end
            end

            ST_DONE: begin
                // Raise done for one cycle, then return to idle
                done <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                // Return to the initial state if an unexpected state is reached
                state <= ST_IDLE;
                read_count <= '0;
                emit_count <= '0;
                bram_act_en <= 1'b0;
                bram_act_addr <= '0;
                raw_valid <= 1'b0;
                done <= 1'b0;
            end
        endcase
    end
end

endmodule

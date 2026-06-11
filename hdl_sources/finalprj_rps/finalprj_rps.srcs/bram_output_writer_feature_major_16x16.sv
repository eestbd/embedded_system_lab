`timescale 1ns / 1ps

module bram_output_writer_feature_major_16x16 #(
    parameter int N      = 16,
    parameter int DATA_W = 8,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         en,
    input  logic                         start,

    input  logic [ADDR_W-1:0]            out_base_addr,

    input  logic                         in_valid,
    input  logic [$clog2(N)-1:0]         in_row_idx,
    input  logic signed [DATA_W-1:0]     in_vec [0:N-1],

    output logic                         bram_wr,
    output logic [ADDR_W-1:0]            bram_addr,
    output logic [WORD_W-1:0]            bram_wdata,

    output logic                         busy,
    output logic                         done
);

localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);
localparam int IDX_W   = (N <= 1) ? 1 : $clog2(N);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_CAPTURE,
    ST_WRITE,
    ST_DONE
} state_t;

state_t state;

logic [COUNT_W-1:0] capture_count;
logic [IDX_W-1:0]   write_col_idx;
logic [ADDR_W-1:0]  col_addr_offset;

logic signed [DATA_W-1:0] tile_buf [0:N-1][0:N-1];

assign busy = (state != ST_IDLE);

always_comb begin
    col_addr_offset = '0;
    col_addr_offset[IDX_W-1:0] = write_col_idx;
end

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state          <= ST_IDLE;
        capture_count  <= '0;
        write_col_idx  <= '0;
        bram_wr        <= 1'b0;
        bram_addr      <= '0;
        bram_wdata     <= '0;
        done           <= 1'b0;
        for (int row = 0; row < N; row++) begin
            for (int col = 0; col < N; col++) begin
                tile_buf[row][col] <= '0;
            end
        end
    end
    else if (!en) begin
        // Hold internal state and buffered data. Suppress one-cycle outputs.
        bram_wr <= 1'b0;
        done    <= 1'b0;
    end
    else begin
        bram_wr <= 1'b0;
        done    <= 1'b0;

        case (state)
            ST_IDLE: begin
                capture_count <= '0;
                write_col_idx <= '0;

                if (start) begin
                    state <= ST_CAPTURE;
                end
            end

            ST_CAPTURE: begin
                // Input arrives row-wise from post_processor:
                // in_vec[col] = C[in_row_idx][col].
                if (in_valid) begin
                    for (int col = 0; col < N; col++) begin
                        tile_buf[in_row_idx][col] <= in_vec[col];
                    end

                    if (capture_count == N-1) begin
                        capture_count <= '0;
                        write_col_idx <= '0;
                        state         <= ST_WRITE;
                    end
                    else begin
                        capture_count <= capture_count + 1'b1;
                    end
                end
            end

            ST_WRITE: begin
                // Store in feature-major layout for the next layer reader:
                // bram_wdata[8*row +: 8] = C[row][write_col_idx].
                bram_wr   <= 1'b1;
                bram_addr <= out_base_addr + col_addr_offset;
                for (int row = 0; row < N; row++) begin
                    bram_wdata[DATA_W*row +: DATA_W] <= tile_buf[row][write_col_idx];
                end

                if (write_col_idx == N-1) begin
                    write_col_idx <= '0;
                    state         <= ST_DONE;
                end
                else begin
                    write_col_idx <= write_col_idx + 1'b1;
                end
            end

            ST_DONE: begin
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state         <= ST_IDLE;
                capture_count <= '0;
                write_col_idx <= '0;
                bram_wr       <= 1'b0;
                bram_addr     <= '0;
                bram_wdata    <= '0;
                done          <= 1'b0;
            end
        endcase
    end
end

endmodule

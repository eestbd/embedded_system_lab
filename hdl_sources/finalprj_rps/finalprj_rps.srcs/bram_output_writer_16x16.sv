module bram_output_writer_16x16 #(
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
localparam int ROW_W   = (N <= 1) ? 1 : $clog2(N);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_ACTIVE,
    ST_DONE
} state_t;

state_t state;
logic [COUNT_W-1:0] write_count;
logic [ADDR_W-1:0] row_addr_offset;

assign busy = (state == ST_ACTIVE);

always_comb begin
    row_addr_offset = '0;
    row_addr_offset[ROW_W-1:0] = in_row_idx;
end

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state       <= ST_IDLE;
        write_count <= '0;
        bram_wr     <= 1'b0;
        bram_addr   <= '0;
        bram_wdata  <= '0;
        done        <= 1'b0;
    end
    else if (!en) begin
        // Hold state/count while suppressing write and done pulses.
        bram_wr <= 1'b0;
        done    <= 1'b0;
    end
    else begin
        bram_wr <= 1'b0;
        done    <= 1'b0;

        case (state)
            ST_IDLE: begin
                write_count <= '0;

                if (start) begin
                    state <= ST_ACTIVE;
                end
            end

            ST_ACTIVE: begin
                if (in_valid) begin
                    // Pack 16 signed int8 lanes into one 128-bit BRAM word.
                    // lane 0 -> [7:0], lane 1 -> [15:8], ..., lane 15 -> [127:120].
                    bram_wr   <= 1'b1;
                    bram_addr <= out_base_addr + row_addr_offset;
                    for (int lane = 0; lane < N; lane++) begin
                        bram_wdata[DATA_W*lane +: DATA_W] <= in_vec[lane];
                    end

                    // Count accepted valid rows. Addressing uses in_row_idx,
                    // while done is based on seeing N valid write rows.
                    if (write_count == N-1) begin
                        write_count <= '0;
                        state       <= ST_DONE;
                    end
                    else begin
                        write_count <= write_count + 1'b1;
                    end
                end
            end

            ST_DONE: begin
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state       <= ST_IDLE;
                write_count <= '0;
                bram_wr     <= 1'b0;
                bram_addr   <= '0;
                bram_wdata  <= '0;
                done        <= 1'b0;
            end
        endcase
    end
end

endmodule

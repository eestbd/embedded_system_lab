module bram_stream_reader_16x16 #(
    parameter int N      = 16,
    parameter int DATA_W = 8,
    parameter int WORD_W = 128,
    parameter int ADDR_W = 14
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         start,
    input  logic                         en,

    input  logic [ADDR_W-1:0]            act_base_addr,
    input  logic [ADDR_W-1:0]            wgt_base_addr,

    output logic                         bram_act_en,
    output logic [ADDR_W-1:0]            bram_act_addr,
    input  logic [WORD_W-1:0]            bram_act_rdata,

    output logic                         bram_wgt_en,
    output logic [ADDR_W-1:0]            bram_wgt_addr,
    input  logic [WORD_W-1:0]            bram_wgt_rdata,

    output logic                         raw_valid,
    output logic signed [DATA_W-1:0]     raw_act_vec [0:N-1],
    output logic signed [DATA_W-1:0]     raw_wgt_vec [0:N-1],

    output logic                         busy,
    output logic                         done
);

localparam int COUNT_W = (N <= 1) ? 1 : $clog2(N + 1);

typedef enum logic [1:0] {
    ST_IDLE,
    ST_ISSUE,
    ST_DRAIN,
    ST_DONE
} state_t;

state_t state;

logic [COUNT_W-1:0] issue_count;
logic [COUNT_W-1:0] valid_count;
logic               read_pending;

assign busy = (state != ST_IDLE) && (state != ST_DONE);

// BRAM words are little-lane ordered:
// word[7:0] -> lane 0, word[15:8] -> lane 1, ..., word[127:120] -> lane 15.
// raw_valid is delayed by one enabled cycle from address issue, matching a
// synchronous BRAM with one-cycle read latency.
generate
    genvar g_lane;
    for (g_lane = 0; g_lane < N; g_lane++) begin : g_unpack
        assign raw_act_vec[g_lane] = raw_valid ? bram_act_rdata[DATA_W*g_lane +: DATA_W] : '0;
        assign raw_wgt_vec[g_lane] = raw_valid ? bram_wgt_rdata[DATA_W*g_lane +: DATA_W] : '0;
    end
endgenerate

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state         <= ST_IDLE;
        issue_count   <= '0;
        valid_count   <= '0;
        read_pending  <= 1'b0;
        bram_act_en   <= 1'b0;
        bram_act_addr <= '0;
        bram_wgt_en   <= 1'b0;
        bram_wgt_addr <= '0;
        raw_valid     <= 1'b0;
        done          <= 1'b0;
    end
    else if (en) begin
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                issue_count  <= '0;
                valid_count  <= '0;
                read_pending <= 1'b0;
                bram_act_en  <= 1'b0;
                bram_wgt_en  <= 1'b0;
                raw_valid    <= 1'b0;

                if (start) begin
                    // Issue stream word 0. The corresponding BRAM rdata is
                    // considered valid on the next enabled clock.
                    bram_act_en   <= 1'b1;
                    bram_act_addr <= act_base_addr;
                    bram_wgt_en   <= 1'b1;
                    bram_wgt_addr <= wgt_base_addr;
                    read_pending  <= 1'b1;

                    if (N == 1) begin
                        issue_count <= '0;
                        state       <= ST_DRAIN;
                    end
                    else begin
                        issue_count <= 1;
                        state       <= ST_ISSUE;
                    end
                end
            end

            ST_ISSUE: begin
                // Emit data for the address issued one cycle earlier.
                raw_valid <= read_pending;
                if (read_pending) begin
                    valid_count <= valid_count + 1'b1;
                end

                // Issue the next activation/weight stream addresses.
                bram_act_en   <= 1'b1;
                bram_act_addr <= act_base_addr + issue_count;
                bram_wgt_en   <= 1'b1;
                bram_wgt_addr <= wgt_base_addr + issue_count;
                read_pending  <= 1'b1;

                if (issue_count == N-1) begin
                    issue_count <= '0;
                    state       <= ST_DRAIN;
                end
                else begin
                    issue_count <= issue_count + 1'b1;
                end
            end

            ST_DRAIN: begin
                // No more addresses are issued. The final pending BRAM word
                // becomes the last raw_valid output here.
                bram_act_en  <= 1'b0;
                bram_wgt_en  <= 1'b0;
                raw_valid    <= read_pending;
                read_pending <= 1'b0;

                if (read_pending) begin
                    if (valid_count == N-1) begin
                        valid_count <= '0;
                        state       <= ST_DONE;
                    end
                    else begin
                        valid_count <= valid_count + 1'b1;
                    end
                end
            end

            ST_DONE: begin
                raw_valid   <= 1'b0;
                bram_act_en <= 1'b0;
                bram_wgt_en <= 1'b0;
                done        <= 1'b1;
                state       <= ST_IDLE;
            end

            default: begin
                state         <= ST_IDLE;
                issue_count   <= '0;
                valid_count   <= '0;
                read_pending  <= 1'b0;
                bram_act_en   <= 1'b0;
                bram_act_addr <= '0;
                bram_wgt_en   <= 1'b0;
                bram_wgt_addr <= '0;
                raw_valid     <= 1'b0;
                done          <= 1'b0;
            end
        endcase
    end
end

endmodule

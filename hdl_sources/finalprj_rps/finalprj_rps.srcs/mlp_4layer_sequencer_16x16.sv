`timescale 1ns / 1ps

module mlp_4layer_sequencer_16x16 #(
    parameter int N           = 16,
    parameter int DATA_W      = 8,
    parameter int ACC_W       = 32,
    parameter int WORD_W      = 128,
    parameter int ADDR_W      = 14,
    parameter int SCALE_W     = 32,
    parameter int SCALE_FRAC  = 24,
    parameter int K_TILES_W   = 8,
    parameter int OUT_TILES_W = 8
)(
    input  logic                         clk,
    input  logic                         rst,
    input  logic                         clear,
    input  logic                         start,
    input  logic                         en,

    output logic                         bram_act_en,
    output logic [ADDR_W-1:0]            bram_act_addr,
    input  logic [WORD_W-1:0]            bram_act_rdata,

    output logic                         bram_wgt_en,
    output logic [ADDR_W-1:0]            bram_wgt_addr,
    input  logic [WORD_W-1:0]            bram_wgt_rdata,

    output logic                         bram_out_wr,
    output logic [ADDR_W-1:0]            bram_out_addr,
    output logic [WORD_W-1:0]            bram_out_wdata,

    output logic                         busy,
    output logic                         done
);

localparam logic [ADDR_W-1:0] W1_BASE       = 14'h0000;
localparam logic [ADDR_W-1:0] W2_BASE       = 14'h1800;
localparam logic [ADDR_W-1:0] W3_BASE       = 14'h1C00;
localparam logic [ADDR_W-1:0] W4_BASE       = 14'h2000;
localparam logic [ADDR_W-1:0] INPUT_BASE    = 14'h2400;
localparam logic [ADDR_W-1:0] SCRATCH0_BASE = 14'h2700;
localparam logic [ADDR_W-1:0] SCRATCH1_BASE = 14'h2780;
localparam logic [ADDR_W-1:0] FINAL_BASE    = 14'h2880;

localparam logic [ADDR_W-1:0] TILE_STRIDE = 14'd16;

localparam logic [SCALE_W-1:0] M1_Q24 = 32'd6073;
localparam logic [SCALE_W-1:0] M2_Q24 = 32'd24139;
localparam logic [SCALE_W-1:0] M3_Q24 = 32'd328223;
localparam logic [SCALE_W-1:0] M4_Q24 = 32'd16777216;

typedef enum logic [2:0] {
    ST_IDLE,
    ST_START_LAYER,
    ST_WAIT_LAYER_DONE,
    ST_NEXT_LAYER,
    ST_DONE
} state_t;

state_t state;

logic layer_start;
logic layer_busy;
logic layer_done;

logic [1:0] layer_idx;
logic [1:0] load_layer_idx;

logic [ADDR_W-1:0] current_act_base;
logic [ADDR_W-1:0] current_wgt_base;
logic [ADDR_W-1:0] current_out_base;
logic [ADDR_W-1:0] current_wgt_out_stride;
logic              current_act_layout_row_major;
logic              current_out_layout_row_major;
logic [K_TILES_W-1:0] current_num_k_tiles;
logic [OUT_TILES_W-1:0] current_num_out_tiles;
logic [SCALE_W-1:0] current_scale_q;

logic [ADDR_W-1:0] active_act_base;
logic [ADDR_W-1:0] active_wgt_base;
logic [ADDR_W-1:0] active_out_base;
logic [ADDR_W-1:0] active_wgt_out_stride;
logic              active_act_layout_row_major;
logic              active_out_layout_row_major;
logic [K_TILES_W-1:0] active_num_k_tiles;
logic [OUT_TILES_W-1:0] active_num_out_tiles;
logic [SCALE_W-1:0] active_scale_q;

assign busy = (state != ST_IDLE);
assign layer_start = en && (state == ST_START_LAYER);
assign load_layer_idx = (state == ST_NEXT_LAYER) ? (layer_idx + 1'b1) : layer_idx;

always_comb begin
    current_act_base       = INPUT_BASE;
    current_wgt_base       = W1_BASE;
    current_out_base       = SCRATCH0_BASE;
    current_wgt_out_stride = 14'd768;
    current_act_layout_row_major = 1'b1;
    current_out_layout_row_major = 1'b0;
    current_num_k_tiles    = 8'd48;
    current_num_out_tiles  = 8'd8;
    current_scale_q        = M1_Q24;

    case (load_layer_idx)
        2'd0: begin
            current_act_base       = INPUT_BASE;
            current_wgt_base       = W1_BASE;
            current_out_base       = SCRATCH0_BASE;
            current_wgt_out_stride = 14'd768; // 48 K tiles * 16 words
            current_act_layout_row_major = 1'b1; // input_spectrogram.bin is bram_init pre-tiled row-major
            current_out_layout_row_major = 1'b0;
            current_num_k_tiles    = 8'd48;
            current_num_out_tiles  = 8'd8;
            current_scale_q        = M1_Q24;
        end

        2'd1: begin
            current_act_base       = SCRATCH0_BASE;
            current_wgt_base       = W2_BASE;
            current_out_base       = SCRATCH1_BASE;
            current_wgt_out_stride = 14'd128; // 8 K tiles * 16 words
            current_act_layout_row_major = 1'b0; // intermediate activations are feature-major
            current_out_layout_row_major = 1'b0;
            current_num_k_tiles    = 8'd8;
            current_num_out_tiles  = 8'd8;
            current_scale_q        = M2_Q24;
        end

        2'd2: begin
            current_act_base       = SCRATCH1_BASE;
            current_wgt_base       = W3_BASE;
            current_out_base       = SCRATCH0_BASE;
            current_wgt_out_stride = 14'd128;
            current_act_layout_row_major = 1'b0;
            current_out_layout_row_major = 1'b0;
            current_num_k_tiles    = 8'd8;
            current_num_out_tiles  = 8'd8;
            current_scale_q        = M3_Q24;
        end

        2'd3: begin
            current_act_base       = SCRATCH0_BASE;
            current_wgt_base       = W4_BASE;
            current_out_base       = FINAL_BASE;
            current_wgt_out_stride = 14'd128;
            current_act_layout_row_major = 1'b0;
            current_out_layout_row_major = 1'b1; // final BRAM output is row-major for PS/Vitis.
            current_num_k_tiles    = 8'd8;
            current_num_out_tiles  = 8'd1;
            current_scale_q        = M4_Q24;
        end
    endcase
end

single_layer_engine_feature_major_16x16 #(
    .N          (N),
    .DATA_W     (DATA_W),
    .ACC_W      (ACC_W),
    .WORD_W     (WORD_W),
    .ADDR_W     (ADDR_W),
    .SCALE_W    (SCALE_W),
    .SCALE_FRAC (SCALE_FRAC),
    .K_TILES_W  (K_TILES_W),
    .OUT_TILES_W(OUT_TILES_W)
) u_layer_engine (
    .clk            (clk),
    .rst            (rst),
    .clear          (clear),
    .start          (layer_start),
    .en             (en),
    .act_base_addr  (active_act_base),
    .wgt_base_addr  (active_wgt_base),
    .out_base_addr  (active_out_base),
    .act_layout_row_major(active_act_layout_row_major),
    .out_layout_row_major(active_out_layout_row_major),
    .act_k_stride   (TILE_STRIDE),
    .wgt_k_stride   (TILE_STRIDE),
    .wgt_out_stride (active_wgt_out_stride),
    .out_tile_stride(TILE_STRIDE),
    .num_k_tiles    (active_num_k_tiles),
    .num_out_tiles  (active_num_out_tiles),
    .scale_q        (active_scale_q),
    .bram_act_en    (bram_act_en),
    .bram_act_addr  (bram_act_addr),
    .bram_act_rdata (bram_act_rdata),
    .bram_wgt_en    (bram_wgt_en),
    .bram_wgt_addr  (bram_wgt_addr),
    .bram_wgt_rdata (bram_wgt_rdata),
    .bram_out_wr    (bram_out_wr),
    .bram_out_addr  (bram_out_addr),
    .bram_out_wdata (bram_out_wdata),
    .busy           (layer_busy),
    .done           (layer_done)
);

always_ff @(posedge clk) begin
    if (rst || clear) begin
        state     <= ST_IDLE;
        layer_idx <= '0;
        done      <= 1'b0;
        active_act_base             <= '0;
        active_wgt_base             <= '0;
        active_out_base             <= '0;
        active_wgt_out_stride       <= '0;
        active_act_layout_row_major <= 1'b0;
        active_out_layout_row_major <= 1'b0;
        active_num_k_tiles          <= '0;
        active_num_out_tiles        <= '0;
        active_scale_q              <= '0;
    end
    else if (en) begin
        done <= 1'b0;

        case (state)
            ST_IDLE: begin
                layer_idx <= '0;

                if (start) begin
                    active_act_base             <= current_act_base;
                    active_wgt_base             <= current_wgt_base;
                    active_out_base             <= current_out_base;
                    active_wgt_out_stride       <= current_wgt_out_stride;
                    active_act_layout_row_major <= current_act_layout_row_major;
                    active_out_layout_row_major <= current_out_layout_row_major;
                    active_num_k_tiles          <= current_num_k_tiles;
                    active_num_out_tiles        <= current_num_out_tiles;
                    active_scale_q              <= current_scale_q;
                    state                       <= ST_START_LAYER;
                end
            end

            ST_START_LAYER: begin
                // One-cycle start pulse into the reusable layer engine.
                state <= ST_WAIT_LAYER_DONE;
            end

            ST_WAIT_LAYER_DONE: begin
                if (layer_done) begin
                    if (layer_idx == 2'd3) begin
                        state <= ST_DONE;
                    end
                    else begin
                        state <= ST_NEXT_LAYER;
                    end
                end
            end

            ST_NEXT_LAYER: begin
                layer_idx                   <= layer_idx + 1'b1;
                active_act_base             <= current_act_base;
                active_wgt_base             <= current_wgt_base;
                active_out_base             <= current_out_base;
                active_wgt_out_stride       <= current_wgt_out_stride;
                active_act_layout_row_major <= current_act_layout_row_major;
                active_out_layout_row_major <= current_out_layout_row_major;
                active_num_k_tiles          <= current_num_k_tiles;
                active_num_out_tiles        <= current_num_out_tiles;
                active_scale_q              <= current_scale_q;
                state                       <= ST_START_LAYER;
            end

            ST_DONE: begin
                done  <= 1'b1;
                state <= ST_IDLE;
            end

            default: begin
                state                       <= ST_IDLE;
                layer_idx                   <= '0;
                done                        <= 1'b0;
                active_act_base             <= '0;
                active_wgt_base             <= '0;
                active_out_base             <= '0;
                active_wgt_out_stride       <= '0;
                active_act_layout_row_major <= 1'b0;
                active_out_layout_row_major <= 1'b0;
                active_num_k_tiles          <= '0;
                active_num_out_tiles        <= '0;
                active_scale_q              <= '0;
            end
        endcase
    end
end

endmodule

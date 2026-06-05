`timescale 1ns/1ps

module finalprj_top (
    //ports : DO NOT MODIFY
    input   wire                    i_CLK,
    input   wire                    i_RST_n,

    input   wire                    i_PROC_START,
    output  logic                   o_PROC_DONE,

    input   wire                    S_AXI_ARESETN,
    input   wire    [31:0]          S_AXI_AWADDR,
    input   wire                    S_AXI_AWVALID,
    output  logic                   S_AXI_AWREADY,
    input   wire    [31:0]          S_AXI_WDATA,
    input   wire    [3:0]           S_AXI_WSTRB,
    input   wire                    S_AXI_WVALID,
    output  logic                   S_AXI_WREADY,
    output  wire    [1:0]           S_AXI_BRESP,
    output  logic                   S_AXI_BVALID,
    input   wire                    S_AXI_BREADY,
    input   wire    [31:0]          S_AXI_ARADDR,
    input   wire                    S_AXI_ARVALID,
    output  logic                   S_AXI_ARREADY,
    output  logic   [31:0]          S_AXI_RDATA,
    output  wire    [1:0]           S_AXI_RRESP,
    output  logic                   S_AXI_RVALID,
    input   wire                    S_AXI_RREADY
);



//=========================================================================
// BRAM instance : You can freely configure ports A and B
//=========================================================================

logic   [13:0]                  ctrl_pa_addr;
logic                           ctrl_pa_wr;
logic   [127:0]                 ctrl_pa_wdata;
logic   [127:0]                 ctrl_pa_rdata;
logic                           ctrl_pa_busy;

logic   [13:0]                  ctrl_pb_addr;
logic                           ctrl_pb_wr;
logic   [127:0]                 ctrl_pb_wdata;
logic   [127:0]                 ctrl_pb_rdata;

BRAM_TDP #(
    .INIT_FILE          ("C:/Users/super/Workspace/Embedded_System_Lab/hdl_sources/finalprj_rps/finalprj_rps.srcs/bram_init.txt"            )
) u_bram (
    //Port A - I/O path  (read input matrix, write output matrix) + AXI
    .i_PA_ADDR          (ctrl_pa_addr               ),
    .i_PA_WR            (ctrl_pa_wr                 ),
    .i_PA_WDATA         (ctrl_pa_wdata              ),
    .o_PA_RDATA         (ctrl_pa_rdata              ),
    .o_PA_BUSY          (ctrl_pa_busy               ),

    //Port B - weight path  (read only from RTL side)
    .i_PB_ADDR          (ctrl_pb_addr               ),
    .i_PB_WR            (ctrl_pb_wr                 ),
    .i_PB_WDATA         (ctrl_pb_wdata              ),
    .o_PB_RDATA         (ctrl_pb_rdata              ),

    //AXI4-Lite pass-through : DO NOT MODIFY FROM HERE
    .i_CLK              (i_CLK                      ),
    .i_RST_n            (S_AXI_ARESETN              ),

    .S_AXI_AWADDR       (S_AXI_AWADDR               ),
    .S_AXI_AWVALID      (S_AXI_AWVALID              ),
    .S_AXI_AWREADY      (S_AXI_AWREADY              ),
    .S_AXI_WDATA        (S_AXI_WDATA                ),
    .S_AXI_WSTRB        (S_AXI_WSTRB                ),
    .S_AXI_WVALID       (S_AXI_WVALID               ),
    .S_AXI_WREADY       (S_AXI_WREADY               ),
    .S_AXI_BRESP        (S_AXI_BRESP                ),
    .S_AXI_BVALID       (S_AXI_BVALID               ),
    .S_AXI_BREADY       (S_AXI_BREADY               ),
    .S_AXI_ARADDR       (S_AXI_ARADDR               ),
    .S_AXI_ARVALID      (S_AXI_ARVALID              ),
    .S_AXI_ARREADY      (S_AXI_ARREADY              ),
    .S_AXI_RDATA        (S_AXI_RDATA                ),
    .S_AXI_RRESP        (S_AXI_RRESP                ),
    .S_AXI_RVALID       (S_AXI_RVALID               ),
    .S_AXI_RREADY       (S_AXI_RREADY               )
);



//=========================================================================
// CONTROL instance : Write your own control module
//=========================================================================

CONTROL u_ctrl (
    .i_CLK              (i_CLK                      ),
    .i_RST_n            (i_RST_n                    ),

    .i_PROC_START       (i_PROC_START               ),
    .o_PROC_DONE        (o_PROC_DONE                ),

    .o_PA_ADDR          (ctrl_pa_addr               ),
    .o_PA_WR            (ctrl_pa_wr                 ),
    .o_PA_WDATA         (ctrl_pa_wdata              ),
    .i_PA_RDATA         (ctrl_pa_rdata              ),
    .i_PA_BUSY          (ctrl_pa_busy               ),

    .o_PB_ADDR          (ctrl_pb_addr               ),
    .o_PB_WR            (ctrl_pb_wr                 ),
    .o_PB_WDATA         (ctrl_pb_wdata              ),
    .i_PB_RDATA         (ctrl_pb_rdata              )
);

endmodule



//=========================================================================
// CONTROLLER: You can save it as a separate file
//=========================================================================

module CONTROL (
    /* CLOCK AND RESET */
    input   wire                    i_CLK,
    input   wire                    i_RST_n,

    input   wire                    i_PROC_START,
    output  logic                   o_PROC_DONE,

    output  logic   [13:0]          o_PA_ADDR,
    output  logic                   o_PA_WR,
    output  logic   [127:0]         o_PA_WDATA,
    input   wire    [127:0]         i_PA_RDATA,
    input   wire                    i_PA_BUSY,

    output  logic   [13:0]          o_PB_ADDR,
    output  logic                   o_PB_WR,
    output  logic   [127:0]         o_PB_WDATA,
    input   wire    [127:0]         i_PB_RDATA
);

//=========================================================================
// Basic useful parameters
//=========================================================================

localparam int unsigned TOTAL_LAYERS = 4;
localparam int unsigned BATCH_SIZE = 16;
localparam int unsigned SYSTOLIC_SIZE = 16;

localparam int unsigned W_DIMS [TOTAL_LAYERS][2] = '{
//   ROWS  COLS
    '{128,  768},
    '{128,  128},
    '{128,  128},
    '{16,   128}
};

function automatic int unsigned calc_idim(int unsigned layer, dim);
    if(dim == 0)       return BATCH_SIZE;         //ROWS: always the batch size
    else begin                                    //COLS: input features for this layer
        if(layer == 0) return W_DIMS[0][1];       //   | first layer: matches W COLS
        else           return W_DIMS[layer-1][0]; //   | subsequent layers: prev W ROWS
    end
endfunction

localparam int unsigned I_DIMS [TOTAL_LAYERS+1][2] = '{
//   ROWS            COLS
    '{calc_idim(0,0), calc_idim(0,1)},  //{16, 768}
    '{calc_idim(1,0), calc_idim(1,1)},  //{16, 128}
    '{calc_idim(2,0), calc_idim(2,1)},  //{16, 128}
    '{calc_idim(3,0), calc_idim(3,1)},  //{16, 128}
    '{calc_idim(4,0), calc_idim(4,1)}   //{16, 16}
};

//weight base address
localparam int unsigned W_BADDR [TOTAL_LAYERS] = '{
    32'h0000_0000,
    32'h0000_1800,
    32'h0000_1C00,
    32'h0000_2000
};

//input base address
localparam int unsigned I_BADDR [TOTAL_LAYERS] = '{
    32'h0000_2400,
    32'h0000_2700,
    32'h0000_2780,
    32'h0000_2800
};

//output base address
localparam int unsigned O_BADDR [TOTAL_LAYERS] = '{
    I_BADDR[1],
    I_BADDR[2],
    I_BADDR[3],
    32'h0000_2880
};

/*
    M1 = 0.00036199 x 2^32
    M2 = 0.00143881 x 2^32
    M3 = 0.01956364 x 2^32
    M4 = 1.00000000 x 2^32
*/
localparam int unsigned PP_SCALER [TOTAL_LAYERS] = '{
    32'h0017_B92F,
    32'h005E_4B3A,
    32'h0502_1F6A,
    32'hFFFF_FFFF //roughly 1.0
};

// First BRAM read probe for bring-up: input spectrogram base address.
localparam logic [13:0] INPUT_SPECTROGRAM_BADDR = 14'h2400;

typedef enum logic [2:0] {
    ST_IDLE,
    ST_READ_ADDR_SET,
    ST_READ_WAIT,
    ST_READ_CAPTURE,
    ST_DONE
} state_t;

state_t         r_state;
logic [127:0]  r_pa_read_data_capture;
logic          r_pa_read_data_valid;

always_ff @(posedge i_CLK or negedge i_RST_n) begin
    if (!i_RST_n) begin
        r_state                <= ST_IDLE;
        o_PROC_DONE            <= 1'b0;

        o_PA_ADDR              <= 14'd0;
        o_PA_WR                <= 1'b0;
        o_PA_WDATA             <= 128'd0;

        o_PB_ADDR              <= 14'd0;
        o_PB_WR                <= 1'b0;
        o_PB_WDATA             <= 128'd0;

        r_pa_read_data_capture <= 128'd0;
        r_pa_read_data_valid   <= 1'b0;
    end
    else begin
        o_PROC_DONE          <= 1'b0;
        o_PA_WR              <= 1'b0;
        o_PA_WDATA           <= 128'd0;
        o_PB_ADDR            <= 14'd0;
        o_PB_WR              <= 1'b0;
        o_PB_WDATA           <= 128'd0;
        r_pa_read_data_valid <= 1'b0;

        case (r_state)
            ST_IDLE: begin
                o_PA_ADDR <= 14'd0;

                if (i_PROC_START) begin
                    o_PA_ADDR <= INPUT_SPECTROGRAM_BADDR;
                    r_state   <= ST_READ_ADDR_SET;
                end
            end

            ST_READ_ADDR_SET: begin
                o_PA_ADDR <= INPUT_SPECTROGRAM_BADDR;

                if (!i_PA_BUSY) begin
                    r_state <= ST_READ_WAIT;
                end
            end

            ST_READ_WAIT: begin
                o_PA_ADDR <= INPUT_SPECTROGRAM_BADDR;
                r_state   <= ST_READ_CAPTURE;
            end

            ST_READ_CAPTURE: begin
                o_PA_ADDR              <= INPUT_SPECTROGRAM_BADDR;
                r_pa_read_data_capture <= i_PA_RDATA;
                r_pa_read_data_valid   <= 1'b1;
                r_state                <= ST_DONE;
            end

            ST_DONE: begin
                o_PA_ADDR   <= INPUT_SPECTROGRAM_BADDR;
                o_PROC_DONE <= 1'b1;
            end

            default: begin
                r_state <= ST_IDLE;
            end
        endcase
    end
end

endmodule
















//=========================================================================
// AXI BRAM MODULE : DO NOT MODIFY
//=========================================================================

module BRAM_TDP #(
    parameter INIT_FILE = "C:/Users/super/Workspace/Embedded_System_Lab/hdl_sources/finalprj_rps/finalprj_rps.srcs/bram_init.txt"
)(
    input   wire                i_CLK,
    input   wire                i_RST_n,
 
    //---- Port A : RTL read / write ----
    input   wire    [13:0]      i_PA_ADDR,
    input   wire                i_PA_WR,
    input   wire    [127:0]     i_PA_WDATA,
    output  logic   [127:0]     o_PA_RDATA,
    output  wire                o_PA_BUSY,      //AXI owns port A this cycle
 
    //---- Port B : RTL read / write ----
    input   wire    [13:0]      i_PB_ADDR,
    input   wire                i_PB_WR,
    input   wire    [127:0]     i_PB_WDATA,
    output  logic   [127:0]     o_PB_RDATA,
 
    //---- AXI4-Lite Slave (32-bit data) ----
    input   wire    [31:0]      S_AXI_AWADDR,
    input   wire                S_AXI_AWVALID,
    output  logic               S_AXI_AWREADY,
    input   wire    [31:0]      S_AXI_WDATA,
    input   wire    [3:0]       S_AXI_WSTRB,
    input   wire                S_AXI_WVALID,
    output  logic               S_AXI_WREADY,
    output  wire    [1:0]       S_AXI_BRESP,
    output  logic               S_AXI_BVALID,
    input   wire                S_AXI_BREADY,
    input   wire    [31:0]      S_AXI_ARADDR,
    input   wire                S_AXI_ARVALID,
    output  logic               S_AXI_ARREADY,
    output  logic   [31:0]      S_AXI_RDATA,
    output  wire    [1:0]       S_AXI_RRESP,
    output  logic               S_AXI_RVALID,
    input   wire                S_AXI_RREADY
);
 
assign S_AXI_BRESP = 2'b00;   //OKAY
assign S_AXI_RRESP = 2'b00;
 
 
//=========================================================================
// Memory array  (Vivado byte-write-enable inference pattern)
//=========================================================================
 
(* ram_style = "block" *)
logic [127:0] mem [0:(1<<14)-1];
 
initial $readmemh(INIT_FILE, mem);
 
 
//=========================================================================
// AXI4-Lite write channel FSM
//=========================================================================
 
logic        aw_fire, w_fire;
logic [13:0] axi_waddr;
logic [1:0]  axi_wlane;
logic        axi_wr_pending;     //write data captured, issue to port A
logic [15:0] axi_wbe;            //byte-write-enable (16 bytes)
logic [127:0] axi_wdata_128;     //write data spread to 128-bit
 
assign aw_fire = S_AXI_AWVALID & S_AXI_AWREADY;
assign w_fire  = S_AXI_WVALID  & S_AXI_WREADY;
 
always_ff @(posedge i_CLK) begin
    if (!i_RST_n) begin
        S_AXI_AWREADY  <= 1'b1;
        S_AXI_WREADY   <= 1'b1;
        S_AXI_BVALID   <= 1'b0;
        axi_wr_pending  <= 1'b0;
    end
    else begin
        //Accept AW
        if (aw_fire) begin
            axi_waddr     <= S_AXI_AWADDR[17:4];
            axi_wlane     <= S_AXI_AWADDR[3:2];
            S_AXI_AWREADY <= 1'b0;
        end
 
        //Accept W
        if (w_fire) begin
            S_AXI_WREADY <= 1'b0;
        end
 
        //Both AW and W received -> issue write next cycle
        if ((!S_AXI_AWREADY || aw_fire) && (!S_AXI_WREADY || w_fire)
            && !axi_wr_pending && !S_AXI_BVALID) begin
 
            logic [1:0] lane;
            lane = aw_fire ? S_AXI_AWADDR[3:2] : axi_wlane;
 
            //Build byte-enable and data vectors
            axi_wbe       <= '0;
            axi_wdata_128 <= '0;
            for (int i = 0; i < 4; i++) begin
                axi_wbe      [lane*4 + i] <= S_AXI_WSTRB[i];
                axi_wdata_128[(lane*4 + i)*8 +: 8] <= S_AXI_WDATA[i*8 +: 8];
            end
            axi_wr_pending <= 1'b1;
        end
 
        //Write has been issued to BRAM -> respond
        if (axi_wr_pending) begin
            axi_wr_pending <= 1'b0;
            S_AXI_BVALID   <= 1'b1;
        end
 
        //B handshake complete
        if (S_AXI_BVALID && S_AXI_BREADY) begin
            S_AXI_BVALID  <= 1'b0;
            S_AXI_AWREADY <= 1'b1;
            S_AXI_WREADY  <= 1'b1;
        end
    end
end
 
 
//=========================================================================
// AXI4-Lite read channel FSM
//=========================================================================
 
logic        axi_rd_pending;
logic        axi_rd_wait;    // extra pipeline stage: holds address while waiting for BRAM registered output
logic [13:0] axi_raddr;
logic [1:0]  axi_rlane;
 
always_ff @(posedge i_CLK) begin
    if (!i_RST_n) begin
        S_AXI_ARREADY  <= 1'b1;
        S_AXI_RVALID   <= 1'b0;
        axi_rd_pending <= 1'b0;
        axi_rd_wait    <= 1'b0;
    end
    else begin
        //Accept AR
        if (S_AXI_ARVALID && S_AXI_ARREADY) begin
            axi_raddr      <= S_AXI_ARADDR[17:4];
            axi_rlane      <= S_AXI_ARADDR[3:2];
            S_AXI_ARREADY  <= 1'b0;
            axi_rd_pending <= 1'b1;
        end
 
        // Stage 1 ?? axi_rd_pending: axi_raddr is now driving pa_addr.
        // The BRAM address input is stable; its registered output (o_PA_RDATA)
        // will reflect this address only AFTER the next rising edge.
        // Do NOT capture o_PA_RDATA here ?? it still holds the previous address's data.
        if (axi_rd_pending) begin
            axi_rd_pending <= 1'b0;
            axi_rd_wait    <= 1'b1;   // wait one more cycle for BRAM latency
        end
 
        // Stage 2 ?? axi_rd_wait: o_PA_RDATA now holds valid data for axi_raddr.
        // Capture it and assert RVALID.
        if (axi_rd_wait) begin
            axi_rd_wait    <= 1'b0;
            S_AXI_RVALID   <= 1'b1;
            case (axi_rlane)
                2'd0: S_AXI_RDATA <= o_PA_RDATA[ 31:  0];
                2'd1: S_AXI_RDATA <= o_PA_RDATA[ 63: 32];
                2'd2: S_AXI_RDATA <= o_PA_RDATA[ 95: 64];
                2'd3: S_AXI_RDATA <= o_PA_RDATA[127: 96];
            endcase
        end
 
        //R handshake complete
        if (S_AXI_RVALID && S_AXI_RREADY) begin
            S_AXI_RVALID  <= 1'b0;
            S_AXI_ARREADY <= 1'b1;
        end
    end
end
 
 
//=========================================================================
// Port A mux : AXI has absolute priority over RTL read
//=========================================================================
 
wire        pa_axi_active = axi_wr_pending | axi_rd_pending | axi_rd_wait;
assign      o_PA_BUSY     = pa_axi_active;
 
wire [13:0] pa_addr = pa_axi_active ? (axi_wr_pending ? axi_waddr : axi_raddr)
                                    : i_PA_ADDR;
 
//=========================================================================
// Port A : BRAM read + byte-write  (Vivado inference pattern)
//=========================================================================
 
always_ff @(posedge i_CLK) begin
    //Byte-granularity write (AXI - absolute priority)
    if (axi_wr_pending) begin
        for (int i = 0; i < 16; i++) begin
            if (axi_wbe[i])
                mem[pa_addr][i*8 +: 8] <= axi_wdata_128[i*8 +: 8];
        end
    end
    //Full-width write (RTL - only when AXI is idle)
    else if (i_PA_WR && !pa_axi_active) begin
        mem[pa_addr] <= i_PA_WDATA;
    end
    //Synchronous read (always - read-first mode)
    o_PA_RDATA <= mem[pa_addr];
end
 
 
//=========================================================================
// Port B : BRAM read / write  (RTL only)
//=========================================================================
 
always_ff @(posedge i_CLK) begin
    if (i_PB_WR) begin
        mem[i_PB_ADDR] <= i_PB_WDATA;
    end
    o_PB_RDATA <= mem[i_PB_ADDR];
end
 
 
endmodule

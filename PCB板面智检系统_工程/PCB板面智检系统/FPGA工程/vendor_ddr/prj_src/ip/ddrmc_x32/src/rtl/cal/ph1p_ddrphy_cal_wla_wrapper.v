
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_wla_wrapper 
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module  ph1p_ddrphy_cal_wla_wrapper #(
    parameter DX_NUM     = 2
)(
    input                       clk        ,
    input                       rst_n      ,

    input                       start      ,
    output reg                  done       ,
    output reg                  err        ,

    output reg [DX_NUM* 9-1:0]  dcp_code   ,
    output reg [DX_NUM* 4-1:0]  dcp_type   ,
    output reg [DX_NUM   -1:0]  dcp_vld    ,
    output reg [DX_NUM   -1:0]  dcp_inc    ,
    input      [DX_NUM   -1:0]  dcp_rdy    ,

    input      [DX_NUM* 4-1:0]  cur_wsl    ,
    output reg [DX_NUM* 4-1:0]  wsl_o      ,

    input      [DX_NUM* 9-1:0]  dly_cur    ,

    output reg                  cmd_vld    ,
    output reg [         31:0]  cmd_code   ,

    input                       wdata_en   ,
    output     [DX_NUM*64-1:0]  wdata      ,
    output     [DX_NUM* 8-1:0]  wmask      ,
    input      [DX_NUM   -1:0]  rdata_vld  ,
    input      [DX_NUM*64-1:0]  rdata      ,
    
    output     [DX_NUM*64-1:0]  dbg_rdata_x0,
    output     [DX_NUM*64-1:0]  dbg_rdata_x1,
    output     [DX_NUM*64-1:0]  dbg_rdata_x2,
    output     [DX_NUM*64-1:0]  dbg_rdata_x3

);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
// op_code
localparam [3:0] CMD_PRE = 4'b1010;
localparam [3:0] CMD_ACT = 4'b0011;
localparam [3:0] CMD_WR  = 4'b1100;
localparam [3:0] CMD_RD  = 4'b1101;

// State
localparam [3:0] S_IDLE  = 4'b0000;
localparam [3:0] S_CFG   = 4'b0001;
localparam [3:0] S_PRE   = 4'b0010;
localparam [3:0] S_ACT   = 4'b0011;
localparam [3:0] S_WR    = 4'b0100;
localparam [3:0] S_RD    = 4'b0101;
localparam [3:0] S_WAIT  = 4'b0110;
localparam [3:0] S_DONE  = 4'b1000;

`ifdef PH1P_DDRPHY_SIM
localparam [5:0] SAMPLE_MAX = 6'h08;
`else
localparam [5:0] SAMPLE_MAX = 6'h20;
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Internal Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [       1:0] start_r;
wire              start_pos;
reg  [       3:0] state;
reg  [       3:0] state_pre;
reg  [       4:0] wait_cnt; 

reg  [       1:0] dcp_rdy_r;
wire              dcp_rdy_pos;

reg               find_match;

wire [DX_NUM-1:0] find_match_dx;

wire [DX_NUM*9-1:0] dly_cal;
wire [DX_NUM*4-1:0] wsl_cal;
reg  [DX_NUM*4-1:0] wsl_int;

wire [DX_NUM  -1:0] wla_err;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Control Pulse Gen
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        start_r <= 2'b00;
    end else begin
        start_r <= {start_r[0], start};
    end
end

assign start_pos = (start_r[1:0] == 2'b01);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dcp_rdy_r <= 2'b00;
    end else begin
        dcp_rdy_r <= {dcp_rdy_r[0], &dcp_rdy};
    end
end

assign dcp_rdy_pos = (dcp_rdy_r[1:0] == 2'b01);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  FSM
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        state <= S_IDLE ;
    end else begin
        case (state) 
            ///////////////////////////////////////////////////////////////////////////////////////
            S_IDLE : begin
                state <= (start_pos == 1'b1) ? S_CFG : S_IDLE;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_CFG  : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_PRE  : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_ACT  : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_WR   : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_RD   : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_WAIT : begin
                state <= ((wait_cnt == 5'h0) && (err       == 1'b1  )                         ) ? S_DONE :
                         ((wait_cnt == 5'h0) && (state_pre == S_CFG ) && (dcp_rdy_pos == 1'b1)) ? S_PRE  :
                         ((wait_cnt == 5'h0) && (state_pre == S_PRE )                         ) ? find_match ? S_DONE : S_ACT  :
                         ((wait_cnt == 5'h0) && (state_pre == S_ACT )                         ) ? S_WR   :
                         ((wait_cnt == 5'h0) && (state_pre == S_WR  )                         ) ? S_RD   :
                         ((wait_cnt == 5'h0) && (state_pre == S_RD  )                         ) ? S_CFG  : S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_DONE : begin
                state <= S_DONE;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            default : begin
                state <= S_IDLE; 
            end
        endcase
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        state_pre <= S_IDLE ;
    end else begin
        state_pre <= (state == S_CFG ) ? state :
                     (state == S_PRE ) ? state :
                     (state == S_ACT ) ? state :
                     (state == S_WR  ) ? state :
                     (state == S_RD  ) ? state :
                     (state == S_DONE) ? state : state_pre;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  CNT
///////////////////////////////////////////////////////////////////////////////////////////////////
wire       ld_cnt;
wire [4:0] ld_cnt_code;

assign ld_cnt      = (state == S_CFG) || (state == S_PRE) || (state == S_ACT) || (state == S_WR) || (state == S_RD);
assign ld_cnt_code = (state == S_CFG) ? 5'h0f :
                     (state == S_PRE) ? 5'h0f :
                     (state == S_ACT) ? 5'h0f :
                     (state == S_WR ) ? 5'h0f :
                     (state == S_RD ) ? 5'h18 : 5'h0f;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        wait_cnt <= 5'h0;
    end else if (ld_cnt && (wait_cnt == 5'h0)) begin
        wait_cnt <= ld_cnt_code;
    end else begin
        wait_cnt <= (wait_cnt == 5'h0) ? 5'h0 : (wait_cnt - 1'b1);
    end
end


///////////////////////////////////////////////////////////////////////////////////////////////////
//  DX Instance
///////////////////////////////////////////////////////////////////////////////////////////////////
genvar n, b, p;
generate
for (n = 0; n < DX_NUM; n = n+1) begin : dx_wla
ph1p_ddrphy_cal_wla #(
    .SAMPLE_MAX   ( SAMPLE_MAX )
) u_cal_wla (
    .clk          ( clk                    ),
    .rst_n        ( rst_n                  ),

    .start        ( start                  ),

    .wdata_en     ( wdata_en               ),
    .wdata        ( wdata       [n*64+: 64]),
    .wmask        ( wmask       [n* 8+:  8]),
    .rdata_vld    ( rdata_vld   [n]        ),
    .rdata        ( rdata       [n*64+: 64]),

    .find_match   ( find_match_dx[n]       ),

    .cur_wsl      ( cur_wsl     [n*4 +: 4] ),
    .cal_wsl      ( wsl_cal     [n*4 +: 4] ),

    .err          ( wla_err     [n]        ),

    .dbg_rdata_x0 ( dbg_rdata_x0[n*64 +: 64]),
    .dbg_rdata_x1 ( dbg_rdata_x1[n*64 +: 64]),
    .dbg_rdata_x2 ( dbg_rdata_x2[n*64 +: 64]),
    .dbg_rdata_x3 ( dbg_rdata_x3[n*64 +: 64])
);
end
endgenerate

for (n = 0; n <= DX_NUM-1; n = n+1) begin : dx_dcp
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dcp_inc [n]        <=  1'b0;
        dcp_vld [n]        <=  1'b0;
        dcp_type[n*4 +: 4] <=  4'b0100;
        dcp_code[n*9 +: 9] <=  1'b0;
        wsl_o   [n*4 +: 4] <=  4'h0;
    end else if (state == S_CFG) begin
        dcp_vld [n]        <=  1'b1;
        dcp_code[n*9 +: 9] <=  dly_cur[n*9 +: 9];
        wsl_o   [n*4 +: 4] <=  find_match_dx[n] ? wsl_cal[n*4 +: 4] : wsl_int[n*4 +: 4];
    end else begin
        dcp_vld [n]        <=  1'b0;
    end
end
end

for (n = 0; n <= DX_NUM-1; n = n+1) begin : dx_wsl_ctl
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        wsl_int[n*4 +: 4] <= 4'h0;
    end else if (start_pos == 1'b1) begin
        wsl_int[n*4 +: 4] <= cur_wsl[n*4 +: 4];
    end else if (rdata_vld[n] == 1'b1) begin
        wsl_int[n*4 +: 4] <= wsl_int[n*4 +: 4] + 2'b10;
    end
end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  CMD Gen
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        cmd_vld  <=  1'b0;
        cmd_code <= 32'b0;
    end else if (state == S_PRE) begin
        cmd_vld  <= 1'b1 ;
        cmd_code <= {CMD_PRE, 4'b0000, 4'b0000, 20'h00400};
    end else if (state == S_ACT) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_ACT, 4'b0000, 4'b0000, 20'h00000};
    end else if (state == S_WR ) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_WR,  4'b0000, 4'b0000, 20'h00000};
    end else if (state == S_RD ) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_RD,  4'b0000, 4'b0000, 20'h00000};
    end else begin
        cmd_vld  <=  1'b0;
        cmd_code <= 32'b0;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_match <= 1'b0;
    end else begin
        find_match <= &find_match_dx;
    end
end

//  Write Latency Adjust Done
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        done <= 1'b0;
    end else if (state == S_DONE) begin
        done <= 1'b1;
    end
end

//  Write Latency Adjust Error
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err <= 1'b0;
    end else if (|wla_err == 1'b1) begin
        err <= 1'b1;
    end
end


endmodule

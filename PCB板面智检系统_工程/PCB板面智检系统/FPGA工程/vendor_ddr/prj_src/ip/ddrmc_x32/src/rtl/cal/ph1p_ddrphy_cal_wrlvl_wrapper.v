
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_wrlvl_wrapper 
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module  ph1p_ddrphy_cal_wrlvl_wrapper #(
    parameter DX_NUM     = 2
)(
    input                       clk        ,
    input                       rst_n      ,

    input      [DX_NUM*9-1:0]   ui         ,

    input                       start      ,
    output reg                  done       ,
    output reg                  err        ,

    output reg [DX_NUM*9-1:0]   dcp_code   ,
    output reg [DX_NUM*4-1:0]   dcp_type   ,
    output reg [DX_NUM  -1:0]   dcp_vld    ,
    output reg [DX_NUM  -1:0]   dcp_inc    ,
    input      [DX_NUM  -1:0]   dcp_rdy    ,

    input      [DX_NUM*9-1:0]   dly_cur    ,

    input      [DX_NUM*4-1:0]   cur_wsl    ,
    output reg [DX_NUM*4-1:0]   wsl_o      ,

    output reg                  cmd_vld    ,
    output reg [        31:0]   cmd_code   ,

    // wrlvl
    output reg                  wrlvl_en   ,
    input      [DX_NUM  -1:0]   wrlvl_din  ,
    input      [        12:0]   mr1_set     
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
// op_code
localparam [3:0] CMD_MRS = 4'b1000;
localparam [3:0] CMD_WR  = 4'b1100;

// State
localparam [3:0] S_IDLE  = 4'b0000;
localparam [3:0] S_MRS   = 4'b0001;
localparam [3:0] S_CFG   = 4'b0010;
localparam [3:0] S_WDQS  = 4'b0011;
localparam [3:0] S_WAIT  = 4'b0100;
localparam [3:0] S_DONE  = 4'b1000;

`ifdef PH1P_DDRPHY_SIM
localparam [5:0] SAMPLE_MAX = 6'h08;
`else
localparam [5:0] SAMPLE_MAX = 6'h20;
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Internal Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////

reg  [       3:0] state;
reg  [       3:0] state_pre;
reg  [       3:0] wait_cnt; 
reg  [       5:0] sample_cnt;

wire              check;

reg  [       1:0] dcp_rdy_r;
wire              dcp_rdy_pos;

reg               dly_mode; // 0 load, 1 inc

reg               find_s0;
reg               find_s1;

wire [DX_NUM-1:0] find_s0_dx;
wire [DX_NUM-1:0] find_s1_dx;

wire [DX_NUM*9-1:0] dly_cal;
wire [DX_NUM*4-1:0] wsl_cal;

wire [DX_NUM  -1:0] wrlvl_err;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dcp_rdy_r <= 2'b00;
    end else begin
        dcp_rdy_r <= {dcp_rdy_r[0], &dcp_rdy};
    end
end

assign dcp_rdy_pos = (dcp_rdy_r[0] == 1'b1) & (dcp_rdy_r[1] == 1'b0);

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
                state <= (start == 1'b1) ? S_MRS : S_IDLE;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_MRS  : begin
                state <= S_WAIT; 
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_CFG  : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_WDQS : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_WAIT : begin
                state <= ((wait_cnt == 4'h0) && (err       == 1'b1  )                                              ) ? S_MRS  :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS ) && (find_s0 == 1'b0) && (find_s1 == 1'b0)    ) ? S_CFG  :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS ) && (find_s0 == 1'b1) && (find_s1 == 1'b1)    ) ? S_DONE : 
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS ) && (err     == 1'b1)                         ) ? S_DONE : 
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b0) && (dcp_rdy_pos == 1'b1)) ? S_WDQS :
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b1) && (dcp_rdy_pos == 1'b1)) ? S_MRS  :
                         ((wait_cnt == 4'h0) && (state_pre == S_WDQS)                                              ) ? ((sample_cnt == 5'h0) ? S_CFG : S_WDQS) : S_WAIT;
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
        state_pre <= (state == S_MRS ) ? state :
                     (state == S_CFG ) ? state :
                     (state == S_WDQS) ? state : state_pre;
    end
end

assign check = (state_pre == S_WDQS) && (wait_cnt == 4'h4);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  CNT
///////////////////////////////////////////////////////////////////////////////////////////////////
wire ld_cnt;

assign ld_cnt = (state == S_MRS) || (state == S_CFG) || (state == S_WDQS);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        wait_cnt <= 4'h0;
    end else if (ld_cnt && (wait_cnt == 4'h0)) begin
        wait_cnt <= 4'hf;
    end else begin
        wait_cnt <= (wait_cnt == 4'h0) ? 4'h0 : (wait_cnt - 1'b1);
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        sample_cnt <= 6'h0;
    end else if (check == 1'b1) begin
        if (sample_cnt == SAMPLE_MAX-1)
            sample_cnt <= 6'h0;
        else
            sample_cnt <= sample_cnt + 1'b1;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  DX Instance
///////////////////////////////////////////////////////////////////////////////////////////////////
genvar n, b, p;
generate
for (n = 0; n < DX_NUM; n = n+1) begin : dx_wrlvl
ph1p_ddrphy_cal_wrlvl #(
    .SAMPLE_MAX   ( SAMPLE_MAX )
) u_cal_wrlvl (
    .clk          ( clk                    ),
    .rst_n        ( rst_n                  ),

    .ui           ( ui          [n*9 +: 9] ),
    .din          ( wrlvl_din   [n]        ),
    .check        ( check                  ),
    .sample_cnt   ( sample_cnt             ),

    .find_s0      ( find_s0_dx  [n]        ),
    .find_s1      ( find_s1_dx  [n]        ),

    .cur_wsl      ( cur_wsl     [n*4 +: 4] ),
    .wsl_o        ( wsl_cal     [n*4 +: 4] ),

    .dly_cur      ( dly_cur     [n*9 +: 9] ),
    .dly_cal      ( dly_cal     [n*9 +: 9] ),

    .err          ( wrlvl_err   [n]        ) 

);
end
endgenerate

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Write Leveling Mode Control
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        wrlvl_en <= 1'b0;
    end else if ((state == S_CFG) && (find_s0 == 1'b0) && (find_s1 == 1'b0)) begin
        wrlvl_en <= 1'b1;
//  end else if ((state == S_CFG) && (find_s0 == 1'b1) && (find_s1 == 1'b1)) begin
    end else if ((state_pre == S_CFG) && (wait_cnt == 4'h0) && (find_s0 == 1'b1) && (find_s1 == 1'b1)) begin
        wrlvl_en <= 1'b0;
    end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  DelayLine Control
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dly_mode <= 1'b0;
    end else if ((find_s0 == 1'b0) && (state == S_CFG)) begin
        dly_mode <= 1'b1;
    end else if (find_s1 == 1'b1) begin
        dly_mode <= 1'b0;
    end
end

for (n = 0; n <= DX_NUM-1; n = n+1) begin : dx_dcp
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dcp_inc [n]        <=  1'b0;
        dcp_vld [n]        <=  1'b0;
        dcp_type[n*4 +: 4] <=  4'b0100;
        dcp_code[n*9 +: 9] <=  1'b0;
        wsl_o   [n*4 +: 4] <=  4'h1;
    end else if (state == S_CFG) begin
        dcp_inc [n]        <=  dly_mode ? 1'b1 : 1'b0;
        dcp_vld [n]        <=  1'b1;
        dcp_code[n*9 +: 9] <=  dly_mode ? 9'h0 : dly_cal[n*9 +: 9];
        wsl_o   [n*4 +: 4] <=  dly_mode ? 4'h1 : wsl_cal[n*4 +: 4];
    end else begin
        dcp_vld [n]        <=  1'b0;
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
    end else if  ((state == S_MRS) && (find_s1 == 1'b0)) begin
        cmd_vld  <= 1'b1 ;
        cmd_code <= {CMD_MRS, 4'b0, 4'b0001, 4'h0, 3'b0, mr1_set[12:8], 1'b1, mr1_set[6:0]};
    end else if  ((state == S_MRS) && (find_s1 == 1'b1)) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_MRS, 4'b0, 4'b0001, 4'h0, 3'b0, mr1_set};
    end else if  (state == S_WDQS) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_WR,  4'd0, 4'b0000, 4'h0, 16'h0};
    end else begin
        cmd_vld  <=  1'b0;
        cmd_code <= 32'b0;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_s0 <= 1'b0;
        find_s1 <= 1'b0;
    end else begin
        find_s0 <= &find_s0_dx;
        find_s1 <= &find_s1_dx;
    end
end

//  Write Leveling Done
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        done <= 1'b0;
    end else if (state == S_DONE) begin
        done <= 1'b1;
    end
end

//  Write Leveling Error
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err <= 1'b0;
    end else if (|wrlvl_err == 1'b1) begin
        err <= 1'b1;
    end
end


endmodule

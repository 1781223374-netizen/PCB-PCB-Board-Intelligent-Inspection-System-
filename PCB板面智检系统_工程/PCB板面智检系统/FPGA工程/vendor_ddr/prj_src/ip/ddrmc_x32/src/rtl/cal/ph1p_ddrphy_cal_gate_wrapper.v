
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_gate_wrapper 
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module  ph1p_ddrphy_cal_gate_wrapper #(
    parameter DX_NUM  = 2
)(
    input                       clk         ,
    input                       rst_n       ,

    input      [DX_NUM*9-1:0]   ui          ,

    input                       start       ,
    output reg                  done        ,
    output reg                  err         ,

    output reg [DX_NUM*9-1:0]   dcp_code    ,
    output reg [DX_NUM*4-1:0]   dcp_type    ,
    output reg [DX_NUM  -1:0]   dcp_vld     ,
    output reg [DX_NUM  -1:0]   dcp_inc     ,
    input      [DX_NUM  -1:0]   dcp_rdy     ,

    input      [DX_NUM*9-1:0]   dly_cur     ,

    input      [DX_NUM*4-1:0]   cur_rsl     ,
    output reg [DX_NUM*4-1:0]   rsl_o       ,

    output reg                  cmd_vld     ,
    output reg [        31:0]   cmd_code    ,

    output reg                  fifo_rst_n  ,
    output reg                  dqs_pupd_en ,

    // gate status
    input      [DX_NUM*2-1:0]   gate_status
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter
///////////////////////////////////////////////////////////////////////////////////////////////////
// op_code
localparam [3:0] CMD_MRS = 4'b1000;
localparam [3:0] CMD_RD  = 4'b1101;

// State
localparam [3:0] S_IDLE  = 4'b0000;
localparam [3:0] S_MRS3  = 4'b0001;
localparam [3:0] S_MRS4  = 4'b0010;
localparam [3:0] S_CFG   = 4'b0011;
localparam [3:0] S_RD    = 4'b0100;
localparam [3:0] S_WAIT  = 4'b0101;
localparam [3:0] S_DONE  = 4'b1000;

`ifdef PH1P_DDRPHY_SIM
localparam [5:0] SAMPLE_MAX = 6'h08;
`else
localparam [5:0] SAMPLE_MAX = 6'h20;
`endif

localparam [3:0] INIT_RSL   = 4'h2;

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
wire [DX_NUM*4-1:0] rsl_cal;

wire [DX_NUM  -1:0] gate_err;

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
                state <= (start == 1'b1) ? S_MRS3 : S_IDLE;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_MRS3  : begin
                state <= S_WAIT; 
            end
            
            ///////////////////////////////////////////////////////////////////////////////////////
            S_MRS4 : begin
                state <= S_WAIT; 
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_CFG  : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_RD   : begin
                state <= S_WAIT;
            end

            ///////////////////////////////////////////////////////////////////////////////////////
            S_WAIT : begin
                state <= 
`ifdef DRAM_DDR4
                         ((wait_cnt == 4'h0) && (err       == 1'b1)                                                ) ? S_DONE :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS3) && (find_s0 == 1'b0) && (find_s1 == 1'b0)    ) ? S_MRS4 :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS4) && (find_s0 == 1'b0) && (find_s1 == 1'b0)    ) ? S_CFG  :
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b0) && (dcp_rdy_pos == 1'b1)) ? S_RD   :
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b1) && (dcp_rdy_pos == 1'b1)) ? S_MRS3 :
                         ((wait_cnt == 4'h0) && (state_pre == S_RD  )                                              ) ? ((sample_cnt == 5'h0) ? S_CFG : S_RD  ) :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS3) && (find_s0 == 1'b1) && (find_s1 == 1'b1)    ) ? S_MRS4 :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS4) && (find_s0 == 1'b1) && (find_s1 == 1'b1)    ) ? S_DONE : S_WAIT;
`else
                         ((wait_cnt == 4'h0) && (err       == 1'b1)                                                ) ? S_DONE :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS3) && (find_s0 == 1'b0) && (find_s1 == 1'b0)    ) ? S_CFG  :
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b0) && (dcp_rdy_pos == 1'b1)) ? S_RD   :
                         ((wait_cnt == 4'h0) && (state_pre == S_CFG ) && (find_s1 == 1'b1) && (dcp_rdy_pos == 1'b1)) ? S_MRS3 :
                         ((wait_cnt == 4'h0) && (state_pre == S_RD  )                                              ) ? ((sample_cnt == 5'h0) ? S_CFG : S_RD  ) :
                         ((wait_cnt == 4'h0) && (state_pre == S_MRS3) && (find_s0 == 1'b1) && (find_s1 == 1'b1)    ) ? S_DONE : S_WAIT;
`endif
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
        state_pre <= (state == S_MRS3) ? state :
                     (state == S_MRS4) ? state :
                     (state == S_CFG ) ? state :
                     (state == S_RD  ) ? state :
                     (state == S_DONE) ? state : state_pre;
    end
end

assign check = (state_pre == S_RD  ) && (wait_cnt == 4'h4);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  CNT
///////////////////////////////////////////////////////////////////////////////////////////////////
wire ld_cnt;

assign ld_cnt = (state == S_MRS3) || (state == S_CFG) || (state == S_RD  );

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
for (n = 0; n < DX_NUM; n = n+1) begin : dx_gate
ph1p_ddrphy_cal_gate #(
    .SAMPLE_MAX   ( SAMPLE_MAX )
) u_cal_gate (
    .clk          ( clk                    ),
    .rst_n        ( rst_n                  ),

    .ui           ( ui          [n*9 +: 9] ),
    .gate_status  ( gate_status [n*2 +: 2] ),
    .check        ( check                  ),
    .sample_cnt   ( sample_cnt             ),

    .find_s0      ( find_s0_dx  [n]        ),
    .find_s1      ( find_s1_dx  [n]        ),

    .cur_rsl      ( cur_rsl     [n*4 +: 4] ),
    .rsl_o        ( rsl_cal     [n*4 +: 4] ),

    .dly_cur      ( dly_cur     [n*9 +: 9] ),
    .dly_cal      ( dly_cal     [n*9 +: 9] ),

    .err          ( gate_err    [n]        ) 

);
end
endgenerate

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Gate Control
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dqs_pupd_en <= 1'b0;
    end else if (state == S_MRS3) begin
        dqs_pupd_en <= ~dqs_pupd_en;
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
        dcp_type[n*4 +: 4] <=  4'b1100;
        dcp_code[n*9 +: 9] <=  1'b0;
        rsl_o   [n*4 +: 4] <=  INIT_RSL;
    end else if (state == S_CFG) begin
        dcp_inc [n]        <=  dly_mode ? 1'b1 : 1'b0;
        dcp_vld [n]        <=  1'b1;
        dcp_code[n*9 +: 9] <=  dly_mode ? 9'h0     : dly_cal[n*9 +: 9];
        rsl_o   [n*4 +: 4] <=  dly_mode ? INIT_RSL : rsl_cal[n*4 +: 4];
    end else begin
        dcp_vld [n]        <=  1'b0;
    end
end
end

///////////////////////////////////////////////////////////////////////////////////////////////////
//  CMD Gen
///////////////////////////////////////////////////////////////////////////////////////////////////

always @ ( posedge clk or negedge rst_n ) begin
    if (rst_n == 1'b0) begin
        cmd_vld  <=  1'b0;
        cmd_code <= 32'b0;
    end else if  (state == S_MRS3) begin
        cmd_vld  <= 1'b1 ;
        cmd_code <= (find_s1 == 1'b0) ? {CMD_MRS, 4'd0, 4'b0011,4'd0, 16'h004} : {CMD_MRS, 4'd0, 4'b0011,4'd0, 16'h0};
    end else if  (state == S_MRS4) begin
        cmd_vld  <= 1'b1 ;
       cmd_code  <= (find_s1 == 1'b0) ? {CMD_MRS, 4'd0, 4'b0100,4'd0, 16'h400} : {CMD_MRS, 4'd0, 4'b0100,4'd0, 16'h0};
    end else if  (state == S_RD) begin
        cmd_vld  <= 1'b1;
        cmd_code <= {CMD_RD, 4'd0, 4'h0, 4'd0, 16'h0};
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

//  ddrphy_fifo_rst_n
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        fifo_rst_n <= 1'b1;
    end else if (state == S_DONE) begin
       `ifdef DRAM_DDR4
       fifo_rst_n <= ((find_s1 == 1'b1) && (state_pre == S_MRS4)) ? 1'b0 : 1'b1;
       `else
       fifo_rst_n <= ((find_s1 == 1'b1) && (state_pre == S_MRS3)) ? 1'b0 : 1'b1;
       `endif
    end
end

//  Read Leveling Done
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        done <= 1'b0;
    end else if (state == S_DONE) begin
        done <= 1'b1;
    end
end

//  Read Leveling Error
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err <= 1'b0;
    end else if (|gate_err == 1'b1) begin
        err <= 1'b1;
    end
end

endmodule

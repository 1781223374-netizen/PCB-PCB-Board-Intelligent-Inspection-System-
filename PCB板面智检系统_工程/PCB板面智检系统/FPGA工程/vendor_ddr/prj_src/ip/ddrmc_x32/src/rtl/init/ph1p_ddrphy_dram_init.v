
`timescale 1ps/1ps

module ph1p_ddrphy_dram_init #(
    parameter  tCK      = 2500,
    parameter  CL       = 5  ,
    parameter  CWL      = 6  ,
    parameter  PAR      = 0  ,
    parameter  WDM      = 1  ,
    parameter  WDBI     = 0  ,
    parameter  RDBI     = 0  ,
    parameter  DRAM_DRV = "40",
    parameter  DRAM_ODT = "60"
)(
    input                  clk          ,
    input                  rst_n        ,

    input                  start        ,
    output                 done         ,
    output  reg            phy_rst_n    ,

    output  reg            cmd_vld      ,
    output  reg  [  31:0]  cmd_code     ,

    output       [13-1:0]  mr1

);

//*****************************************************************************************************************************
//    Parameter Definition
//*****************************************************************************************************************************
localparam integer tWR = 15_000;
localparam integer nWR = tWR/tCK + 1;
    
localparam DRV     = (DRAM_DRV == "40" ) ? "RZQ/6" :
                     (DRAM_DRV == "34" ) ? "RZQ/7" :
                     (DRAM_DRV == "80" ) ? "RZQ/3" :
                     (DRAM_DRV == "60" ) ? "RZQ/4" : "RZQ/6";

localparam RTT_NOM = (DRAM_ODT == "30" ) ? "RZQ/8" :
                     (DRAM_ODT == "40" ) ? "RZQ/6" :
                     (DRAM_ODT == "60" ) ? "RZQ/4" :
                     (DRAM_ODT == "120") ? "RZQ/2" : "DISABLE";

localparam RTT_WR  = "DISABLE";

// MR0
localparam  [ 1:0]  MR0_BL    = 2'b00; // 2'b00 : BL8, 2'b01 : BC4/BL8, 2'b10 : BC4
localparam  [ 2:0]  MR0_WR    = (nWR <=  5) ? 3'b001 :
                                (nWR <=  6) ? 3'b010 :
                                (nWR <=  7) ? 3'b011 :
                                (nWR <=  8) ? 3'b100 :
                                (nWR <= 10) ? 3'b101 :
                                (nWR <= 12) ? 3'b110 :
                                (nWR <= 14) ? 3'b111 :
                                (nWR <= 16) ? 3'b000 : 3'b000;
localparam  [ 3:0]  MR0_CL    = (CL ==  5) ? 4'b0010 :
                                (CL ==  6) ? 4'b0100 :
                                (CL ==  7) ? 4'b0110 :
                                (CL ==  8) ? 4'b1000 :
                                (CL ==  9) ? 4'b1010 :
                                (CL == 10) ? 4'b1100 :
                                (CL == 11) ? 4'b1110 :
                                (CL == 12) ? 4'b0001 :
                                (CL == 13) ? 4'b0011 :
                                (CL == 14) ? 4'b0101 : 4'b1110;

// MR1
localparam  [ 1:0]  MR1_AL    = 2'b00;
localparam  [ 1:0]  MR1_DRV   = (DRV == "RZQ/6"  ) ? 2'b00 :
                                (DRV == "RZQ/7"  ) ? 2'b01 :
                                (DRV == "RZQ/3"  ) ? 2'b10 :
                                (DRV == "RZQ/4"  ) ? 2'b11 : 2'b00;
localparam  [ 2:0]  MR1_RTTNOM= (RTT_NOM == "RZQ/4"  ) ? 3'b001 :
                                (RTT_NOM == "RZQ/2"  ) ? 3'b010 :
                                (RTT_NOM == "RZQ/6"  ) ? 3'b011 :
                                (RTT_NOM == "RZQ/8"  ) ? 3'b101 :
                                (RTT_NOM == "DISABLE") ? 3'b000 : 3'b011;

// MR2
localparam  [ 2:0]  MR2_CWL   = (CWL - 5);
localparam  [ 1:0]  MR2_RTTWR = 2'b00; 
//localparam  [ 1:0]  MR2_RTTWR = (RTT_WR == "RZQ/4"  ) ? 2'b01 :
//                                (RTT_WR == "RZQ/2"  ) ? 2'b10 :
//                                (RTT_WR == "DISABLE") ? 2'b00 : 2'b01;

///////////////////////////////////////////////////////////////////////////////////////////////////
// MR0                     A12,  A11:A9,      A8,   A7,   A6:A4,       A3,   A2,        A1:A0
localparam  [12:0]  MR0 = {1'b0, MR0_WR[2:0], 1'b1, 1'b0, MR0_CL[3:1], 1'b0, MR0_CL[0], MR0_BL[1:0]};
// MR1                     A12,  A11,  A10,  A9,            A8,   A7,   A6,            A5,         A4:A3,       A2,            A1,         A0 
localparam  [12:0]  MR1 = {1'b0, 1'b0, 1'b0, MR1_RTTNOM[2], 1'b0, 1'b0, MR1_RTTNOM[1], MR1_DRV[1], MR1_AL[1:0], MR1_RTTNOM[0], MR1_DRV[0], 1'b0};
// MR2                     A12:A11, A10:A9,         A8,   A7,   A6,   A5:A3,        A2:A0
localparam  [12:0]  MR2 = {2'b00,   MR2_RTTWR[1:0], 1'b0, 1'b0, 1'b0, MR2_CWL[2:0], 3'b000};
// MR3
localparam  [12:0]  MR3 = 13'h0;

///////////////////////////////////////////////////////////////////////////////////////////////////
// Timing Control, in ps
`ifdef PH1P_DDRPHY_SIM
localparam tRST     = 500_000;
`else
localparam tRST     = 500_000_000;
`endif
localparam tRFC     = 350_000; // 8Gb: 350ns, 4Gb: 260ns, 2Gb: 160ns, 1Gb: 110ns, 512Mb: 90ns
localparam tXPR     = tRFC + 10_000;
localparam tMOD     = 15_000;
localparam tZQinit  = 640_000;

localparam [31:0] nRST = tRST/tCK + 4;
localparam [31:0] nXPR = tXPR/tCK + 4;
localparam [31:0] nMRD = 4 + 16;
localparam [31:0] nMOD = ( 12 >= tMOD/tCK   ) ? ( 12 + 4) : (tMOD/tCK    + 4);
localparam [31:0] nZQC = (512 >= tZQinit/tCK) ? (512 + 4) : (tZQinit/tCK + 4); // max(512nCK, 640ns)

///////////////////////////////////////////////////////////////////////////////////////////////////
localparam [3 : 0] CMD_RST = 4'b1111;
localparam [3 : 0] CMD_CKE = 4'b1111;
localparam [3 : 0] CMD_MRS = 4'b1000;
localparam [3 : 0] CMD_REF = 4'b1001;
localparam [3 : 0] CMD_PRE = 4'b1010;
localparam [3 : 0] CMD_ACT = 4'b0011;
localparam [3 : 0] CMD_WR  = 4'b1100;
localparam [3 : 0] CMD_RD  = 4'b1101;
localparam [3 : 0] CMD_ZQC = 4'b1110;

///////////////////////////////////////////////////////////////////////////////////////////////////
localparam  [3:0]  S_IDLE  = 4'b0000 ;
localparam  [3:0]  S_RST   = 4'b0001 ; 
localparam  [3:0]  S_CKE   = 4'b0010 ;
localparam  [3:0]  S_MR2   = 4'b0011 ;
localparam  [3:0]  S_MR3   = 4'b0100 ;
localparam  [3:0]  S_MR1   = 4'b0101 ;
localparam  [3:0]  S_MR0   = 4'b0110 ;
localparam  [3:0]  S_ZQCL  = 4'b0111 ;
localparam  [3:0]  S_DONE  = 4'b1000 ;

//*****************************************************************************************************************************
//    Internal Signal Definition
//*****************************************************************************************************************************
reg   [ 3:0] state_cnt;
reg   [ 3:0] state_cnt_r;
reg   [31:0] wait_cnt;
reg          wait_done;

reg   [ 1:0] start_r ;
wire         start_pos;

//*****************************************************************************************************************************
//    Internal Signal Definition
//*****************************************************************************************************************************
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        start_r <= 2'b00;
    else 
        start_r <= {start_r[0], start};
end

assign start_pos = (start_r[0] == 1'b1) & (start_r[1] == 1'b0);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        state_cnt <= 4'h0;
    else
        state_cnt <= ((wait_done == 1'b1) || (start_pos == 1'b1)) ? state_cnt + 1 : state_cnt;
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        state_cnt_r <= 4'h0;
    else
        state_cnt_r <= state_cnt;
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        wait_cnt <= 32'h0;
//  else if (state_cnt != state_cnt_r)
    else if (wait_done == 1'b1)
        wait_cnt <= 32'h0;
    else if ((start_r[1] == 1'b1) && (done == 1'b0))
        wait_cnt <= (wait_done == 1'b1) ? wait_cnt : wait_cnt + 1'b1;
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        wait_done <= 1'b0;
//  else if (cmd_vld == 1'b1)
//      wait_done <= 1'b0;
    else case (state_cnt)
        S_RST   : wait_done <= (wait_cnt == {2'b00, nRST[31:2]}); 
        S_CKE   : wait_done <= (wait_cnt == {2'b00, nXPR[31:2]});
        S_MR2   : wait_done <= (wait_cnt == {2'b00, nMRD[31:2]});
        S_MR3   : wait_done <= (wait_cnt == {2'b00, nMRD[31:2]});
        S_MR1   : wait_done <= (wait_cnt == {2'b00, nMRD[31:2]});
        S_MR0   : wait_done <= (wait_cnt == {2'b00, nMOD[31:2]});
        S_ZQCL  : wait_done <= (wait_cnt == {2'b00, nZQC[31:2]});
        default : wait_done <= wait_done; 
    endcase
end

// cmd_vld
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        cmd_vld <= 1'b0;
    else
        cmd_vld <= (wait_cnt == 32'h1) ? 1'b1 : 1'b0;
end

// cmd_code
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0)
        cmd_code <= 32'h0;
    else case (state_cnt)
        S_RST   : cmd_code <= {CMD_RST, 4'b0001, 4'b0000, 20'h0}; 
        S_CKE   : cmd_code <= {CMD_CKE, 4'b0011, 4'b0000, 20'h0}; 
        S_MR2   : cmd_code <= {CMD_MRS, 4'b0000, 4'b0010, {7'h0, MR2}}; 
        S_MR3   : cmd_code <= {CMD_MRS, 4'b0000, 4'b0011, {7'h0, MR3}}; 
        S_MR1   : cmd_code <= {CMD_MRS, 4'b0000, 4'b0001, {7'h0, MR1}}; 
        S_MR0   : cmd_code <= {CMD_MRS, 4'b0000, 4'b0000, {7'h0, MR0}}; 
        S_ZQCL  : cmd_code <= {CMD_ZQC, 4'b0000, 4'b0000, 20'h0_04_00}; 
        default : cmd_code <= 32'h0; 
    endcase
end

assign done = (state_cnt[3:0] == S_DONE);

assign mr1  = MR1;

endmodule


///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_wrlvl
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module ph1p_ddrphy_cal_wrlvl #(
    parameter  [5:0]  SAMPLE_MAX = 6'h20
)(
    input             clk          ,
    input             rst_n        ,

    input      [8:0]  ui           ,
    input             din          ,

    input             check        ,
    input      [5:0]  sample_cnt   ,

    output reg        find_s0      ,
    output reg        find_s1      ,

    input      [3:0]  cur_wsl      ,
    output reg [3:0]  wsl_o        ,
    input      [8:0]  dly_cur      ,
    output reg [8:0]  dly_cal      ,

    output reg        err
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef PH1P_DDRPHY_SIM
localparam [7:0]  WIN  = 8'h04;
`else
localparam [7:0]  WIN  = 8'h10;
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Interanl Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [5:0]  sample_cnt0;
reg  [5:0]  sample_cnt1;

reg         sample_cnt0_vld;
reg         sample_cnt1_vld;

reg  [5:0]  find_s0_cnt;
reg  [5:0]  find_s1_cnt;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Function Definition
///////////////////////////////////////////////////////////////////////////////////////////////////

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        sample_cnt0_vld <= 1'b0;
        sample_cnt0     <= 6'h0;
    end else if ((check == 1'b0) && (sample_cnt == 6'h0)) begin
        sample_cnt0_vld <= 1'b0;
        sample_cnt0     <= 6'h0;
    end else if ((check == 1'b1) && (din == 1'b0)) begin
        sample_cnt0_vld <= (sample_cnt == SAMPLE_MAX-1);
        sample_cnt0     <= sample_cnt0 + 1'b1;
    end else begin
        sample_cnt0_vld <= 1'b0;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        sample_cnt1_vld <= 1'b0;
        sample_cnt1     <= 6'h0;
    end else if ((check == 1'b0) && (sample_cnt == 6'h0)) begin
        sample_cnt1_vld <= 1'b0;
        sample_cnt1     <= 6'h0;
    end else if ((check == 1'b1) && (din == 1'b1)) begin
        sample_cnt1_vld <= (sample_cnt == SAMPLE_MAX-1);
        sample_cnt1     <= sample_cnt1 + 1'b1;
    end else begin
        sample_cnt1_vld <= 1'b0;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_s0_cnt <= 6'h0; 
    end else if (sample_cnt0_vld == 1'b1) begin
        find_s0_cnt <= (sample_cnt0 == SAMPLE_MAX) ? find_s0_cnt + 1'b1 : 6'h0;
    end else if (sample_cnt1_vld == 1'b1) begin
        find_s0_cnt <= 6'h0; 
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_s0 <= 1'b0; 
    end else if (find_s0_cnt == WIN) begin
        find_s0 <= 1'b1;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_s1 <= 1'b0; 
    end else if (find_s0 == 1'b1) begin
        if ((sample_cnt1_vld == 1'b1) && (sample_cnt1 == SAMPLE_MAX)) begin
            find_s1 <= 1'b1;
        end
    end
end

// DelayLine Cal
reg  find_s1_r;
wire find_s1_pos;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_s1_r <= 1'b0; 
    end else begin
        find_s1_r <= find_s1;
    end
end

assign find_s1_pos = (find_s1 == 1'b1) && (find_s1_r == 1'b0);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        wsl_o   <= 4'h1;
        dly_cal <= 9'h0; 
    end else if (find_s1_pos == 1'b1) begin
        wsl_o   <= (dly_cur <= 9'h8) ? (cur_wsl - 1) : cur_wsl;
        dly_cal <= (dly_cur <= 9'h8) ? (ui + dly_cur - 9'h8) : (dly_cur - 9'h8);
    end
end

// Error Check
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err <= 1'b0;
    end else if (cur_wsl == 4'hf) begin
        err <= 1'b1;
    end
end

endmodule

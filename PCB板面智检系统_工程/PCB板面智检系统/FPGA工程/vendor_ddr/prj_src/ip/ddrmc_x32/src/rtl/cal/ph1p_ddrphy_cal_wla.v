
///////////////////////////////////////////////////////////////////////////////////////////////////
// module : ph1p_ddrphy_cal_wla 
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps

module ph1p_ddrphy_cal_wla #(
    parameter  [5:0]  SAMPLE_MAX = 6'h20
)(
    input             clk          ,
    input             rst_n        ,

    input             start        ,
    input             check        ,
    input      [5:0]  sample_cnt   ,

    input             wdata_en     ,
    output    [63:0]  wdata        ,
    output    [ 7:0]  wmask        ,
    input             rdata_vld    ,
    input     [63:0]  rdata        ,

    output reg        find_match   ,

    input      [3:0]  cur_wsl      ,
    output reg [3:0]  cal_wsl      ,

    output reg [63:0] dbg_rdata_x0 ,
    output reg [63:0] dbg_rdata_x1 ,
    output reg [63:0] dbg_rdata_x2 ,
    output reg [63:0] dbg_rdata_x3 ,

    output reg        err
);

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Local Parameter Definition
///////////////////////////////////////////////////////////////////////////////////////////////////

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Interanl Signals Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
reg  [ 3:0] rd_cnt;
reg         rdata_vld_r;
reg  [63:0] rdata_r;

wire [63:0] rdata_xor;

///////////////////////////////////////////////////////////////////////////////////////////////////
//  Function Definition
///////////////////////////////////////////////////////////////////////////////////////////////////
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        rdata_vld_r <=  1'b0; 
        rdata_r     <= 64'h0; 
    end else begin
        rdata_vld_r <= rdata_vld; 
        rdata_r     <= rdata; 
    end
end

assign rdata_xor = (rdata_vld_r) ? (rdata_r ^ wdata) : {64{1'b1}};

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_match <= 1'b0; 
    end else if (start == 1'b0) begin
        find_match <= 1'b0; 
    end else if (rdata_vld_r && (|rdata_xor == 1'b0)) begin
        find_match <= 1'b1;
    end
end

// DelayLine Cal
reg  find_match_r;
wire find_match_pos;

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        find_match_r <= 1'b0; 
    end else begin
        find_match_r <= find_match;
    end
end

assign find_match_pos = (find_match == 1'b1) && (find_match_r == 1'b0);

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        cal_wsl <= 4'h0;
    end else if (find_match_pos == 1'b1) begin
        cal_wsl <= cur_wsl;
    end
end

// Error Check
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        err <= 1'b0;
//    end else if (cur_wsl >= 4'h4) begin
//        err <= 1'b1;
    end
end

assign wdata = 64'hAA559966_55AA00FF;
`ifdef DRAM_DDR4
assign wmask = 8'hff;
`else
assign wmask = 8'h00;
`endif

// Debug
always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        rd_cnt <= 4'h0;
    end else if (rdata_vld_r == 1'b1) begin
        rd_cnt <= (rd_cnt == 4'h4) ? 4'h4 : rd_cnt + 1'b1;
    end
end


always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dbg_rdata_x0 <= 64'h0;
    end else if ((rdata_vld_r == 1'b1) && (rd_cnt == 4'h0)) begin
        dbg_rdata_x0 <= rdata_r;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dbg_rdata_x1 <= 64'h0;
    end else if ((rdata_vld_r == 1'b1) && (rd_cnt == 4'h1)) begin
        dbg_rdata_x1 <= rdata_r;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dbg_rdata_x2 <= 64'h0;
    end else if ((rdata_vld_r == 1'b1) && (rd_cnt == 4'h2)) begin
        dbg_rdata_x2 <= rdata_r;
    end
end

always @ (posedge clk or negedge rst_n)
begin
    if (rst_n == 1'b0) begin
        dbg_rdata_x3 <= 64'h0;
    end else if ((rdata_vld_r == 1'b1) && (rd_cnt == 4'h3)) begin
        dbg_rdata_x3 <= rdata_r;
    end
end

endmodule

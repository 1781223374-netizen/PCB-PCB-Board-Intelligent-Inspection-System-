`timescale 1ns/1ps
// Centred 3x3 range-gated binomial filter. No decimation or image translation.
// RGB and metadata share one-line-plus-seven-clock latency, even OFF/playback.
module spatial_denoise #(parameter WIDTH=1920,HEIGHT=1080,H_TOTAL=WIDTH+160)(
 input clk,rst_n,input [23:0] in_rgb,input in_de,in_hs,in_vs,input [11:0] in_x,in_y,
 input [1:0] mode,input bypass,
 output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs,output reg [11:0] out_x,out_y);
 (* ram_style="bram" *) reg [23:0] line1[0:H_TOTAL-1],line2[0:H_TOTAL-1];
 (* ram_style="bram" *) reg [29:0] meta_line[0:H_TOTAL-1];
 reg [23:0] upper_q,top_q,a_rgb;
 reg [29:0] meta_q,meta_left;
 reg [23:0] t_left,t_left2,m_left,m_left2,b_left,b_left2;
 reg [1:0] active_mode;
 reg seen_line,a_valid,left_valid;
 wire [1:0] frame_mode=(in_de && in_x==0 && in_y==0)?mode:active_mode;
 always @(posedge clk)begin
  if(in_x<H_TOTAL)begin
   upper_q<=line1[in_x];top_q<=line2[in_x];meta_q<=meta_line[in_x];
   line2[in_x]<=line1[in_x];line1[in_x]<=in_rgb;
   meta_line[in_x]<={in_de,in_hs,in_vs,in_x,in_y,frame_mode,bypass};
  end
 end
 wire [11:0] cx=meta_left[26:15],cy=meta_left[14:3];
 wire [23:0] ml=cx==0?m_left:m_left2, mr=cx==WIDTH-1?m_left:upper_q;
 wire [23:0] tl=cx==0?t_left:t_left2, tr=cx==WIDTH-1?t_left:top_q;
 wire [23:0] bl=cx==0?b_left:b_left2, br=cx==WIDTH-1?b_left:a_rgb;
 reg [23:0] w[0:8],g[0:8];
 reg [29:0] b_meta,g_meta,r_meta,s_meta;
 reg b_valid,g_valid,r_valid,s_valid;
 reg [23:0] g_center,r_center,s_center;
 reg [9:0] rows[0:8];reg [11:0] sums[0:2];
 function [7:0] gate_channel;
  input [7:0] center,neighbor,limit;reg [7:0] difference;
  begin difference=center>neighbor?center-neighbor:neighbor-center;
   gate_channel=difference<=limit?neighbor:center;
  end
 endfunction
 wire [7:0] limit=b_meta[2:1]==1?8'd16:8'd32;
 integer i,c,j;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   a_rgb<=0;active_mode<=0;seen_line<=0;a_valid<=0;left_valid<=0;
   meta_left<=0;t_left<=0;t_left2<=0;m_left<=0;m_left2<=0;b_left<=0;b_left2<=0;
   b_meta<=0;g_meta<=0;r_meta<=0;s_meta<=0;b_valid<=0;g_valid<=0;r_valid<=0;s_valid<=0;
   g_center<=0;r_center<=0;s_center<=0;
   out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=1;out_x<=0;out_y<=0;
   for(i=0;i<9;i=i+1)begin w[i]<=0;g[i]<=0;rows[i]<=0;end
   for(i=0;i<3;i=i+1)sums[i]<=0;
  end else begin
   if(in_de && in_x==0 && in_y==0)active_mode<=mode;
   if(in_x==H_TOTAL-1)seen_line<=1;
   a_rgb<=in_rgb;a_valid<=seen_line && in_x<H_TOTAL;
   t_left<=top_q;t_left2<=t_left;m_left<=upper_q;m_left2<=m_left;
   b_left<=a_rgb;b_left2<=b_left;meta_left<=meta_q;left_valid<=a_valid;
   w[0]<=cy==0?ml:tl;w[1]<=cy==0?m_left:t_left;w[2]<=cy==0?mr:tr;
   w[3]<=ml;w[4]<=m_left;w[5]<=mr;
   w[6]<=cy==HEIGHT-1?ml:bl;w[7]<=cy==HEIGHT-1?m_left:b_left;w[8]<=cy==HEIGHT-1?mr:br;
   b_meta<=meta_left;b_valid<=left_valid;
   for(i=0;i<9;i=i+1)for(c=0;c<3;c=c+1)
    g[i][c*8+:8]<=gate_channel(w[4][c*8+:8],w[i][c*8+:8],limit);
   g_meta<=b_meta;g_valid<=b_valid;g_center<=w[4];
   // Registered row sums keep the 114.75MHz path short.
   for(j=0;j<3;j=j+1)for(c=0;c<3;c=c+1)
    rows[j*3+c]<={2'd0,g[j*3][c*8+:8]}+{1'd0,g[j*3+1][c*8+:8],1'd0}+{2'd0,g[j*3+2][c*8+:8]};
   r_meta<=g_meta;r_valid<=g_valid;r_center<=g_center;
   for(c=0;c<3;c=c+1)
    sums[c]<={2'd0,rows[c]}+{1'd0,rows[3+c],1'd0}+{2'd0,rows[6+c]}+12'd8;
   s_meta<=r_meta;s_valid<=r_valid;s_center<=r_center;
   out_rgb<=s_valid && s_meta[29]?
    ((s_meta[2:1]==0 || s_meta[0])?s_center:{sums[2][11:4],sums[1][11:4],sums[0][11:4]}):24'd0;
   out_de<=s_valid && s_meta[29];out_hs<=s_valid && s_meta[28];out_vs<=s_valid?s_meta[27]:1'b1;
   out_x<=s_valid?s_meta[26:15]:12'd0;out_y<=s_valid?s_meta[14:3]:12'd0;
  end
 end
endmodule

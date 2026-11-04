`timescale 1ns/1ps
`default_nettype none
// Passive, pre-ISP green-channel Sobel energy in a centered ROI. Clipped
// gradients and an 8-level dead band reduce isolated glare/RGB565 noise.
// A serial divider normalizes exposure; it is outside the pixel critical path.
module focus_metric #(parameter WIDTH=1920,HEIGHT=1080,ROI_W=512,ROI_H=256)(
 input wire clk,rst_n,available,input wire [23:0] rgb,input wire de,
 input wire [11:0] x,y,input wire [31:0] frame_id,
 output reg valid,usable,output reg [31:0] score,sample_frame);
 localparam X0=(WIDTH-ROI_W)/2,Y0=(HEIGHT-ROI_H)/2;
 localparam N=(ROI_W-2)*(ROI_H-2),AW=$clog2(ROI_W);
 // Power-of-two ROI dimensions keep brightness normalization a fixed shift.
 localparam SHIFT=$clog2(ROI_W)+$clog2(ROI_H);
 reg [7:0] row0[0:ROI_W-1],row1[0:ROI_W-1];
 wire inside_roi=de && x>=X0 && x<X0+ROI_W && y>=Y0 && y<Y0+ROI_H;
 wire [AW-1:0] address=x-X0;
 reg [7:0] top,middle,bottom,t2,t1,m2,m1,b2,b1,center;
 reg pvalid,gvalid,evalid;reg [11:0] px,py;
 reg signed [10:0] gx,gy;
 wire [10:0] ax=gx[10]?-gx:gx,ay=gy[10]?-gy:gy;
 wire [7:0] cx=ax<=8?8'd0:ax>263?8'd255:ax-11'd8;
 wire [7:0] cy=ay<=8?8'd0:ay>263?8'd255:ay-11'd8;
 reg [16:0] energy;reg [7:0] light;reg [35:0] total;
 reg [25:0] brightness;reg [18:0] count,clipped;reg [31:0] active_frame;
 // Synchronous RAM read/write; first two rows/columns are excluded.
 always @(posedge clk)if(inside_roi)begin
  top<=row1[address];middle<=row0[address];bottom<=rgb[15:8];
  row1[address]<=row0[address];row0[address]<=rgb[15:8];
 end
 function signed [10:0] sobel;
 input [7:0] a,b,c,d,e,f;
 begin sobel=$signed({3'd0,a})+($signed({3'd0,b})<<<1)+$signed({3'd0,c})
             -$signed({3'd0,d})-($signed({3'd0,e})<<<1)-$signed({3'd0,f});end
 endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   pvalid<=0;gvalid<=0;evalid<=0;px<=0;py<=0;gx<=0;gy<=0;
   t2<=0;t1<=0;m2<=0;m1<=0;b2<=0;b1<=0;center<=0;light<=0;energy<=0;
   total<=0;brightness<=0;count<=0;clipped<=0;active_frame<=0;
  end else begin
   pvalid<=inside_roi;px<=x;py<=y;gvalid<=0;evalid<=gvalid;
   if(pvalid)begin
    t2<=t1;t1<=top;m2<=m1;m1<=middle;b2<=b1;b1<=bottom;
    if(px>=X0+2 && py>=Y0+2)begin
     gx<=sobel(top,middle,bottom,t2,m2,b2);
     gy<=sobel(b2,b1,bottom,t2,t1,top);center<=m1;gvalid<=1;
    end
   end
   energy<=cx*cx+cy*cy;light<=center;
   if(de && x==0 && y==0)begin
    total<=0;brightness<=0;count<=0;clipped<=0;active_frame<=frame_id;
   end else if(evalid)begin
    total<=total+energy;brightness<=brightness+light;count<=count+1'b1;
    if(light<=3 || light>=252)clipped<=clipped+1'b1;
   end
  end
 end
 wire [7:0] mean_light=(brightness>>SHIFT)<16?8'd16:(brightness>>SHIFT);
 reg dividing;reg [5:0] steps;reg [35:0] quotient;reg [16:0] remainder;
 reg [15:0] denominator;reg good;reg [31:0] pending_frame;
 wire [16:0] trial={remainder[15:0],quotient[35]};
 wire subtract=trial>={1'b0,denominator};
 wire [35:0] next_quotient={quotient[34:0],subtract};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   valid<=0;usable<=0;score<=0;sample_frame<=0;dividing<=0;steps<=0;
   quotient<=0;remainder<=0;denominator<=1;good<=0;pending_frame<=0;
  end else begin
   valid<=0;
   if(de && x==WIDTH-1 && y==HEIGHT-1 && !dividing)begin
    quotient<=total;remainder<=0;denominator<=mean_light*mean_light;steps<=0;dividing<=1;
    good<=available && count==N && clipped<(N*3)/5;pending_frame<=active_frame;
   end else if(dividing)begin
    quotient<=next_quotient;remainder<=subtract?trial-denominator:trial;
    if(steps==35)begin
     dividing<=0;valid<=1;usable<=good;sample_frame<=pending_frame;
     score<=|next_quotient[35:32]?32'hffffffff:next_quotient[31:0];
    end else steps<=steps+1'b1;
   end
  end
 end
endmodule
`default_nettype wire

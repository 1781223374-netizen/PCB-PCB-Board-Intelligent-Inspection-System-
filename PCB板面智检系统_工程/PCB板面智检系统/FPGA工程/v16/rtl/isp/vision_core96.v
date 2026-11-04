// Seven stages before optional morphology, then four common alignment stages.
// V243C: 2 contrast gray; 3 visible edges; 7 color surface detail.
// All modes retain the original latency, BRAMs and frame-latched controls.
module vision_core96 #(parameter IMG_WIDTH=1024,IMG_HEIGHT=600)(
 input I_clk,I_rst_n,I_tlast,I_tuser,input [95:0] I_tdata,input I_tvalid,
 input [3:0] I_mode,input [2:0] I_th_sel,
 output O_tlast,O_tuser,O_tvalid,output [95:0] O_tdata,output O_hist_ready,
 // Ambient statistic tap: the first-pixel group of every beat with its sidebands.
 output [31:0] O_amb_gray,output O_amb_user,output O_amb_last,output O_amb_valid);
localparam GROUPS=IMG_WIDTH/4;
reg [10:0] x,y,xp[0:2],yp[0:2];
reg [6:0] vp,up,lp;
reg [95:0] rgb[0:5];reg [3:0] mode[0:6];reg [2:0] th[0:5];
reg [3:0] cfg_mode;reg [2:0] cfg_th;
wire [3:0] inmode=I_tuser?I_mode:cfg_mode;
wire [2:0] inth=I_tuser?I_th_sel:cfg_th;
integer k;
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin
  x<=0;y<=0;vp<=0;up<=0;lp<=0;cfg_mode<=0;cfg_th<=3;
  for(k=0;k<6;k=k+1) begin rgb[k]<=0;th[k]<=3;end
  for(k=0;k<7;k=k+1) mode[k]<=0;
  for(k=0;k<3;k=k+1) begin xp[k]<=0;yp[k]<=0;end
 end else begin
  vp<={vp[5:0],I_tvalid};up<={up[5:0],I_tuser};lp<={lp[5:0],I_tlast};
  if(I_tuser) begin cfg_mode<=I_mode;cfg_th<=I_th_sel;end
  rgb[0]<=I_tdata;mode[0]<=inmode;th[0]<=inth;
  for(k=1;k<6;k=k+1) begin rgb[k]<=rgb[k-1];th[k]<=th[k-1];end
  for(k=1;k<7;k=k+1) mode[k]<=mode[k-1];
  xp[0]<=I_tuser?0:x;yp[0]<=I_tuser?0:y;
  for(k=1;k<3;k=k+1) begin xp[k]<=xp[k-1];yp[k]<=yp[k-1];end
  if(I_tuser) begin x<=I_tvalid?1:0;y<=0;end
  else if(I_tvalid) begin
   if(x==GROUPS-1) begin x<=0;y<=y==IMG_HEIGHT-1?0:y+1'b1;end else x<=x+1'b1;
  end
 end
end
reg [31:0] gray;
genvar i;
generate for(i=0;i<4;i=i+1) begin:LUMA
 wire [23:0] p=rgb[0][24*(3-i)+:24];
 wire [9:0] s={2'b0,p[23:16]}+{1'b0,p[15:8],1'b0}+{2'b0,p[7:0]};
 always @(posedge I_clk) gray[i*8+:8]<=s[9:2];
end endgenerate
(* ram_style="bram" *) reg [31:0] line1[0:GROUPS-1],line2[0:GROUPS-1];
(* ram_style="bram" *) reg [95:0] colorline[0:GROUPS-1];
reg [31:0] tr,mr,br;reg [95:0] cr;
always @(posedge I_clk) if(vp[1]) begin
 tr<=line2[xp[1]];mr<=line1[xp[1]];br<=gray;
 line2[xp[1]]<=line1[xp[1]];line1[xp[1]]<=gray;
 cr<=colorline[xp[1]];colorline[xp[1]]<=rgb[1];
end
reg [15:0] ht,hm,hb;reg [23:0] hc;
always @(posedge I_clk) if(vp[2]) begin ht<=tr[31:16];hm<=mr[31:16];hb<=br[31:16];hc<=cr[23:0];end
wire [47:0] t={tr,xp[2]==0?16'd0:ht},m={mr,xp[2]==0?16'd0:hm},b={br,xp[2]==0?16'd0:hb};
wire [31:0] hist_pixels;
hist_equal4 #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT)) HE(
 .clk(I_clk),.rst_n(I_rst_n),.valid(vp[1]),.user(up[1]),.gray(gray),.mapped(hist_pixels),.ready(O_hist_ready));
reg [31:0] he4,he5;
always @(posedge I_clk) begin he4<=hist_pixels;he5<=he4;end
reg [95:0] core_data;
// Signed, saturating arithmetic: strong detail must never wrap to black.
function [7:0] clip8;
 input signed [12:0] value;
 begin clip8=value<0?8'd0:value>255?8'd255:value[7:0];end
endfunction
function [7:0] contrast;
 input [7:0] value;input [2:0] level;
 reg signed [12:0] d,g;
 begin
  d=$signed({1'b0,value})-13'sd128;
  case(level)
   0:g=d;1:g=d+(d>>>2);2:g=d+(d>>>1);3:g=d<<<1;
   4:g=(d<<<1)+(d>>>1);5:g=(d<<<1)+d;default:g=d<<<2;
  endcase
  contrast=clip8(g+13'sd128);
 end
endfunction
function signed [12:0] detail;
 input signed [10:0] lap;input [2:0] level;
 reg signed [12:0] d;
 begin
  // Continuous 8-DN coring reduces amplification of flat-field sensor noise.
  d=lap>8?lap-13'sd8:lap< -8?lap+13'sd8:13'sd0;
  case(level)
   0:detail=0;1:detail=d>>>3;2:detail=d>>>2;3:detail=d>>>1;
   4:detail=(d>>>1)+(d>>>2);5:detail=d;default:detail=d+(d>>>1);
  endcase
 end
endfunction
function [7:0] edge_gain;
 input [9:0] magnitude;input [2:0] level;
 reg [12:0] v;
 begin
  v={3'd0,magnitude};
  case(level)
   0:v=v>>2;1:v=v>>1;2:v=v;3:v=v+(v>>1);
   4:v=v<<1;5:v=(v<<1)+v;default:v=v<<2;
  endcase
  edge_gain=v>255?8'd255:v[7:0];
 end
endfunction
generate for(i=0;i<4;i=i+1) begin:LANE
 wire [7:0] c=m[8*(i+1)+:8];
 reg [9:0] cross3,cross4;reg [7:0] c3,c4;reg [9:0] mag5;
 reg [7:0] current3,current4,current5;
 reg [7:0] gray4,gray5;reg signed [10:0] lap4;
 reg [23:0] color3,color4,color5;reg warm3,warm4,warm5;reg [7:0] center5;
 always @(posedge I_clk) begin
  cross3<={2'b0,t[8*(i+1)+:8]}+{2'b0,m[8*i+:8]}+{2'b0,m[8*(i+2)+:8]}+{2'b0,b[8*(i+1)+:8]};
  c3<=c;cross4<=cross3;c4<=c3;center5<=c4;
  mag5<=({c4,2'b0}>=cross4)?({c4,2'b0}-cross4):(cross4-{c4,2'b0});
  current3<=br[8*i+:8];current4<=current3;current5<=current4;
  gray4<=contrast(current3,th[3]);gray5<=gray4;
  lap4<=$signed({1'b0,c3,2'b0})-$signed({1'b0,cross3});
  color4<=color3;
  color5<={clip8($signed({1'b0,color4[23:16]})+detail(lap4,th[4])),
           clip8($signed({1'b0,color4[15:8]})+detail(lap4,th[4])),
           clip8($signed({1'b0,color4[7:0]})+detail(lap4,th[4]))};
  warm3<=yp[2]>=2 && (xp[2]!=0 || i>=2);warm4<=warm3;warm5<=warm4;
 end
 if(i==0)begin:PREVIOUS_COLOR
  always @(posedge I_clk)color3<=xp[2]==0?24'd0:hc;
 end else begin:CURRENT_COLOR
  always @(posedge I_clk)color3<=cr[24*(4-i)+:24];
 end
 wire [7:0] edge_th=({5'd0,th[5]}+8'd1)<<2;
 wire [7:0] binary_th=({5'd0,th[5]}+8'd1)<<5;
 wire edge_on=mag5>{edge_th,2'b0};
 always @(posedge I_clk or negedge I_rst_n)
  if(!I_rst_n) core_data[24*(3-i)+:24]<=0;
  else case(mode[5])
   2: core_data[24*(3-i)+:24]<={3{gray5}};
   3: core_data[24*(3-i)+:24]<=warm5?{3{edge_gain(mag5,th[5])}}:24'd0;
   4: core_data[24*(3-i)+:24]<=(warm5 && edge_on)?24'hffffff:24'd0;
   5: core_data[24*(3-i)+:24]<=!warm5?24'd0:edge_on?24'hffffff:center5>=binary_th?24'h00b060:24'h101820;
   6: core_data[24*(3-i)+:24]<=current5>=binary_th?24'hffffff:24'd0;
   7: core_data[24*(3-i)+:24]<=!warm5?24'd0:color5;
   9: core_data[24*(3-i)+:24]<=current5<(8'd144+th[5]*8'd12)?24'd0:24'hffffff;
   8: core_data[24*(3-i)+:24]<={3{he5[8*i+:8]}};
   default: core_data[24*(3-i)+:24]<=rgb[5][24*(3-i)+:24];
  endcase
end endgenerate
wire [3:0] bp={core_data[0],core_data[24],core_data[48],core_data[72]};
wire [3:0] dil,closed;wire dv,du,cv,cu;
binary_morph4 #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.DILATE(1)) D(I_clk,I_rst_n,vp[6],up[6],bp,dv,du,dil);
binary_morph4 #(.WIDTH(IMG_WIDTH),.HEIGHT(IMG_HEIGHT),.DILATE(0)) E(I_clk,I_rst_n,dv,du,dil,cv,cu,closed);
reg [95:0] tail[0:3];reg [3:0] tv,tu,tl;reg [3:0] tm[0:3];
always @(posedge I_clk or negedge I_rst_n) begin
 if(!I_rst_n) begin tv<=0;tu<=0;tl<=0;for(k=0;k<4;k=k+1) begin tail[k]<=0;tm[k]<=0;end end
 else begin
  tv<={tv[2:0],vp[6]};tu<={tu[2:0],up[6]};tl<={tl[2:0],lp[6]};
  tail[0]<=core_data;tm[0]<=mode[6];
  for(k=1;k<4;k=k+1) begin tail[k]<=tail[k-1];tm[k]<=tm[k-1];end
 end
end
assign O_tvalid=tv[3];assign O_tuser=tu[3];assign O_tlast=tl[3];
// The ambient tap must present value and sidebands together, so expose the
// registered vp/up/lp sidebands that line up with `gray`.
assign O_amb_gray=gray;
assign O_amb_user=up[1];
assign O_amb_last=lp[1];
assign O_amb_valid=vp[1];
generate for(i=0;i<4;i=i+1) begin:OUT
 assign O_tdata[24*(3-i)+:24]=tm[3]==6?{24{closed[i]}}:tail[3][24*(3-i)+:24];
end endgenerate
endmodule

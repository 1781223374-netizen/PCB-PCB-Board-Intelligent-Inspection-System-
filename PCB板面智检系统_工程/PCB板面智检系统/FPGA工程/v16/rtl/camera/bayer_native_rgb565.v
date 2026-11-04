`timescale 1ns/1ps
`default_nettype none
// One RGB output per Bayer position: four-site bilinear reconstruction.
// Neighbours reconstruct missing colours; spatial positions are never binned.
// A bounded group FIFO absorbs the cropped RAW burst into two RGB565/clock.
module bayer_native_rgb565 #(
 parameter CROP_WIDTH=1920,CROP_HEIGHT=1080,X_START=972,Y_START=556,
 parameter BLACK_LEVEL=50,FIFO_DEPTH=512
)(
 input wire clk,rst_n,frame_start,line_start,line_end,pixels_valid,
 input wire [39:0] pixels,input wire [1:0] pattern_setting,
 input wire wb_request_toggle,frame_finish,frame_good,
 output reg word_valid,output reg [31:0] rgb_pair,preview_words,
 output wire [127:0] diagnostic,output wire [63:0] calibration_diagnostic,
 output wire idle,output reg frame_error
);
 // Reuse the proven RAW-domain calibration estimator. Its unused preview
 // datapath is eliminated by synthesis; its gains/controls remain unchanged.
 bayer_preview_rgb565 #(.CROP_WIDTH(CROP_WIDTH),.CROP_HEIGHT(CROP_HEIGHT),
  .X_START(X_START),.Y_START(Y_START),.BLACK_LEVEL(BLACK_LEVEL),.DOWNSAMPLE(2)) calibration(
  .clk(clk),.rst_n(rst_n),.frame_start(frame_start),.line_start(line_start),.line_end(line_end),
  .pixels_valid(pixels_valid),.pixels(pixels),.pattern_setting(pattern_setting),
  .wb_request_toggle(wb_request_toggle),.frame_finish(frame_finish),.frame_good(frame_good),
  .word_valid(),.rgb_pair(),.preview_words(),.diagnostic(diagnostic),.calibration_diagnostic(calibration_diagnostic));
 wire [10:0] gain_r=diagnostic[74:64],gain_b=diagnostic[122:112];
 wire [12:0] gain_e=calibration_diagnostic[60:48];
 localparam BUFFER_X=X_START-4,GROUPS=CROP_WIDTH/4+2;
 localparam LA=$clog2(GROUPS),FA=$clog2(FIFO_DEPTH);
 reg [12:0] x,y;reg [1:0] active_pattern;
 wire [12:0] group_index=(x-BUFFER_X)>>2;
 wire take=pixels_valid && x>=BUFFER_X && x<=X_START+CROP_WIDTH;
 (* ram_style="bram" *) reg [39:0] line1[0:GROUPS-1],line2[0:GROUPS-1];
 reg [39:0] tr,mr,br;reg [19:0] ht,hm,hb;
 reg v1,v2,v3,v4,v5;reg [12:0] x1,x2,x3,x4,x5,y1,y2,y3,y4,y5;
 always @(posedge clk)if(take)begin
  tr<=line2[group_index[LA-1:0]];mr<=line1[group_index[LA-1:0]];br<=pixels;
  line2[group_index[LA-1:0]]<=line1[group_index[LA-1:0]];
  line1[group_index[LA-1:0]]<=pixels;
 end
 wire [59:0] t={tr,x1==BUFFER_X?20'd0:ht};
 wire [59:0] m={mr,x1==BUFFER_X?20'd0:hm};
 wire [59:0] b={br,x1==BUFFER_X?20'd0:hb};
 function [9:0] black;input [9:0] a;begin black=a>BLACK_LEVEL?a-BLACK_LEVEL:0;end endfunction
 function [29:0] reconstruct;
  input [9:0] nw,n,ne,w,c,e,sw,s,se;input [1:0] site;
  reg [11:0] cross_sum,diagonal;reg [10:0] horizontal,vertical;
  reg [9:0] rr,gg,bb;
  begin
   cross_sum={2'd0,black(n)}+{2'd0,black(w)}+{2'd0,black(e)}+{2'd0,black(s)};
   diagonal={2'd0,black(nw)}+{2'd0,black(ne)}+{2'd0,black(sw)}+{2'd0,black(se)};
   horizontal={1'b0,black(w)}+{1'b0,black(e)};vertical={1'b0,black(n)}+{1'b0,black(s)};
   case(site)
    0:begin bb=black(c);gg=cross_sum[11:2];rr=diagonal[11:2];end
    1:begin gg=black(c);bb=horizontal[10:1];rr=vertical[10:1];end
    2:begin gg=black(c);rr=horizontal[10:1];bb=vertical[10:1];end
    default:begin rr=black(c);gg=cross_sum[11:2];bb=diagonal[11:2];end
   endcase
   reconstruct={rr,gg,bb};
  end
 endfunction
 function [7:0] clipped;input [33:0] a;begin clipped=a>=34'd67043328 ? 8'd255 : a[25:18];end endfunction
 wire [63:0] colour;
 genvar i;
 generate for(i=0;i<4;i=i+1)begin:lane
  localparam [0:0] ODD=i%2;
  wire [1:0] site=active_pattern^{~y1[0],(~x1[0])^ODD};
  reg [29:0] raw_rgb;
  reg [20:0] pr,pg,pb;reg [33:0] er,eg,eb;reg [15:0] rgb;
  wire [7:0] r8,g8,b8;
  preview_gamma gr(clipped(er),r8),gg(clipped(eg),g8),gb(clipped(eb),b8);
  always @(posedge clk)begin
   raw_rgb<=reconstruct(t[10*i+:10],t[10*(i+1)+:10],t[10*(i+2)+:10],
    m[10*i+:10],m[10*(i+1)+:10],m[10*(i+2)+:10],
    b[10*i+:10],b[10*(i+1)+:10],b[10*(i+2)+:10],site);
   pr<=raw_rgb[29:20]*gain_r;pg<={raw_rgb[19:10],8'd0};pb<=raw_rgb[9:0]*gain_b;
   er<=pr*gain_e;eg<=pg*gain_e;eb<=pb*gain_e;
   rgb<={r8[7:3],g8[7:2],b8[7:3]};
  end
  assign colour[i*16+:16]=rgb;
 end endgenerate
 reg [47:0] previous;
 wire group_valid=v5 && y5>Y_START && y5<=Y_START+CROP_HEIGHT &&
                  x5>=X_START+4 && x5<=X_START+CROP_WIDTH;
 wire [63:0] group_data={colour[15:0],previous};
 (* ram_style="bram" *) reg [63:0] fifo[0:FIFO_DEPTH-1];
 reg [FA-1:0] wp,rp;reg [FA:0] count;
 reg [63:0] read_q;reg read_pending,upper_pending;reg [31:0] upper;
 wire push=group_valid && count<FIFO_DEPTH;
 wire pop=!read_pending && count!=0;
 always @(posedge clk)begin
  if(rst_n && !frame_start && push)fifo[wp]<=group_data;
  if(pop)read_q<=fifo[rp];
 end
 assign idle=count==0 && !read_pending && !upper_pending && !word_valid && !(v1|v2|v3|v4|v5);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   x<=0;y<=0;active_pattern<=1;ht<=0;hm<=0;hb<=0;
   v1<=0;v2<=0;v3<=0;v4<=0;v5<=0;
   x1<=0;x2<=0;x3<=0;x4<=0;x5<=0;y1<=0;y2<=0;y3<=0;y4<=0;y5<=0;
   previous<=0;wp<=0;rp<=0;count<=0;read_pending<=0;upper_pending<=0;upper<=0;
   word_valid<=0;rgb_pair<=0;preview_words<=0;frame_error<=0;
  end else if(frame_start)begin
   x<=0;y<=0;active_pattern<=pattern_setting;ht<=0;hm<=0;hb<=0;
   v1<=0;v2<=0;v3<=0;v4<=0;v5<=0;
   previous<=0;wp<=0;rp<=0;count<=0;read_pending<=0;upper_pending<=0;
   word_valid<=0;preview_words<=0;frame_error<=0;
  end else begin
   if(line_start)x<=0;if(line_end)y<=y+1'b1;if(pixels_valid)x<=x+13'd4;
   v1<=take;v2<=v1;v3<=v2;v4<=v3;v5<=v4;
   x1<=x;y1<=y;x2<=x1;y2<=y1;x3<=x2;y3<=y2;x4<=x3;y4<=y3;x5<=x4;y5<=y4;
   if(v1)begin ht<=tr[39:20];hm<=mr[39:20];hb<=br[39:20];end
   if(v5)previous<=colour[63:16];
   if(group_valid && count==FIFO_DEPTH)frame_error<=1;
   if(push)wp<=wp+1'b1;if(pop)rp<=rp+1'b1;
   case({push,pop})2'b10:count<=count+1'b1;2'b01:count<=count-1'b1;endcase
   read_pending<=pop;word_valid<=0;
   if(read_pending)begin
    rgb_pair<=read_q[31:0];upper<=read_q[63:32];upper_pending<=1;
    word_valid<=1;preview_words<=preview_words+1'b1;
   end else if(upper_pending)begin
    rgb_pair<=upper;upper_pending<=0;word_valid<=1;preview_words<=preview_words+1'b1;
   end
  end
 end
endmodule
`default_nettype wire

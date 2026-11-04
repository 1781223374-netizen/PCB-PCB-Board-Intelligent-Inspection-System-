`timescale 1ns/1ps
`default_nettype none
// DOWNSAMPLE=2: each independent 2x2 Bayer tile becomes one RGB565 pixel.
// DOWNSAMPLE=4 retains the V17 four-tile mean for baseline regression.
module bayer_preview_rgb565 #(
 parameter CROP_WIDTH=1024,CROP_HEIGHT=600,X_START=1420,Y_START=796,
 parameter WB_WIDTH=(CROP_WIDTH<16?CROP_WIDTH:CROP_WIDTH/2),WB_HEIGHT=(CROP_HEIGHT<256?CROP_HEIGHT:256),
 parameter BLACK_LEVEL=50,WHITE_TARGET=768,DOWNSAMPLE=4
)(
 input wire clk,rst_n,frame_start,line_start,line_end,pixels_valid,
 input wire [39:0] pixels,input wire [1:0] pattern_setting,
 input wire wb_request_toggle,frame_finish,frame_good,
 output reg word_valid,output reg [31:0] rgb_pair,
 output reg [31:0] preview_words,output wire [127:0] diagnostic,
 output wire [63:0] calibration_diagnostic
);
 localparam WB_X=X_START+(CROP_WIDTH-WB_WIDTH)/2,WB_Y=Y_START+(CROP_HEIGHT-WB_HEIGHT)/2;
 localparam WB_WORDS=WB_WIDTH*WB_HEIGHT/8,WB_PIXELS=WB_WIDTH*WB_HEIGHT/4;
 localparam [27:0] WHITE_SUM=WB_PIXELS*WHITE_TARGET;
 reg [12:0] x,y;
 reg [19:0] top_a[0:CROP_WIDTH/4-1],top_b[0:CROP_WIDTH/4-1];
 reg [32:0] horizontal[0:CROP_WIDTH/4-1];
 wire within_x=x>=X_START && x<X_START+CROP_WIDTH;
 wire within_y=y>=Y_START && y<Y_START+CROP_HEIGHT;
 wire [12:0] relative_x=x-X_START,relative_y=y-Y_START;
 wire bottom_row=relative_y[0];
 wire emit=pixels_valid && within_x && within_y && bottom_row;
 wire roi=emit && x>=WB_X && x<WB_X+WB_WIDTH && y>=WB_Y && y<WB_Y+WB_HEIGHT;
 wire [9:0] line_addr=relative_x>>2;
 reg [1:0] active_pattern;
 wire [1:0] local_pattern=active_pattern ^ (X_START%2) ^ ((Y_START%2)*2);
 function [9:0] black;
  input [9:0] value;begin black=value>BLACK_LEVEL?value-BLACK_LEVEL:0;end
 endfunction
 function [29:0] planes;
  input [19:0] top,bottom;input [1:0] pattern;reg [9:0] r,b;reg [10:0] g;
  begin
   case(pattern)
    0:begin r=black(bottom[19:10]);b=black(top[9:0]);g={1'b0,black(top[19:10])}+{1'b0,black(bottom[9:0])};end
    1:begin r=black(bottom[9:0]);b=black(top[19:10]);g={1'b0,black(top[9:0])}+{1'b0,black(bottom[19:10])};end
    2:begin r=black(top[19:10]);b=black(bottom[9:0]);g={1'b0,black(top[9:0])}+{1'b0,black(bottom[19:10])};end
    3:begin r=black(top[9:0]);b=black(bottom[19:10]);g={1'b0,black(top[19:10])}+{1'b0,black(bottom[9:0])};end
   endcase
   planes={r,g[10:1],b};
  end
 endfunction
 wire [29:0] p0=planes(top_a[line_addr],pixels[19:0],local_pattern);
 wire [29:0] p1=planes(top_b[line_addr],pixels[39:20],local_pattern);
 wire [10:0] horizontal_r={1'b0,p0[29:20]}+{1'b0,p1[29:20]};
 wire [10:0] horizontal_g={1'b0,p0[19:10]}+{1'b0,p1[19:10]};
 wire [10:0] horizontal_b={1'b0,p0[9:0]}+{1'b0,p1[9:0]};
 wire [32:0] previous_horizontal=horizontal[line_addr];
 wire [11:0] total_r={1'b0,previous_horizontal[32:22]}+{1'b0,horizontal_r};
 wire [11:0] total_g={1'b0,previous_horizontal[21:11]}+{1'b0,horizontal_g};
 wire [11:0] total_b={1'b0,previous_horizontal[10:0]}+{1'b0,horizontal_b};
 reg valid_mean,valid_gain,valid_exposure,valid_color,half_pending;
 reg [29:0] raw_mean,raw_mean_second;
 reg [20:0] product_r,product_g,product_b,product_r_second,product_g_second,product_b_second;
 reg [33:0] exposed_r,exposed_g,exposed_b,exposed_r_second,exposed_g_second,exposed_b_second;
 reg [15:0] color565,color565_second,first_pixel;
 reg [10:0] gain_r,gain_b,next_gain_r,next_gain_b;
 reg [12:0] gain_e,next_gain_e;
 function [7:0] clipped;
  input [33:0] product;begin clipped=product>=34'd67043328 ? 8'd255 : product[25:18];end
 endfunction
 wire [7:0] r8,g8,b8,r8_second,g8_second,b8_second;
 preview_gamma gamma_r(clipped(exposed_r),r8),gamma_g(clipped(exposed_g),g8),gamma_b(clipped(exposed_b),b8);
 preview_gamma gamma_r_second(clipped(exposed_r_second),r8_second),gamma_g_second(clipped(exposed_g_second),g8_second),gamma_b_second(clipped(exposed_b_second),b8_second);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin x<=0;y<=0;raw_mean<=0;raw_mean_second<=0;product_r_second<=0;product_g_second<=0;product_b_second<=0;exposed_r_second<=0;exposed_g_second<=0;exposed_b_second<=0;color565_second<=0;valid_mean<=0;valid_gain<=0;valid_exposure<=0;valid_color<=0;
   product_r<=0;product_g<=0;product_b<=0;exposed_r<=0;exposed_g<=0;exposed_b<=0;
   color565<=0;first_pixel<=0;half_pending<=0;rgb_pair<=0;word_valid<=0;preview_words<=0;end
  else if(frame_start)begin x<=0;y<=0;valid_mean<=0;valid_gain<=0;valid_exposure<=0;valid_color<=0;half_pending<=0;word_valid<=0;preview_words<=0;end
  else begin
   if(line_start)x<=0;
   if(line_end)y<=y+1'b1;
   if(pixels_valid)x<=x+13'd4;
   valid_mean<=emit && (DOWNSAMPLE==2 || relative_y[1]);
   raw_mean<=DOWNSAMPLE==2?p0:{total_r[11:2],total_g[11:2],total_b[11:2]};raw_mean_second<=p1;
   valid_gain<=valid_mean;product_r<=raw_mean[29:20]*gain_r;product_g<={raw_mean[19:10],8'd0};product_b<=raw_mean[9:0]*gain_b;
   product_r_second<=raw_mean_second[29:20]*gain_r;product_g_second<={raw_mean_second[19:10],8'd0};product_b_second<=raw_mean_second[9:0]*gain_b;
   valid_exposure<=valid_gain;exposed_r<=product_r*gain_e;exposed_g<=product_g*gain_e;exposed_b<=product_b*gain_e;
   exposed_r_second<=product_r_second*gain_e;exposed_g_second<=product_g_second*gain_e;exposed_b_second<=product_b_second*gain_e;
   color565_second<={r8_second[7:3],g8_second[7:2],b8_second[7:3]};
   valid_color<=valid_exposure;color565<={r8[7:3],g8[7:2],b8[7:3]};
   word_valid<=0;
   if(valid_color && DOWNSAMPLE==2)begin rgb_pair<={color565_second,color565};word_valid<=1;preview_words<=preview_words+1'b1;end
   else if(valid_color)begin
    half_pending<=!half_pending;
    if(!half_pending)first_pixel<=color565;
    else begin rgb_pair<={color565,first_pixel};word_valid<=1;preview_words<=preview_words+1'b1;end
   end
  end
 end
 always @(posedge clk)if(rst_n && pixels_valid && within_x && within_y && !bottom_row)begin
  top_a[line_addr]<=pixels[19:0];top_b[line_addr]<=pixels[39:20];
 end
 always @(posedge clk)if(rst_n && emit && !relative_y[1])horizontal[line_addr]<={horizontal_r,horizontal_g,horizontal_b};

 reg [27:0] sum_r,sum_g,sum_b,cal_sum_r,cal_sum_g,cal_sum_b;
 reg [31:0] roi_words;
 reg [9:0] mean_r,mean_g,mean_b,cal_r,cal_g,cal_b;
 reg [15:0] calibrations;
 reg seen_request,calibrate_frame,calibrated,apply_pending,cal_failed,solver_start;
 reg [1:0] solver_pattern;
 wire [2:0] solver_busy,solver_done,solver_valid;
 wire [12:0] solution_r,solution_b,solution_e;
 color_ratio_solver red_solver(clk,rst_n,solver_start,cal_sum_g,cal_sum_r,solver_busy[0],solver_done[0],solver_valid[0],solution_r);
 color_ratio_solver blue_solver(clk,rst_n,solver_start,cal_sum_g,cal_sum_b,solver_busy[1],solver_done[1],solver_valid[1],solution_b);
 color_ratio_solver #(.MIN_GAIN(128),.MAX_GAIN(4096)) exposure_solver(clk,rst_n,solver_start,WHITE_SUM,cal_sum_g,solver_busy[2],solver_done[2],solver_valid[2],solution_e);
 wire [1:0] wb_state=((|solver_busy) || calibrate_frame || apply_pending)?2'd2:cal_failed?2'd3:calibrated?2'd1:2'd0;
 assign diagnostic={5'd0,gain_b,calibrations,6'd0,mean_b,5'd0,gain_r,
                    6'd0,mean_r,6'd0,mean_g,22'd0,(|solver_busy),apply_pending,2'd0,wb_state,2'd0,active_pattern};
 assign calibration_diagnostic={3'd0,gain_e,6'd0,cal_b,6'd0,cal_r,6'd0,cal_g};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active_pattern<=1;gain_r<=256;gain_b<=256;gain_e<=256;next_gain_r<=256;next_gain_b<=256;next_gain_e<=256;
   sum_r<=0;sum_g<=0;sum_b<=0;roi_words<=0;mean_r<=0;mean_g<=0;mean_b<=0;cal_r<=0;cal_g<=0;cal_b<=0;
   cal_sum_r<=0;cal_sum_g<=0;cal_sum_b<=0;calibrations<=0;seen_request<=0;calibrate_frame<=0;calibrated<=0;apply_pending<=0;
   cal_failed<=0;solver_start<=0;solver_pattern<=1;end
  else begin
   solver_start<=0;
   if((&solver_done) && (&solver_valid) && solver_pattern==active_pattern && solver_pattern==pattern_setting)begin
    next_gain_r<=solution_r[10:0];next_gain_b<=solution_b[10:0];next_gain_e<=solution_e;apply_pending<=1;
   end
   if(frame_start)begin
    sum_r<=0;sum_g<=0;sum_b<=0;roi_words<=0;active_pattern<=pattern_setting;seen_request<=wb_request_toggle;
    calibrate_frame<=wb_request_toggle!=seen_request && pattern_setting==active_pattern && !(|solver_busy);
    if(wb_request_toggle!=seen_request)cal_failed<=0;
    if(pattern_setting!=active_pattern)begin gain_r<=256;gain_b<=256;gain_e<=256;calibrated<=0;apply_pending<=0;cal_failed<=0;cal_r<=0;cal_g<=0;cal_b<=0;end
    else if(apply_pending)begin gain_r<=next_gain_r;gain_b<=next_gain_b;gain_e<=next_gain_e;apply_pending<=0;calibrated<=1;cal_failed<=0;calibrations<=calibrations+1'b1;end
   end else begin
    if(roi)begin
     sum_r<=sum_r+{18'd0,p0[29:20]}+{18'd0,p1[29:20]};
     sum_g<=sum_g+{18'd0,p0[19:10]}+{18'd0,p1[19:10]};
     sum_b<=sum_b+{18'd0,p0[9:0]}+{18'd0,p1[9:0]};roi_words<=roi_words+1'b1;
    end
    if(frame_finish)begin
     if(frame_good && roi_words==WB_WORDS)begin mean_r<=sum_r/WB_PIXELS;mean_g<=sum_g/WB_PIXELS;mean_b<=sum_b/WB_PIXELS;end
     if(calibrate_frame)begin
      calibrate_frame<=0;
      if(frame_good && roi_words==WB_WORDS && !(|solver_busy) &&
         sum_r>=WB_PIXELS*8 && sum_g>=WB_PIXELS*8 && sum_b>=WB_PIXELS*8 &&
         sum_r<WB_PIXELS*950 && sum_g<WB_PIXELS*950 && sum_b<WB_PIXELS*950)begin
       solver_start<=1;solver_pattern<=active_pattern;cal_sum_r<=sum_r;cal_sum_g<=sum_g;cal_sum_b<=sum_b;
       cal_r<=sum_r/WB_PIXELS;cal_g<=sum_g/WB_PIXELS;cal_b<=sum_b/WB_PIXELS;
      end else cal_failed<=1;
     end
    end
   end
  end
 end
endmodule
`default_nettype wire

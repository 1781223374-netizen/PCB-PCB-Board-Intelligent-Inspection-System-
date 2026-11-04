`timescale 1ns/1ps
// V26.2: classic hierarchical camera menu; image/SD processing remains V26.1.2.
module smart_app #(
 parameter CLOCK_HZ=74250000,WIDTH=1920,HEIGHT=1080,PHOTO_BUFFER_BYTES=98304,BUFFER_ADDR_BITS=21,
 parameter DEBOUNCE_CYCLES=742500,REPEAT_DELAY=29700000,REPEAT_RATE=7425000,
 parameter SD_INIT_DIV=150,SD_DATA_DIV=3,SD_FAST_ODD=1,SD_POWER_WAIT=742500,SD_TIMEOUT=148500000,DENOISE_DEFAULT=2
)(
 input clk,rst_n,input [7:0] key_n,input image_available,buffer_held,play_store_ready,
 input [23:0] in_rgb,input in_de,in_hs,in_vs,input [11:0] in_x,in_y,
 input sd_miso,input exposure_busy,exposure_error,
 input [31:0] camera_frame_id,output wire focus_busy,focus_beep,
 input lift_ready,input [15:0] lift_applied,input lift_enabled,
 output wire lift_apply,output wire [15:0] lift_setting,
 output sd_cs_n,sd_sck,sd_mosi,output reg light_on,output hold_display,
 output play_start,play_write,play_commit,output [BUFFER_ADDR_BITS-1:0] play_addr,output [31:0] play_data,
 output reg [2:0] exposure_level,output [23:0] out_rgb,output out_de,out_hs,out_vs,output [11:0] out_x,out_y,
 output [3:0] file_status,output [7:0] file_error,output reg photo_beep
);
 reg manual_apply,af_start,af_cancel;reg [15:0] manual_setting;
 wire af_apply,metric_valid,metric_usable;
 wire [15:0] af_target,af_best;
 wire [31:0] metric_score,metric_frame,af_score;wire [3:0] af_phase,af_error;
 // DDR briefly lowers image_available while prefetching each new frame.
 // This hysteresis prevents a normal blanking-period refill from aborting AF.
 localparam IMAGE_GRACE=CLOCK_HZ/4,IMAGE_AGE_W=$clog2(IMAGE_GRACE+1);
 reg [IMAGE_AGE_W-1:0] af_image_age;reg af_image_seen;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)begin af_image_age<=IMAGE_GRACE;af_image_seen<=0;end
  else if(image_available)begin af_image_age<=0;af_image_seen<=1;end
  else if(af_image_age<IMAGE_GRACE)af_image_age<=af_image_age+1'b1;
 wire af_scene_ready=af_image_seen && af_image_age<IMAGE_GRACE && !buffer_held;
 assign lift_apply=focus_busy?af_apply:manual_apply;
 assign lift_setting=focus_busy?af_target:manual_setting;
 localparam AF_W=WIDTH>=512?512:32,AF_H=HEIGHT>=256?256:16;
 focus_metric #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.ROI_W(AF_W),.ROI_H(AF_H)) focus_measure(
  .clk(clk),.rst_n(rst_n),.available(image_available && !buffer_held),.rgb(in_rgb),.de(in_de),
  .x(in_x),.y(in_y),.frame_id(camera_frame_id),.valid(metric_valid),.usable(metric_usable),.score(metric_score),.sample_frame(metric_frame));
 focus_controller #(.CLOCK_HZ(CLOCK_HZ)) focus_search(
  .clk(clk),.rst_n(rst_n),.start(af_start),.cancel(af_cancel),.image_available(af_scene_ready),
  .servo_ready(lift_ready),.servo_enabled(lift_enabled),.servo_applied(lift_applied),.servo_apply(af_apply),.servo_target(af_target),
  .metric_valid(metric_valid),.metric_usable(metric_usable),.metric_score(metric_score),.metric_frame(metric_frame),
  .busy(focus_busy),.beep(focus_beep),
  .phase(af_phase),.error(af_error),
  .best_pulse(af_best),.best_score(af_score));

 wire [7:0] press,repeated,down;wire armed;
 ui_keys8 #(.DEBOUNCE_CYCLES(DEBOUNCE_CYCLES),.REPEAT_DELAY(REPEAT_DELAY),.REPEAT_RATE(REPEAT_RATE)) keys(
  clk,rst_n,key_n,press,repeated,down,armed);
 reg play_toggle,request,retry,osd_enable;
 // Original MENU/BACK/UP/DOWN/LEFT/RIGHT/OK/FN navigation, with six live groups.
 // 0 live, 1 main, 2 display settings, 3 capture/storage, 4 playback, 5 light, 6 image algorithms, 7 lift.
 reg [3:0] ui_page;reg [2:0] cursor;reg [2:0] main_cursor,selected,threshold;reg [1:0] play_direction,denoise_mode;
 wire menu_open=ui_page!=0 && ui_page!=4;
 wire play_enable=ui_page==4;
 wire photo_busy=file_status==2 || file_status==3;
 wire play_busy,play_view,play_bank,play_done;
 wire [7:0] events=press|repeated;
 wire up=events[2] && !down[3],dn=events[3] && !down[2];
 wire left=events[4] && !down[5],right=events[5] && !down[4];
 wire save_ready=file_status==1 || file_status==4;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   af_start<=0;af_cancel<=0;manual_apply<=0;manual_setting<=1500;
   ui_page<=0;cursor<=0;main_cursor<=0;selected<=0;threshold<=3;play_toggle<=0;play_direction<=0;request<=0;retry<=0;
   osd_enable<=1;light_on<=0;exposure_level<=6;photo_beep<=1;denoise_mode<=DENOISE_DEFAULT;
  end else begin
   af_start<=0;af_cancel<=0;request<=0;retry<=0;manual_apply<=0;
   if(focus_beep)manual_setting<=af_best;

   // Read cancellation bypasses play_busy; photo writes remain atomic.
   if(focus_busy)begin
    if(press[0] || press[1] || press[6])begin
     af_cancel<=1;
     if(press[0])ui_page<=0;
     else if(press[1])begin ui_page<=1;cursor<=main_cursor;end
    end
   end else if(!photo_busy && play_enable && (press[0] || press[1]))begin
    ui_page<=press[1]?3'd1:3'd0;cursor<=main_cursor;
   end else if(!photo_busy && !play_busy)begin
    if(press[7])light_on<=!light_on;
    if(press[0])begin ui_page<=ui_page==0?3'd1:3'd0;cursor<=main_cursor;end
    else if(press[1])begin
     if(ui_page>1)begin ui_page<=1;cursor<=main_cursor;end
     else if(ui_page==1)ui_page<=0;
    end else case(ui_page)
     0:begin
      if(up || dn)selected<=up?selected-1'b1:selected+1'b1;
      if(left && exposure_level!=0)exposure_level<=exposure_level-1'b1;
      else if(right && exposure_level!=6)exposure_level<=exposure_level+1'b1;
      if(press[6] && save_ready)request<=1;
     end
     1:begin
      if(up)begin cursor<=cursor==0?3'd6:cursor-1'b1;main_cursor<=cursor==0?3'd6:cursor-1'b1;end
      else if(dn)begin cursor<=cursor==6?3'd0:cursor+1'b1;main_cursor<=cursor==6?3'd0:cursor+1'b1;end
      else if(press[6])case(cursor)
       0:begin ui_page<=6;cursor<=selected;end
       1:begin ui_page<=3;cursor<=0;end
       2:if(save_ready)begin ui_page<=4;play_direction<=0;play_toggle<=!play_toggle;end
         else begin ui_page<=3;cursor<=1;end
       3:begin ui_page<=5;cursor<=0;end
       4:begin ui_page<=2;cursor<=0;end
       5:begin ui_page<=7;cursor<=0;end
       6:begin ui_page<=8;cursor<=0;end
      endcase
     end
     2:begin
      if(up)cursor<=cursor==0?3'd2:cursor-1'b1;
      else if(dn)cursor<=cursor==2?3'd0:cursor+1'b1;
      else case(cursor)
       0:if(left && exposure_level!=0)exposure_level<=exposure_level-1'b1;
         else if(right && exposure_level!=6)exposure_level<=exposure_level+1'b1;
       1:if(left && denoise_mode!=0)denoise_mode<=denoise_mode-1'b1;
         else if(right && denoise_mode!=2)denoise_mode<=denoise_mode+1'b1;
         else if(press[6])denoise_mode<=denoise_mode==2?0:denoise_mode+1'b1;
       2:if(left)osd_enable<=0;else if(right)osd_enable<=1;else if(press[6])osd_enable<=!osd_enable;
      endcase
     end
     3:begin
      if(up)cursor<=cursor==0?3'd2:cursor-1'b1;
      else if(dn)cursor<=cursor==2?3'd0:cursor+1'b1;
      else if(cursor==2)begin
       if(left)photo_beep<=0;else if(right)photo_beep<=1;else if(press[6])photo_beep<=!photo_beep;
      end else if(press[6])begin
       if(cursor==0)begin if(save_ready)begin request<=1;ui_page<=0;end end
       else begin retry<=file_status==15;ui_page<=0;end
      end
     end
     4:if(press[4] || press[5] || press[6])begin
      play_direction<=press[4]?2'd1:press[5]?2'd2:2'd0;play_toggle<=!play_toggle;
     end
     5:if(left)light_on<=0;else if(right)light_on<=1;else if(press[6])light_on<=!light_on;
     6:begin
      if(up || dn)cursor<=up?cursor-1'b1:cursor+1'b1;
      if(left && threshold!=0)threshold<=threshold-1'b1;
      else if(right && threshold!=6)threshold<=threshold+1'b1;
      if(press[6])begin selected<=cursor;ui_page<=0;end
     end
     7:begin
      if(up)manual_setting<=manual_setting>=2230?16'd2250:manual_setting+16'd20;
      else if(dn)manual_setting<=manual_setting<=770?16'd750:manual_setting-16'd20;
      else if(press[6] && lift_ready)manual_apply<=1;
     end
     8:if(press[6])af_start<=1;
     default:ui_page<=0;
    endcase
   end
  end
 end
 wire snap_hold,stream_start;wire [7:0] stream_data,stream_error;wire stream_valid,stream_ready;
 assign hold_display=snap_hold || play_enable;
 reg [1:0] warm_frames;reg [27:0] snap_timeout;
 wire snap_ready=buffer_held && image_available && warm_frames>=2;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin warm_frames<=0;snap_timeout<=0;end
  else begin
   if(!snap_hold || !buffer_held)warm_frames<=0;
   else if(in_x==0 && in_y==HEIGHT && !in_de && warm_frames!=3)warm_frames<=warm_frames+1'b1;
   if(!snap_hold || snap_ready)snap_timeout<=0;else if(snap_timeout<CLOCK_HZ*2)snap_timeout<=snap_timeout+1'b1;
  end
 end
 wire [7:0] snap_error=snap_timeout>=CLOCK_HZ*2?8'h40:stream_error;
 wire [23:0] clean_rgb;wire clean_de,clean_hs,clean_vs;wire [11:0] clean_x,clean_y;
 spatial_denoise #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.H_TOTAL(WIDTH+160)) denoise(clk,rst_n,in_rgb,in_de,in_hs,in_vs,in_x,in_y,denoise_mode,play_enable,
  clean_rgb,clean_de,clean_hs,clean_vs,clean_x,clean_y);
 // Reuse the V243C frame-latched ISP at native 720p. Playback uses the
 // equal-latency original path; stored algorithm images are not processed twice.
 wire [23:0] processed;wire processed_de,processed_hs,processed_vs,hist_ready;
 wire [11:0] processed_x,processed_y;
 video_algorithms #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) video(
  clk,rst_n,clean_rgb,clean_de,clean_hs,clean_vs,clean_x,clean_y,selected,threshold,play_enable,
  processed,processed_de,processed_hs,processed_vs,processed_x,processed_y,hist_ready);
 raster_photo_stream #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BUFFER_BYTES(PHOTO_BUFFER_BYTES)) stream(
  clk,rst_n,snap_hold,stream_start,processed,processed_de,processed_x,processed_y,stream_ready,stream_data,stream_valid,stream_error);
 wire card_ready,card_busy,card_done,card_start,card_write,rx_valid;
 wire [7:0] card_error,rx_data,tx_data,play_byte,progress;wire [19:0] file_number;
 wire [31:0] lba;wire [8:0] rx_index,tx_index;wire play_valid,play_ready;
 sd_spi_block #(.INIT_DIV(SD_INIT_DIV),.DATA_DIV(SD_DATA_DIV),.FAST_ODD(SD_FAST_ODD),.POWER_WAIT(SD_POWER_WAIT),.TIMEOUT(SD_TIMEOUT)) sd(
  clk,rst_n,retry,card_start,card_write,lba,card_ready,card_busy,card_done,card_error,rx_index,rx_valid,rx_data,
  tx_index,tx_data,sd_cs_n,sd_sck,sd_mosi,sd_miso);
 fat32_photo #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) fs(clk,rst_n,request,retry,card_ready,card_busy,card_done,card_error,
  card_start,card_write,lba,rx_valid,rx_data,tx_index,tx_data,snap_hold,snap_ready,snap_error,stream_start,
  stream_data,stream_valid,stream_ready,file_status,file_error,progress,file_number,play_enable,play_toggle,
  play_direction,play_busy,play_view,play_start,play_bank,play_byte,play_valid,play_ready,play_done);
 playback_rgb565 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SCALE(1),.ADDR_BITS(BUFFER_ADDR_BITS)) playback(
  clk,rst_n,play_enable && buffer_held,play_start,play_byte,play_valid,play_ready,play_done,play_write,play_addr,play_data,play_store_ready);
 reg bank_seen;
 always @(posedge clk or negedge rst_n)if(!rst_n)bank_seen<=0;else bank_seen<=play_bank;
 assign play_commit=bank_seen!=play_bank;
 camera_osd #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) osd_video(
  .clk(clk),.rst_n(rst_n),.rgb(processed),.de(processed_de),.hs(processed_hs),.vs(processed_vs),.x(processed_x),.y(processed_y),
  .available(image_available),.playback(play_enable),.page(ui_page),.cursor(cursor),.osd_enable(osd_enable),
  .selected(selected),.threshold(threshold),.hist_ready(hist_ready),
  .light(light_on),.photo_beep(photo_beep),.exposure(exposure_level),.denoise(denoise_mode),
  .status(file_status),.error(file_error),.progress(progress),.number(file_number),
  .exposure_busy(exposure_busy),.exposure_error(exposure_error),
  .focus_busy(focus_busy),.focus_phase(af_phase),.focus_error(af_error),
  .focus_best(af_best),
  .lift_setting(lift_setting),.lift_applied(lift_applied),.lift_enabled(lift_enabled),.lift_ready(lift_ready),
  .out_rgb(out_rgb),.out_de(out_de),.out_hs(out_hs),.out_vs(out_vs),.out_x(out_x),.out_y(out_y));

endmodule

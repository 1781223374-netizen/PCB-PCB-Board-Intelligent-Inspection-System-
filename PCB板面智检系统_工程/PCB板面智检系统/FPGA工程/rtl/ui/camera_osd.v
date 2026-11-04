`timescale 1ns/1ps
// V26.2: V24.3 reference visual language, original 80x80 Anlogic logo,
// proportional 720p placement and only current camera functions.
module camera_osd #(parameter WIDTH=1920,HEIGHT=1080)(
 input clk,rst_n,input [23:0] rgb,input de,hs,vs,input [11:0] x,y,
 input available,playback,input [3:0] page,input [2:0] cursor,input osd_enable,light,photo_beep,
 input [2:0] exposure,selected,threshold,input hist_ready,input [1:0] denoise,input [3:0] status,input [7:0] error,progress,
 input [19:0] number,input exposure_busy,exposure_error,
 input focus_busy,input [3:0] focus_phase,focus_error,
 input [15:0] focus_best,
 input [15:0] lift_setting,lift_applied,input lift_enabled,lift_ready,
 output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs,output reg [11:0] out_x,out_y
);
 localparam PANEL_X=WIDTH-560,PANEL_R=WIDTH-16,PANEL_Y=144,PANEL_B=640;
 wire menu_open=page!=0 && page!=4;
 wire visible=osd_enable || menu_open;
 reg [23:0] background,foreground;reg text_on;
 reg [6:0] line;reg [5:0] column;reg [3:0] font_row,font_bit;
 reg [11:0] relative_y;reg [2:0] row;reg [3:0] rows;
 reg [6:0] title,entry,status_line;
 always @*begin
  case(status)0:status_line=27;1:status_line=28;2:status_line=29;3:status_line=30;4:status_line=31;
   6:status_line=32;7:status_line=33;8:status_line=34;9:status_line=35;default:status_line=36;endcase
  title=10;entry=14;rows=7;
  case(page)8:begin title=65;entry=66;rows=3;end
   7:begin title=56;entry=59;rows=1;end
   6:begin title=55;entry=47;rows=8;end
   2:begin title=12;entry=21;rows=3;end
   3:begin title=11;entry=60;rows=3;end
   5:begin title=13;entry=24;rows=1;end
  endcase
  background=rgb;foreground=24'he8eef5;text_on=0;line=0;column=0;font_row=0;font_bit=0;relative_y=0;row=0;
  if(visible)begin
   if(y<112)background=24'h102034;
   if(y==110)background=24'h2e6279;
   if(x>=112 && x<496 && y>=16 && y<48)begin
    text_on=1;line=0;column=(x-112)>>5;font_row=(y-16)>>1;font_bit=(x-112)>>1;foreground=24'h7be3ca;
   end else if(x>=112 && x<752 && y>=64 && y<80)begin
    text_on=1;line=playback?3:47+selected;column=(x-112)>>4;font_row=y-64;font_bit=x-112;
   end else if(x>=112 && x<752 && y>=88 && y<104)begin
    text_on=1;line=exposure_error?40:exposure_busy?39:5;column=(x-112)>>4;font_row=y-88;font_bit=x-112;
    foreground=exposure_error?24'hff6060:24'h9cb4c9;
   end else if(x>=WIDTH-336 && x<WIDTH-16 && y>=20 && y<36)begin
    text_on=1;line=status_line;column=(x-(WIDTH-336))>>4;font_row=y-20;font_bit=x-(WIDTH-336);
    foreground=status==15?24'hff6060:24'h7be3ca;
   end else if(x>=WIDTH-336 && x<WIDTH-16 && y>=48 && y<64)begin
    text_on=1;line=6;column=(x-(WIDTH-336))>>4;font_row=y-48;font_bit=x-(WIDTH-336);foreground=24'h9cb4c9;
   end else if(x>=WIDTH-336 && x<WIDTH-16 && y>=80 && y<96)begin
    text_on=1;line=playback?3:available?38:37;column=(x-(WIDTH-336))>>4;font_row=y-80;font_bit=x-(WIDTH-336);
    foreground=available?24'h7be3ca:24'hffc565;
   end
   if(menu_open && x>=PANEL_X && x<PANEL_R && y>=PANEL_Y && y<PANEL_B)begin
    background=24'h142a42;text_on=0;
    if(x==PANEL_X || x==PANEL_R-1 || y==PANEL_Y || y==PANEL_B-1 || y==198 || y==536)background=24'h2e6279;
    if(y<PANEL_Y+3)background=24'h7be3ca;
    if(x>=PANEL_X+24 && x<PANEL_R-16 && y>=168 && y<184)begin
     text_on=1;line=title;column=(x-PANEL_X-24)>>4;font_row=y-168;font_bit=x-PANEL_X-24;foreground=24'h7be3ca;
    end else if(y>=216 && y<536)begin
     relative_y=y-216;row=relative_y/40;
     if(row<rows)begin
      if(x>=PANEL_X+12 && x<PANEL_R-12 && relative_y%40<32 && row==cursor)begin
       background=24'h22647b;
       if(x<PANEL_X+16)background=24'h7be3ca;
      end
      if(x>=PANEL_X+24 && x<PANEL_R-16 && relative_y%40>=8 && relative_y%40<24)begin
       text_on=1;line=page==1 && row==6?7'd64:entry+row;column=(x-PANEL_X-24)>>4;font_row=relative_y%40-8;font_bit=x-PANEL_X-24;
       foreground=row==cursor?24'hffffff:24'he8eef5;
      end
     end
    end else if(x>=PANEL_X+24 && x<PANEL_R-16 && y>=560 && y<576)begin
     text_on=1;line=page==8?73:page==7?63:page==6?58:page==1?26:page==3?(cursor==1?42:41):25;
     column=(x-PANEL_X-24)>>4;font_row=y-560;font_bit=x-PANEL_X-24;foreground=24'h9cb4c9;
    end else if(x>=PANEL_X+24 && x<PANEL_R-16 && y>=608 && y<624)begin
     text_on=1;line=page==8?74:page==7?20:46;column=(x-PANEL_X-24)>>4;font_row=y-608;font_bit=x-PANEL_X-24;foreground=24'h9cb4c9;
    end
    if(page==6 && x>=PANEL_R-144 && x<PANEL_R-16 && y>=168 && y<184)begin
     text_on=1;line=57;column=(x-(PANEL_R-144))>>4;font_row=y-168;font_bit=x-(PANEL_R-144);foreground=24'hffc565;
    end
   end
  end
  // Focus status remains readable after leaving its menu or hiding OSD.
  if(x>=800 && x<1440 && y>=48 && y<64)begin
   background=24'h102034;foreground=focus_phase==7?24'hff6060:24'h7be3ca;text_on=1;line=75;
   column=(x-800)>>4;font_row=y-48;font_bit=x-800;
  end
  if((page==8 || focus_busy) && ((x>=704 && x<1216 && (y==412 || y==667)) || (y>=412 && y<668 && (x==704 || x==1215))))background=24'h7be3ca;
 // Pulse setting and actual applied PWM stay visible on every page, even
 // with the general OSD hidden. 40 characters fit between logo and status.
  if(x>=800 && x<1440 && y>=24 && y<40)begin
   background=24'h102034;foreground=24'hffc565;text_on=1;line=1;
   column=(x-800)>>4;font_row=y-24;font_bit=x-800;
  end
 end
 wire logo_visible=visible && x>=16 && x<96 && y>=8 && y<88;
 wire [12:0] logo_address=(y-8)*13'd80+(x-16);wire [24:0] logo_pixel;
 anlogic_logo_small logo(clk,logo_address,logo_pixel);
 reg logo_a;reg [6:0] line_a;reg [5:0] column_a;reg [2:0] exposure_a,threshold_a;reg [1:0] denoise_a;
 reg focus_busy_a;reg [3:0] focus_phase_a,focus_error_a;
 reg [15:0] focus_best_a;
 reg [15:0] lift_setting_a,lift_applied_a;reg lift_enabled_a,lift_ready_a;
 reg light_a,beep_a,osd_a;reg [7:0] progress_a,error_a;reg [19:0] number_a;
 reg [3:0] row_a,bit_a,row_b,bit_b;reg text_a,text_b,de_a,hs_a,vs_a,de_b,hs_b,vs_b;
 reg [23:0] bg_a,fg_a,bg_b,fg_b;reg [11:0] x_a,y_a,x_b,y_b;wire [7:0] character;wire [15:0] glyph;
 reg [15:0] glyph_c;reg [3:0] bit_c;reg text_c,de_c,hs_c,vs_c;
 reg [23:0] bg_c,fg_c;reg [11:0] x_c,y_c;
 classic_menu_text text_rom(clk,line_a,column_a,exposure_a,denoise_a,light_a,beep_a,osd_a,threshold_a,progress_a,error_a,number_a,character,lift_setting_a,lift_applied_a,lift_enabled_a,lift_ready_a,focus_busy_a,focus_phase_a,focus_error_a,focus_best_a);
 osd_font16 font(character,row_b,glyph);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   focus_busy_a<=0;focus_phase_a<=0;focus_error_a<=0;focus_best_a<=1500;
   lift_setting_a<=1500;lift_applied_a<=1500;lift_enabled_a<=0;lift_ready_a<=0;
   logo_a<=0;line_a<=0;column_a<=0;exposure_a<=6;threshold_a<=3;denoise_a<=0;light_a<=0;beep_a<=1;osd_a<=1;progress_a<=0;error_a<=0;number_a<=0;
   row_a<=0;bit_a<=0;row_b<=0;bit_b<=0;text_a<=0;text_b<=0;de_a<=0;hs_a<=0;vs_a<=0;de_b<=0;hs_b<=0;vs_b<=0;
   bg_a<=0;fg_a<=0;bg_b<=0;fg_b<=0;x_a<=0;y_a<=0;x_b<=0;y_b<=0;
   glyph_c<=0;bit_c<=0;text_c<=0;de_c<=0;hs_c<=0;vs_c<=0;bg_c<=0;fg_c<=0;x_c<=0;y_c<=0;
   out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;out_x<=0;out_y<=0;
  end else begin
   focus_busy_a<=focus_busy;focus_phase_a<=focus_phase;focus_error_a<=focus_error;focus_best_a<=focus_best;
   lift_setting_a<=lift_setting;lift_applied_a<=lift_applied;lift_enabled_a<=lift_enabled;lift_ready_a<=lift_ready;
   logo_a<=logo_visible;line_a<=line;column_a<=column;exposure_a<=exposure;threshold_a<=threshold;denoise_a<=denoise;
   light_a<=light;beep_a<=photo_beep;osd_a<=osd_enable;progress_a<=progress;error_a<=error;number_a<=number;
   row_a<=font_row;bit_a<=font_bit;text_a<=text_on;bg_a<=background;fg_a<=foreground;de_a<=de;hs_a<=hs;vs_a<=vs;x_a<=x;y_a<=y;
   row_b<=row_a;bit_b<=bit_a;text_b<=text_a;bg_b<=logo_a && logo_pixel[24]?logo_pixel[23:0]:bg_a;
   fg_b<=fg_a;de_b<=de_a;hs_b<=hs_a;vs_b<=vs_a;x_b<=x_a;y_b<=y_a;
   glyph_c<=glyph;bit_c<=bit_b;text_c<=text_b;bg_c<=bg_b;fg_c<=fg_b;
   de_c<=de_b;hs_c<=hs_b;vs_c<=vs_b;x_c<=x_b;y_c<=y_b;
   out_rgb<=!de_c?24'd0:text_c && glyph_c[15-bit_c]?fg_c:bg_c;
   out_de<=de_c;out_hs<=hs_c;out_vs<=vs_c;out_x<=x_c;out_y<=y_c;
  end
 end
endmodule

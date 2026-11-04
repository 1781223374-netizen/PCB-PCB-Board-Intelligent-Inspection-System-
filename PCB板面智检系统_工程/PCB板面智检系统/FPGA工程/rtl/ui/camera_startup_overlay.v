`timescale 1ns/1ps
`default_nettype none
// Always passive: this overlay neither acknowledges faults nor changes acceptance.
// It disappears after a clean live frame; it returns on a latched DMA fault.
module camera_startup_overlay(
 input wire clk,rst_n,input wire [23:0] rgb,input wire de,hs,vs,input wire [11:0] x,y,
 input wire available,input wire [15:0] cfg,input wire [415:0] cam_diag,input wire [31:0] byte_hz,
 input wire [351:0] ddr_diag,output reg [23:0] out_rgb,output reg out_de,out_hs,out_vs
);
 function [7:0] hexchar;input [3:0] v;begin hexchar=v<10?8'd48+v:8'd55+v;end endfunction
 function [383:0] puthex;input [383:0] s;input integer start,n;input [31:0] value;integer j;
  begin puthex=s;for(j=0;j<n;j=j+1)puthex[383-(start+j)*8-:8]=hexchar((value>>((n-1-j)*4))&15);end
 endfunction
 reg [383:0] text;reg show;reg [5:0] col;reg [3:0] row,font_row,font_bit;
 always @*begin
  text=384'd0;col=0;row=0;font_row=0;font_bit=0;
  show=(!available || ddr_diag[325]) && x>=16 && x<784 && y>=64 && y<224;
  if(show)begin
   col=(x-16)>>4;row=(y-64)>>4;font_row=(y-64)&15;font_bit=(x-16)&15;
   case(row)
    0:begin text="STARTUP V2632    WAITING FOR CAMERA             ";
    end
    1:begin text="CFG:0 ERR:0 IDX:000 TRY:0 BYTE_HZ:00000000      ";
      text=puthex(text,4,1,{31'd0,cfg[11]});
      text=puthex(text,10,1,{31'd0,cfg[10]});
      text=puthex(text,16,3,{23'd0,cfg[8:0]});
      text=puthex(text,24,1,{29'd0,cfg[14:12]});
      text=puthex(text,34,8,byte_hz);
    end
    2:begin text="MIPI DONE:0 EYE:0 TAP:00000000                  ";
      text=puthex(text,10,1,cam_diag[224+:32]);
      text=puthex(text,16,1,{28'd0,cam_diag[228+:4]});
      text=puthex(text,22,8,cam_diag[192+:32]);
    end
    3:begin text="FS:00000000 FE:00000000 CSI:00000000            ";
      text=puthex(text,3,8,cam_diag[0+:32]);
      text=puthex(text,15,8,cam_diag[32+:32]);
      text=puthex(text,28,8,cam_diag[64+:32]);
    end
    4:begin text="GEO:00000000 ROWS:0000 PAIRS:00000000           ";
      text=puthex(text,4,8,cam_diag[96+:32]);
      text=puthex(text,18,4,cam_diag[128+:32]);
      text=puthex(text,29,8,cam_diag[160+:32]);
    end
    5:begin text="DDR FLAGS:00 STORE:00000000 DROP:00000000       ";
      text=puthex(text,10,2,ddr_diag[320+:32]);
      text=puthex(text,19,8,ddr_diag[0+:32]);
      text=puthex(text,33,8,ddr_diag[64+:32]);
    end
    6:begin text="DMA CAUSE:00 WR:00000000 RD:00000000            ";
      text=puthex(text,10,2,ddr_diag[192+:32]);
      text=puthex(text,16,8,ddr_diag[96+:32]);
      text=puthex(text,28,8,ddr_diag[128+:32]);
    end
    7:begin text="BADHDR:00000000 CRC:00000000 TRUNC:00000000     ";
      text=puthex(text,7,8,cam_diag[256+:32]);
      text=puthex(text,20,8,cam_diag[288+:32]);
      text=puthex(text,35,8,cam_diag[320+:32]);
    end
    8:begin text="GEO FLAGS:00 MISSING_SOT:00000000               ";
      text=puthex(text,10,2,{24'd0,cam_diag[144+:8]});
      text=puthex(text,25,8,cam_diag[352+:32]);
    end
    9:begin text="COUNTERS ABOVE ARE HEX; BOARD K1 RESETS         ";
    end
    default:text=384'd0;
   endcase
  end
 end
 reg [383:0] text_a;reg [5:0] col_a;
 reg [3:0] font_row_a,font_bit_a;reg show_a,de_a,hs_a,vs_a;reg [23:0] rgb_a;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin text_a<=0;col_a<=0;font_row_a<=0;font_bit_a<=0;show_a<=0;de_a<=0;hs_a<=0;vs_a<=0;rgb_a<=0;end
  else begin text_a<=text;col_a<=col;font_row_a<=font_row;font_bit_a<=font_bit;show_a<=show;de_a<=de;hs_a<=hs;vs_a<=vs;rgb_a<=rgb;end
 end
 reg [7:0] character;reg [3:0] glyph_row,glyph_bit;wire [15:0] glyph;
 reg show_q,de_q,hs_q,vs_q;reg [23:0] rgb_q;
 reg [15:0] glyph_r;reg [3:0] bit_r;reg show_r,de_r,hs_r,vs_r;reg [23:0] rgb_r;
 osd_font16 font(character,glyph_row,glyph);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin character<=0;glyph_row<=0;glyph_bit<=0;show_q<=0;de_q<=0;hs_q<=0;vs_q<=0;rgb_q<=0;
   glyph_r<=0;bit_r<=0;show_r<=0;de_r<=0;hs_r<=0;vs_r<=0;rgb_r<=0;
   out_rgb<=0;out_de<=0;out_hs<=0;out_vs<=0;end
  else begin
   character<=text_a[383-col_a*8-:8];glyph_row<=font_row_a;glyph_bit<=font_bit_a;show_q<=show_a;
   de_q<=de_a;hs_q<=hs_a;vs_q<=vs_a;rgb_q<=rgb_a;
   glyph_r<=glyph;bit_r<=glyph_bit;show_r<=show_q;de_r<=de_q;hs_r<=hs_q;vs_r<=vs_q;rgb_r<=rgb_q;
   out_rgb<=!de_r?24'd0:show_r?(glyph_r[15-bit_r]?24'hfff0b0:24'h102034):rgb_r;
   out_de<=de_r;out_hs<=hs_r;out_vs<=vs_r;
  end
 end
endmodule
`default_nettype wire

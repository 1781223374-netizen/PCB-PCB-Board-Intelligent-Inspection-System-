`timescale 1ns/1ps
`default_nettype none
// Logical read address uses a padded row stride; DDR stores packed rows.
module preview_display_rgb565 #(parameter WIDTH=1920,HEIGHT=1080,ADDR_BITS=21)(
 input wire clk,rst_n,image_available,test_pattern,input wire [31:0] framebuffer_data,
 output wire read_enable,output wire [ADDR_BITS-1:0] read_addr,
 output wire buffer_boundary,display_line_end,
 output wire [23:0] rgb,output reg de,hs,vs,output reg [11:0] pixel_x,pixel_y
);
 localparam ROW_SHIFT=$clog2(WIDTH/2);
 wire [11:0] x,y;wire current_de,current_hs,current_vs;
 reg select_upper,available_d,pattern_d;reg [23:0] no_image_rgb,test_rgb;
 wire [15:0] pixel=select_upper?framebuffer_data[31:16]:framebuffer_data[15:0];
 wire [23:0] expanded={{pixel[15:11],pixel[15:13]},{pixel[10:5],pixel[10:9]},{pixel[4:0],pixel[4:2]}};
 raster #(.H_ACTIVE(WIDTH),.V_ACTIVE(HEIGHT)) u_raster(clk,rst_n,x,y,current_de,current_hs,current_vs,buffer_boundary);
 assign read_addr=({{(ADDR_BITS-12){1'b0}},y}<<ROW_SHIFT)+(x>>1);
 assign display_line_end=current_de && x==WIDTH-1;
 assign read_enable=current_de;
 assign rgb=!de?24'd0:pattern_d?test_rgb:available_d?expanded:no_image_rgb;
 reg [23:0] pattern_now;
 always @*begin
  case(x/(WIDTH/8))
   0:pattern_now=24'hffffff;1:pattern_now=24'hffff00;2:pattern_now=24'h00ffff;3:pattern_now=24'h00ff00;
   4:pattern_now=24'hff00ff;5:pattern_now=24'hff0000;6:pattern_now=24'h0000ff;default:pattern_now=0;
  endcase
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin de<=0;hs<=0;vs<=0;select_upper<=0;available_d<=0;pattern_d<=0;no_image_rgb<=0;test_rgb<=0;pixel_x<=0;pixel_y<=0;end
  else begin
   de<=current_de;hs<=current_hs;vs<=current_vs;select_upper<=x[0];available_d<=image_available;pattern_d<=test_pattern;
   pixel_x<=x;pixel_y<=y;test_rgb<=pattern_now;no_image_rgb<=x[6]^y[6]?24'h204060:24'h102030;
  end
 end
endmodule
`default_nettype wire

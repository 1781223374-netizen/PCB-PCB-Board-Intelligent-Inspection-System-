`timescale 1ns/1ps
`default_nettype none
// F9P onboard HC595 chain, matching vendor demo 17_spi_hc595:
// MSB-first digit select 08, then active-low dp/g/f/e/d/c/b/a segments.
// One digit remains selected; the other seven are blank. No scan clock needed.
module board_id_hc595 #(parameter HALF_PERIOD=125,REFRESH_CYCLES=250000)(
 input wire clk,rst_n,input wire [1:0] device_id,input wire profile_done,
 output reg sclk,mosi,latch
);
 localparam CW=HALF_PERIOD>1?$clog2(HALF_PERIOD+1):1;
 localparam RW=REFRESH_CYCLES>1?$clog2(REFRESH_CYCLES+1):1;
 reg [7:0] segments;
 always @*begin
  segments=8'hbf;
  if(profile_done)case(device_id)
   1:segments=8'hf9;2:segments=8'ha4;3:segments=8'hb0;default:segments=8'h86;
  endcase
 end
 reg [15:0] payload;reg [3:0] bit_count;reg [1:0] state;
 reg [CW-1:0] divider;reg [RW-1:0] refresh;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sclk<=0;mosi<=0;latch<=0;payload<=0;bit_count<=0;state<=0;divider<=0;refresh<=0;end
  else case(state)
   0:begin
    latch<=0;
    if(refresh==REFRESH_CYCLES-1)begin
     payload<={8'h08,segments};mosi<=0;bit_count<=0;divider<=0;refresh<=0;state<=1;
    end else refresh<=refresh+1'b1;
   end
   1:if(divider==HALF_PERIOD-1)begin
    divider<=0;sclk<=1;state<=2;
   end else divider<=divider+1'b1;
   2:if(divider==HALF_PERIOD-1)begin
    divider<=0;sclk<=0;
    if(bit_count==15)begin latch<=1;state<=3;end
    else begin payload<={payload[14:0],1'b0};mosi<=payload[14];bit_count<=bit_count+1'b1;state<=1;end
   end else divider<=divider+1'b1;
   3:begin latch<=0;state<=0;end
   default:state<=0;
  endcase
 end
endmodule
`default_nettype wire

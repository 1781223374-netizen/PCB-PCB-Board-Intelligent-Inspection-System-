`timescale 1ns/1ps
// IMX415 datasheet pp.39,70-73,82: VMAX=2250, 8 <= SHR0 <= 2246.
// All image processing remains RTL. Both masters drive open-drain pins;
// initialization owns the bus until configured is asserted.
module imx415_exposure #(parameter HALF_CYCLES=250,RETRIES=2)(
 input clk,rst_n,configured,input [2:0] level,
 output reg busy,error,output reg [2:0] applied,inout scl,sda);
 reg [1:0] state;reg [2:0] seen,target,index,retries;reg [15:0] shr;
 reg start,had_error;wire transaction_busy,done,failed;
 reg [15:0] address;reg [7:0] value;
 always @*begin
  address=16'h3001;value=0;
  case(index)
   0:value=1;
   1:begin address=16'h3050;value=shr[7:0];end
   2:begin address=16'h3051;value=shr[15:8];end
   3:begin address=16'h3052;value=0;end
   default:begin address=16'h3001;value=0;end
  endcase
 end
 i2c_write16 #(.HALF_CYCLES(HALF_CYCLES)) bus(clk,rst_n,start,address,value,transaction_busy,done,failed,scl,sda);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin state<=0;seen<=6;target<=6;applied<=6;index<=0;retries<=0;shr<=8;start<=0;had_error<=0;busy<=0;error<=0;end
  else begin
   start<=0;
   case(state)
    0:if(configured && level!=seen && level<=6)begin
     seen<=level;target<=level;index<=0;retries<=0;had_error<=0;busy<=1;error<=0;state<=1;
     case(level)0:shr<=2218;1:shr<=2186;2:shr<=2122;3:shr<=1994;4:shr<=1738;5:shr<=1226;default:shr<=8;endcase
    end
    1:if(!transaction_busy)begin start<=1;state<=2;end
    2:if(done)begin
     if(failed && retries<RETRIES)begin retries<=retries+1'b1;state<=1;end
     else if(failed)begin
      error<=1;had_error<=1;retries<=0;
      // Always attempt to release REGHOLD after an interrupted update.
      if(index==4)begin busy<=0;state<=0;end else begin index<=4;state<=1;end
     end else if(index==4)begin
      if(!had_error)applied<=target;busy<=0;state<=0;
     end else begin index<=index+1'b1;retries<=0;state<=1;end
    end
    default:state<=0;
   endcase
  end
 end
endmodule

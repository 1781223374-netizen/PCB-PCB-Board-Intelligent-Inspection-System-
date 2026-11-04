`timescale 1ns/1ps
module photo_buzzer #(parameter CLOCK_HZ=74250000)(
 input clk,rst_n,photo_enable,input [3:0] file_status,input [7:0] file_error,output buzzer_n
);
 reg [3:0] previous_status;reg [31:0] left;
 assign buzzer_n=!(photo_enable && left!=0);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin previous_status<=0;left<=0;end
  else begin
   previous_status<=file_status;
   if(!photo_enable)left<=0;
   else if(file_status==4 && previous_status!=4 && file_error==0)left<=CLOCK_HZ/8;
   else if(left!=0)left<=left-1'b1;
  end
 end
endmodule

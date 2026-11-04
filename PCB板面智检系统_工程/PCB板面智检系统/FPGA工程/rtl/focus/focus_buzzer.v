`timescale 1ns/1ps
`default_nettype none
module focus_buzzer #(parameter CLOCK_HZ=114750000)(
 input wire clk,rst_n,success,output wire buzzer_n);
 localparam DURATION=CLOCK_HZ/8,COUNT_W=$clog2(DURATION+1);
 reg [COUNT_W-1:0] left;
 assign buzzer_n=left==0;
 always @(posedge clk or negedge rst_n)
  if(!rst_n)left<=0;
  else if(success)left<=DURATION;
  else if(left!=0)left<=left-1'b1;
endmodule
`default_nettype wire

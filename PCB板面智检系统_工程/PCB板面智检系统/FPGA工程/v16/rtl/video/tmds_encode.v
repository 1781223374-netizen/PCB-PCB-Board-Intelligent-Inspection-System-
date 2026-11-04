`timescale 1ns/1ps
`default_nettype none
// Two equal-latency stages: transition minimization, then DC balance.
module tmds_encode(input wire clk,rst_n,de,input wire [7:0] data,
 input wire [1:0] control,output reg [9:0] symbol);
 function [3:0] pop8;input [7:0] value;
  begin pop8=({3'd0,value[0]}+{3'd0,value[1]})+({3'd0,value[2]}+{3'd0,value[3]})+
             ({3'd0,value[4]}+{3'd0,value[5]})+({3'd0,value[6]}+{3'd0,value[7]});end
 endfunction
 wire [3:0] ones=pop8(data);
 wire xnor_mode=ones>4 || (ones==4 && !data[0]);
 reg [8:0] transition;integer k;
 always @*begin
  transition[0]=data[0];
  for(k=1;k<8;k=k+1)transition[k]=transition[k-1]^data[k]^xnor_mode;
  transition[8]=!xnor_mode;
 end
 wire [3:0] q_ones=pop8(transition[7:0]);
 reg [8:0] q;reg signed [4:0] balance;reg active;reg [1:0] ctl;
 reg signed [5:0] disparity;
 wire signed [5:0] b={balance[4],balance};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin q<=0;balance<=0;active<=0;ctl<=0;symbol<=10'b1101010100;disparity<=0;end
  else begin
   q<=transition;balance<=$signed({q_ones,1'b0})-5'sd8;active<=de;ctl<=control;
   if(!active)begin
    disparity<=0;
    case(ctl)
     0:symbol<=10'b1101010100;1:symbol<=10'b0010101011;
     2:symbol<=10'b0101010100;3:symbol<=10'b1010101011;
    endcase
   end else if(disparity==0 || b==0)begin
    symbol<={!q[8],q[8],q[8]?q[7:0]:~q[7:0]};
    disparity<=q[8]?disparity+b:disparity-b;
   end else if((disparity>0 && b>0) || (disparity<0 && b<0))begin
    symbol<={1'b1,q[8],~q[7:0]};
    disparity<=disparity+(q[8]?6'sd2:6'sd0)-b;
   end else begin
    symbol<={1'b0,q[8],q[7:0]};
    disparity<=disparity-(q[8]?6'sd0:6'sd2)+b;
   end
  end
 end
endmodule
`default_nettype wire

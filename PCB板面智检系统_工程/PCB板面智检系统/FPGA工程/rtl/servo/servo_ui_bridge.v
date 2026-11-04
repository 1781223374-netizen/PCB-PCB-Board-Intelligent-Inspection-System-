`timescale 1ns/1ps
`default_nettype none
// Two bundled-data mailboxes. Both sides asynchronously reset together, then
// release locally. Data is held until a two-flop synchronized acknowledgement;
// the receiver waits two more clocks before sampling the held bus. No bitwise
// synchronization of a changing binary pulse value is used.
module servo_ui_bridge(
 input wire rst_n,ui_clk,ui_apply,input wire [15:0] ui_target,output wire ui_ready,
 input wire net_clk,output reg net_apply,output reg [15:0] net_target,
 input wire [15:0] net_applied,input wire net_enabled,
 output reg [15:0] ui_applied,output reg ui_enabled);
 (* async_reg="true" *) reg [1:0] ui_release,net_release;
 always @(posedge ui_clk or negedge rst_n)
  if(!rst_n)ui_release<=0;else ui_release<={ui_release[0],1'b1};
 always @(posedge net_clk or negedge rst_n)
  if(!rst_n)net_release<=0;else net_release<={net_release[0],1'b1};
 reg request,acknowledge;(* keep="true" *)reg [15:0] held_target;
 (* async_reg="true" *)reg [1:0] request_sync,ack_sync;
 reg [1:0] request_settling;
 assign ui_ready=ui_release[1] && ack_sync[1]==request;
 always @(posedge ui_clk or negedge ui_release[1])begin
  if(!ui_release[1])begin request<=0;held_target<=1500;ack_sync<=0;end
  else begin
   ack_sync<={ack_sync[0],acknowledge};
   if(ui_apply && ui_ready)begin held_target<=ui_target;request<=~request;end
  end
 end
 always @(posedge net_clk or negedge net_release[1])begin
  if(!net_release[1])begin
   request_sync<=0;acknowledge<=0;request_settling<=0;net_apply<=0;net_target<=1500;
  end else begin
   request_sync<={request_sync[0],request};net_apply<=0;
   if(request_sync[1]!=acknowledge)begin
    if(request_settling==2)begin
     net_target<=held_target;net_apply<=1;acknowledge<=request_sync[1];request_settling<=0;
    end else request_settling<=request_settling+1'b1;
   end else request_settling<=0;
  end
 end
 // Latest coherent applied pulse and enable status are pushed on change.
 reg status_request,status_ack;
 (* keep="true" *)reg [16:0] held_status;
 (* async_reg="true" *)reg [1:0] status_sync,status_ack_sync;
 reg [1:0] status_settling;
 always @(posedge net_clk or negedge net_release[1])begin
  if(!net_release[1])begin status_request<=0;status_ack_sync<=0;held_status<={1'b0,16'd1500};end
  else begin
   status_ack_sync<={status_ack_sync[0],status_ack};
   if(status_ack_sync[1]==status_request && held_status!={net_enabled,net_applied})begin
    held_status<={net_enabled,net_applied};status_request<=~status_request;
   end
  end
 end
 always @(posedge ui_clk or negedge ui_release[1])begin
  if(!ui_release[1])begin
   status_sync<=0;status_ack<=0;status_settling<=0;ui_applied<=1500;ui_enabled<=0;
  end else begin
   status_sync<={status_sync[0],status_request};
   if(status_sync[1]!=status_ack)begin
    if(status_settling==2)begin
     {ui_enabled,ui_applied}<=held_status;status_ack<=status_sync[1];status_settling<=0;
    end else status_settling<=status_settling+1'b1;
   end else status_settling<=0;
  end
 end
endmodule
`default_nettype wire

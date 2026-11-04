`timescale 1ns/1ps
`default_nettype none
// Positional RC servo only. No homing, position sensor or stall detection.
// Lost lease freezes the commanded pulse and keeps holding PWM until explicit
// disable/reset. Power loss cannot provide mechanical anti-fall protection.
module servo_control #(parameter CYCLES_PER_US=125,FRAME_US=20000,LEASE_US=2000000)(
 input wire clk,rst_n,input wire [1:0] device_id,
 input wire rx_valid,input wire [7:0] rx_data,input wire [15:0] rx_len,
 output wire pwm,output wire [255:0] reply,output wire reply_valid,input wire reply_take,
 input wire local_apply,input wire [15:0] local_target,
 output wire [15:0] applied_us,target_us,output wire pwm_enabled,local_control,input wire local_lock);
 function [15:0] crc_byte;
  input [15:0] crc;input [7:0] value;integer i;reg [15:0] c;
  begin c=crc^{value,8'd0};for(i=0;i<8;i=i+1)c=c[15]?(c<<1)^16'h1021:c<<1;crc_byte=c;end
 endfunction
 (* async_reg="true" *) reg [1:0] release_sync;
 always @(posedge clk or negedge rst_n)if(!rst_n)release_sync<=0;else release_sync<={release_sync[0],1'b1};
 localparam DW=$clog2(CYCLES_PER_US+1);
 reg [DW-1:0] divider;reg [14:0] phase;wire tick=divider==CYCLES_PER_US-1;
 wire boundary=tick && phase==FRAME_US-1;
 reg configured,enabled,pulse_enabled,lease_lost,local_mode;
 reg [15:0] applied,target,lower,upper,slew;
 assign applied_us=applied;assign target_us=target;assign pwm_enabled=enabled;assign local_control=local_mode;
 reg [31:0] token,last_seq;reg [22:0] lease_left;
 assign pwm=enabled && pulse_enabled && phase<applied;
 reg previous_valid;reg [5:0] count;reg [15:0] length,rx_crc;reg [255:0] packet;
 wire [7:0] op=packet[215:208];wire [31:0] incoming_token=packet[191:160],seq=packet[159:128];
 wire [15:0] arg_min=packet[127:112],arg_max=packet[111:96],arg_target=packet[95:80],arg_slew=packet[79:64];
 wire valid_packet=previous_valid && !rx_valid && count==32 && length==32 &&
  packet[255:224]==32'h53564354 && packet[223:216]==1 && packet[207:200]=={6'd0,device_id} && device_id!=0 &&
  packet[199:192]==0 && packet[63:48]==2000 && packet[47:32]==0 && packet[31:16]==16'h5aa5 && packet[15:0]==rx_crc;
 wire [31:0] seq_difference=seq-last_seq;
 wire new_seq=seq!=last_seq && !seq_difference[31];
 reg reply_request;reg [31:0] echo_seq;reg [7:0] error;
 wire [7:0] flags={4'd0,lease_lost,(enabled && target!=applied && !lease_lost),configured,enabled};
 wire [239:0] status_header={32'h53565354,8'd1,{6'd0,device_id},flags,error,token,echo_seq,
   applied,target,lower,upper,slew,16'd2000,16'ha55a};
 servo_status_packet u_status(clk,release_sync[1],reply_request,status_header,reply,reply_valid,reply_take);
 always @(posedge clk or negedge release_sync[1])begin
  if(!release_sync[1])begin
   divider<=0;phase<=0;configured<=0;enabled<=0;pulse_enabled<=0;lease_lost<=0;local_mode<=0;
   applied<=1500;target<=1500;lower<=750;upper<=2250;slew<=5;token<=0;last_seq<=0;lease_left<=0;
   previous_valid<=0;count<=0;length<=0;rx_crc<=16'hffff;packet<=0;reply_request<=0;echo_seq<=0;error<=0;
  end else begin
   reply_request<=0;previous_valid<=rx_valid;
   if(tick)begin
    divider<=0;
    if(boundary)begin
     phase<=0;pulse_enabled<=enabled;
     if(enabled && !lease_lost && (local_mode || lease_left>1) && !(valid_packet && incoming_token==token && new_seq && (op==2 || op==4 || op==5)))begin
      if(target>applied)applied<=target-applied>slew?applied+slew:target;
      else if(target<applied)applied<=applied-target>slew?applied-slew:target;
     end
    end else phase<=phase+1'b1;
    if(enabled && !local_mode && !lease_lost && lease_left!=0)begin
     lease_left<=lease_left-1'b1;
     if(lease_left==1)begin lease_lost<=1;target<=applied;end
    end
   end else divider<=divider+1'b1;
   if(rx_valid)begin
    packet<={packet[247:0],rx_data};
    if(!previous_valid)begin count<=1;length<=rx_len;rx_crc<=crc_byte(16'hffff,rx_data);end
    else begin
     if(count!=63)count<=count+1'b1;
     if(count<30)rx_crc<=crc_byte(rx_crc,rx_data);
    end
   end else begin
    count<=0;
    if(valid_packet)begin
     reply_request<=1;echo_seq<=seq;error<=0;
     if(op==0)begin end // Read-only discovery does not renew the motion lease.
     else if(local_lock)error<=5;
     else if(op==1 && (!configured || incoming_token!=token))begin
      if(enabled && !lease_lost && !local_mode)error<=5;
      else if(incoming_token==0 || seq==0 || arg_min<750 || arg_max>2250 || arg_min>=arg_max ||
       arg_target<arg_min || arg_target>arg_max || arg_slew<1 || arg_slew>20 ||
       (enabled && (applied<arg_min || applied>arg_max)))error<=2;
      else begin
       configured<=1;local_mode<=0;token<=incoming_token;last_seq<=seq;lower<=arg_min;upper<=arg_max;slew<=arg_slew;
       if(!enabled)begin target<=arg_target;applied<=arg_target;lease_lost<=0;end
       else begin target<=applied;if(local_mode)begin lease_lost<=1;lease_left<=0;end end
      end
     end else if(!configured || incoming_token!=token)error<=3;
     else if(seq==last_seq)begin end // Retry is idempotent, never repeats motion.
     else if(!new_seq)error<=4;
     else if(op==1)error<=5; // New configuration needs a new session token.
     else if(op==2)begin
      last_seq<=seq;enabled<=1;lease_lost<=0;lease_left<=LEASE_US;target<=applied;
     end else if(op==3)begin
      if(!enabled || lease_lost)error<=5;
      else if(arg_target<lower || arg_target>upper)error<=2;
      else begin last_seq<=seq;target<=arg_target;lease_left<=LEASE_US;end
     end else if(op==4)begin last_seq<=seq;target<=applied;lease_left<=LEASE_US;end
     else if(op==5)begin last_seq<=seq;enabled<=0;pulse_enabled<=0;target<=applied;lease_lost<=0;lease_left<=0;end
     else if(op==6)begin last_seq<=seq;if(enabled && !lease_lost)lease_left<=LEASE_US;end
     else error<=6;
    end
   end
   // A physical OK is an explicit local takeover. No network heartbeat or
   // delayed remote MOVE may undo it. PWM is enabled only here or remote ARM.
   if(local_apply)begin
    local_mode<=1;configured<=0;enabled<=1;lease_lost<=0;lease_left<=0;
    token<=0;last_seq<=0;lower<=750;upper<=2250;slew<=5;
    target<=local_target<750?16'd750:local_target>2250?16'd2250:local_target;
    if(valid_packet && op!=0)error<=5;
   end
  end
 end
endmodule
`default_nettype wire

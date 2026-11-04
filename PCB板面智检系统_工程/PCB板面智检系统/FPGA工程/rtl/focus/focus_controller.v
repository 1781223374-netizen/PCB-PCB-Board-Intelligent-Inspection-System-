`timescale 1ns/1ps
`default_nettype none
// Three-stage100/20/5us search. Two coarse/refine samples, four fine/verify.
// Complete only after optical return verification; actuator slew is unchanged.
// No displacement sensor or measurement history is required.
module focus_controller #(
 parameter CLOCK_HZ=114750000,LOWER=750,UPPER=2250,COARSE=100,REFINE=20,FINE=5,
 parameter SETTLE_MS=250,VERIFY_SETTLE_MS=500,PHASE_TIMEOUT_MS=12000,TOTAL_TIMEOUT_MS=120000,
 parameter IMAGE_TIMEOUT_MS=2500)(
 input wire clk,rst_n,start,cancel,image_available,servo_ready,servo_enabled,
 input wire [15:0] servo_applied,
 output reg servo_apply,output reg [15:0] servo_target,
 input wire metric_valid,metric_usable,input wire [31:0] metric_score,metric_frame,
 output wire busy,output reg beep,output reg [3:0] phase,error,
 output reg [15:0] best_pulse,output reg [31:0] best_score);
 localparam IDLE=0,SEND=1,WAIT_LOW=2,WAIT_ACK=3,MOVE=4,SETTLE=5,
  TAKE=6,JUDGE=7,CANCEL_SEND=10,CANCEL_LOW=11,CANCEL_ACK=12;
 reg [3:0] state,old_state;reg [2:0] mode;
 assign busy=state!=IDLE;
 localparam MS=(CLOCK_HZ/1000)<1?1:CLOCK_HZ/1000;
 reg [$clog2(MS+1)-1:0] divider;
 wire ms_tick=divider==MS-1;
 reg [16:0] total_ms;reg [15:0] phase_ms,settle_ms;
 reg [31:0] last_frame,low_score,point_score,verify_score;
 reg [33:0] scores;reg [2:0] frames;reg [15:0] fine_end;
 wire [15:0] chosen_pulse=point_score>best_score?servo_target:best_pulse;
 wire [31:0] chosen_score=point_score>best_score?point_score:best_score;
 wire [31:0] chosen_low=point_score<low_score?point_score:low_score;
 task fail;
 input [3:0] why;
 begin error<=why;phase<=7;state<=CANCEL_SEND;end
 endtask
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;old_state<=IDLE;mode<=0;divider<=0;total_ms<=0;phase_ms<=0;settle_ms<=0;
   servo_apply<=0;servo_target<=1500;beep<=0;phase<=0;error<=0;
   best_pulse<=1500;best_score<=0;low_score<=32'hffffffff;point_score<=0;verify_score<=0;
   last_frame<=0;scores<=0;frames<=0;fine_end<=UPPER;
  end else begin
   servo_apply<=0;beep<=0;old_state<=state;
   if(ms_tick)divider<=0;else divider<=divider+1'b1;
   // Idle time must not become the timeout of the next motion request.
   if(!busy || state!=old_state)phase_ms<=0;else if(ms_tick && phase_ms!=65535)phase_ms<=phase_ms+1'b1;
   if(!busy)total_ms<=0;else if(ms_tick && total_ms!=131071)total_ms<=total_ms+1'b1;
   if(cancel && busy && state<CANCEL_SEND)begin fail(4'd1);end
   else if(busy && state<CANCEL_SEND && total_ms>=TOTAL_TIMEOUT_MS)begin fail(4'd8);end
   else if(busy && state<CANCEL_SEND && !image_available)begin fail(4'd2);end
   else if(state>=SEND && state<=MOVE && phase_ms>=PHASE_TIMEOUT_MS)begin fail(4'd3);end
   else case(state)
    IDLE:if(start)begin
     error<=0;
     if(!image_available)begin phase<=7;error<=2;end
     else if(!servo_ready)begin phase<=7;error<=3;end
     else begin
      best_score<=0;low_score<=32'hffffffff;best_pulse<=LOWER;
      servo_target<=LOWER;mode<=0;phase<=1;state<=SEND;
     end
    end
    SEND:if(servo_ready)begin servo_apply<=1;state<=WAIT_LOW;end
    WAIT_LOW:if(!servo_ready)state<=WAIT_ACK;
    WAIT_ACK:if(servo_ready)state<=MOVE;
    MOVE:if(servo_enabled && servo_applied==servo_target)begin state<=SETTLE;settle_ms<=0;end
    SETTLE:begin
     if(!servo_enabled || servo_applied!=servo_target)begin fail(3);end
     else if(ms_tick)begin
      if(settle_ms>=(mode==3?VERIFY_SETTLE_MS:SETTLE_MS))begin
       if(mode==2)begin servo_target<=best_pulse;mode<=3;phase<=3;state<=SEND;end
       else begin scores<=0;frames<=0;last_frame<=metric_frame;state<=TAKE;end
      end else settle_ms<=settle_ms+1'b1;
     end
    end
    TAKE:begin
     if(!servo_enabled || servo_applied!=servo_target)begin fail(3);end
     else if(phase_ms>=IMAGE_TIMEOUT_MS)begin fail(2);end
     else if(metric_valid && metric_frame!=last_frame)begin
      last_frame<=metric_frame;
      if(!metric_usable)begin fail(4);end
      else begin
       scores<=scores+metric_score;
       if(frames==((mode==0 || mode==4)?1:3))begin
        point_score<=(mode==0 || mode==4)?((scores+metric_score)>>1):((scores+metric_score)>>2);state<=JUDGE;end
       else frames<=frames+1'b1;
      end
     end
    end
    JUDGE:begin
     if(mode==3)begin
      // Confirm the return-to-best image, not merely the PWM number.
      if(point_score<verify_score-(verify_score>>2) || point_score<16)begin fail(5);end
      else begin beep<=1;phase<=5;error<=0;state<=IDLE;end
     end else begin
      best_pulse<=chosen_pulse;best_score<=chosen_score;low_score<=chosen_low;
      if(mode==0 && servo_target<UPPER)begin
       servo_target<=servo_target+COARSE>UPPER?UPPER:servo_target+COARSE;state<=SEND;
      end else if(mode==0)begin
       if(chosen_score<=chosen_low+(chosen_low>>3)+16)begin fail(4);end
       else begin
        servo_target<=chosen_pulse<LOWER+COARSE?LOWER:chosen_pulse-COARSE;
        fine_end<=chosen_pulse+COARSE>UPPER?UPPER:chosen_pulse+COARSE;
        mode<=4;phase<=2;state<=SEND;best_score<=0;low_score<=32'hffffffff;
       end
      end else if(mode==4)begin
       if(servo_target<fine_end)begin
        servo_target<=servo_target+REFINE>fine_end?fine_end:servo_target+REFINE;state<=SEND;
       end else begin
        servo_target<=chosen_pulse<LOWER+REFINE?LOWER:chosen_pulse-REFINE;
        fine_end<=chosen_pulse+REFINE>UPPER?UPPER:chosen_pulse+REFINE;
        mode<=1;state<=SEND;best_score<=0;low_score<=32'hffffffff;
       end
      end else if(servo_target<fine_end)begin
       servo_target<=servo_target+FINE>fine_end?fine_end:servo_target+FINE;state<=SEND;
      end else if(chosen_pulse==LOWER || chosen_pulse==UPPER)begin fail(9);end
      else begin
       verify_score<=chosen_score;servo_target<=chosen_pulse<LOWER+60?LOWER:chosen_pulse-60;
       mode<=2;phase<=3;state<=SEND;
      end
     end
    end
    CANCEL_SEND:if(servo_ready)begin servo_target<=servo_applied;servo_apply<=1;state<=CANCEL_LOW;end
    CANCEL_LOW:if(!servo_ready)state<=CANCEL_ACK;
    CANCEL_ACK:if(servo_ready || phase_ms>=PHASE_TIMEOUT_MS)state<=IDLE;
    default:state<=IDLE;
   endcase
   // A failed transport must not leave the local network lock asserted forever.
   if(state>=CANCEL_SEND && phase_ms>=PHASE_TIMEOUT_MS)state<=IDLE;
  end
 end
endmodule
`default_nettype wire

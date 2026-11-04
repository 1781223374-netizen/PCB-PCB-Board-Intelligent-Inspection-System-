`timescale 1ns/1ps
`default_nettype none
// Score a qualified SOT once per completed LP11-delimited burst at each delay code.
//
// V6 keeps the V5 full 256-code sweep and the two-polarity scoring, and adds the
// run map that decides whether the delay range is the limiting factor at all:
// the eye repeats every bit period, so if 256 codes span more than one bit
// period a lane must show TWO separate qualifying runs. A single run means the
// range is shorter than one bit period, so a dead zone exists that no per-lane
// code can reach and other lanes' absence of a window proves nothing.
//
//   runs        qualifying runs seen, saturated at 3
//   win_len     longest qualifying run, in codes, full 8 bits
//   first_start first code of the first qualifying run
//   last_end    last code of the last qualifying run
//
// Pick the midpoint of the widest run meeting MIN_HITS for the winning polarity,
// or that polarity's peak code if nothing qualifies. A qualifying run is only a
// synchronisation observation: it is not CSI ECC/CRC and not an image.
module lane_delay_cal #(
 parameter MAX_TAP=255, TRIAL_BURSTS=15, SKIP_BURSTS=1, MIN_HITS=12
)(
 input wire clk,rst_n,enable,stop_state,locked,locked_inv,
 output reg [7:0] tap,peak_hits,
 output reg done,eye,invert,
 output reg [7:0] win_len,
 output reg [1:0] runs,
 output reg [7:0] first_start,last_end,
 output wire align_enable
);
 localparam IDLE=0,SKIP=1,MEASURE=2,FINAL=3,DONE=4;
 reg [2:0] state;
 reg prev_stop,seen_sync,seen_sync_i;
 reg [7:0] trials,hits,hits_i,skipped;
 reg [7:0] run_start,run_start_i,best_center,best_center_i,peak_tap,peak_tap_i,peak_hits_i;
 reg [7:0] first_start_i,last_end_i;
 reg [1:0] run_count,run_count_i;
 reg first_seen,first_seen_i;
 reg [8:0] run_length,run_length_i,best_length,best_length_i;
 wire complete_burst=stop_state && !prev_stop;
 wire [8:0] next_hits  ={1'b0,hits}  +((seen_sync  ||locked    )?9'd1:9'd0);
 wire [8:0] next_hits_i={1'b0,hits_i}+((seen_sync_i||locked_inv)?9'd1:9'd0);
 wire passing  =next_hits  >=MIN_HITS;
 wire passing_i=next_hits_i>=MIN_HITS;
 wire [8:0] next_run  =passing  ?run_length  +9'd1:9'd0;
 wire [8:0] next_run_i=passing_i?run_length_i+9'd1:9'd0;
 wire [7:0] start  =run_length  ==0?tap:run_start;
 wire [7:0] start_i=run_length_i==0?tap:run_start_i;
 wire [7:0] center  =start  +((next_run  -9'd1)>>1);
 wire [7:0] center_i=start_i+((next_run_i-9'd1)>>1);
 // Freeze values including the final code, whose scores are still in flight.
 wire [8:0] f_len  =next_run  >best_length  ?next_run  :best_length;
 wire [8:0] f_len_i=next_run_i>best_length_i?next_run_i:best_length_i;
 wire [7:0] f_ctr  =next_run  >best_length  ?center    :best_center;
 wire [7:0] f_ctr_i=next_run_i>best_length_i?center_i  :best_center_i;
 wire [7:0] f_pk   =next_hits  >peak_hits   ?next_hits  [7:0]:peak_hits;
 wire [7:0] f_pk_i =next_hits_i>peak_hits_i ?next_hits_i[7:0]:peak_hits_i;
 wire [7:0] f_pkt  =next_hits  >peak_hits   ?tap             :peak_tap;
 wire [7:0] f_pkt_i=next_hits_i>peak_hits_i ?tap             :peak_tap_i;
 // Longer qualifying run wins; equal runs fall back to the higher peak.
 wire f_inv=(f_len_i>f_len)||(f_len_i==f_len&&f_pk_i>f_pk);
 wire [8:0] f_win=f_inv?f_len_i:f_len;
 wire have_win=f_win!=0;
 wire [7:0] f_code=have_win?(f_inv?f_ctr_i:f_ctr):(f_inv?f_pkt_i:f_pkt);
 // Run map of the winning polarity: a run still open at MAX_TAP counts too.
 wire open_run  =run_length  !=0||next_run  !=0;
 wire open_run_i=run_length_i!=0||next_run_i!=0;
 wire [1:0] f_runs_n=run_count  +(open_run   &&run_count  !=2'd3);
 wire [1:0] f_runs_i=run_count_i+(open_run_i &&run_count_i!=2'd3);
 wire [7:0] f_fs =first_seen  ?first_start  :tap;
 wire [7:0] f_fs_i=first_seen_i?first_start_i:tap;
 wire [7:0] f_le =next_run  !=0?tap:last_end;
 wire [7:0] f_le_i=next_run_i!=0?tap:last_end_i;
 assign align_enable=enable && (state==MEASURE || state==DONE);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;prev_stop<=1;seen_sync<=0;seen_sync_i<=0;tap<=0;peak_hits<=0;
   done<=0;eye<=0;invert<=0;win_len<=0;runs<=0;first_start<=0;last_end<=0;
   trials<=0;hits<=0;hits_i<=0;skipped<=0;
   run_start<=0;run_start_i<=0;best_center<=0;best_center_i<=0;
   peak_tap<=0;peak_tap_i<=0;peak_hits_i<=0;first_start_i<=0;last_end_i<=0;
   run_count<=0;run_count_i<=0;first_seen<=0;first_seen_i<=0;
   run_length<=0;run_length_i<=0;best_length<=0;best_length_i<=0;
  end else begin
   prev_stop<=stop_state;
   if(!enable)begin
    state<=IDLE;seen_sync<=0;seen_sync_i<=0;tap<=0;peak_hits<=0;done<=0;eye<=0;invert<=0;
    win_len<=0;runs<=0;first_start<=0;last_end<=0;
    trials<=0;hits<=0;hits_i<=0;skipped<=0;run_start<=0;run_start_i<=0;
    best_center<=0;best_center_i<=0;peak_tap<=0;peak_tap_i<=0;peak_hits_i<=0;
    first_start_i<=0;last_end_i<=0;run_count<=0;run_count_i<=0;
    first_seen<=0;first_seen_i<=0;
    run_length<=0;run_length_i<=0;best_length<=0;best_length_i<=0;
   end else case(state)
    IDLE:begin state<=SKIP;skipped<=0;seen_sync<=0;seen_sync_i<=0;end
    SKIP,FINAL:begin
     seen_sync<=0;seen_sync_i<=0;
     if(complete_burst)begin
      if(skipped==SKIP_BURSTS-1)begin
       skipped<=0;trials<=0;hits<=0;hits_i<=0;
       if(state==FINAL)begin done<=1;state<=DONE;end
       else state<=MEASURE;
      end else skipped<=skipped+1'b1;
     end
    end
    MEASURE:begin
     if(!stop_state&&locked)seen_sync<=1;
     if(!stop_state&&locked_inv)seen_sync_i<=1;
     if(complete_burst)begin
      seen_sync<=0;seen_sync_i<=0;
      if(trials==TRIAL_BURSTS-1)begin
       trials<=0;hits<=0;hits_i<=0;skipped<=0;
       run_length<=next_run;run_length_i<=next_run_i;
       // A run opens on the first passing code and closes on the first failing
       // code after it. A run still open at MAX_TAP is counted at the freeze.
       if(passing)begin
        if(run_length==0)begin
         run_start<=tap;
         if(!first_seen)begin first_seen<=1;first_start<=tap;end
        end
        last_end<=tap;
       end else if(run_length!=0)begin
        if(run_count!=2'd3)run_count<=run_count+2'd1;
       end
       if(passing_i)begin
        if(run_length_i==0)begin
         run_start_i<=tap;
         if(!first_seen_i)begin first_seen_i<=1;first_start_i<=tap;end
        end
        last_end_i<=tap;
       end else if(run_length_i!=0)begin
        if(run_count_i!=2'd3)run_count_i<=run_count_i+2'd1;
       end
       if(next_run  >best_length  )begin best_length  <=next_run;  best_center  <=center;  end
       if(next_run_i>best_length_i)begin best_length_i<=next_run_i;best_center_i<=center_i;end
       if(next_hits  >peak_hits  )begin peak_hits  <=next_hits  [7:0];peak_tap  <=tap;end
       if(next_hits_i>peak_hits_i)begin peak_hits_i<=next_hits_i[7:0];peak_tap_i<=tap;end
       if(tap==MAX_TAP)begin
        // These assignments come last, so they win over the per-code updates.
        invert<=f_inv;
        eye<=have_win;
        win_len<=f_win[7:0];
        runs<=have_win?(f_inv?f_runs_i:f_runs_n):2'd0;
        first_start<=have_win?(f_inv?f_fs_i:f_fs):8'd0;
        last_end<=have_win?(f_inv?f_le_i:f_le):8'd0;
        peak_hits<=f_inv?f_pk_i:f_pk;
        tap<=f_code;
        state<=FINAL;
       end else begin tap<=tap+1'b1;state<=SKIP;end
      end else begin trials<=trials+1'b1;hits<=next_hits[7:0];hits_i<=next_hits_i[7:0];end
     end
    end
    DONE:begin done<=1;seen_sync<=0;seen_sync_i<=0;end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
`default_nettype wire

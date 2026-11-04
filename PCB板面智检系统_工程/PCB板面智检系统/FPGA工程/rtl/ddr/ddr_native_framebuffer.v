`timescale 1ns/1ps
`default_nettype none
// Three complete frames stay in external DDR. Only eight scan lines live in
// dual-clock block RAM. A frame is pinned for the whole HDMI scan, including
// photograph freeze and playback. Read commands may have 16 in-order replies
// outstanding; no frame-sized ERAM or interpolation is used.
module ddr_native_framebuffer #(
 parameter ENABLE_NETWORK=0,WIDTH=1920,HEIGHT=1080,ADDR_BITS=21,CACHE_ROWS=8,TIMEOUT=2000000
)(
 input wire [12:0] net_cmd,input wire net_cmd_valid,output wire net_cmd_ready,
 output wire [129:0] net_response,output wire net_response_valid,input wire net_response_ready,
 input wire cam_clk,cam_rst_n,frame_start,frame_end,frame_error,word_valid,
 input wire [31:0] word_data,output reg [31:0] accepted_frames,dropped_frames,
 input wire pixel_clk,pixel_rst_n,display_frame_start,display_line_end,read_enable,
 input wire [ADDR_BITS-1:0] read_addr,output wire [31:0] read_data,output reg image_available,
 input wire hold_display,play_start,play_write,play_commit,
 input wire [ADDR_BITS-1:0] play_addr,input wire [31:0] play_data,output wire play_ready,
 output reg held,output reg [31:0] displayed_frames,busy_skips,hold_skips,fifo_errors,
 output wire [63:0] diagnostic,
 input wire ddr_clk,ddr_rst_n,ddr_enable,
 output reg [31:0] ddr_stored,ddr_dropped,ddr_read,ddr_write_beats,ddr_read_beats,ddr_protocol_errors,
 output wire ddr_fault,
 output wire [127:0] fault_diagnostic,
 output wire [26:0] awaddr,output wire awvalid,input wire awready,
 output wire [127:0] wdata,output wire [15:0] wstrb,output wire wvalid,wlast,input wire wready,
 output wire [26:0] araddr,output wire arvalid,input wire arready,
 input wire [127:0] rdata,input wire rvalid,rlast,output wire rready
);
 localparam ROW_WORDS=WIDTH/2,ROW_BEATS=WIDTH/8,FRAME_WORDS=WIDTH*HEIGHT/2;
 localparam RW=$clog2(ROW_WORDS),RB=$clog2(ROW_BEATS),CB=$clog2(CACHE_ROWS);
 localparam CACHE_BITS=CB+RB;
 localparam [10:0] CACHE_N=CACHE_ROWS;
 localparam [31:0] FRAME_SIZE=FRAME_WORDS;
 // Hold all transport FIFOs reset until the DDR self-test hands over the bus.
 wire fifo_reset_n=cam_rst_n && pixel_rst_n && ddr_rst_n && ddr_enable;
 (* async_reg="true" *) reg [1:0] cam_release,pix_release,dma_release;
 always @(posedge cam_clk or negedge fifo_reset_n)
  if(!fifo_reset_n)cam_release<=0;else cam_release<={cam_release[0],1'b1};
 always @(posedge pixel_clk or negedge fifo_reset_n)
  if(!fifo_reset_n)pix_release<=0;else pix_release<={pix_release[0],1'b1};
 always @(posedge ddr_clk or negedge fifo_reset_n)
  if(!fifo_reset_n)dma_release<=0;else dma_release<={dma_release[0],1'b1};
 reg overflow,error_seen;
 wire push=frame_start || frame_end || word_valid || (frame_error && !error_seen);
 wire in_ready,cv,cr,cf_valid,cf_ready;wire [36:0] cd,cf_data;
 // Registered-ready skid stage removes DDR arbitration from ERAM CSB.
 // A spare entry preserves one beat per cycle and absorbs backpressure.
 ddr_elastic_buffer #(.WIDTH(37)) camera_events_stage(ddr_clk,dma_release[1],
  cf_data,cf_valid,cf_ready,cd,cv,cr);
 always @(posedge cam_clk or negedge cam_release[1])begin
  if(!cam_release[1])begin overflow<=0;error_seen<=0;end
  else begin error_seen<=frame_error;
   if(push && !in_ready)overflow<=1;else if(frame_start)overflow<=0;
  end
 end
 ddr_async_fifo #(.WIDTH(37),.AW(13)) input_events(cam_clk,ddr_clk,fifo_reset_n,push,
  {word_valid,overflow,frame_error,frame_end,frame_start,word_data},in_ready,cf_valid,cf_data,cf_ready);

 // Raster requests and slow SD playback use independent FIFOs, so a vertical
 // blank cannot discard a coincident playback word or commit pulse.
 wire qv,qr,qready,qf_valid,qf_ready;wire [12:0] qd,qf_data;
 reg request_valid;reg [12:0] request_data;
 assign qv=request_valid;assign qd=request_data;assign qf_ready=!request_valid;
 // Stage the ERAM output before arbitration. In particular, START must not
 // drive a camera FIFO Gray-pointer increment through the RAM clock-to-Q path.
 always @(posedge ddr_clk or negedge dma_release[1])begin
  if(!dma_release[1])begin request_valid<=0;request_data<=0;end
  else begin
   if(qv && qr)request_valid<=0;
   if(qf_valid && qf_ready)begin request_valid<=1;request_data<=qf_data;end
  end
 end
 wire [10:0] display_row=read_addr>>RW;
 wire request_row=display_line_end && display_row+CACHE_ROWS<HEIGHT;
 ddr_async_fifo #(.WIDTH(13),.AW(5)) raster_requests(pixel_clk,ddr_clk,fifo_reset_n,
  display_frame_start || request_row,
  display_frame_start?{1'b1,hold_display,11'd0}:{2'b00,display_row+CACHE_N},qready,qf_valid,qf_data,qf_ready);
 wire pv,pr,pready,pf_valid,pf_ready;wire [ADDR_BITS+34:0] pd,pf_data;
 reg playback_valid;reg [ADDR_BITS+34:0] playback_data;
 assign pv=playback_valid;assign pd=playback_data;assign pf_ready=!playback_valid || pr;
 always @(posedge ddr_clk or negedge dma_release[1])begin
  if(!dma_release[1])begin playback_valid<=0;playback_data<=0;end
  else if(pf_ready)begin playback_valid<=pf_valid;if(pf_valid)playback_data<=pf_data;end
 end
 ddr_async_fifo #(.WIDTH(ADDR_BITS+35),.AW(9)) playback_events(pixel_clk,ddr_clk,fifo_reset_n,
  play_start || play_write || play_commit,{play_start,play_commit,play_write,play_addr,play_data},pready,pf_valid,pf_data,pf_ready);
 assign play_ready=pready && !play_start && !play_commit;
 wire sf_valid,sf_ready,sf_out;wire [13:0] sf_data,sf_received;
 reg [13:0] response;
 reg response_valid;
 assign sf_valid=response_valid;
 assign sf_data=response;
 ddr_async_fifo #(.WIDTH(14),.AW(5)) returned_events(ddr_clk,pixel_clk,fifo_reset_n,
  sf_valid,sf_data,sf_ready,sf_out,sf_received,1'b1);

 function [26:0] base;
  input [1:0] bank;
  begin case(bank)0:base=27'h0200000;1:base=27'h0400000;2:base=27'h0600000;default:base=27'h0800000;endcase end
 endfunction
 reg [1:0] display_bank,pending_bank,capture_bank,play_bank;
 reg display_valid,pending,capture,tainted,play_active,play_bad,play_pending;
 reg [ADDR_BITS:0] captured,played;
 reg [1:0] pack_count;
 reg [95:0] pack;
 reg [127:0] write_payload;
 reg [26:0] write_address;
 reg aw_pending,w_pending,fault;
 wire write_busy=aw_pending || w_pending;
 wire write_done=write_busy && (!aw_pending || awready) && (!w_pending || wready);
 assign awaddr=write_address;assign awvalid=aw_pending;
 assign wdata=write_payload;assign wvalid=w_pending;assign wstrb=0;assign wlast=1;
 (* async_reg="true" *) reg [1:0] hold_sync;
 reg [31:0] write_wait,read_wait;
 reg [10:0] read_row;
 reg [RB:0] issued,received;
 reg [1:0] reader;
 reg prefill;
 wire read_take;
 reg net_pinned,read_is_net,net_ack_valid;
 reg [1:0] net_bank;
 reg [129:0] net_ack;
 assign net_response_valid=ENABLE_NETWORK && (net_ack_valid || (read_take && read_is_net));
 assign net_response=net_ack_valid?net_ack:{2'b00,rdata};
 assign net_cmd_ready=ENABLE_NETWORK && dma_release[1] && ddr_enable && !fault && reader==0 && !write_busy && !qv && !net_ack_valid;
 wire net_take=net_cmd_valid && net_cmd_ready;
 wire bank0_busy=(display_valid && display_bank==0) || (pending && pending_bank==0) || (capture && capture_bank==0) || (net_pinned && net_bank==0);
 wire bank1_busy=(display_valid && display_bank==1) || (pending && pending_bank==1) || (capture && capture_bank==1) || (net_pinned && net_bank==1);
 wire bank2_busy=(display_valid && display_bank==2) || (pending && pending_bank==2) || (capture && capture_bank==2) || (net_pinned && net_bank==2);

 reg ar_stalled;
 reg [127:0] first_fault;
 wire read_expected=reader==1 && received<issued;
 assign read_take=rvalid && rready && read_expected;
 assign qr=ddr_enable && !fault && reader==0 && !response_valid && !write_busy;
 // Finish a whole row before starting another write. The factory memory test
 // uses separate read/write phases; camera and playback FIFOs absorb the pause.
 // A consumed raster request owns this clock too, including non-START rows.
 assign pr=ddr_enable && !fault && reader==0 && !write_busy && !capture && !(qv && qr) && !net_take;
 assign cr=ddr_enable && !fault && reader==0 && !write_busy && !(qv && qr) &&
           (!pv || capture) && !net_take;
 wire have_free_bank=!(bank0_busy && bank1_busy && bank2_busy);
 wire [1:0] free_bank=ENABLE_NETWORK?(!bank0_busy?2'd0:!bank1_busy?2'd1:!bank2_busy?2'd2:2'd3):(display_valid && display_bank==0 || pending && pending_bank==0 || capture && capture_bank==0)?
                     ((display_valid && display_bank==1 || pending && pending_bank==1 || capture && capture_bank==1)?2'd2:2'd1):2'd0;
 wire [1:0] selected_bank=play_pending?play_bank:(!qd[11] && pending)?pending_bank:display_bank;
 wire selected_valid=play_pending || display_valid || (!qd[11] && pending);
 assign araddr=base(read_is_net?net_bank:display_bank)+((read_row*ROW_BEATS+issued)<<3);
 assign arvalid=reader==1 && issued<ROW_BEATS && issued-received<16 && (!fault || ar_stalled);
 // Match the factory's always-ready receive side. Faulted transactions drain
 // their accepted replies; an already stalled AR remains valid until accepted.
 assign rready=ddr_enable && dma_release[1];
 assign ddr_fault=fault;
 wire write_timeout=write_busy && !write_done && write_wait==TIMEOUT-1;
 wire read_timeout=reader==1 && (issued!=received || arvalid) && !read_take && read_wait==TIMEOUT-1;
 wire unexpected_read=rvalid && rready && !read_expected;
 wire [7:0] next_cause=ENABLE_NETWORK && read_take && read_is_net && !net_response_ready?8'h06:read_take && !rlast?8'h04:unexpected_read?8'h05:
                         write_timeout?8'h01:read_timeout?(issued==received?8'h02:8'h03):8'h00;
 wire [8:0] issue_snapshot=issued,receive_snapshot=received;
 wire [11:0] channel_snapshot={reader,rvalid,rlast,rready,arvalid,arready,wvalid,wready,awvalid,awready,write_busy};
 wire [127:0] live_fault_snapshot={26'd0,araddr,awaddr,channel_snapshot,receive_snapshot,issue_snapshot,read_row,next_cause};
 assign fault_diagnostic=fault?first_fault:live_fault_snapshot;
 always @(posedge ddr_clk or negedge dma_release[1])begin
  if(!dma_release[1])begin
   display_bank<=0;pending_bank<=0;capture_bank<=0;play_bank<=0;
   display_valid<=0;pending<=0;capture<=0;tainted<=0;play_active<=0;play_bad<=0;play_pending<=0;
   captured<=0;played<=0;pack_count<=0;pack<=0;write_payload<=0;write_address<=0;
   aw_pending<=0;w_pending<=0;fault<=0;hold_sync<=0;write_wait<=0;read_wait<=0;
   read_row<=0;issued<=0;received<=0;reader<=0;prefill<=0;ar_stalled<=0;first_fault<=0;
   response<=0;response_valid<=0;net_pinned<=0;net_bank<=0;read_is_net<=0;net_ack<=0;net_ack_valid<=0;
   ddr_stored<=0;ddr_dropped<=0;ddr_read<=0;ddr_write_beats<=0;ddr_read_beats<=0;ddr_protocol_errors<=0;
  end else begin
   hold_sync<={hold_sync[0],hold_display};
   if(net_ack_valid && net_response_ready)net_ack_valid<=0;
   if(net_take)begin
    if(net_cmd[12:11]==2'b10)begin
     // Pin only a committed live frame. Capture cannot choose this bank until END.
     if(!net_pinned && (hold_sync[1]?display_valid:(pending || display_valid)) && !play_active && !play_pending)begin
      net_pinned<=1;net_bank<=hold_sync[1]?display_bank:(pending?pending_bank:display_bank);
      net_ack<={2'b01,126'd0,hold_sync[1],1'b1};
     end else net_ack<={2'b10,128'd0};
     net_ack_valid<=1;
    end else if(net_cmd[12:11]==2'b11)begin
     net_pinned<=0;net_ack<={2'b01,128'd0};net_ack_valid<=1;
    end else if(net_pinned && net_cmd[10:0]<HEIGHT)begin
     read_is_net<=1;read_row<=net_cmd[10:0];issued<=0;received<=0;prefill<=0;reader<=1;
    end else begin net_ack<={2'b10,128'd0};net_ack_valid<=1;end
   end
   ar_stalled<=arvalid && !arready;
   if(!fault && next_cause!=0)begin
    fault<=1;first_fault<=live_fault_snapshot;ddr_protocol_errors<=ddr_protocol_errors+1'b1;
   end
   if(response_valid && sf_ready)response_valid<=0;
   if(aw_pending && awready)aw_pending<=0;
   if(w_pending && wready)w_pending<=0;
   if(write_done)begin ddr_write_beats<=ddr_write_beats+1'b1;write_wait<=0;end
   else if(write_busy)write_wait<=write_wait+1'b1;else write_wait<=0;
   // The command FIFO is consumed only after all previous row replies and
   // write handshakes finish. The formerly displayed bank can then be reused.
   if(qv && qr)begin
    read_is_net<=0;
    if(qd[12])begin
     display_bank<=selected_bank;display_valid<=selected_valid;
     if(play_pending)begin play_pending<=0;pending<=0;end
     else if(!qd[11] && pending)pending<=0;
     response<={1'b1,qd[11],selected_valid,10'd0,(play_pending || (!qd[11] && pending))};response_valid<=1;
     read_row<=0;issued<=0;received<=0;prefill<=1;
     if(selected_valid)reader<=3;
    end else if(display_valid && qd[10:0]<HEIGHT)begin
     read_row<=qd[10:0];issued<=0;received<=0;prefill<=0;reader<=1;
    end
   end
   if(reader==3 && !response_valid && !fault)reader<=1;
   if(arvalid && arready)issued<=issued+1'b1;
   if(read_take)begin
    received<=received+1'b1;ddr_read_beats<=ddr_read_beats+1'b1;
    if(received==ROW_BEATS-1)begin reader<=read_is_net?0:2;end
   end
   if(reader==2 && !response_valid && !fault && next_cause==0)begin
    response<={3'b000,read_row};response_valid<=1;
    if(read_row==HEIGHT-1)ddr_read<=ddr_read+1'b1;
    if(prefill && read_row==CACHE_ROWS-1)begin prefill<=0;reader<=0;end
    else if(prefill)begin read_row<=read_row+1'b1;issued<=0;received<=0;reader<=3;end
    else reader<=0;
   end
   if(reader==1 && (issued!=received || arvalid) && !read_take)read_wait<=read_wait+1'b1;else read_wait<=0;
   if(cv && cr)begin
    if(cd[32])begin
     if(capture)ddr_dropped<=ddr_dropped+1'b1;
     capture<=0;captured<=0;tainted<=cd[35];
     // Live camera SOF events continue while a TF photo is being loaded.
     // Playback owns the shared 128-bit packer until its commit/cancel.
     // Draining a skipped camera frame must not discard a partial photo beat.
     if(!play_active)pack_count<=0;
     if(!hold_sync[1] && !play_active && !play_pending && (capture || have_free_bank))begin
      capture_bank<=capture?capture_bank:free_bank;capture<=1;
     end else ddr_dropped<=ddr_dropped+1'b1;
    end else if(capture)begin
     if(cd[34] || cd[35])tainted<=1;
     if(cd[36])begin
      if(captured<FRAME_WORDS)begin
       captured<=captured+1'b1;pack_count<=pack_count+1'b1;
       case(pack_count)
        0:pack[31:0]<=cd[31:0];1:pack[63:32]<=cd[31:0];2:pack[95:64]<=cd[31:0];
        3:begin write_payload<={cd[31:0],pack};
         write_address<=base(capture_bank)+((captured>>2)<<3);aw_pending<=1;w_pending<=1;end
       endcase
      end else tainted<=1;
     end
     if(cd[33])begin
      capture<=0;
      if(!tainted && !cd[34] && !cd[35] && !cd[36] && captured==FRAME_WORDS && pack_count==0)begin
       if(pending)ddr_dropped<=ddr_dropped+1'b1;
       pending<=1;pending_bank<=capture_bank;ddr_stored<=ddr_stored+1'b1;
      end else ddr_dropped<=ddr_dropped+1'b1;
     end
    end
   end
   // Playback is a complete frame transaction, with ordered words and commit.
   // A BACK/cancel cannot publish its partially written bank.
   if(pv && pr)begin
    if(pd[ADDR_BITS+34])begin
     play_bank<=free_bank;play_active<=hold_sync[1] && have_free_bank;play_pending<=0;
     pending<=0;played<=0;pack_count<=0;play_bad<=0;
    end else if(play_active)begin
     if(pd[ADDR_BITS+32])begin
      if(pd[32+:ADDR_BITS]!=played || played>=FRAME_WORDS)play_bad<=1;
      else begin
       played<=played+1'b1;pack_count<=pack_count+1'b1;
       case(pack_count)
        0:pack[31:0]<=pd[31:0];1:pack[63:32]<=pd[31:0];2:pack[95:64]<=pd[31:0];
        3:begin write_payload<={pd[31:0],pack};
         write_address<=base(play_bank)+((played>>2)<<3);aw_pending<=1;w_pending<=1;end
       endcase
      end
     end
     if(pd[ADDR_BITS+33])begin
      play_active<=0;
      if(hold_sync[1] && !play_bad && played==FRAME_WORDS && pack_count==0)play_pending<=1;
     end
    end
   end
   if(!hold_sync[1] && !write_busy)begin play_active<=0;play_pending<=0;end
  end
 end

 // Four independent 32-bit RAM lanes accept one 128-bit DDR beat per clock.
 // Pixel reads have the same one-cycle latency as the V17 display interface.
 wire [CACHE_BITS-1:0] wr_cache={read_row[CB-1:0],received[RB-1:0]};
 wire [CACHE_BITS-1:0] rd_cache={read_addr[RW+:CB],read_addr[2+:RB]};
 wire [31:0] cache_data[0:3];
 genvar lane;
 generate for(lane=0;lane<4;lane=lane+1)begin:lane_ram
  (* ram_style="bram" *) reg [31:0] mem[0:(1<<CACHE_BITS)-1];
  reg [31:0] dout;
  always @(posedge ddr_clk)if(read_take && !read_is_net && !fault && rlast)mem[wr_cache]<=rdata[lane*32+:32];
  always @(posedge pixel_clk)if(read_enable)dout<=mem[rd_cache];
  assign cache_data[lane]=dout;
 end endgenerate
 reg [1:0] select_lane;
 reg [10:0] row_tag[0:CACHE_ROWS-1];
 reg [CACHE_ROWS-1:0] tag_valid;
 reg cache_present,have_frame;
 reg [10:0] last_missing_row;
 wire matching=tag_valid[display_row[CB-1:0]] && row_tag[display_row[CB-1:0]]==display_row;
 assign read_data=cache_present?cache_data[select_lane]:32'd0;
 assign diagnostic={24'd0,3'd0,held,1'b0,1'b0,1'b0,1'b0,(image_available?FRAME_SIZE:32'd0)};
 integer k;
 always @(posedge pixel_clk or negedge pix_release[1])begin
  if(!pix_release[1])begin
   image_available<=0;held<=0;accepted_frames<=0;dropped_frames<=0;displayed_frames<=0;
   busy_skips<=0;hold_skips<=0;fifo_errors<=0;tag_valid<=0;cache_present<=0;select_lane<=0;
   have_frame<=0;last_missing_row<=2047;
   for(k=0;k<CACHE_ROWS;k=k+1)row_tag[k]<=0;
  end else begin
   select_lane<=read_addr[1:0];cache_present<=matching && image_available;
   if(display_frame_start)begin
    last_missing_row<=2047;
    if(hold_display)hold_skips<=hold_skips+1'b1;
   end
   if((display_frame_start || request_row) && !qready || (play_start || play_write || play_commit) && !pready)begin
    fifo_errors<=fifo_errors+1'b1;dropped_frames<=dropped_frames+1'b1;
   end
   if(read_enable && image_available && !matching && display_row!=last_missing_row)begin
    last_missing_row<=display_row;fifo_errors<=fifo_errors+1'b1;
   end
   if(sf_out)begin
    if(sf_received[13])begin
     tag_valid<=0;image_available<=0;have_frame<=sf_received[11];held<=sf_received[12];
     if(sf_received[0])begin displayed_frames<=displayed_frames+1'b1;accepted_frames<=accepted_frames+!sf_received[12];end
    end else begin
     row_tag[sf_received[CB-1:0]]<=sf_received[10:0];tag_valid[sf_received[CB-1:0]]<=1;
     if(sf_received[10:0]==CACHE_ROWS-1 && have_frame)begin
      image_available<=1;
     end
    end
   end
  end
 end
endmodule
`default_nettype wire

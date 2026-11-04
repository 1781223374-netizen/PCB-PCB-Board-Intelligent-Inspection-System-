`timescale 1ns/1ps
`default_nettype none
// Candidate soft D-PHY: LVDS HR ISERDES, SOT search and bounded byte deskew.
// K18/K19 uses the existing CSI clock branch through R24/R32 (100 ohms).
// V6 sweeps the full 256-code HRIO delayline (IPUG026 table 3-3), resolves HS
// polarity per lane in the same sweep, and reports a per-lane run map plus an
// ungated 0xB8 census, so "range too short" can be told apart from "no usable
// analogue signal". This is an input-only diagnostic experiment; its electrical
// sampling window requires hardware validation. L14/L15 is not connected here.
module mipi_hr_rx_diag #(
    parameter [3:0] INVERT=4'b0000,
    parameter REVERSE_SAMPLES=0,
    parameter CALIBRATE=1,MAX_TAP=255,TRIAL_BURSTS=15,SKIP_BURSTS=1,MIN_HITS=12,
    parameter FIFO_LOG2=5,
    parameter SOT_ZERO_BYTES=4,
    parameter ENABLE_SOT_RETRY=1
)(
    input wire rst_n,
    input wire I_clk_hs_p,
    input wire [3:0] I_data_hs_p,I_data_lp_p,I_data_lp_n,
    output wire byte_clk,
    output reg valid,
    output reg [31:0] data,
    output reg overflow,
    output wire [1023:0] statistics,output wire [31:0] byte_gray,
    input wire configured,output wire [767:0] burst_head,
    output reg burst_error,
    output reg [31:0] missing_sot_bursts,
    output wire [383:0] fault_diagnostic
);
    wire bit_clk,byte_raw;
    // Vendor external-clock topology: IOCLK for DDR sampling, divided LCLK.
    // Share the buffered byte clock between the HR parallel side and fabric.
    // Driving HR pclk from unbuffered byte_raw caused routed hold violations
    // into the fabric; do not waive those synchronous data paths.
    PH1P_PHY_IOCLK u_ioclock(.clkin(I_clk_hs_p),.clkout(bit_clk));
    PH1P_LOGIC_BUFG u_byte_buffer(.i(byte_raw),.o(byte_clk));
    PH1P_PHY_LCLK #(.CEMD("SYNC"),.CLKSEL("ORG"),.DIV("4"),.LCLK("DIV2TO8")) u_clock(
        .clkin(I_clk_hs_p),.rst(!rst_n),.ce(1'b1),.clkout(byte_raw),.clkdivout());
    wire [3:0] lane_valid,stop_state,locked,locked_n,locked_i,overflow_event;
    wire [3:0] sync_event,sync_n,sync_i;
    wire retry_enable;
    reg started;
    wire [31:0] sample_bus,lane_bus;
    wire [7:0] lane_data_n[0:3],lane_data_i[0:3];
    (* async_reg="true" *) reg [1:0] configured_sync;
    reg armed;
    wire base_active=configured_sync[1] && armed;
    wire [3:0] cal_done,cal_eye,align_enable,cal_invert;
    wire [31:0] tap_bus,peak_bus,win_len_bus,first_start_bus,last_end_bus;
    wire [7:0] runs_bus;
    wire link_active=base_active && (&cal_done) && (&cal_eye);
    // Ungated 0xB8 census: counts the sync byte in the raw deserialised stream
    // regardless of LP11 gating or the eight-zero prefix qualification. A lane
    // with a healthy analogue input shows a large count even when no code
    // produces a stable run; a dead or badly terminated lane does not.
    reg [15:0] raw8[0:3];
    always @(posedge byte_clk or negedge rst_n)begin
        if(!rst_n)begin configured_sync<=0;armed<=0;end
        else begin
            configured_sync<={configured_sync[0],configured};
            if(!configured_sync[1])armed<=0;
            else if(&stop_state)armed<=1;
        end
    end
    genvar g;
    generate for(g=0;g<4;g=g+1) begin: lane
        wire [9:0] parallel;
        wire [7:0] samples;
        wire delayed_input;
        wire valid_n,valid_i;
        reg [1:0] stop_sync;
        always @(posedge byte_clk or negedge rst_n)
            if(!rst_n) begin stop_sync<=2'b11;raw8[g]<=16'd0;end
            else begin
                stop_sync<={stop_sync[0],I_data_lp_p[g]&I_data_lp_n[g]};
                if(sample_bus[g*8+:8]==8'hb8 && raw8[g]!=16'hffff)raw8[g]<=raw8[g]+1'b1;
            end
        assign stop_state[g]=stop_sync[1];
        assign samples=(REVERSE_SAMPLES ? {parallel[0],parallel[1],parallel[2],parallel[3],parallel[4],parallel[5],parallel[6],parallel[7]} : parallel[7:0])^{8{INVERT[g]}};
        if(CALIBRATE)begin: calibration
            lane_delay_cal #(.MAX_TAP(MAX_TAP),.TRIAL_BURSTS(TRIAL_BURSTS),.SKIP_BURSTS(SKIP_BURSTS),.MIN_HITS(MIN_HITS)) u_cal(
                .clk(byte_clk),.rst_n(rst_n),.enable(base_active),.stop_state(stop_state[g]),
                .locked(locked_n[g]),.locked_inv(locked_i[g]),
                .tap(tap_bus[g*8+:8]),.peak_hits(peak_bus[g*8+:8]),
                .done(cal_done[g]),.eye(cal_eye[g]),.invert(cal_invert[g]),
                .win_len(win_len_bus[g*8+:8]),.runs(runs_bus[g*2+:2]),
                .first_start(first_start_bus[g*8+:8]),.last_end(last_end_bus[g*8+:8]),
                .align_enable(align_enable[g]));
            PH1P_LOGIC_DYNAMIC_HR_IDELAY #(.DEVICE("PH1P50"),.CAS_MODE("NONE")) u_delay(
                .i(I_data_hs_p[g]),.dly(tap_bus[g*8+:8]),.o(delayed_input),
                .cas_i(1'b0),.cas_rtn_i(1'b0),.cas_o(),.cas_rtn_o());
        end else begin: no_calibration
            assign delayed_input=I_data_hs_p[g];
            assign cal_done[g]=1'b1;assign cal_eye[g]=1'b1;assign align_enable[g]=1'b1;
            assign tap_bus[g*8+:8]=0;assign peak_bus[g*8+:8]=0;
            assign cal_invert[g]=1'b0;assign win_len_bus[g*8+:8]=0;
            assign runs_bus[g*2+:2]=0;assign first_start_bus[g*8+:8]=0;assign last_end_bus[g*8+:8]=0;
        end
        PH1P_LOGIC_HR_ISERDES #(.IDDRMODE("DDRX4")) u_serdes(
            .sclk(bit_clk),.pclk(byte_clk),.rst(!rst_n),.idata(delayed_input),.odata(parallel));
        // Both polarity hypotheses run on the same samples, so one sweep answers
        // "is the eye out of range?" and "is P/N swapped?" at the same time.
        lane_sot_align #(.QUALIFY_BYTES(SOT_ZERO_BYTES),.SYNC(8'hb8),.QUALIFY_VALUE(8'h00)) u_align_n(
            .clk(byte_clk),.rst_n(rst_n && base_active && align_enable[g]),.stop_state(stop_state[g]),
            .retry_enable(retry_enable),.packet_committed(ENABLE_SOT_RETRY && started),.samples(samples),.valid(valid_n),.data(lane_data_n[g]),.locked(locked_n[g]),.sync_event(sync_n[g]));
        lane_sot_align #(.QUALIFY_BYTES(SOT_ZERO_BYTES),.SYNC(8'h47),.QUALIFY_VALUE(8'hff)) u_align_i(
            .clk(byte_clk),.rst_n(rst_n && base_active && align_enable[g]),.stop_state(stop_state[g]),
            .retry_enable(retry_enable),.packet_committed(ENABLE_SOT_RETRY && started),.samples(samples),.valid(valid_i),.data(lane_data_i[g]),.locked(locked_i[g]),.sync_event(sync_i[g]));
        assign lane_valid[g]=cal_invert[g]?valid_i:valid_n;
        assign lane_bus[g*8+:8]=cal_invert[g]?lane_data_i[g]:lane_data_n[g];
        assign locked[g]=cal_invert[g]?locked_i[g]:locked_n[g];
        assign sync_event[g]=cal_invert[g]?sync_i[g]:sync_n[g];
        assign sample_bus[g*8+:8]=samples;
    end endgenerate
    // V10: V9 hardware shows complete packets lost at deskew with clean CSI
    // checks on surviving packets. Increase bounded elastic storage from 8 to
    // 32 bytes/lane. ECC/CRC and full-frame publication checks stay enabled.
    localparam FIFO_DEPTH=(1<<FIFO_LOG2);
    reg [7:0] queue[0:4*FIFO_DEPTH-1];
    reg [FIFO_LOG2-1:0] wr[0:3],rd[0:3];
    reg [FIFO_LOG2:0] count[0:3];
    reg aborted;
    reg all_ready,any_data,pop;
    // A registered SOT replacement must reach the lane FIFO before the first
    // combined word is popped. Wait two ready clocks, restart the wait on any
    // SOT or empty lane, and freeze retry exactly when first pop is eligible.
    // This avoids a new candidate racing with a committed old header.
    reg [1:0] head_quiet;
    wire [3:0] queue_restart=ENABLE_SOT_RETRY?sync_event:4'd0;
    assign retry_enable=ENABLE_SOT_RETRY && link_active && !aborted && !started && head_quiet!=0;
    always @(posedge byte_clk or negedge rst_n)begin
        if(!rst_n)head_quiet<=2;
        else if(!link_active || aborted || started || !all_ready || (|queue_restart))head_quiet<=2;
        else if(head_quiet!=0)head_quiet<=head_quiet-1'b1;
    end
    integer i;
    always @* begin
        all_ready=1;any_data=0;
        for(i=0;i<4;i=i+1) begin
            if(count[i]==0) begin
                if(!started || !stop_state[i]) all_ready=0;
            end else any_data=1;
        end
        pop=link_active && !aborted && all_ready && any_data && !(|queue_restart) &&
            (started || !ENABLE_SOT_RETRY || head_quiet==0);
    end
    generate for(g=0;g<4;g=g+1)begin: overflow_flags
        assign overflow_event[g]=link_active && !aborted && !queue_restart[g] && lane_valid[g] && !(count[g]<FIFO_DEPTH || (pop && count[g]!=0));
    end endgenerate
    wire [1023:0] raw_statistics;
    // Report a complete HS burst lost before CSI, including a missing SOT on
    // every lane. A sticky historical overflow bit cannot identify bad frames.
    reg burst_open;
    reg [3:0] burst_locks;
    always @(posedge byte_clk or negedge rst_n) begin
        if(!rst_n) begin burst_open<=0;burst_locks<=0;burst_error<=0;missing_sot_bursts<=0;end
        else begin
            burst_error<=0;
            if(!link_active) begin burst_open<=0;burst_locks<=0;end
            else begin
                if(!(&stop_state)) begin
                    burst_open<=1;burst_locks<=burst_locks|locked;
                end
                if(|overflow_event) burst_error<=1;
                if(burst_open && (&stop_state)) begin
                    if(!(&burst_locks) || aborted) burst_error<=1;
                    if(!(&burst_locks)) missing_sot_bursts<=missing_sot_bursts+1'b1;
                    burst_open<=0;burst_locks<=0;
                end
            end
        end
    end
    // Capture the state BEFORE an overflow abort. An overflowing lane can be
    // the early lane waiting for another lane: the overflow mask is not a
    // diagnosis of which physical lane is faulty.
    // LASTOVR = age[31:24], started[16], overflow[15:12], locks[11:8],
    //           stop[7:4], lane_valid[3:0]. Ages are byte-clock cycles since
    //           the first lane left LP11; FF means no observed lock/saturation.
    reg [31:0] overflow_pre,overflow_post,last_overflow;
    reg [7:0] burst_age;
    reg [7:0] lock_age[0:3],last_lock_age[0:3],last_count[0:3],max_count[0:3];
    integer d;
    always @(posedge byte_clk or negedge rst_n) begin
        if(!rst_n) begin
            overflow_pre<=0;overflow_post<=0;last_overflow<=0;burst_age<=0;
            for(d=0;d<4;d=d+1)begin lock_age[d]<=8'hff;last_lock_age[d]<=8'hff;last_count[d]<=0;max_count[d]<=0;end
        end else begin
            if(!link_active || (&stop_state)) begin
                burst_age<=0;
                for(d=0;d<4;d=d+1)lock_age[d]<=8'hff;
            end else begin
                if(burst_age!=8'hff)burst_age<=burst_age+1'b1;
                for(d=0;d<4;d=d+1)
                    if(queue_restart[d] || (locked[d] && lock_age[d]==8'hff))lock_age[d]<=burst_age;
            end
            if(link_active)begin
                for(d=0;d<4;d=d+1)if(count[d]>max_count[d])max_count[d]<=count[d];
                if(|overflow_event)begin
                    if(started)overflow_post<=overflow_post+1'b1;
                    else overflow_pre<=overflow_pre+1'b1;
                    last_overflow<={burst_age,7'd0,started,overflow_event,locked,stop_state,lane_valid};
                    for(d=0;d<4;d=d+1)begin
                        last_count[d]<=count[d];
                        last_lock_age[d]<=lock_age[d]==8'hff && locked[d]?burst_age:lock_age[d];
                    end
                end
            end
        end
    end
    // V11: preserve evidence from bad headers, even when no FIFO overflows.
    // Save per-burst lock ages and queue occupancy at the FIRST pop, then
    // associate them with that packet's header. Parser acceptance is untouched.
    // The monitor uses exactly the parser's six ECC parity masks; bits 7:6 of
    // syndrome retain illegal received ECC reserved bits. Lower bits are XOR.
    function [5:0] monitor_ecc;
        input [23:0] h;
        begin
            monitor_ecc[0]=^(h&24'hf12cb7);monitor_ecc[1]=^(h&24'hf2555b);
            monitor_ecc[2]=^(h&24'h749a6d);monitor_ecc[3]=^(h&24'hb8e38e);
            monitor_ecc[4]=^(h&24'hdf03f0);monitor_ecc[5]=^(h&24'heffc00);
        end
    endfunction
    wire [7:0] header_syndrome={data[31:30],data[29:24]^monitor_ecc(data[23:0])};
    reg monitor_previous_valid;
    reg [31:0] packet_ages,packet_counts;
    reg [31:0] last_bad_header,first_bad_header,last_bad_ages,last_bad_counts;
    reg [31:0] first_bad_ages,first_bad_counts,bad_capture_count;
    reg [7:0] last_bad_syndrome;
    reg [3:0] first_bad_polarity,last_bad_polarity;
    integer f;
    always @(posedge byte_clk or negedge rst_n)begin
        if(!rst_n)begin
            monitor_previous_valid<=0;packet_ages<=32'hffffffff;packet_counts<=0;
            last_bad_header<=0;first_bad_header<=0;last_bad_ages<=32'hffffffff;last_bad_counts<=0;
            first_bad_ages<=32'hffffffff;first_bad_counts<=0;bad_capture_count<=0;
            last_bad_syndrome<=0;first_bad_polarity<=0;last_bad_polarity<=0;
        end else begin
            monitor_previous_valid<=valid;
            if(pop && !started)begin
                for(f=0;f<4;f=f+1)begin
                    packet_ages[f*8+:8]<=lock_age[f]==8'hff && locked[f]?burst_age:lock_age[f];
                    packet_counts[f*8+:8]<=count[f];
                end
            end
            if(valid && !monitor_previous_valid && header_syndrome!=0)begin
                bad_capture_count<=bad_capture_count+1'b1;
                last_bad_header<=data;last_bad_ages<=packet_ages;last_bad_counts<=packet_counts;
                last_bad_syndrome<=header_syndrome;last_bad_polarity<=cal_invert;
                if(bad_capture_count==0)begin
                    first_bad_header<=data;first_bad_ages<=packet_ages;first_bad_counts<=packet_counts;
                    first_bad_polarity<=cal_invert;
                end
            end
        end
    end
    // Eight 32-bit slots, low first: last/first bad header, last ages/queues,
    // first ages/queues, {zero16,first polarity4,last polarity4,syndrome8}, count.
    reg [3:0] seen_sync;
    reg [31:0] retry_count[0:3];
    integer r;
    always @(posedge byte_clk or negedge rst_n)begin
        if(!rst_n)begin seen_sync<=0;for(r=0;r<4;r=r+1)retry_count[r]<=0;end
        else for(r=0;r<4;r=r+1)begin
            if(!link_active || stop_state[r])seen_sync[r]<=0;
            else if(queue_restart[r])begin
                seen_sync[r]<=1;
                if(seen_sync[r])retry_count[r]<=retry_count[r]+1'b1;
            end
        end
    end
    assign fault_diagnostic={retry_count[3],retry_count[2],retry_count[1],retry_count[0],bad_capture_count,16'd0,first_bad_polarity,last_bad_polarity,last_bad_syndrome,
        first_bad_counts,first_bad_ages,last_bad_counts,last_bad_ages,first_bad_header,last_bad_header};
    mipi_lane_statistics u_statistics(byte_clk,rst_n,sample_bus,lane_bus,stop_state,locked,lane_valid,overflow_event,valid,raw_statistics,byte_gray,base_active,burst_head);
    // V10 keeps the V6 tap/eye fields and adds pre-abort diagnostics.
    // Slot A = {last_count,last_lock_age,peak,tap}; slot B retains the run map.
    // Former zero slots 3/7/11/15 now hold PRE/POST/LASTOVR/QMAX.
    // SOT slots 0/4/8/12 and raw statistics slots 16..31 are unchanged.
    wire [127:0] slot_a_flat,slot_b_flat;
    generate for(g=0;g<4;g=g+1)begin: slot_pack
        assign slot_a_flat[g*32+:32]={last_count[g],last_lock_age[g],peak_bus[g*8+:8],tap_bus[g*8+:8]};
        assign slot_b_flat[g*32+:32]={win_len_bus[g*8+:8],first_start_bus[g*8+:8],last_end_bus[g*8+:8],
                                      runs_bus[g*2+:2],cal_invert[g],cal_eye[g],cal_done[g],3'd0};
    end endgenerate
    assign statistics={
        raw_statistics[1023:512],
        {max_count[3],max_count[2],max_count[1],max_count[0]},slot_b_flat[127:96],slot_a_flat[127:96],
        raw_statistics[415:384],
        last_overflow,slot_b_flat[95:64],slot_a_flat[95:64],
        raw_statistics[287:256],
        overflow_post,slot_b_flat[63:32],slot_a_flat[63:32],
        raw_statistics[159:128],
        overflow_pre,slot_b_flat[31:0],slot_a_flat[31:0],
        raw_statistics[31:0]};
    integer j;
    always @(posedge byte_clk or negedge rst_n) begin
        if(!rst_n) begin
            started<=0;aborted<=0;valid<=0;data<=0;overflow<=0;
            for(j=0;j<4;j=j+1) begin wr[j]<=0;rd[j]<=0;count[j]<=0;end
        end else if(!link_active || aborted || (|overflow_event) ||
                    ((&stop_state) && !started && !(|lane_valid))) begin
            // Drop the rest of an overflowing/missing-lane burst. All four
            // queues restart together at LP11; never carry bytes into a new packet.
            started<=0;valid<=0;
            for(j=0;j<4;j=j+1)begin wr[j]<=0;rd[j]<=0;count[j]<=0;end
            if(|overflow_event)begin aborted<=1;overflow<=1;end
            else if(!link_active || ((&stop_state) && !(|lane_valid)))aborted<=0;
        end else begin
            valid<=pop;
            if(pop) started<=1;
            if(&stop_state && !any_data && !(|lane_valid)) started<=0;
            for(j=0;j<4;j=j+1) begin
                if(queue_restart[j])begin
                    wr[j]<=0;rd[j]<=0;count[j]<=0;
                end else begin
                if(pop) begin
                    data[j*8+:8]<=count[j]!=0 ? queue[j*FIFO_DEPTH+rd[j]] : 8'd0;
                    if(count[j]!=0) rd[j]<=rd[j]+1'b1;
                end
                if(lane_valid[j] && (count[j]<FIFO_DEPTH || (pop && count[j]!=0))) begin
                    queue[j*FIFO_DEPTH+wr[j]]<=lane_bus[j*8+:8];wr[j]<=wr[j]+1'b1;
                end else if(lane_valid[j]) overflow<=1;
                case({lane_valid[j] && (count[j]<FIFO_DEPTH || (pop && count[j]!=0)),pop && count[j]!=0})
                    2'b10:count[j]<=count[j]+1'b1;
                    2'b01:count[j]<=count[j]-1'b1;
                    default:count[j]<=count[j];
                endcase
                end
            end
        end
    end
endmodule
`default_nettype wire

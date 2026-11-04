`timescale 1ns/1ps
`default_nettype none
module session_image_pipeline_rgb565 #(
    parameter CROP_WIDTH=1920,CROP_HEIGHT=1080,X_START=972,Y_START=556,
    parameter BAYER_PATTERN=1,GRAYSCALE=0,SENSOR_WIDTH=3864,SENSOR_HEIGHT=2192,
    parameter ENABLE_FRAME_GUARD=1,ENABLE_COLOR_CONTROL=0,
    parameter DOWNSAMPLE=1,
    parameter FRAME_WORDS=CROP_WIDTH*CROP_HEIGHT/(DOWNSAMPLE*DOWNSAMPLE*2),
    parameter ADDR_BITS=21,ENABLE_NETWORK=1
)(
    input wire [12:0] net_cmd,input wire net_cmd_valid,output wire net_cmd_ready,
 output wire [129:0] net_response,output wire net_response_valid,input wire net_response_ready,
    input wire cam_clk,cam_rst_n,hs_valid,
    input wire burst_error,
    input wire [31:0] hs_data,
    output wire [31:0] csi_errors,accepted_frames,dropped_frames,
    input wire pixel_clk,pixel_rst_n,display_frame_start,read_enable,
    input wire display_line_end,output wire play_ready,
    input wire [ADDR_BITS-1:0] read_addr,
    output wire [31:0] read_data,
    output wire image_available,
    output wire [31:0] good_headers,bad_headers,bad_crc,truncated,raw_lines,fs_count,fe_count,last_header,
    output wire [15:0] last_wc,
    output wire [31:0] geometry_rejected,
    output wire [12:0] last_frame_lines,
    output wire [575:0] diagnostic,
    output wire [31:0] displayed_frames,
    input wire [1:0] color_pattern,input wire wb_request,
    output wire [127:0] color_diagnostic,output wire [63:0] calibration_diagnostic,output wire [31:0] busy_skips,
    input wire hold_display,play_start,play_write,play_commit,
    input wire [ADDR_BITS-1:0] play_addr,input wire [31:0] play_data,
    output wire held,output wire [31:0] hold_skips,fifo_errors,
    input wire ddr_clk,ddr_rst_n,ddr_enable,
    output wire [191:0] ddr_diagnostic,output wire ddr_fault,
    output wire [127:0] ddr_fault_diagnostic,
    output wire [26:0] ddr_awaddr,output wire ddr_awvalid,input wire ddr_awready,
    output wire [127:0] ddr_wdata,output wire [15:0] ddr_wstrb,output wire ddr_wvalid,ddr_wlast,input wire ddr_wready,
    output wire [26:0] ddr_araddr,output wire ddr_arvalid,input wire ddr_arready,
    input wire [127:0] ddr_rdata,input wire ddr_rvalid,ddr_rlast,output wire ddr_rready
);
    wire fs,fe,frame_bad,ls,le,pv;
    wire [15:0] line_bytes;
    wire [2:0] payload_count;
    wire [31:0] payload;
    wire raw_ls,raw_le,raw_valid,raw_error;
    wire [39:0] raw;
    wire pair_valid;
    wire [31:0] pair_data;
    wire [31:0] preview_words;
    wire geometry_bad;
    wire [255:0] geometry_diag;
    wire [63:0] buffer_diag;
    wire [31:0] bad_raw_wc;
    wire [15:0] last_bad_raw_wc;
    wire color_idle,color_error;
    reg finish_pending,drained_fe;reg [3:0] finish_wait;
    always @(posedge cam_clk or negedge cam_rst_n)begin
      if(!cam_rst_n)begin finish_pending<=0;drained_fe<=0;finish_wait<=0;end
      else begin
        drained_fe<=0;
        if(fs)begin finish_pending<=0;finish_wait<=0;end
        else if(fe)begin finish_pending<=1;finish_wait<=8;end
        else if(finish_pending)begin
          if(finish_wait!=0)finish_wait<=finish_wait-1'b1;
          else if(color_idle)begin drained_fe<=1;finish_pending<=0;end
        end
      end
    end
    reg monitor_active;
    reg [2:0] frame_flags,last_frame_flags;
    reg [31:0] crop_words,last_crop_words,burst_count,raw_error_count;
    reg [31:0] frame_bursts,last_frame_bursts,csi_base,last_frame_csi;
    reg [15:0] last_fs_id,last_fe_id;
    wire [2:0] observed_flags={burst_error,raw_error,frame_bad};
    // Diagnostic buses are sampled coherently by the top-level mailbox.
    // Words 0..7 geometry; 8..15 passive frame monitor; 16..17 buffer status.
    assign diagnostic={buffer_diag,
        last_fs_id,last_fe_id,
        last_bad_raw_wc,13'd0,last_frame_flags,
        bad_raw_wc,raw_error_count,burst_count,last_frame_bursts,
        last_frame_csi,last_crop_words,geometry_diag};
    always @(posedge cam_clk or negedge cam_rst_n) begin
        if(!cam_rst_n) begin
            monitor_active<=0;frame_flags<=0;last_frame_flags<=0;
            crop_words<=0;last_crop_words<=0;burst_count<=0;raw_error_count<=0;
            frame_bursts<=0;last_frame_bursts<=0;csi_base<=0;last_frame_csi<=0;
            last_fs_id<=0;last_fe_id<=0;
        end else begin
            if(burst_error) burst_count<=burst_count+1'b1;
            if(raw_error) raw_error_count<=raw_error_count+1'b1;
            if(fs) begin
                if(monitor_active) begin
                    last_crop_words<=crop_words;last_frame_flags<=frame_flags;
                    last_frame_bursts<=frame_bursts;last_frame_csi<=csi_errors-csi_base;
                end
                monitor_active<=1;frame_flags<=0;crop_words<=0;frame_bursts<=0;
                csi_base<=csi_errors;last_fs_id<=last_header[23:8];
            end else if(monitor_active) begin
                frame_flags<=frame_flags|observed_flags;
                if(pair_valid) crop_words<=crop_words+1'b1;
                if(burst_error) frame_bursts<=frame_bursts+1'b1;
                if(drained_fe) begin
                    monitor_active<=0;last_crop_words<=crop_words;
                    last_frame_flags<=frame_flags|observed_flags;
                    last_frame_bursts<=frame_bursts+burst_error;
                    last_frame_csi<=csi_errors-csi_base;
                end
            end
            if(fe) last_fe_id<=last_header[23:8];
        end
    end
    reg format_bad;
    always @(posedge cam_clk or negedge cam_rst_n)
        if(!cam_rst_n) format_bad<=0;
        else if(fs) format_bad<=0;
        else if(raw_error || color_error) format_bad<=1;
    csi2_raw10_rx4_diag u_csi(.clk(cam_clk),.rst_n(cam_rst_n),.hs_valid(hs_valid),.hs_data(hs_data),
        .frame_start(fs),.frame_end(fe),.frame_error(frame_bad),.line_start(ls),.line_end(le),
        .line_bytes(line_bytes),.payload_valid(pv),.payload_bytes(payload_count),.payload_data(payload),.error_count(csi_errors),.good_headers(good_headers),.bad_headers(bad_headers),.bad_crc(bad_crc),
        .truncated(truncated),.raw_lines(raw_lines),.fs_count(fs_count),.fe_count(fe_count),.last_header(last_header),.last_wc(last_wc),
        .bad_raw_wc(bad_raw_wc),.last_bad_raw_wc(last_bad_raw_wc));
    raw10_unpack4 u_raw(.clk(cam_clk),.rst_n(cam_rst_n),.line_start_in(ls),.line_end_in(le),
        .payload_valid(pv),.payload_bytes(payload_count),.payload_data(payload),
        .line_start(raw_ls),.line_end(raw_le),.pixels_valid(raw_valid),.pixels(raw),.format_error(raw_error));
    frame_geometry_guard #(.SENSOR_WIDTH(SENSOR_WIDTH),.SENSOR_HEIGHT(SENSOR_HEIGHT)) u_geometry(
        .clk(cam_clk),.rst_n(cam_rst_n),.frame_start(fs),.frame_end(fe),
        .line_start(raw_ls),.line_end(raw_le),.pixels_valid(raw_valid),.line_bytes(line_bytes),
        .input_error(frame_bad|raw_error|burst_error),.frame_bad(geometry_bad),
        .rejected_frames(geometry_rejected),.last_frame_lines(last_frame_lines),.diagnostic(geometry_diag));
    generate if(DOWNSAMPLE==1)begin: native_colour
    bayer_native_rgb565 #(.CROP_WIDTH(CROP_WIDTH),.CROP_HEIGHT(CROP_HEIGHT),.X_START(X_START),.Y_START(Y_START)) u_color(
        .clk(cam_clk),.rst_n(cam_rst_n),.frame_start(fs),.line_start(raw_ls),.line_end(raw_le),
        .pixels_valid(raw_valid),.pixels(raw),.pattern_setting(color_pattern),.wb_request_toggle(wb_request),
        .frame_finish(drained_fe),.frame_good(!(frame_bad|format_bad|geometry_bad|burst_error)),
        .word_valid(pair_valid),.rgb_pair(pair_data),.preview_words(preview_words),.diagnostic(color_diagnostic),.calibration_diagnostic(calibration_diagnostic),.idle(color_idle),.frame_error(color_error));
    end else begin: legacy_colour
    bayer_preview_rgb565 #(.CROP_WIDTH(CROP_WIDTH),.CROP_HEIGHT(CROP_HEIGHT),.X_START(X_START),.Y_START(Y_START),.DOWNSAMPLE(DOWNSAMPLE)) u_color(
        .clk(cam_clk),.rst_n(cam_rst_n),.frame_start(fs),.line_start(raw_ls),.line_end(raw_le),
        .pixels_valid(raw_valid),.pixels(raw),.pattern_setting(color_pattern),.wb_request_toggle(wb_request),
        .frame_finish(drained_fe),.frame_good(!(frame_bad|format_bad|geometry_bad|burst_error)),
        .word_valid(pair_valid),.rgb_pair(pair_data),.preview_words(preview_words),.diagnostic(color_diagnostic),.calibration_diagnostic(calibration_diagnostic));
    assign color_idle=1;assign color_error=0;
    end endgenerate
    generate begin: native_path
    ddr_native_framebuffer #(.ENABLE_NETWORK(ENABLE_NETWORK),.WIDTH(CROP_WIDTH/DOWNSAMPLE),.HEIGHT(CROP_HEIGHT/DOWNSAMPLE),.ADDR_BITS(ADDR_BITS)) u_buffer(
        .net_cmd(net_cmd),.net_cmd_valid(net_cmd_valid),.net_cmd_ready(net_cmd_ready),
        .net_response(net_response),.net_response_valid(net_response_valid),.net_response_ready(net_response_ready),
        .cam_clk(cam_clk),.cam_rst_n(cam_rst_n),.frame_start(fs),.frame_end(drained_fe),.frame_error(frame_bad|format_bad|raw_error|(ENABLE_FRAME_GUARD && (geometry_bad|burst_error))),
        .word_valid(pair_valid),.word_data(pair_data),.accepted_frames(accepted_frames),.dropped_frames(dropped_frames),
        .pixel_clk(pixel_clk),.pixel_rst_n(pixel_rst_n),.display_frame_start(display_frame_start),.display_line_end(display_line_end),.read_enable(read_enable),
        .read_addr(read_addr),.read_data(read_data),.image_available(image_available),
        .displayed_frames(displayed_frames),.diagnostic(buffer_diag),
        .hold_display(hold_display),.play_start(play_start),.play_write(play_write),.play_commit(play_commit),
        .play_addr(play_addr),.play_data(play_data),.play_ready(play_ready),.held(held),.busy_skips(busy_skips),.hold_skips(hold_skips),.fifo_errors(fifo_errors),
        .ddr_clk(ddr_clk),.ddr_rst_n(ddr_rst_n),.ddr_enable(ddr_enable),
        .ddr_stored(ddr_diagnostic[0+:32]),.ddr_read(ddr_diagnostic[32+:32]),.ddr_dropped(ddr_diagnostic[64+:32]),
        .ddr_write_beats(ddr_diagnostic[96+:32]),.ddr_read_beats(ddr_diagnostic[128+:32]),.ddr_protocol_errors(ddr_diagnostic[160+:32]),.ddr_fault(ddr_fault),
        .fault_diagnostic(ddr_fault_diagnostic),
        .awaddr(ddr_awaddr),.awvalid(ddr_awvalid),.awready(ddr_awready),
        .wdata(ddr_wdata),.wstrb(ddr_wstrb),.wvalid(ddr_wvalid),.wlast(ddr_wlast),.wready(ddr_wready),
        .araddr(ddr_araddr),.arvalid(ddr_arvalid),.arready(ddr_arready),
        .rdata(ddr_rdata),.rvalid(ddr_rvalid),.rlast(ddr_rlast),.rready(ddr_rready));
    end endgenerate

endmodule
`default_nettype wire

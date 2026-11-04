`timescale 1ns/1ps
`default_nettype none
// CRC cannot detect a whole packet that never reached the CSI parser. Count
// every RAW line and every unpacked pixel, including those outside the crop.
// A missing/extra line must invalidate the whole frame before publication.
module frame_geometry_guard #(
    parameter SENSOR_WIDTH=3864,
    parameter SENSOR_HEIGHT=2192
)(
    input wire clk,rst_n,frame_start,frame_end,
    input wire line_start,line_end,pixels_valid,
    input wire [15:0] line_bytes,
    input wire input_error,
    output reg frame_bad,
    output reg [31:0] rejected_frames,
    output reg [12:0] last_frame_lines,
    output wire [255:0] diagnostic
);
    reg in_frame,line_open;
    reg [12:0] lines;
    reg [13:0] line_pixels;
    wire [14:0] pixels_after={1'b0,line_pixels}+(pixels_valid?15'd4:15'd0);
    wire geometry_invalid=!in_frame || line_open || lines!=SENSOR_HEIGHT;
    // Passive diagnostics. Bits: 0 input error; 1 WC; 2 pixel count;
    // 3 frame row count; 4 line/frame sequence; 5 missing FE; 6 excess rows.
    // Keep the existing acceptance policy unchanged during hardware diagnosis.
    reg [7:0] reasons,last_reasons,ever_reasons;
    reg [15:0] min_pixels,max_pixels,min_wc,max_wc;
    reg [15:0] last_min_pixels,last_max_pixels,last_min_wc,last_max_wc;
    reg [15:0] min_rows,max_rows,last_pixels,last_bytes;
    reg [31:0] completed,interrupted;
    wire [7:0] faults={1'b0,
        (line_end && lines>=SENSOR_HEIGHT),1'b0,
        ((line_start && (!in_frame || line_open)) ||
         (pixels_valid && (!in_frame || !line_open)) ||
         (line_end && !line_open) || (frame_end && (!in_frame || line_open))),
        (frame_end && lines!=SENSOR_HEIGHT),
        ((pixels_valid && pixels_after>SENSOR_WIDTH) ||
         (line_end && pixels_after!=SENSOR_WIDTH)),
        (line_start && line_bytes!=SENSOR_WIDTH*5/4),
        (in_frame && input_error)};
    wire [7:0] completed_reasons=reasons|faults;
    assign diagnostic={
        reasons,6'd0,line_open,in_frame,3'd0,lines,
        last_pixels,last_bytes,
        interrupted,completed,
        min_rows,max_rows,
        last_min_wc,last_max_wc,
        last_min_pixels,last_max_pixels,
        last_reasons,ever_reasons,3'd0,last_frame_lines};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            reasons<=0;last_reasons<=0;ever_reasons<=0;
            min_pixels<=16'hffff;max_pixels<=0;min_wc<=16'hffff;max_wc<=0;
            last_min_pixels<=0;last_max_pixels<=0;last_min_wc<=0;last_max_wc<=0;
            min_rows<=16'hffff;max_rows<=0;completed<=0;interrupted<=0;
            last_pixels<=0;last_bytes<=0;
        end else if(frame_start) begin
            reasons<=0;min_pixels<=16'hffff;max_pixels<=0;min_wc<=16'hffff;max_wc<=0;
            if(in_frame) begin
                interrupted<=interrupted+1'b1;
                last_reasons<=reasons|8'h20;ever_reasons<=ever_reasons|reasons|8'h20;
                last_min_pixels<=min_pixels;last_max_pixels<=max_pixels;
                last_min_wc<=min_wc;last_max_wc<=max_wc;
            end
        end else begin
            reasons<=completed_reasons;
            if(line_start) begin
                last_bytes<=line_bytes;
                if(line_bytes<min_wc) min_wc<=line_bytes;
                if(line_bytes>max_wc) max_wc<=line_bytes;
            end
            if(line_end) begin
                last_pixels<={1'b0,pixels_after};
                if(pixels_after<min_pixels) min_pixels<={1'b0,pixels_after};
                if(pixels_after>max_pixels) max_pixels<={1'b0,pixels_after};
            end
            if(frame_end) begin
                completed<=completed+1'b1;
                last_reasons<=completed_reasons;ever_reasons<=ever_reasons|completed_reasons;
                last_min_pixels<=min_pixels;last_max_pixels<=max_pixels;
                last_min_wc<=min_wc;last_max_wc<=max_wc;
                if(lines<min_rows) min_rows<={3'd0,lines};
                if(lines>max_rows) max_rows<={3'd0,lines};
            end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            in_frame<=0;line_open<=0;lines<=0;line_pixels<=0;
            frame_bad<=0;rejected_frames<=0;last_frame_lines<=0;
        end else if(frame_start) begin
            // An unclosed prior frame is discarded too. Clear bad only at FS.
            if(in_frame) begin rejected_frames<=rejected_frames+1'b1;last_frame_lines<=lines;end
            in_frame<=1;line_open<=0;lines<=0;line_pixels<=0;frame_bad<=0;
        end else begin
            if(in_frame && input_error) frame_bad<=1;
            if(line_start) begin
                line_open<=1;line_pixels<=0;
                if(!in_frame || line_open || line_bytes!=SENSOR_WIDTH*5/4)
                    frame_bad<=1;
            end
            if(pixels_valid) begin
                line_pixels<=pixels_after[13:0];
                if(!in_frame || !line_open || pixels_after>SENSOR_WIDTH)
                    frame_bad<=1;
            end
            if(line_end) begin
                line_open<=0;
                if(lines!=13'h1fff) lines<=lines+1'b1;
                if(!line_open || pixels_after!=SENSOR_WIDTH || lines>=SENSOR_HEIGHT)
                    frame_bad<=1;
            end
            if(frame_end) begin
                in_frame<=0;last_frame_lines<=lines;
                if(frame_bad || input_error || geometry_invalid) begin
                    frame_bad<=1;rejected_frames<=rejected_frames+1'b1;
                end
            end
        end
    end
endmodule
`default_nettype wire

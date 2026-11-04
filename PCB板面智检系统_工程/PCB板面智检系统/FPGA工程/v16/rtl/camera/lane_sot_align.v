`timescale 1ns/1ps
`default_nettype none
// V12 active aligner. A SOT is provisional until the deskew receiver closes
// its pre-header retry window. A new qualified SOT replaces an earlier one,
// invalidates that cycle's byte, and asks the receiver to flush ONLY this lane.
// Search remains bounded since LP11 exit, including time spent provisionally
// locked. No retry is allowed after the receiver commits its first word.
module lane_sot_align #(
    parameter SEARCH_CYCLES=64,
    parameter QUALIFY_ZERO=1,
    parameter QUALIFY_BYTES=1,
    parameter [7:0] SYNC=8'hb8,
    parameter [7:0] QUALIFY_VALUE=8'h00
)(
    input wire clk,rst_n,stop_state,retry_enable,packet_committed,
    input wire [7:0] samples,
    output reg valid,
    output reg [7:0] data,
    output reg locked,
    output reg sync_event
);
    // Only observed samples after LP11 exit may qualify a sync. Reset zeros
    // are not a measured HS-zero preamble. Active V11 receivers require 32
    // consecutive bits; passive census detectors retain their old settings.
    localparam HISTORY_BITS=(QUALIFY_BYTES+1)*8;
    localparam PREFIX_BITS=QUALIFY_BYTES*8;
    reg [HISTORY_BITS-1:0] history;
    reg [7:0] history_samples;
    reg [6:0] search_age;
    reg [2:0] shift;
    reg found;
    reg [2:0] found_shift;
    wire [15:0] window={samples,history[HISTORY_BITS-1-:8]};
    wire [HISTORY_BITS+7:0] qualified_window={samples,history};
    integer k;
    always @* begin
        found=0;found_shift=0;
        for(k=0;k<8;k=k+1)
            if(!found && (!QUALIFY_ZERO ||
               (history_samples>=QUALIFY_BYTES+1 && qualified_window[k+:PREFIX_BITS]=={QUALIFY_BYTES{QUALIFY_VALUE}})) && window[k+:8]==SYNC)
                begin found=1;found_shift=k;end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin history<=0;history_samples<=0;search_age<=0;shift<=0;valid<=0;data<=0;locked<=0;sync_event<=0;end
        else begin
            history<={samples,history[HISTORY_BITS-1:8]};valid<=0;sync_event<=0;
            if(history_samples<QUALIFY_BYTES+1)history_samples<=history_samples+1'b1;
            if(stop_state) begin locked<=0;history<=0;history_samples<=0;search_age<=0;end
            else begin
                if(SEARCH_CYCLES!=0 && search_age<SEARCH_CYCLES)search_age<=search_age+1'b1;
                if(!packet_committed && (!locked || retry_enable) && found &&
                   (SEARCH_CYCLES==0 || search_age<SEARCH_CYCLES)) begin
                    locked<=1;shift<=found_shift;sync_event<=1;
                end else if(locked) begin valid<=1;data<=window[shift+:8];end
            end
        end
    end
endmodule
`default_nettype wire

`timescale 1ns/1ps
`default_nettype none
// Search only the beginning of a burst, and require HS-zero before the sync.
// A missed sync must not later lock onto an arbitrary B8 in RAW payload.
//
// V5: the sync word and its qualifying prefix are parameters, so the same
// detector can run on the normal and on the P/N-swapped hypothesis in
// parallel. HS 0xB8 behind an eight-zero prefix is the wired-for polarity;
// the same byte seen through a swapped pair is 0x47 behind eight ones.
module lane_byte_align #(
    parameter SEARCH_CYCLES=64,
    parameter QUALIFY_ZERO=1,
    parameter QUALIFY_BYTES=1,
    parameter [7:0] SYNC=8'hb8,
    parameter [7:0] QUALIFY_VALUE=8'h00
)(
    input wire clk,rst_n,stop_state,
    input wire [7:0] samples,
    output reg valid,
    output reg [7:0] data,
    output reg locked
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
        if(!rst_n) begin history<=0;history_samples<=0;search_age<=0;shift<=0;valid<=0;data<=0;locked<=0;end
        else begin
            history<={samples,history[HISTORY_BITS-1:8]};valid<=0;
            if(history_samples<QUALIFY_BYTES+1)history_samples<=history_samples+1'b1;
            if(stop_state) begin locked<=0;history<=0;history_samples<=0;search_age<=0;end
            else if(!locked) begin
                if(SEARCH_CYCLES==0 || search_age<SEARCH_CYCLES) begin
                    if(SEARCH_CYCLES!=0)search_age<=search_age+1'b1;
                    if(found) begin locked<=1;shift<=found_shift;end
                end
            end else begin valid<=1;data<=window[shift+:8];end
        end
    end
endmodule
`default_nettype wire

`timescale 1ps/1ps

module ph1p_ddrphy_dbi_wrapper #(
    parameter DX_NUM = 8,
    parameter RDBI   = 1,
    parameter WDBI   = 1
) (
    // rdbi
    input   [DX_NUM*8*8 - 1 : 0]  rddata_in  , // per_byte
    input   [DX_NUM*8   - 1 : 0]  rddata_dbi ,
    output  [DX_NUM*8*8 - 1 : 0]  rddata_out ,

    // wdbi
    input   [DX_NUM*8*8 - 1 : 0]  wrdata_in  , // per_byte
    input   [DX_NUM*8   - 1 : 0]  wrdata_mask,
    output  [DX_NUM*8   - 1 : 0]  wrdata_dbi ,
    output  [DX_NUM*8*8 - 1 : 0]  wrdata_out
);

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//    Instance : RDBI
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
generate 
if (RDBI == 1) begin : rdbi
ph1p_ddrphy_rdbi #(
    .DX_NUM ( DX_NUM ),
    .RDBI   ( RDBI   )
) u_ddrphy_rdbi(
    .rddata_in ( rddata_in  ),// per_byte
    .rddata_dbi( rddata_dbi ),
    .rddata_out( rddata_out )
);
end else begin :rdbi_dis
assign rddata_out = rddata_in;
end
endgenerate
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
//    Instance : WDBI
///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

generate 
if (WDBI == 1) begin : wdbi
ph1p_ddrphy_wdbi #(
    .DX_NUM ( DX_NUM ),
    .WDBI   ( WDBI   )
) u_ddrphy_wdbi (
    .wrdata_in   ( wrdata_in   ), // per_byte
    .wrdata_mask ( wrdata_mask ),
    .wrdata_dbi  ( wrdata_dbi  ),
    .wrdata_out  ( wrdata_out  )
);
end else begin :wdbi_dis
assign wrdata_out = wrdata_in  ;
assign wrdata_dbi = wrdata_mask;
end
endgenerate
endmodule

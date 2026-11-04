///////////////////////////////////////////////////////////////////////////////////////////////////
// RDBI
///////////////////////////////////////////////////////////////////////////////////////////////////
`timescale 1ps/1ps
module ph1p_ddrphy_rdbi #(
    parameter DX_NUM = 8,
    parameter RDBI   = 0
) (
    input   [DX_NUM*8*8 - 1 : 0]  rddata_in  , // per_byte
    input   [DX_NUM*8   - 1 : 0]  rddata_dbi ,
    output  [DX_NUM*8*8 - 1 : 0]  rddata_out
);

wire  [DX_NUM*8*8 - 1 : 0]  rddata_out_tmp;

genvar n, p;

generate
    for (n = 0; n <= DX_NUM - 1; n = n+1) begin : decode_nIdx
        for (p = 0; p <= 7; p = p+1) begin : decode_pIdx
            
            assign rddata_out_tmp[(p*(DX_NUM*8) + n*8) +: 8] = (rddata_dbi [(p*(DX_NUM*1) + n*1)] == 1'b1) ?  rddata_in[(p*(DX_NUM*8) + n*8) +: 8]
                                                                                                           : ~rddata_in[(p*(DX_NUM*8) + n*8) +: 8];
        end
    end
endgenerate

    assign rddata_out = (RDBI == 1) ? rddata_out_tmp  : rddata_in;

endmodule


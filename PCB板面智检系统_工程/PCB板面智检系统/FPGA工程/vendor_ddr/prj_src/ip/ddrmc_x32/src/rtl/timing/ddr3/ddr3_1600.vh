
// min in tCK
localparam nRTP_min  = 4;
localparam nWTR_min  = 4;
localparam nZQCS_min = 64;
localparam nXS_min   = 5;
localparam nRRD_min  = 4;
localparam nCCD      = 4;

// min in ps
localparam real tRAS      = 35_000;
localparam real tRTP_min  =  7_500;
localparam real tWTR_min  =  7_500;
localparam real tZQCS_min = 80_000;
localparam real tXS_min   = tRFC + 10_000;

`ifdef DDR3_8G
localparam real tRRD_min  =  7_500;
localparam real tFAW      = 40_000;
`else // DDR3_512M DDR3_1G DDR3_2G DDR3_4G
`ifdef DDR3_X16
localparam real tRRD_min  =  7_500;
localparam real tFAW      = 40_000;
`else // DDR3_X4 DDR3_X8
localparam real tRRD_min  =  6_000;
localparam real tFAW      = 30_000;
`endif
`endif


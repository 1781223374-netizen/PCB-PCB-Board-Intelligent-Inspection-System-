
// DDR3_512M
// DDR3_1G
// DDR3_2G
// DDR3_4G
// DDR3_8G

// DDR3_X4
// DDR3_X8
// DDR3_X16

// DDR3_800D
// DDR3_800E
// DDR3_1066E
// DDR3_1066F
// DDR3_1066G
// DDR3_1333F
// DDR3_1333G
// DDR3_1333H
// DDR3_1333J
// DDR3_1600G
// DDR3_1600H
// DDR3_1600J
// DDR3_1600K
// DDR3_1866J
// DDR3_1866K
// DDR3_1866L
// DDR3_1866M


///////////////////////////////////////////////////////////////////////////////////////////////////
localparam real tREFI = 7_800_000;
localparam real tWR   = 15_000;
///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef DDR3_512M
localparam real tRFC = 90_000;
`endif

`ifdef DDR3_1G
localparam real tRFC = 110_000;
`endif

`ifdef DDR3_2G
localparam real tRFC = 160_000;
`endif

`ifdef DDR3_4G
localparam real tRFC = 260_000;
`endif

`ifdef DDR3_8G
localparam real tRFC = 350_000;
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
`ifdef DDR3_800D
localparam CL   = 5;
localparam real tRC  = 50_000;
`include "ddr3_800.vh"
`endif

`ifdef DDR3_800E
localparam CL   = 6;
localparam real tRC  = 52_500;
`include "ddr3_800.vh"
`endif

`ifdef DDR3_1066E
localparam CL   = 6;
localparam real tRC  = 48_750;
`include "ddr3_1066.vh"
`endif

`ifdef DDR3_1066F
localparam CL   = 7;
localparam real tRC  = 50_625;
`include "ddr3_1066.vh"
`endif

`ifdef DDR3_1066G
localparam CL   = 8;
localparam real tRC  = 52_500;
`include "ddr3_1066.vh"
`endif

`ifdef DDR3_1333F
localparam CL   = 7;
localparam real tRC  = 46_500;
`include "ddr3_1333.vh"
`endif

`ifdef DDR3_1333G
localparam CL   = 8;
localparam real tRC  = 48_000;
`include "ddr3_1333.vh"
`endif

`ifdef DDR3_1333H
localparam CL   = 9;
localparam real tRC  = 49_500;
`include "ddr3_1333.vh"
`endif

`ifdef DDR3_1333J
localparam CL   = 10;
localparam real tRC  = 51_000;
`include "ddr3_1333.vh"
`endif

`ifdef DDR3_1600G
localparam CL   = 8;
localparam real tRC  = 45_000;
`include "ddr3_1600.vh"
`endif

`ifdef DDR3_1600H
localparam CL   = 9;
localparam real tRC  = 46_250;
`include "ddr3_1600.vh"
`endif

`ifdef DDR3_1600J
localparam CL   = 10;
localparam real tRC  = 47_500;
`include "ddr3_1600.vh"
`endif

`ifdef DDR3_1600K
localparam CL   = 11;
localparam real tRC  = 48_750;
`include "ddr3_1600.vh"
`endif

`ifdef DDR3_1866J
localparam CL   = 10;
localparam real tRC  = 44_700;
`include "ddr3_1866.vh"
`endif

`ifdef DDR3_1866K
localparam CL   = 11;
localparam real tRC  = 45_770;
`include "ddr3_1866.vh"
`endif

`ifdef DDR3_1866L
localparam CL   = 12;
localparam real tRC  = 46_840;
`include "ddr3_1866.vh"
`endif

`ifdef DDR3_1866M
localparam CL   = 13;
localparam real tRC  = 47_910;
`include "ddr3_1866.vh"
`endif

///////////////////////////////////////////////////////////////////////////////////////////////////
localparam integer nRCD  = CL;
localparam integer nRP   = CL;
localparam integer nREFI = $ceil(tREFI/tCK);
localparam integer nFAW  = $ceil(tFAW /tCK);
localparam integer nRAS  = $ceil(tRAS /tCK);
localparam integer nRFC  = $ceil(tRFC /tCK);
localparam integer nWR   = (5         > $ceil(tWR      /tCK)) ? 5         : $ceil(tWR      /tCK);
localparam integer nRTP  = (nRTP_min  > $ceil(tRTP_min /tCK)) ? nRTP_min  : $ceil(tRTP_min /tCK);
localparam integer nWTR  = (nWTR_min  > $ceil(tWTR_min /tCK)) ? nWTR_min  : $ceil(tWTR_min /tCK);
localparam integer nRRD  = (nRRD_min  > $ceil(tRRD_min /tCK)) ? nRRD_min  : $ceil(tRRD_min /tCK);
localparam integer nZQCS = (nZQCS_min > $ceil(tZQCS_min/tCK)) ? nZQCS_min : $ceil(tZQCS_min/tCK);
localparam integer nXS   = (nXS_min   > $ceil(tXS_min  /tCK)) ? nXS_min   : $ceil(tXS_min  /tCK);
///////////////////////////////////////////////////////////////////////////////////////////////////


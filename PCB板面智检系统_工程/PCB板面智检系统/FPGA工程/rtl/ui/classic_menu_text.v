`timescale 1ns/1ps
// Classic reference colors/logo are rendered separately. Registered character ROM.
module classic_menu_text(input clk,input [6:0] line,input [5:0] column,input [2:0] exposure,input [1:0] denoise,
 input light,photo_beep,osd,input [2:0] threshold,input [7:0] progress,error,input [19:0] number,output reg [7:0] character,
 input [15:0] lift_setting,lift_applied,input lift_enabled,lift_ready,
 input focus_busy,input [3:0] focus_phase,focus_error,
 input [15:0] focus_best);
 (* rom_style="bram" *) reg [7:0] contents[0:8191];integer i;
 initial begin for(i=0;i<8192;i=i+1)contents[i]=8'h20;
 contents[0]=8'h53;
 contents[1]=8'h4d;
 contents[2]=8'h41;
 contents[3]=8'h52;
 contents[4]=8'h54;
 contents[6]=8'h43;
 contents[7]=8'h41;
 contents[8]=8'h4d;
 contents[9]=8'h45;
 contents[10]=8'h52;
 contents[11]=8'h41;





















 contents[192]=8'h50;
 contents[193]=8'h48;
 contents[194]=8'h4f;
 contents[195]=8'h54;
 contents[196]=8'h4f;
 contents[198]=8'h50;
 contents[199]=8'h4c;
 contents[200]=8'h41;
 contents[201]=8'h59;
 contents[202]=8'h42;
 contents[203]=8'h41;
 contents[204]=8'h43;
 contents[205]=8'h4b;





 contents[320]=8'h45;
 contents[321]=8'h58;
 contents[322]=8'h50;
 contents[323]=8'h3a;
 contents[324]=8'h36;
 contents[326]=8'h44;
 contents[327]=8'h45;
 contents[328]=8'h4e;
 contents[329]=8'h4f;
 contents[330]=8'h49;
 contents[331]=8'h53;
 contents[332]=8'h45;
 contents[333]=8'h3a;
 contents[335]=8'h4c;
 contents[336]=8'h4f;
 contents[337]=8'h57;
 contents[343]=8'h4c;
 contents[344]=8'h49;
 contents[345]=8'h47;
 contents[346]=8'h48;
 contents[347]=8'h54;
 contents[348]=8'h3a;
 contents[349]=8'h4f;
 contents[350]=8'h46;
 contents[351]=8'h46;
 contents[384]=8'h46;
 contents[385]=8'h49;
 contents[386]=8'h4c;
 contents[387]=8'h45;
 contents[389]=8'h30;
 contents[390]=8'h30;
 contents[391]=8'h30;
 contents[392]=8'h30;
 contents[393]=8'h30;
 contents[395]=8'h50;
 contents[396]=8'h30;
 contents[397]=8'h30;
 contents[398]=8'h30;
 contents[400]=8'h45;
 contents[401]=8'h30;
 contents[402]=8'h30;
 contents[640]=8'h4d;
 contents[641]=8'h41;
 contents[642]=8'h49;
 contents[643]=8'h4e;
 contents[645]=8'h4d;
 contents[646]=8'h45;
 contents[647]=8'h4e;
 contents[648]=8'h55;
 contents[704]=8'h43;
 contents[705]=8'h41;
 contents[706]=8'h50;
 contents[707]=8'h54;
 contents[708]=8'h55;
 contents[709]=8'h52;
 contents[710]=8'h45;
 contents[712]=8'h41;
 contents[713]=8'h4e;
 contents[714]=8'h44;
 contents[716]=8'h53;
 contents[717]=8'h54;
 contents[718]=8'h4f;
 contents[719]=8'h52;
 contents[720]=8'h41;
 contents[721]=8'h47;
 contents[722]=8'h45;
 contents[768]=8'h44;
 contents[769]=8'h49;
 contents[770]=8'h53;
 contents[771]=8'h50;
 contents[772]=8'h4c;
 contents[773]=8'h41;
 contents[774]=8'h59;
 contents[776]=8'h53;
 contents[777]=8'h45;
 contents[778]=8'h54;
 contents[779]=8'h54;
 contents[780]=8'h49;
 contents[781]=8'h4e;
 contents[782]=8'h47;
 contents[783]=8'h53;
 contents[832]=8'h4d;
 contents[833]=8'h41;
 contents[834]=8'h4e;
 contents[835]=8'h55;
 contents[836]=8'h41;
 contents[837]=8'h4c;
 contents[839]=8'h4c;
 contents[840]=8'h49;
 contents[841]=8'h47;
 contents[842]=8'h48;
 contents[843]=8'h54;
































































 contents[3840]=8'h30;
 contents[3841]=8'h31;
 contents[3843]=8'h54;
 contents[3844]=8'h41;
 contents[3845]=8'h4b;
 contents[3846]=8'h45;
 contents[3848]=8'h50;
 contents[3849]=8'h48;
 contents[3850]=8'h4f;
 contents[3851]=8'h54;
 contents[3852]=8'h4f;
 contents[3904]=8'h30;
 contents[3905]=8'h32;
 contents[3907]=8'h52;
 contents[3908]=8'h45;
 contents[3909]=8'h54;
 contents[3910]=8'h52;
 contents[3911]=8'h59;
 contents[3913]=8'h54;
 contents[3914]=8'h46;
 contents[3916]=8'h43;
 contents[3917]=8'h41;
 contents[3918]=8'h52;
 contents[3919]=8'h44;
 contents[3968]=8'h30;
 contents[3969]=8'h33;
 contents[3971]=8'h50;
 contents[3972]=8'h48;
 contents[3973]=8'h4f;
 contents[3974]=8'h54;
 contents[3975]=8'h4f;
 contents[3977]=8'h42;
 contents[3978]=8'h45;
 contents[3979]=8'h45;
 contents[3980]=8'h50;
 contents[3991]=8'h4f;
 contents[3992]=8'h4e;
 contents[1344]=8'h30;
 contents[1345]=8'h31;
 contents[1347]=8'h45;
 contents[1348]=8'h58;
 contents[1349]=8'h50;
 contents[1350]=8'h4f;
 contents[1351]=8'h53;
 contents[1352]=8'h55;
 contents[1353]=8'h52;
 contents[1354]=8'h45;
 contents[1367]=8'h4c;
 contents[1368]=8'h45;
 contents[1369]=8'h56;
 contents[1370]=8'h45;
 contents[1371]=8'h4c;
 contents[1373]=8'h36;
 contents[1408]=8'h30;
 contents[1409]=8'h32;
 contents[1411]=8'h44;
 contents[1412]=8'h45;
 contents[1413]=8'h4e;
 contents[1414]=8'h4f;
 contents[1415]=8'h49;
 contents[1416]=8'h53;
 contents[1417]=8'h45;
 contents[1431]=8'h4c;
 contents[1432]=8'h4f;
 contents[1433]=8'h57;
 contents[1472]=8'h30;
 contents[1473]=8'h33;
 contents[1475]=8'h53;
 contents[1476]=8'h54;
 contents[1477]=8'h41;
 contents[1478]=8'h54;
 contents[1479]=8'h55;
 contents[1480]=8'h53;
 contents[1482]=8'h4f;
 contents[1483]=8'h53;
 contents[1484]=8'h44;
 contents[1495]=8'h4f;
 contents[1496]=8'h4e;
 contents[1536]=8'h30;
 contents[1537]=8'h31;
 contents[1539]=8'h4c;
 contents[1540]=8'h49;
 contents[1541]=8'h47;
 contents[1542]=8'h48;
 contents[1543]=8'h54;
 contents[1559]=8'h4f;
 contents[1560]=8'h46;
 contents[1561]=8'h46;
 contents[1600]=8'h4c;
 contents[1601]=8'h45;
 contents[1602]=8'h46;
 contents[1603]=8'h54;
 contents[1604]=8'h2f;
 contents[1605]=8'h52;
 contents[1606]=8'h49;
 contents[1607]=8'h47;
 contents[1608]=8'h48;
 contents[1609]=8'h54;
 contents[1611]=8'h41;
 contents[1612]=8'h44;
 contents[1613]=8'h4a;
 contents[1614]=8'h55;
 contents[1615]=8'h53;
 contents[1616]=8'h54;
 contents[1619]=8'h4f;
 contents[1620]=8'h4b;
 contents[1622]=8'h54;
 contents[1623]=8'h4f;
 contents[1624]=8'h47;
 contents[1625]=8'h47;
 contents[1626]=8'h4c;
 contents[1627]=8'h45;
 contents[1664]=8'h55;
 contents[1665]=8'h50;
 contents[1666]=8'h2f;
 contents[1667]=8'h44;
 contents[1668]=8'h4f;
 contents[1669]=8'h57;
 contents[1670]=8'h4e;
 contents[1672]=8'h53;
 contents[1673]=8'h45;
 contents[1674]=8'h4c;
 contents[1675]=8'h45;
 contents[1676]=8'h43;
 contents[1677]=8'h54;
 contents[1680]=8'h4f;
 contents[1681]=8'h4b;
 contents[1683]=8'h41;
 contents[1684]=8'h50;
 contents[1685]=8'h50;
 contents[1686]=8'h4c;
 contents[1687]=8'h59;
 contents[1728]=8'h54;
 contents[1729]=8'h46;
 contents[1731]=8'h49;
 contents[1732]=8'h4e;
 contents[1733]=8'h49;
 contents[1734]=8'h54;
 contents[1792]=8'h54;
 contents[1793]=8'h46;
 contents[1795]=8'h52;
 contents[1796]=8'h45;
 contents[1797]=8'h41;
 contents[1798]=8'h44;
 contents[1799]=8'h59;
 contents[1856]=8'h43;
 contents[1857]=8'h41;
 contents[1858]=8'h50;
 contents[1859]=8'h54;
 contents[1860]=8'h55;
 contents[1861]=8'h52;
 contents[1862]=8'h49;
 contents[1863]=8'h4e;
 contents[1864]=8'h47;
 contents[1920]=8'h57;
 contents[1921]=8'h52;
 contents[1922]=8'h49;
 contents[1923]=8'h54;
 contents[1924]=8'h49;
 contents[1925]=8'h4e;
 contents[1926]=8'h47;
 contents[1984]=8'h53;
 contents[1985]=8'h41;
 contents[1986]=8'h56;
 contents[1987]=8'h45;
 contents[1988]=8'h44;
 contents[2048]=8'h4c;
 contents[2049]=8'h4f;
 contents[2050]=8'h41;
 contents[2051]=8'h44;
 contents[2052]=8'h49;
 contents[2053]=8'h4e;
 contents[2054]=8'h47;
 contents[2056]=8'h50;
 contents[2057]=8'h48;
 contents[2058]=8'h4f;
 contents[2059]=8'h54;
 contents[2060]=8'h4f;
 contents[2112]=8'h50;
 contents[2113]=8'h48;
 contents[2114]=8'h4f;
 contents[2115]=8'h54;
 contents[2116]=8'h4f;
 contents[2118]=8'h56;
 contents[2119]=8'h49;
 contents[2120]=8'h45;
 contents[2121]=8'h57;
 contents[2176]=8'h4e;
 contents[2177]=8'h4f;
 contents[2179]=8'h4e;
 contents[2180]=8'h45;
 contents[2181]=8'h49;
 contents[2182]=8'h47;
 contents[2183]=8'h48;
 contents[2184]=8'h42;
 contents[2185]=8'h4f;
 contents[2186]=8'h55;
 contents[2187]=8'h52;
 contents[2240]=8'h42;
 contents[2241]=8'h41;
 contents[2242]=8'h44;
 contents[2244]=8'h50;
 contents[2245]=8'h48;
 contents[2246]=8'h4f;
 contents[2247]=8'h54;
 contents[2248]=8'h4f;
 contents[2304]=8'h54;
 contents[2305]=8'h46;
 contents[2307]=8'h45;
 contents[2308]=8'h52;
 contents[2309]=8'h52;
 contents[2310]=8'h4f;
 contents[2311]=8'h52;
 contents[2368]=8'h57;
 contents[2369]=8'h41;
 contents[2370]=8'h49;
 contents[2371]=8'h54;
 contents[2373]=8'h43;
 contents[2374]=8'h41;
 contents[2375]=8'h4d;
 contents[2376]=8'h45;
 contents[2377]=8'h52;
 contents[2378]=8'h41;
 contents[2432]=8'h56;
 contents[2433]=8'h49;
 contents[2434]=8'h44;
 contents[2435]=8'h45;
 contents[2436]=8'h4f;
 contents[2438]=8'h4c;
 contents[2439]=8'h49;
 contents[2440]=8'h56;
 contents[2441]=8'h45;
 contents[2496]=8'h45;
 contents[2497]=8'h58;
 contents[2498]=8'h50;
 contents[2499]=8'h4f;
 contents[2500]=8'h53;
 contents[2501]=8'h55;
 contents[2502]=8'h52;
 contents[2503]=8'h45;
 contents[2505]=8'h42;
 contents[2506]=8'h55;
 contents[2507]=8'h53;
 contents[2508]=8'h59;
 contents[2560]=8'h45;
 contents[2561]=8'h58;
 contents[2562]=8'h50;
 contents[2563]=8'h4f;
 contents[2564]=8'h53;
 contents[2565]=8'h55;
 contents[2566]=8'h52;
 contents[2567]=8'h45;
 contents[2569]=8'h45;
 contents[2570]=8'h52;
 contents[2571]=8'h52;
 contents[2572]=8'h4f;
 contents[2573]=8'h52;
 contents[2624]=8'h4f;
 contents[2625]=8'h4b;
 contents[2627]=8'h43;
 contents[2628]=8'h41;
 contents[2629]=8'h50;
 contents[2630]=8'h54;
 contents[2631]=8'h55;
 contents[2632]=8'h52;
 contents[2633]=8'h45;
 contents[2636]=8'h42;
 contents[2637]=8'h41;
 contents[2638]=8'h43;
 contents[2639]=8'h4b;
 contents[2641]=8'h52;
 contents[2642]=8'h45;
 contents[2643]=8'h54;
 contents[2644]=8'h55;
 contents[2645]=8'h52;
 contents[2646]=8'h4e;
 contents[2688]=8'h52;
 contents[2689]=8'h45;
 contents[2690]=8'h54;
 contents[2691]=8'h52;
 contents[2692]=8'h59;
 contents[2694]=8'h43;
 contents[2695]=8'h41;
 contents[2696]=8'h52;
 contents[2697]=8'h44;
 contents[2699]=8'h41;
 contents[2700]=8'h46;
 contents[2701]=8'h54;
 contents[2702]=8'h45;
 contents[2703]=8'h52;
 contents[2705]=8'h49;
 contents[2706]=8'h4e;
 contents[2707]=8'h53;
 contents[2708]=8'h45;
 contents[2709]=8'h52;
 contents[2710]=8'h54;
 contents[2711]=8'h49;
 contents[2712]=8'h4e;
 contents[2713]=8'h47;
 contents[2752]=8'h50;
 contents[2753]=8'h48;
 contents[2754]=8'h4f;
 contents[2755]=8'h54;
 contents[2756]=8'h4f;
 contents[2758]=8'h53;
 contents[2759]=8'h41;
 contents[2760]=8'h56;
 contents[2761]=8'h45;
 contents[2762]=8'h44;
 contents[2816]=8'h53;
 contents[2817]=8'h50;
 contents[2818]=8'h41;
 contents[2819]=8'h54;
 contents[2820]=8'h49;
 contents[2821]=8'h41;
 contents[2822]=8'h4c;
 contents[2824]=8'h44;
 contents[2825]=8'h45;
 contents[2826]=8'h4e;
 contents[2827]=8'h4f;
 contents[2828]=8'h49;
 contents[2829]=8'h53;
 contents[2830]=8'h45;
 contents[2880]=8'h43;
 contents[2881]=8'h41;
 contents[2882]=8'h52;
 contents[2883]=8'h44;
 contents[2885]=8'h4e;
 contents[2886]=8'h4f;
 contents[2887]=8'h54;
 contents[2889]=8'h52;
 contents[2890]=8'h45;
 contents[2891]=8'h41;
 contents[2892]=8'h44;
 contents[2893]=8'h59;
 contents[2944]=8'h42;
 contents[2945]=8'h41;
 contents[2946]=8'h43;
 contents[2947]=8'h4b;
 contents[2949]=8'h52;
 contents[2950]=8'h45;
 contents[2951]=8'h54;
 contents[2952]=8'h55;
 contents[2953]=8'h52;
 contents[2954]=8'h4e;
 contents[2957]=8'h4d;
 contents[2958]=8'h45;
 contents[2959]=8'h4e;
 contents[2960]=8'h55;
 contents[2962]=8'h4c;
 contents[2963]=8'h49;
 contents[2964]=8'h56;
 contents[2965]=8'h45;
 contents[896]=8'h30;
 contents[897]=8'h31;
 contents[899]=8'h49;
 contents[900]=8'h4d;
 contents[901]=8'h41;
 contents[902]=8'h47;
 contents[903]=8'h45;
 contents[905]=8'h41;
 contents[906]=8'h4c;
 contents[907]=8'h47;
 contents[908]=8'h4f;
 contents[909]=8'h52;
 contents[910]=8'h49;
 contents[911]=8'h54;
 contents[912]=8'h48;
 contents[913]=8'h4d;
 contents[914]=8'h53;
 contents[960]=8'h30;
 contents[961]=8'h32;
 contents[963]=8'h43;
 contents[964]=8'h41;
 contents[965]=8'h50;
 contents[966]=8'h54;
 contents[967]=8'h55;
 contents[968]=8'h52;
 contents[969]=8'h45;
 contents[971]=8'h41;
 contents[972]=8'h4e;
 contents[973]=8'h44;
 contents[975]=8'h53;
 contents[976]=8'h54;
 contents[977]=8'h4f;
 contents[978]=8'h52;
 contents[979]=8'h41;
 contents[980]=8'h47;
 contents[981]=8'h45;
 contents[1024]=8'h30;
 contents[1025]=8'h33;
 contents[1027]=8'h50;
 contents[1028]=8'h48;
 contents[1029]=8'h4f;
 contents[1030]=8'h54;
 contents[1031]=8'h4f;
 contents[1033]=8'h50;
 contents[1034]=8'h4c;
 contents[1035]=8'h41;
 contents[1036]=8'h59;
 contents[1037]=8'h42;
 contents[1038]=8'h41;
 contents[1039]=8'h43;
 contents[1040]=8'h4b;
 contents[1088]=8'h30;
 contents[1089]=8'h34;
 contents[1091]=8'h4d;
 contents[1092]=8'h41;
 contents[1093]=8'h4e;
 contents[1094]=8'h55;
 contents[1095]=8'h41;
 contents[1096]=8'h4c;
 contents[1098]=8'h4c;
 contents[1099]=8'h49;
 contents[1100]=8'h47;
 contents[1101]=8'h48;
 contents[1102]=8'h54;
 contents[3008]=8'h30;
 contents[3009]=8'h31;
 contents[3011]=8'h4f;
 contents[3012]=8'h52;
 contents[3013]=8'h49;
 contents[3014]=8'h47;
 contents[3015]=8'h49;
 contents[3016]=8'h4e;
 contents[3017]=8'h41;
 contents[3018]=8'h4c;
 contents[3072]=8'h30;
 contents[3073]=8'h32;
 contents[3075]=8'h47;
 contents[3076]=8'h52;
 contents[3077]=8'h41;
 contents[3078]=8'h59;
 contents[3080]=8'h43;
 contents[3081]=8'h4f;
 contents[3082]=8'h4e;
 contents[3083]=8'h54;
 contents[3084]=8'h52;
 contents[3085]=8'h41;
 contents[3086]=8'h53;
 contents[3087]=8'h54;
 contents[3136]=8'h30;
 contents[3137]=8'h33;
 contents[3139]=8'h45;
 contents[3140]=8'h44;
 contents[3141]=8'h47;
 contents[3142]=8'h45;
 contents[3144]=8'h47;
 contents[3145]=8'h41;
 contents[3146]=8'h49;
 contents[3147]=8'h4e;
 contents[3200]=8'h30;
 contents[3201]=8'h34;
 contents[3203]=8'h45;
 contents[3204]=8'h44;
 contents[3205]=8'h47;
 contents[3206]=8'h45;
 contents[3208]=8'h42;
 contents[3209]=8'h49;
 contents[3210]=8'h4e;
 contents[3211]=8'h41;
 contents[3212]=8'h52;
 contents[3213]=8'h59;
 contents[3264]=8'h30;
 contents[3265]=8'h35;
 contents[3267]=8'h46;
 contents[3268]=8'h49;
 contents[3269]=8'h4c;
 contents[3270]=8'h4c;
 contents[3272]=8'h41;
 contents[3273]=8'h4e;
 contents[3274]=8'h44;
 contents[3276]=8'h45;
 contents[3277]=8'h44;
 contents[3278]=8'h47;
 contents[3279]=8'h45;
 contents[3280]=8'h53;
 contents[3328]=8'h30;
 contents[3329]=8'h36;
 contents[3331]=8'h42;
 contents[3332]=8'h49;
 contents[3333]=8'h4e;
 contents[3334]=8'h41;
 contents[3335]=8'h52;
 contents[3336]=8'h59;
 contents[3338]=8'h43;
 contents[3339]=8'h4c;
 contents[3340]=8'h4f;
 contents[3341]=8'h53;
 contents[3342]=8'h49;
 contents[3343]=8'h4e;
 contents[3344]=8'h47;
 contents[3392]=8'h30;
 contents[3393]=8'h37;
 contents[3395]=8'h50;
 contents[3396]=8'h43;
 contents[3397]=8'h42;
 contents[3399]=8'h43;
 contents[3400]=8'h4f;
 contents[3401]=8'h4c;
 contents[3402]=8'h4f;
 contents[3403]=8'h52;
 contents[3405]=8'h44;
 contents[3406]=8'h45;
 contents[3407]=8'h54;
 contents[3408]=8'h41;
 contents[3409]=8'h49;
 contents[3410]=8'h4c;
 contents[3456]=8'h30;
 contents[3457]=8'h38;
 contents[3459]=8'h48;
 contents[3460]=8'h49;
 contents[3461]=8'h53;
 contents[3462]=8'h54;
 contents[3463]=8'h4f;
 contents[3464]=8'h47;
 contents[3465]=8'h52;
 contents[3466]=8'h41;
 contents[3467]=8'h4d;
 contents[3469]=8'h45;
 contents[3470]=8'h51;
 contents[3471]=8'h55;
 contents[3472]=8'h41;
 contents[3473]=8'h4c;
 contents[3474]=8'h49;
 contents[3475]=8'h5a;
 contents[3476]=8'h45;
 contents[3520]=8'h49;
 contents[3521]=8'h4d;
 contents[3522]=8'h41;
 contents[3523]=8'h47;
 contents[3524]=8'h45;
 contents[3526]=8'h41;
 contents[3527]=8'h4c;
 contents[3528]=8'h47;
 contents[3529]=8'h4f;
 contents[3530]=8'h52;
 contents[3531]=8'h49;
 contents[3532]=8'h54;
 contents[3533]=8'h48;
 contents[3534]=8'h4d;
 contents[3535]=8'h53;
 contents[3648]=8'h4c;
 contents[3649]=8'h45;
 contents[3650]=8'h56;
 contents[3651]=8'h45;
 contents[3652]=8'h4c;
 contents[3654]=8'h34;
 contents[3712]=8'h4c;
 contents[3713]=8'h45;
 contents[3714]=8'h46;
 contents[3715]=8'h54;
 contents[3716]=8'h2f;
 contents[3717]=8'h52;
 contents[3718]=8'h49;
 contents[3719]=8'h47;
 contents[3720]=8'h48;
 contents[3721]=8'h54;
 contents[3723]=8'h4c;
 contents[3724]=8'h45;
 contents[3725]=8'h56;
 contents[3726]=8'h45;
 contents[3727]=8'h4c;
 contents[3730]=8'h4f;
 contents[3731]=8'h4b;
 contents[3733]=8'h41;
 contents[3734]=8'h50;
 contents[3735]=8'h50;
 contents[3736]=8'h4c;
 contents[3737]=8'h59;
 contents[1152]=8'h30;
 contents[1153]=8'h35;
 contents[1155]=8'h44;
 contents[1156]=8'h49;
 contents[1157]=8'h53;
 contents[1158]=8'h50;
 contents[1159]=8'h4c;
 contents[1160]=8'h41;
 contents[1161]=8'h59;
 contents[1163]=8'h53;
 contents[1164]=8'h45;
 contents[1165]=8'h54;
 contents[1166]=8'h54;
 contents[1167]=8'h49;
 contents[1168]=8'h4e;
 contents[1169]=8'h47;
 contents[1170]=8'h53;





 contents[64]=8'h50;
 contents[65]=8'h43;
 contents[66]=8'h42;
 contents[68]=8'h49;
 contents[69]=8'h4e;
 contents[70]=8'h53;
 contents[71]=8'h50;
 contents[72]=8'h45;
 contents[73]=8'h43;
 contents[74]=8'h54;
 contents[75]=8'h49;
 contents[76]=8'h4f;
 contents[77]=8'h4e;
 contents[80]=8'h31;
 contents[81]=8'h39;
 contents[82]=8'h32;
 contents[83]=8'h30;
 contents[84]=8'h58;
 contents[85]=8'h31;
 contents[86]=8'h30;
 contents[87]=8'h38;
 contents[88]=8'h30;

// Lift additions occupy previously unused ROM lines.
 contents[64]=8'h53;
 contents[65]=8'h45;
 contents[66]=8'h54;
 contents[67]=8'h3a;
 contents[68]=8'h31;
 contents[69]=8'h35;
 contents[70]=8'h30;
 contents[71]=8'h30;
 contents[72]=8'h55;
 contents[73]=8'h53;
 contents[74]=8'h20;
 contents[75]=8'h50;
 contents[76]=8'h57;
 contents[77]=8'h4d;
 contents[78]=8'h3a;
 contents[79]=8'h31;
 contents[80]=8'h35;
 contents[81]=8'h30;
 contents[82]=8'h30;
 contents[83]=8'h55;
 contents[84]=8'h53;
 contents[85]=8'h20;
 contents[86]=8'h4f;
 contents[87]=8'h46;
 contents[88]=8'h46;
 contents[1216]=8'h30;
 contents[1217]=8'h36;
 contents[1218]=8'h20;
 contents[1219]=8'h4c;
 contents[1220]=8'h49;
 contents[1221]=8'h46;
 contents[1222]=8'h54;
 contents[1223]=8'h20;
 contents[1224]=8'h43;
 contents[1225]=8'h4f;
 contents[1226]=8'h4e;
 contents[1227]=8'h54;
 contents[1228]=8'h52;
 contents[1229]=8'h4f;
 contents[1230]=8'h4c;
 contents[1280]=8'h4f;
 contents[1281]=8'h4b;
 contents[1282]=8'h20;
 contents[1283]=8'h41;
 contents[1284]=8'h50;
 contents[1285]=8'h50;
 contents[1286]=8'h4c;
 contents[1287]=8'h59;
 contents[1288]=8'h20;
 contents[1289]=8'h2f;
 contents[1290]=8'h20;
 contents[1291]=8'h42;
 contents[1292]=8'h41;
 contents[1293]=8'h43;
 contents[1294]=8'h4b;
 contents[1295]=8'h20;
 contents[1296]=8'h52;
 contents[1297]=8'h45;
 contents[1298]=8'h54;
 contents[1299]=8'h55;
 contents[1300]=8'h52;
 contents[1301]=8'h4e;
 contents[3584]=8'h4c;
 contents[3585]=8'h49;
 contents[3586]=8'h46;
 contents[3587]=8'h54;
 contents[3588]=8'h20;
 contents[3589]=8'h43;
 contents[3590]=8'h4f;
 contents[3591]=8'h4e;
 contents[3592]=8'h54;
 contents[3593]=8'h52;
 contents[3594]=8'h4f;
 contents[3595]=8'h4c;
 contents[3776]=8'h50;
 contents[3777]=8'h55;
 contents[3778]=8'h4c;
 contents[3779]=8'h53;
 contents[3780]=8'h45;
 contents[3781]=8'h3a;
 contents[3782]=8'h20;
 contents[3783]=8'h31;
 contents[3784]=8'h35;
 contents[3785]=8'h30;
 contents[3786]=8'h30;
 contents[3787]=8'h20;
 contents[3788]=8'h55;
 contents[3789]=8'h53;
 contents[4032]=8'h55;
 contents[4033]=8'h50;
 contents[4034]=8'h20;
 contents[4035]=8'h2b;
 contents[4036]=8'h32;
 contents[4037]=8'h30;
 contents[4038]=8'h55;
 contents[4039]=8'h53;
 contents[4040]=8'h20;
 contents[4041]=8'h2f;
 contents[4042]=8'h20;
 contents[4043]=8'h44;
 contents[4044]=8'h4f;
 contents[4045]=8'h57;
 contents[4046]=8'h4e;
 contents[4047]=8'h20;
 contents[4048]=8'h2d;
 contents[4049]=8'h32;
 contents[4050]=8'h30;
 contents[4051]=8'h55;
 contents[4052]=8'h53;

// Row2 is unused in this sensor-free release.

// Local autofocus strings, kept separate from original menu rows.
 contents[4096]=8'h30;
 contents[4097]=8'h37;
 contents[4098]=8'h20;
 contents[4099]=8'h41;
 contents[4100]=8'h55;
 contents[4101]=8'h54;
 contents[4102]=8'h4f;
 contents[4103]=8'h20;
 contents[4104]=8'h46;
 contents[4105]=8'h4f;
 contents[4106]=8'h43;
 contents[4107]=8'h55;
 contents[4108]=8'h53;
 contents[4224]=8'h4f;
 contents[4225]=8'h4b;
 contents[4226]=8'h20;
 contents[4227]=8'h53;
 contents[4228]=8'h54;
 contents[4229]=8'h41;
 contents[4230]=8'h52;
 contents[4231]=8'h54;
 contents[4232]=8'h20;
 contents[4233]=8'h2f;
 contents[4234]=8'h20;
 contents[4235]=8'h52;
 contents[4236]=8'h45;
 contents[4237]=8'h50;
 contents[4238]=8'h45;
 contents[4239]=8'h41;
 contents[4240]=8'h54;
 contents[4288]=8'h53;
 contents[4289]=8'h54;
 contents[4290]=8'h41;
 contents[4291]=8'h54;
 contents[4292]=8'h45;
 contents[4293]=8'h3a;
 contents[4294]=8'h20;
 contents[4295]=8'h52;
 contents[4296]=8'h45;
 contents[4297]=8'h41;
 contents[4298]=8'h44;
 contents[4299]=8'h59;
 contents[4300]=8'h20;
 contents[4301]=8'h20;
 contents[4302]=8'h20;
 contents[4303]=8'h20;
 contents[4304]=8'h45;
 contents[4305]=8'h52;
 contents[4306]=8'h52;
 contents[4307]=8'h3a;
 contents[4308]=8'h30;
 contents[4352]=8'h42;
 contents[4353]=8'h45;
 contents[4354]=8'h53;
 contents[4355]=8'h54;
 contents[4356]=8'h3a;
 contents[4357]=8'h20;
 contents[4358]=8'h31;
 contents[4359]=8'h35;
 contents[4360]=8'h30;
 contents[4361]=8'h30;
 contents[4362]=8'h55;
 contents[4363]=8'h53;
 contents[4672]=8'h4f;
 contents[4673]=8'h4b;
 contents[4674]=8'h20;
 contents[4675]=8'h53;
 contents[4676]=8'h54;
 contents[4677]=8'h41;
 contents[4678]=8'h52;
 contents[4679]=8'h54;
 contents[4680]=8'h20;
 contents[4681]=8'h2f;
 contents[4682]=8'h20;
 contents[4683]=8'h52;
 contents[4684]=8'h55;
 contents[4685]=8'h4e;
 contents[4686]=8'h4e;
 contents[4687]=8'h49;
 contents[4688]=8'h4e;
 contents[4689]=8'h47;
 contents[4690]=8'h3a;
 contents[4691]=8'h20;
 contents[4692]=8'h4f;
 contents[4693]=8'h4b;
 contents[4694]=8'h20;
 contents[4695]=8'h53;
 contents[4696]=8'h54;
 contents[4697]=8'h4f;
 contents[4698]=8'h50;
 contents[4736]=8'h42;
 contents[4737]=8'h41;
 contents[4738]=8'h43;
 contents[4739]=8'h4b;
 contents[4740]=8'h3a;
 contents[4741]=8'h20;
 contents[4742]=8'h53;
 contents[4743]=8'h54;
 contents[4744]=8'h4f;
 contents[4745]=8'h50;
 contents[4746]=8'h20;
 contents[4747]=8'h2f;
 contents[4748]=8'h20;
 contents[4749]=8'h52;
 contents[4750]=8'h45;
 contents[4751]=8'h54;
 contents[4752]=8'h55;
 contents[4753]=8'h52;
 contents[4754]=8'h4e;


// Sensor-free release text.
 contents[4160]=8'h41;
 contents[4161]=8'h55;
 contents[4162]=8'h54;
 contents[4163]=8'h4f;
 contents[4164]=8'h20;
 contents[4165]=8'h46;
 contents[4166]=8'h4f;
 contents[4167]=8'h43;
 contents[4168]=8'h55;
 contents[4169]=8'h53;
 contents[4800]=8'h41;
 contents[4801]=8'h46;
 contents[4802]=8'h3a;
 contents[4803]=8'h20;
 contents[4804]=8'h52;
 contents[4805]=8'h45;
 contents[4806]=8'h41;
 contents[4807]=8'h44;
 contents[4808]=8'h59;
 contents[4809]=8'h20;
 contents[4810]=8'h20;
 contents[4811]=8'h20;
 contents[4812]=8'h20;
 contents[4813]=8'h42;
 contents[4814]=8'h45;
 contents[4815]=8'h53;
 contents[4816]=8'h54;
 contents[4817]=8'h3a;
 contents[4818]=8'h20;
 contents[4819]=8'h31;
 contents[4820]=8'h35;
 contents[4821]=8'h30;
 contents[4822]=8'h30;
 contents[4823]=8'h55;
 contents[4824]=8'h53;
 contents[4825]=8'h20;
 contents[4826]=8'h45;
 contents[4827]=8'h52;
 contents[4828]=8'h52;
 contents[4829]=8'h3a;
 contents[4830]=8'h30;
// Final visible release tag.
end
function [7:0] hexchar;input [3:0] value;begin hexchar=value<10?8'd48+value:8'd55+value;end endfunction
 reg [15:0] setting_bcd=16'h1500,applied_bcd=16'h1500;
 reg [27:0] setting_shift=0,applied_shift=0;reg [3:0] convert_count=0;
 function [27:0] bcd_step;
 input [27:0] value;integer d;reg [27:0] v;
 begin v=value;for(d=0;d<4;d=d+1)if(v[12+d*4+:4]>=5)v[12+d*4+:4]=v[12+d*4+:4]+3;
  bcd_step=v<<1;end
 endfunction
 always @(posedge clk)begin
  if(convert_count==0)begin
   setting_shift<={16'd0,lift_setting[11:0]};applied_shift<={16'd0,lift_applied[11:0]};convert_count<=1;
  end else if(convert_count<=12)begin
   setting_shift<=bcd_step(setting_shift);applied_shift<=bcd_step(applied_shift);convert_count<=convert_count+1'b1;
  end else begin setting_bcd<=setting_shift[27:12];applied_bcd<=applied_shift[27:12];convert_count<=0;end
 end
 function [7:0] decimal_digit;
 input [15:0] value;input [1:0] digit;
 begin case(digit)0:decimal_digit=8'd48+value[15:12];1:decimal_digit=8'd48+value[11:8];
  2:decimal_digit=8'd48+value[7:4];default:decimal_digit=8'd48+value[3:0];endcase end
 endfunction
 function [7:0] onchar;input enabled;input [1:0] pos;begin
  case(pos)0:onchar="O";1:onchar=enabled?"N":"F";2:onchar=enabled?" ":"F";default:onchar=" ";endcase
 end endfunction
 wire [63:0] focus_word=focus_phase==1?"COARSE  ":focus_phase==2?"FINE    ":focus_phase==3?"VERIFY  ":focus_phase==5?"DONE    ":focus_phase==7?"FAILED  ":"READY   ";
 reg [27:0] best_shift=0;reg [3:0] best_count=0;reg [15:0] best_bcd=16'h1500;
 always @(posedge clk)begin
  if(best_count==0)begin best_shift<={16'd0,focus_best[11:0]};best_count<=1;end
  else if(best_count<=12)begin best_shift<=bcd_step(best_shift);best_count<=best_count+1'b1;end
  else begin best_bcd<=best_shift[27:12];best_count<=0;end
 end
 wire [47:0] denoise_word=denoise==0?"OFF   ":denoise==1?"LOW   ":"NORMAL";
 wire [7:0] pct=progress>100?8'd100:progress;
 always @(posedge clk)begin
  character<=contents[{line,column}];
  if(line==66 && focus_busy)begin
   if(column<7)character<=(56'h4f4b2053544f50>>((6-column)*8));else character<=" ";
  end
  if(line==67)begin
   if(column>=7 && column<15)character<=focus_word[(14-column)*8+:8];
   if(column==20)character<=hexchar(focus_error);
  end
  if(line==68 && column>=6 && column<10)character<=decimal_digit(best_bcd,column-6);
  if(line==75)begin
   if(column>=4 && column<12)character<=focus_word[(11-column)*8+:8];
   if(column>=19 && column<23)character<=decimal_digit(best_bcd,column-19);
   if(column==30)character<=hexchar(focus_error);
  end
  if(line==1)begin
   if(column>=4 && column<=7)character<=decimal_digit(setting_bcd,column-4);
   if(column>=15 && column<=18)character<=decimal_digit(applied_bcd,column-15);
   if(column>=22 && column<=25)begin
    if(!lift_ready)case(column)22:character<="W";23:character<="A";24:character<="I";25:character<="T";endcase
    else character<=onchar(lift_enabled,column-22);
   end
  end
  if(line==59 && column>=7 && column<=10)character<=decimal_digit(setting_bcd,column-7);
  if(line==57 && column==6)character<=8'd49+threshold;
  if(line==5)begin
   if(column==4)character<=8'd48+exposure;
   if(column>=15 && column<21)character<=denoise_word[(20-column)*8+:8];
   if(column>=29 && column<32)character<=onchar(light,column-29);
  end
  if(line==62 && column>=23 && column<26)character<=onchar(photo_beep,column-23);
  if(line==21 && column==29)character<=8'd48+exposure;
  if(line==22 && column>=23 && column<29)character<=denoise_word[(28-column)*8+:8];
  if(line==23 && column>=23 && column<26)character<=onchar(osd,column-23);
  if(line==24 && column>=23 && column<26)character<=onchar(light,column-23);
  if(line==6)case(column)
   5:character<=hexchar(number[19:16]);6:character<=hexchar(number[15:12]);7:character<=hexchar(number[11:8]);
   8:character<=hexchar(number[7:4]);9:character<=hexchar(number[3:0]);
   12:character<=8'd48+pct/100;13:character<=8'd48+(pct/10)%10;14:character<=8'd48+pct%10;
   17:character<=hexchar(error[7:4]);18:character<=hexchar(error[3:0]);
  endcase
 end
endmodule

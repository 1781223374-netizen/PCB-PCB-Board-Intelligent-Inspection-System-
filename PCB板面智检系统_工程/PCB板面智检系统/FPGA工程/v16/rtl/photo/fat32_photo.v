// Bounded FAT32 camera writer. Creates new IMGxxxxx.BMP files in root directory.
// Requires a free root slot in its first cluster and a contiguous free extent.
// Existing allocated clusters/files are never overwritten. Publishes directory last.
module fat32_photo #(parameter WIDTH=1024,HEIGHT=600)(
 input clk,rst_n,request,retry,input card_ready,card_busy,card_done,input [7:0] card_error,
 output reg card_start,card_write,output reg [31:0] card_lba,
 input rx_valid,input [7:0] rx_data,input [8:0] tx_index,output [7:0] tx_data,
 output reg snap_hold,input snap_ready,input [7:0] snap_error,
 output reg stream_start,input [7:0] pixel_data,input pixel_valid,output pixel_ready,
 output reg [3:0] status,output reg [7:0] error,progress,output reg [19:0] file_number,
 // Read-only playback shares the mounted volume, directory scanner and sector RAM.
 // Direction: 0 latest, 1 previous, 2 next. Unsupported files are never displayed.
 input play_enable,play_toggle,input [1:0] play_direction,
 output reg play_busy,play_view,play_start,play_bank,
 output [7:0] play_data,output play_valid,input play_ready,play_done);
localparam FILE_BYTES=54+WIDTH*HEIGHT*3,FILE_SECTORS=(FILE_BYTES+511)/512;
localparam WAITCARD=0,MBR=1,BOOT=2,BPB1=3,BPB2=4,BPB3=5,GEOM=6,VALIDATE=7,IDLE=8,
 SNAP=9,DIR_SECTOR=10,DIR_ENTRY=11,DIR_CHECK=12,DIR_NEXT=13,ALLOC=14,FAT_SECTOR=15,FAT_ENTRY=16,FAT_CHECK=17,
 RESERVE=18,RES_READ=19,RES_PATCH=20,RES_NEXT=21,RES_MIRROR=22,FSINFO=23,FSI_CHECK=24,FSI_PATCH=25,FSI_NEXT=26,
 IMAGE_START=27,IMAGE_FILL=28,IMAGE_WRITE=29,IMAGE_NEXT=30,PUBLISH=31,PUB_PATCH=32,PUB_WRITE=33,SUCCESS=34,
 FSI_DONE=35,FSI_SIG=36,FSI_SIG2=37,PUB_MARK=38,PUB_NEXTREAD=39,
 IO_WAIT=40,GET_ADDR=41,GET_WAIT=42,GET_BYTE=43,PATCH=44,RES_VALUE=45,PUB_CLEAR=46,
 ROOT_CHECK=47,ROOT_VALUE=48,MBRSIG=49,FAILED=63,
 PB_LOAD=50,PB_BEGIN=51,PB_WAIT=52,PB_BYTE=53,PB_NEXT=54,PB_FAT=55,
 PB_CHAIN=56,PB_FINISH=57;
reg [5:0] state,ret,after_get,after_patch;
reg play_seen;reg [1:0] play_dir;
(* ram_style="bram" *) reg [7:0] sector[0:511];
reg [8:0] read_addr,rx_count,patch_addr;reg [7:0] read_q;
reg [255:0] record,patch_data;reg [5:0] count,length,patch_len;
reg [31:0] partition,part_length,total_sectors,fat_size,fat_base,data_base,cluster_count,root_cluster,root_lba;
reg [15:0] reserved,fs_info,backup_boot,flags;reg [7:0] spc,nfats;reg [3:0] cluster_shift;
reg [31:0] dir_lba,free_dir_lba;reg [8:0] dir_offset,free_dir_offset;reg found_slot,end_directory,free_was_end;
reg [7:0] dir_sector;
reg [31:0] scan_cluster,extent_start,allocated_start,allocated_end,current_fat_sector;
reg [13:0] free_run,needed;
reg [8:0] fat_offset;reg mirror;
reg [31:0] image_lba,file_pos;reg [13:0] image_sector;reg [8:0] fill;
// Fractional percentage accumulator. A fixed 36-sector step was specific
// to the old 1024x600 BMP and reached 99 at only 66% of a 720p file.
localparam PROGRESS_BITS=$clog2(FILE_SECTORS+100);
reg [PROGRESS_BITS-1:0] progress_fraction;
wire [PROGRESS_BITS:0] progress_step={1'b0,progress_fraction}+7'd100;
reg [31:0] root_entry_count;
reg [19:0] max_name;reg [31:0] fs_lba;reg fs_backup;
reg [31:0] mount_timeout;
wire [31:0] fat_value=record[31:0]&32'h0fffffff;
assign pixel_ready=state==IMAGE_FILL && file_pos>=54 && file_pos<FILE_BYTES;
assign play_data=read_q;
assign play_valid=state==PB_BYTE && file_pos>=54 && play_enable;
assign tx_data=read_q;
// One explicit write port, not three conditionally exclusive inferred ports.
wire receive_write=rx_valid && state==IO_WAIT;
wire image_write=state==IMAGE_FILL && (file_pos<54 || file_pos>=FILE_BYTES || pixel_valid);
wire ram_we=receive_write || state==PATCH || image_write;
wire [8:0] ram_wa=receive_write?rx_count:state==PATCH?patch_addr:fill;
wire [7:0] ram_wd=receive_write?rx_data:state==PATCH?patch_data[7:0]:file_pos<54?header(file_pos[5:0]):file_pos>=FILE_BYTES?8'd0:pixel_data;
always @(posedge clk) begin
 read_q<=sector[state==IO_WAIT?tx_index:read_addr];
 if(ram_we) sector[ram_wa]<=ram_wd;
end
function [7:0] header;input [5:0] a;reg [31:0] v;begin
 v=0;case(a)
 0:header="B";1:header="M";
 2,3,4,5:begin v=FILE_BYTES;header=v>>((a-2)*8);end
 10:header=54;14:header=40;
 18,19,20,21:begin v=WIDTH;header=v>>((a-18)*8);end
 22,23,24,25:begin v=-HEIGHT;header=v>>((a-22)*8);end
 26:header=1;28:header=24;
 34,35,36,37:begin v=WIDTH*HEIGHT*3;header=v>>((a-34)*8);end
 default:header=0;endcase
end endfunction
function [7:0] hexchar;input [3:0] n;begin hexchar=n<10?48+n:55+n;end endfunction
function [4:0] unhex;input [7:0] c;begin unhex=c>=48&&c<=57?c-48:c>=65&&c<=70?c-55:31;end endfunction
wire [4:0] h0=unhex(record[31:24]),h1=unhex(record[39:32]),h2=unhex(record[47:40]),h3=unhex(record[55:48]),h4=unhex(record[63:56]);
wire name_match=record[23:0]==24'h474d49 && record[87:64]==24'h504d42 && !h0[4]&&!h1[4]&&!h2[4]&&!h3[4]&&!h4[4];
wire [19:0] name_number={h0[3:0],h1[3:0],h2[3:0],h3[3:0],h4[3:0]};
task io;input wr;input [31:0] lba;input [5:0] next_state;begin
 card_lba<=lba;card_write<=wr;card_start<=1;rx_count<=0;ret<=next_state;state<=IO_WAIT;
end endtask
task get;input [8:0] addr;input [5:0] n;input [5:0] next_state;begin
 read_addr<=addr;length<=n;count<=0;record<=0;after_get<=next_state;state<=GET_WAIT;
end endtask
task patch;input [8:0] addr;input [255:0] data;input [5:0] n;input [5:0] next_state;begin
 patch_addr<=addr;patch_data<=data;patch_len<=n;count<=0;after_patch<=next_state;state<=PATCH;
end endtask
task fail;input [7:0] code;begin
 error<=code;snap_hold<=0;card_start<=0;
 if(play_busy) begin status<=9;play_busy<=0;state<=IDLE;end
 else begin status<=15;state<=FAILED;end
end endtask
task advance_progress;begin
 // The small-image branch is only for parameterized simulation fixtures.
 // Real camera sizes use one addition/comparison per completed sector.
 if(FILE_SECTORS<100)progress<=((image_sector+1)*100)/FILE_SECTORS;
 else if(progress_step>=FILE_SECTORS)begin
  progress_fraction<=progress_step-FILE_SECTORS;
  if(progress<99)progress<=progress+1'b1;
 end else progress_fraction<=progress_step;
end endtask
always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
  state<=WAITCARD;ret<=0;after_get<=0;after_patch<=0;card_start<=0;card_write<=0;card_lba<=0;rx_count<=0;
  read_addr<=0;record<=0;patch_addr<=0;patch_data<=0;patch_len<=0;count<=0;length<=0;
  snap_hold<=0;stream_start<=0;status<=0;error<=0;progress<=0;file_number<=0;
  play_seen<=0;play_dir<=0;play_busy<=0;play_view<=0;play_start<=0;play_bank<=0;
  partition<=0;part_length<=0;total_sectors<=0;fat_size<=0;fat_base<=0;data_base<=0;cluster_count<=0;root_cluster<=0;root_lba<=0;
  reserved<=0;fs_info<=0;backup_boot<=0;flags<=0;spc<=0;nfats<=0;cluster_shift<=0;
  dir_lba<=0;free_dir_lba<=0;dir_offset<=0;free_dir_offset<=0;found_slot<=0;end_directory<=0;free_was_end<=0;dir_sector<=0;
  scan_cluster<=2;extent_start<=2;allocated_start<=0;allocated_end<=0;current_fat_sector<=0;free_run<=0;needed<=0;fat_offset<=0;mirror<=0;
  image_lba<=0;file_pos<=0;image_sector<=0;fill<=0;progress_fraction<=0;max_name<=0;root_entry_count<=0;fs_lba<=0;fs_backup<=0;mount_timeout<=0;
 end else begin
  card_start<=0;stream_start<=0;play_start<=0;play_seen<=play_toggle;
  if(state==WAITCARD || play_busy) mount_timeout<=mount_timeout+1'b1;else mount_timeout<=0;
  if(!play_enable) play_view<=0;
  // Exit takes priority over read-side actions except draining a card command
  // already in flight. This also prevents publishing on the cancellation edge.
  if(!(play_busy && !play_enable && state!=IO_WAIT)) begin
  case(state)
   WAITCARD:if(card_error!=0) fail(card_error);else if(card_ready&&!card_busy) io(0,0,MBR);else if(mount_timeout==200000000) fail(8'h30);
   IO_WAIT:begin
    if(rx_valid) rx_count<=rx_count+1'b1;
    if(card_done) begin
     // Transport errors stop the SPI controller too: require the existing card
     // retry/reinitialize path, unlike a malformed BMP or missing neighbour.
     if(card_error!=0) begin error<=card_error;status<=15;snap_hold<=0;play_busy<=0;state<=FAILED;end
     else state<=ret;
    end
   end
   GET_WAIT:state<=GET_BYTE;
   GET_ADDR:state<=GET_WAIT;
   GET_BYTE:begin
    // Store low-to-high, fixed shift then align short records at completion.
    record<={read_q,record[255:8]};count<=count+1'b1;read_addr<=read_addr+1'b1;
    if(count+1==length) begin
     case(length)
      2:record<={240'd0,read_q,record[255:248]};
      4:record<={224'd0,read_q,record[255:232]};
      28:record<={32'd0,read_q,record[255:40]};
      default:record<={read_q,record[255:8]};
     endcase
     state<=after_get;
    end
    else state<=GET_ADDR;
   end
   PATCH:begin patch_addr<=patch_addr+1'b1;patch_data<=patch_data>>8;count<=count+1'b1;if(count+1==patch_len) state<=after_patch;end
   MBR:get(0,32,BOOT);
   BOOT:if(record[103:88]==512 && (record[7:0]==8'heb || record[7:0]==8'he9))
     get(11,32,BPB1);
    else if(partition!=0) fail(8'h32);else get(510,2,MBRSIG);
   MBRSIG:if(record[15:0]!=16'haa55) fail(8'h31);else get(446,32,BPB3);
   BPB3:begin
    if((record[39:32]!=8'h0b && record[39:32]!=8'h0c) || record[95:64]==0 || record[127:96]==0) fail(8'h31);
    else begin partition<=record[95:64];part_length<=record[127:96];io(0,record[95:64],MBR);end
   end
   BPB1:begin
    // record starts at BPB offset 11.
    if(record[15:0]!=512 || record[79:48]!=0 || record[87:80]!=8'hf8 || record[103:88]!=0) fail(8'h32);
    else begin spc<=record[23:16];reserved<=record[39:24];nfats<=record[47:40];
     total_sectors<=record[199:168];fat_size<=record[231:200];flags<=record[247:232];get(42,32,BPB2);end
   end
   BPB2:begin
    if(record[15:0]!=0) fail(8'h32);
    else begin root_cluster<=record[47:16]&32'h0fffffff;fs_info<=record[63:48];backup_boot<=record[79:64];get(510,2,GEOM);end
   end
   GEOM:begin
    if(record[15:0]!=16'haa55 || spc==0 || (spc&(spc-1))!=0 || spc>128 || reserved==0 || (nfats!=1 && nfats!=2) || flags[7] || fat_size==0 || fat_size>32'h00200000 || total_sectors==0) fail(8'h32);
    else begin
     case(spc)1:cluster_shift<=0;2:cluster_shift<=1;4:cluster_shift<=2;8:cluster_shift<=3;16:cluster_shift<=4;32:cluster_shift<=5;64:cluster_shift<=6;128:cluster_shift<=7;endcase
     fat_base<=partition+reserved;data_base<=partition+reserved+(nfats==2?(fat_size<<1):fat_size);state<=VALIDATE;
    end
   end
   VALIDATE:begin
    cluster_count<=(total_sectors-reserved-(nfats==2?(fat_size<<1):fat_size))>>cluster_shift;
    root_lba<=data_base+((root_cluster-2)<<cluster_shift);
    needed<=(FILE_SECTORS+spc-1)>>cluster_shift;
    state<=IDLE;
   end
   IDLE:begin
    if(cluster_count<65525 || cluster_count>32'h0ffffff5 || root_cluster<2 || root_cluster>=cluster_count+2 || (fat_size<<7)<cluster_count+2 ||
       total_sectors<=reserved+(nfats==2?(fat_size<<1):fat_size) || data_base<partition || partition+total_sectors<partition ||
       (part_length!=0 && total_sectors>part_length)) fail(8'h32);
    else if(play_enable && play_toggle!=play_seen) begin
     play_busy<=1;play_dir<=(play_view || status==9)?play_direction:2'd0;status<=6;progress<=0;error<=0;
     dir_lba<=root_lba;dir_sector<=0;found_slot<=0;end_directory<=0;
     max_name<=((play_view || status==9) && play_direction==2)?20'hfffff:20'd0;
     io(0,fat_base+(root_cluster>>7),ROOT_CHECK);
    end
    else if(request && !play_enable) begin snap_hold<=1;status<=2;progress<=0;error<=0;state<=SNAP;end
    else if(!play_enable && status!=4) begin status<=1;error<=0;end
   end
   SNAP:if(snap_error!=0) fail(snap_error);else if(snap_ready) begin
    dir_lba<=root_lba;dir_sector<=0;found_slot<=0;end_directory<=0;max_name<=0;root_entry_count<=0;io(0,fat_base+(root_cluster>>7),ROOT_CHECK);
   end
   ROOT_CHECK:get({root_cluster[6:0],2'b0},4,ROOT_VALUE);
   ROOT_VALUE:if(fat_value>=32'h0ffffff8) state<=DIR_SECTOR;else fail(8'h36);
   DIR_SECTOR:begin dir_offset<=0;io(0,dir_lba,DIR_ENTRY);end
   DIR_ENTRY:get(dir_offset,32,DIR_CHECK);
   DIR_CHECK:begin
    if(play_busy) begin
     // Regular short-name files only; ignore deleted entries, LFN, volume and directories.
     if(!end_directory && name_match && !(record[95:88]&8'h18) && record[255:224]==FILE_BYTES &&
        {record[175:160],record[223:208]}>=2 && {record[175:160],record[223:208]}<cluster_count+2 &&
        ((play_dir==0 && (!found_slot || name_number>max_name)) ||
         (play_dir==1 && name_number<free_dir_lba[19:0] && (!found_slot || name_number>max_name)) ||
         (play_dir==2 && name_number>free_dir_lba[19:0] && (!found_slot || name_number<max_name)))) begin
      found_slot<=1;max_name<=name_number;allocated_start<={record[175:160],record[223:208]};
     end
    end else begin
     if(!found_slot && (record[7:0]==0 || record[7:0]==8'he5 || end_directory)) begin found_slot<=1;free_dir_lba<=dir_lba;free_dir_offset<=dir_offset;free_was_end<=end_directory || record[7:0]==0;end
     if(!end_directory && record[7:0]!=0 && record[7:0]!=8'he5 && name_match && name_number>max_name) max_name<=name_number;
    end
    if(record[7:0]==0) end_directory<=1;
    root_entry_count<=root_entry_count+1'b1;state<=DIR_NEXT;
   end
   DIR_NEXT:if(dir_offset!=480) begin dir_offset<=dir_offset+32;state<=DIR_ENTRY;end
    else if(dir_sector+1<spc) begin dir_sector<=dir_sector+1'b1;dir_lba<=dir_lba+1'b1;state<=DIR_SECTOR;end
    else if(play_busy) begin
     if(found_slot) state<=PB_LOAD;
     else begin play_busy<=0;status<=8;error<=(play_dir==0 || !play_view)?8'h50:play_dir==1?8'h51:8'h52;state<=IDLE;end
    end
    else if(!found_slot) fail(8'h33);
    else if(max_name==20'hfffff) fail(8'h34);
    else begin file_number<=max_name+1'b1;scan_cluster<=2;free_run<=0;state<=ALLOC;end
   ALLOC:begin fat_offset<={scan_cluster[6:0],2'b0};current_fat_sector<=fat_base+(scan_cluster>>7);io(0,fat_base+(scan_cluster>>7),FAT_ENTRY);end
   FAT_ENTRY:get(fat_offset,4,FAT_CHECK);
   FAT_CHECK:begin
    if(fat_value==0) begin
     if(free_run==0) extent_start<=scan_cluster;
     free_run<=free_run+1'b1;
     if(free_run+1==needed) begin allocated_start<=free_run==0?scan_cluster:extent_start;allocated_end<=scan_cluster;state<=RESERVE;end
     else state<=FAT_SECTOR;
    end else begin free_run<=0;state<=FAT_SECTOR;end
   end
   FAT_SECTOR:if(scan_cluster>=cluster_count+1) fail(8'h35);
    else begin scan_cluster<=scan_cluster+1'b1;if(fat_offset==508) state<=ALLOC;else begin fat_offset<=fat_offset+4;state<=FAT_ENTRY;end end
   RESERVE:begin scan_cluster<=allocated_start;mirror<=0;state<=RES_READ;end
   RES_READ:begin fat_offset<={scan_cluster[6:0],2'b0};current_fat_sector<=fat_base+(scan_cluster>>7)+(mirror?fat_size:0);io(0,fat_base+(scan_cluster>>7)+(mirror?fat_size:0),RES_PATCH);end
   RES_PATCH:get(fat_offset,4,RES_VALUE);
   RES_VALUE:patch(fat_offset,{record[31:28],(scan_cluster==allocated_end?28'hfffffff:scan_cluster[27:0]+1'b1)},4,RES_NEXT);
   RES_NEXT:if(scan_cluster==allocated_end || fat_offset==508) io(1,current_fat_sector,RES_MIRROR);
    else begin scan_cluster<=scan_cluster+1'b1;fat_offset<=fat_offset+4;state<=RES_PATCH;end
   RES_MIRROR:if(scan_cluster!=allocated_end) begin scan_cluster<=scan_cluster+1'b1;state<=RES_READ;end
    else if(nfats==2 && !mirror) begin mirror<=1;scan_cluster<=allocated_start;state<=RES_READ;end
    else begin fs_backup<=0;fs_lba<=partition+fs_info;state<=FSINFO;end
   FSINFO:if(fs_info==0 || fs_info>=reserved || (fs_backup && (backup_boot==0 || backup_boot==65535 || backup_boot+fs_info>=reserved))) state<=IMAGE_START;
    else io(0,fs_lba,FSI_CHECK);
   FSI_CHECK:get(0,4,FSI_PATCH);
   FSI_PATCH:if(record[31:0]!=32'h41615252) state<=FSI_DONE;else get(484,28,FSI_SIG);
   FSI_SIG:if(record[31:0]!=32'h61417272 || record[223:192]!=32'haa550000) state<=FSI_DONE;else patch(488,64'hffffffffffffffff,8,FSI_NEXT);
   FSI_NEXT:io(1,fs_lba,FSI_DONE);
   FSI_DONE:if(!fs_backup) begin fs_backup<=1;fs_lba<=partition+backup_boot+fs_info;state<=FSINFO;end else state<=IMAGE_START;
   IMAGE_START:begin
    // Reserved FAT chain now belongs to this capture. Stream exactly one frame.
    stream_start<=1;image_lba<=data_base+((allocated_start-2)<<cluster_shift);image_sector<=0;file_pos<=0;fill<=0;progress<=0;progress_fraction<=0;status<=3;state<=IMAGE_FILL;
   end
   IMAGE_FILL:if(file_pos<54 || file_pos>=FILE_BYTES || pixel_valid) begin
    file_pos<=file_pos+1'b1;fill<=fill+1'b1;if(fill==511) state<=IMAGE_WRITE;
   end
   IMAGE_WRITE:io(1,image_lba,IMAGE_NEXT);
   IMAGE_NEXT:if(image_sector==FILE_SECTORS-1) begin progress<=99;state<=PUBLISH;end
    else begin image_lba<=image_lba+1'b1;image_sector<=image_sector+1'b1;fill<=0;
     advance_progress;
     state<=IMAGE_FILL;
    end
   PUBLISH:if(free_was_end && free_dir_offset==480 && free_dir_lba+1<root_lba+spc) io(0,free_dir_lba+1,PUB_CLEAR);
     else state<=PUB_NEXTREAD;
   PUB_CLEAR:patch(0,0,1,PUB_MARK);
   PUB_MARK:io(1,free_dir_lba+1,PUB_NEXTREAD);
   PUB_NEXTREAD:io(0,free_dir_lba,PUB_PATCH);
   PUB_PATCH:begin
    patch_data<=0;
    patch_data[23:0]<=24'h474d49;
    patch_data[31:24]<=hexchar(file_number[19:16]);patch_data[39:32]<=hexchar(file_number[15:12]);
    patch_data[47:40]<=hexchar(file_number[11:8]);patch_data[55:48]<=hexchar(file_number[7:4]);patch_data[63:56]<=hexchar(file_number[3:0]);
    patch_data[87:64]<=24'h504d42;patch_data[95:88]<=8'h20;
    patch_data[175:160]<=allocated_start[31:16];patch_data[223:208]<=allocated_start[15:0];
    patch_data[255:224]<=FILE_BYTES;
    patch_data[199:192]<=8'h21;patch_data[207:200]<=8'h00; // 1980-01-01, no RTC.
    patch_addr<=free_dir_offset;patch_len<=32;count<=0;after_patch<=PUB_WRITE;state<=PATCH;
   end
   PUB_WRITE:if(free_was_end && free_dir_offset<480) patch(free_dir_offset+32,0,1,FSI_SIG2);else state<=FSI_SIG2;
   FSI_SIG2:io(1,free_dir_lba,SUCCESS);
   SUCCESS:begin snap_hold<=0;status<=4;progress<=100;state<=IDLE;end
   PB_LOAD:begin
    // Keep the previous frame visible until a complete, valid replacement is loaded.
    // Reuse the writer's free-slot address register as the read cursor. This
    // permits skipping a broken latest file while keeping the displayed name.
    free_dir_lba<={12'd0,max_name};
    play_start<=1;scan_cluster<=allocated_start;dir_sector<=0;file_pos<=0;image_sector<=0;progress_fraction<=0;
    image_lba<=data_base+((allocated_start-2)<<cluster_shift);
    io(0,data_base+((allocated_start-2)<<cluster_shift),PB_BEGIN);
   end
   PB_BEGIN:begin read_addr<=0;state<=PB_WAIT;end
   PB_WAIT:state<=PB_BYTE;
   PB_BYTE:if(file_pos<54 || play_ready) begin
    // Exact camera BMP format: 54-byte header, top-down RGB24, no compression.
    if(file_pos<54 && read_q!=header(file_pos[5:0])) fail(8'h53);
    else begin
     file_pos<=file_pos+1'b1;read_addr<=read_addr+1'b1;
     if(file_pos==FILE_BYTES-1) io(0,fat_base+(scan_cluster>>7),PB_FAT);
     else if(read_addr==511) state<=PB_NEXT;
     else state<=PB_WAIT;
    end
   end
   PB_NEXT:begin
    image_sector<=image_sector+1'b1;
    advance_progress;
    if(dir_sector+1==spc) io(0,fat_base+(scan_cluster>>7),PB_FAT);
    else begin dir_sector<=dir_sector+1'b1;image_lba<=image_lba+1'b1;io(0,image_lba+1'b1,PB_BEGIN);end
   end
   PB_FAT:get({scan_cluster[6:0],2'b0},4,PB_CHAIN);
   PB_CHAIN:if(file_pos==FILE_BYTES) begin
     if(fat_value>=32'h0ffffff8) state<=PB_FINISH;else fail(8'h54);
    end else if(fat_value<2 || fat_value>=cluster_count+2 || fat_value==root_cluster) fail(8'h54);
    else begin
     scan_cluster<=fat_value;dir_sector<=0;image_lba<=data_base+((fat_value-2)<<cluster_shift);
     io(0,data_base+((fat_value-2)<<cluster_shift),PB_BEGIN);
    end
   PB_FINISH:if(play_done) begin
    play_bank<=~play_bank;play_view<=1;play_busy<=0;status<=7;file_number<=max_name;progress<=100;state<=IDLE;
   end
   FAILED:if(retry) begin state<=WAITCARD;status<=0;error<=0;partition<=0;part_length<=0;end
   default:fail(8'h3f);
  endcase
  end
  if(snap_hold && snap_error!=0) fail(snap_error);
  // Finish an in-flight card transaction before abandoning its sector. No writes
  // are issued anywhere in playback; exit remains usable even during loading.
  if(play_busy && !play_enable && (state!=IO_WAIT || (card_done && card_error==0))) begin
   // Cancel a request being formed on this same edge as well as the FSM state.
   // Otherwise a sector could start after IDLE, outside IO_WAIT ownership.
   card_start<=0;play_start<=0;play_view<=0;state<=IDLE;play_busy<=0;status<=1;error<=0;
  end else if(play_busy && mount_timeout==2000000000 && state!=IO_WAIT) fail(8'h55);
 end
end
endmodule

//**************************************************************************
// *** 名称 : RGB_YCbCr_face.v
// *** 作者 : xianyu_FPGA
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : RGB565转RGB888再转YCbCr444，最后输出人脸肤色的数据
//--------------------------------------------------------------------------
//        Y   =   0.299*R + 0.587*G + 0.114*B
//        Cb  =   0.586*(B-Y) + 128 = -0.172*R - 0.339*G + 0.511*B + 128
//        Cr  =   0.713*(R-Y) + 128 =  0.511*R - 0.428*G - 0.083*B + 128
// --->
//        Y   =   ( 77*R  +  150*G  +   29*B) >> 8
//        Cb  =   (-43*R  -   85*G  +  128*B) >> 8 + 128
//        Cr  =   (128*R  -  107*G  -   21*B) >> 8 + 128
// --->
//        Y   =   ( 77*R  +  150*G  +   29*B) >> 8
//        Cb  =   (-43*R  -   85*G  +  128*B + 32768) >> 8
//        Cr  =   (128*R  -  107*G  -   21*B + 32768) >> 8
//**************************************************************************

module RGB565_YCbCr444_face
//========================< 端口 >==========================================
(
input   wire                clk                     ,
input   wire                rst_n                   ,
//input ---------------------------------------------
input   wire                RGB_de                  ,
input   wire                RGB_hsync               ,
input   wire                RGB_vsync               ,
input   wire    [15:0]      RGB_data                , //RGB像素
//output --------------------------------------------
output  wire                face_de                 ,
output  wire                face_hsync              ,
output  wire                face_vsync              ,
output  reg     [15:0]      face_data                 //灰度像素
);
//========================< 信号 >==========================================
wire    [ 7:0]              R0, G0, B0              ;
reg     [15:0]              R1, G1, B1              ;
reg     [15:0]              R2, G2, B2              ;
reg     [15:0]              R3, G3, B3              ;
reg     [15:0]              Y1, Cb1, Cr1            ;
reg     [ 7:0]              Y2, Cb2, Cr2            ;
reg     [ 3:0]              RGB_de_r                ;
reg     [ 3:0]              RGB_hsync_r             ;
reg     [ 3:0]              RGB_vsync_r             ;
//==========================================================================
//==    RGB565转RGB888
//==========================================================================
assign R0 = {RGB_data[15:11],RGB_data[13:11]};
assign G0 = {RGB_data[10: 5],RGB_data[ 6: 5]};
assign B0 = {RGB_data[ 4: 0],RGB_data[ 2: 0]};
//==========================================================================
//==    RGB888转YCbCr
//==========================================================================
//clk 1 完成所有的乘法运算
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        {R1,G1,B1} <= {16'd0, 16'd0, 16'd0};
        {R2,G2,B2} <= {16'd0, 16'd0, 16'd0};
        {R3,G3,B3} <= {16'd0, 16'd0, 16'd0};
    end
    else begin
        {R1,G1,B1} <= { {R0 * 16'd77},  {G0 * 16'd150}, {B0 * 16'd29 } };
        {R2,G2,B2} <= { {R0 * 16'd43},  {G0 * 16'd85},  {B0 * 16'd128} };
        {R3,G3,B3} <= { {R0 * 16'd128}, {G0 * 16'd107}, {B0 * 16'd21 } };
    end
end

//clk 2 完成所有的加法运算
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        Y1  <= 16'd0;
        Cb1 <= 16'd0;
        Cr1 <= 16'd0;
    end
    else begin
        Y1  <= R1 + G1 + B1;
        Cb1 <= B2 - R2 - G2 + 16'd32768; //128扩大256倍
        Cr1 <= R3 - G3 - B3 + 16'd32768; //128扩大256倍
    end
end

//clk 3，除以256即右移8位，即取高8位
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
        Y2  <= 8'd0;
        Cb2 <= 8'd0;
        Cr2 <= 8'd0;
    end
    else begin
        Y2  <= Y1[15:8];  
        Cb2 <= Cb1[15:8];
        Cr2 <= Cr1[15:8];
    end
end

//clk 4，人脸肤色检测
//(Y2 > 77) && (Y2 < 255) &&
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        face_data <= 'h0;
    end
    else if( (Cb2 > 77) && (Cb2 < 127) && (Cr2 > 133) && (Cr2 < 173) ) begin
        face_data <= 16'hffff;
    end
    else begin
        face_data <= 'h0;
    end
end
//==========================================================================
//==    信号同步
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        RGB_de_r    <= 4'b0000;
        RGB_hsync_r <= 4'b1111;
        RGB_vsync_r <= 4'b1111;
    end
    else begin  
        RGB_de_r    <= {RGB_de_r[2:0],    RGB_de};
        RGB_hsync_r <= {RGB_hsync_r[2:0], RGB_hsync};
        RGB_vsync_r <= {RGB_vsync_r[2:0], RGB_vsync};
    end
end

assign face_de    = RGB_de_r[3];
assign face_hsync = RGB_hsync_r[3];
assign face_vsync = RGB_vsync_r[3];



endmodule

//**************************************************************************
// *** 名称 : Dilate.v
// *** 作者 : 咸鱼FPGA
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : Dilate膨胀处理，输入必须为二值图像
//**************************************************************************

module Dilate
//========================< 端口 >==========================================
(
input   wire                clk                     ,
input   wire                rst_n                   ,
//input ---------------------------------------------
input   wire                RGB_de                  ,
input   wire                RGB_hsync               ,
input   wire                RGB_vsync               ,
input   wire    [15:0]      RGB_data                ,
//output --------------------------------------------
output  wire                dilate_de               ,
output  wire                dilate_hsync            ,
output  wire                dilate_vsync            ,
output  wire    [15:0]      dilate_data
);
//========================< 信号 >==========================================
//matrix_3x3 ----------------------------------------
wire    [15:0]              matrix_11               ;
wire    [15:0]              matrix_12               ;
wire    [15:0]              matrix_13               ;
wire    [15:0]              matrix_21               ;
wire    [15:0]              matrix_22               ;
wire    [15:0]              matrix_23               ;
wire    [15:0]              matrix_31               ;
wire    [15:0]              matrix_32               ;
wire    [15:0]              matrix_33               ;
//dilate --------------------------------------------
reg                         dilate_1                ;
reg                         dilate_2                ;
reg                         dilate_3                ;
reg                         dilate                  ;
//同步 ----------------------------------------------
reg     [ 2:0]              RGB_de_r                ;
reg     [ 2:0]              RGB_hsync_r             ;
reg     [ 2:0]              RGB_vsync_r             ;
//==========================================================================
//==    matrix_3x3_16bit，生成3x3矩阵，输入和使能需对齐，耗费1clk
//==========================================================================
//--------------------------------------------------- 矩阵顺序
//        {matrix_11, matrix_12, matrix_13}
//        {matrix_21, matrix_22, matrix_23}
//        {matrix_31, matrix_32, matrix_33}
//--------------------------------------------------- 模块例化
matrix_3x3_16bit
#(
    .COL                    (1280                    ),
    .ROW                    (720                    )
)
u_matrix_3x3_16bit
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .din_vld                (RGB_de                 ),
    .din                    (RGB_data               ),
    .matrix_11              (matrix_11              ),
    .matrix_12              (matrix_12              ),
    .matrix_13              (matrix_13              ),
    .matrix_21              (matrix_21              ),
    .matrix_22              (matrix_22              ),
    .matrix_23              (matrix_23              ),
    .matrix_31              (matrix_31              ),
    .matrix_32              (matrix_32              ),
    .matrix_33              (matrix_33              )
);
//==========================================================================
//==    膨胀，耗费2clk
//==========================================================================
//clk1，三行各自相或
//---------------------------------------------------
always @ (posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        dilate_1 <= 'd0;
        dilate_2 <= 'd0;
        dilate_3 <= 'd0;
    end
    else begin
        dilate_1 <= matrix_11 || matrix_12 || matrix_13;
        dilate_2 <= matrix_21 || matrix_22 || matrix_23;
        dilate_3 <= matrix_31 || matrix_32 || matrix_33;
    end
end

//clk2，全部相或
//---------------------------------------------------
always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
        dilate <= 'd0;
    end
    else begin
        dilate <= dilate_1 || dilate_2 || dilate_3;
    end
end
//==========================================================================
//==    膨胀后的数据
//==========================================================================
assign dilate_data = dilate ? 16'hffff : 16'h0000;

//==========================================================================
//==    信号同步
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        RGB_de_r    <= 3'b000;
        RGB_hsync_r <= 3'b111;
        RGB_vsync_r <= 3'b111;
    end
    else begin  
        RGB_de_r    <= {RGB_de_r[1:0],    RGB_de};
        RGB_hsync_r <= {RGB_hsync_r[1:0], RGB_hsync};
        RGB_vsync_r <= {RGB_vsync_r[1:0], RGB_vsync};
    end
end

assign dilate_de    = RGB_de_r[2];
assign dilate_hsync = RGB_hsync_r[2];
assign dilate_vsync = RGB_vsync_r[2];
    


endmodule
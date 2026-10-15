//**************************************************************************
// *** 名称 : Median.v
// *** 作者 : xianyu_FPGA
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : Y分量进行Median中值滤波
//**************************************************************************

module Median
//========================< 端口 >==========================================
(
input   wire                clk                     ,
input   wire                rst_n                   ,
//input ---------------------------------------------
input   wire                Y_de                    ,
input   wire                Y_hsync                 ,
input   wire                Y_vsync                 ,
input   wire    [15:0]      Y_data                  ,
//output --------------------------------------------
output  wire                median_de               ,
output  wire                median_hsync            ,
output  wire                median_vsync            ,
output  wire    [15:0]      median_data
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
//median --------------------------------------------
wire    [15:0]              max_data1               ;
wire    [15:0]              mid_data1               ;
wire    [15:0]              min_data1               ;
wire    [15:0]              max_data2               ;
wire    [15:0]              mid_data2               ;
wire    [15:0]              min_data2               ;
wire    [15:0]              max_data3               ;
wire    [15:0]              mid_data3               ;
wire    [15:0]              min_data3               ;
wire    [15:0]              max_min_data            ;
wire    [15:0]              mid_mid_data            ;
wire    [15:0]              min_max_data            ;
//同步 ----------------------------------------------
reg     [ 3:0]              Y_de_r                  ;
reg     [ 3:0]              Y_hsync_r               ;
reg     [ 3:0]              Y_vsync_r               ;
//==========================================================================
//==    matrix_3x3_8bit，生成3x3矩阵，输入和使能需对齐，耗费1clk
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
    .din_vld                (Y_de                   ),
    .din                    (Y_data                 ),
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
//==    中值滤波，耗费3clk
//==========================================================================
//每行像素降序排列，clk1
//---------------------------------------------------
//第1行
sort u1
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (matrix_11              ), 
    .data2                  (matrix_12              ), 
    .data3                  (matrix_13              ),
    .max_data               (max_data1              ),
    .mid_data               (mid_data1              ),
    .min_data               (min_data1              )
);

//第2行
sort u2
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (matrix_21              ),
    .data2                  (matrix_22              ),
    .data3                  (matrix_23              ),
    .max_data               (max_data2              ),
    .mid_data               (mid_data2              ),
    .min_data               (min_data2              )
);

//第3行
sort u3
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (matrix_31              ),
    .data2                  (matrix_32              ),
    .data3                  (matrix_33              ),
    .max_data               (max_data3              ),
    .mid_data               (mid_data3              ),
    .min_data               (min_data3              )
);

//三行的最小值取最大值
//三行的中间值取中间值
//三行的最大值取最小值，clk2
//---------------------------------------------------
//min-max
sort u4
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (min_data1              ),
    .data2                  (min_data2              ),
    .data3                  (min_data3              ),
    .max_data               (min_max_data           ),
    .mid_data               (                       ),
    .min_data               (                       )
);

//mid-mid
sort u5
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (mid_data1              ),
    .data2                  (mid_data2              ),
    .data3                  (mid_data3              ),
    .max_data               (                       ),
    .mid_data               (mid_mid_data           ),
    .min_data               (                       )
);

//max-min
sort u6
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (max_data1              ), 
    .data2                  (max_data2              ), 
    .data3                  (max_data3              ),
    .max_data               (                       ),
    .mid_data               (                       ),
    .min_data               (max_min_data           )
);

//前面的三个值再取中间值，clk3
//---------------------------------------------------
sort u7
(
    .clk                    (clk                    ),
    .rst_n                  (rst_n                  ),
    .data1                  (max_min_data           ),
    .data2                  (mid_mid_data           ), 
    .data3                  (min_max_data           ),
    .max_data               (                       ),
    .mid_data               (median_data            ),
    .min_data               (                       )
);
//==========================================================================
//==    信号同步
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        Y_de_r    <= 4'b0000;
        Y_hsync_r <= 4'b1111;
        Y_vsync_r <= 4'b1111;
    end
    else begin  
        Y_de_r    <= {Y_de_r[2:0],    Y_de};
        Y_hsync_r <= {Y_hsync_r[2:0], Y_hsync};
        Y_vsync_r <= {Y_vsync_r[2:0], Y_vsync};
    end
end

assign median_de    = Y_de_r[3];
assign median_hsync = Y_hsync_r[3];
assign median_vsync = Y_vsync_r[3];
    


endmodule
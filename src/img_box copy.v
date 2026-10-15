//**************************************************************************
// *** 名称 : img_box.v
// *** 作者 : hanshuo
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : 寻找白色像素最多的列和行，并在二值图上绘制红直线，同时添加黄色指示灯
// *** 优化 : 减少内存使用，适用于资源受限的环境
//**************************************************************************

module img_box
//========================< 端口 >==========================================
(
input   wire                clk                     ,
input   wire                rst_n                   ,
//二值图像 ------------------------------------------
input   wire                face_de                 ,
input   wire                face_hsync              ,
input   wire                face_vsync              ,
input   wire    [15:0]      face_data               ,
//原图 ----------------------------------------------
// 移除未使用的端口以避免未布线网络
/*
input   wire                RGB_de                  , // 保留接口，但不使用
input   wire                RGB_hsync               , // 保留接口，但不使用
input   wire                RGB_vsync               , // 保留接口，但不使用
input   wire    [15:0]      RGB_data                , // 保留接口，但不使用
*/
//最终输出 ------------------------------------------
output  reg                 TFT_de                  ,
output  reg                 TFT_hsync               ,   
output  reg                 TFT_vsync               ,
output  reg     [15:0]      TFT_data                                  
);

//========================< 参数 >==========================================
parameter COL               = 11'd1280               ; //图片长度
parameter ROW               = 11'd720               ; //图片高度
parameter LINE_WIDTH        = 5'd21                 ; //直线宽度，21像素
//========================< 信号 >==========================================
reg                         face_vsync_r            ;
wire                        pos_vsync               ;
wire                        neg_vsync               ;
//---------------------------------------------------
reg     [ 10:0]             face_x           ; //显示驱动生成的坐标值
wire                        add_face_x                ;
wire                        end_face_x                ;
reg     [ 9:0]              face_y           ;
wire                        add_face_y                ;
wire                        end_face_y                ;
//---------------------------------------------------
reg     [ 10:0]              col_counts [COL-1:0]   ; // 每列的白色像素计数
reg     [ 10:0]              max_col_count          ; // 最大列白色像素数
reg     [ 10:0]              max_col_index          ; // 白色像素最多的列索引
reg     [ 10:0]              max_row_count          ; // 最大行白色像素数
reg     [ 9:0]               max_row_index          ; // 白色像素最多的行索引
reg     [ 10:0]              current_row_count      ; // 当前行的白色像素计数

// 用于扫描的临时变量
reg     [ 10:0]              scan_index              ; // 用于遍历列数组的索引
reg     [ 2:0]               state                   ; // 状态机状态
localparam S_IDLE       = 3'd0; // 空闲状态
localparam S_SCAN_FRAME = 3'd1; // 扫描帧状态
localparam S_FIND_COL_MAX = 3'd2; // 寻找列最大值状态

//==========================================================================
//==    帧开始和结束标志
//==========================================================================
always @(posedge clk) begin
    face_vsync_r <= face_vsync;
end

assign pos_vsync =  face_vsync && ~face_vsync_r;
assign neg_vsync = ~face_vsync &&  face_vsync_r;

 
//==========================================================================
//==    利用显示驱动生成的行场计数器
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        face_x <= 11'd0;
    else if(add_face_x) begin
        if(end_face_x)
            face_x <= 11'd0;
        else
            face_x <= face_x + 11'd1;
    end
end

assign add_face_x = face_de;
assign end_face_x = add_face_x && face_x== COL-11'd1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        face_y <= 10'd0;
    else if(add_face_y) begin
        if(end_face_y)
            face_y <= 10'd0;
        else
            face_y <= face_y + 10'd1;
    end
end

assign add_face_y = end_face_x;
assign end_face_y = add_face_y && face_y== ROW-10'd1;

//==========================================================================
//==    白色像素统计和最大值查找（优化版本）
//==========================================================================

// 初始化和清除计数器
integer i;
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        // 初始化col_counts数组
        for(i = 0; i < COL; i = i + 1) begin
            col_counts[i] <= 11'd0;
        end
        current_row_count <= 11'd0;
    end
    else if(pos_vsync) begin
        // 帧开始，清除所有计数
        for(i = 0; i < COL; i = i + 1) begin
            col_counts[i] <= 11'd0;
        end
        current_row_count <= 11'd0;
        max_row_count <= 11'd0;
        max_row_index <= 10'd0;
    end
    // 在有效数据期间统计白色像素
    else if(!end_face_x && face_de && face_data == 16'hffff) begin
        // 增加当前行的计数
        current_row_count <= current_row_count + 11'd1;
        // 增加当前列的计数
        col_counts[face_x] <= col_counts[face_x] + 11'd1;
    end
    // 行结束时，更新行最大值
    else if(end_face_x) begin
        // 比较并更新行最大值
        if(current_row_count > max_row_count) begin
            max_row_count <= current_row_count;
            max_row_index <= face_y;
        end
        // 修改：无论是否是最后一行，都重置当前行计数
        current_row_count <= 11'd0;
    end
end

// 状态机控制
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        state <= S_IDLE;
        max_col_count <= 11'd0;
        max_col_index <= 11'd0;
        scan_index <= 11'd0;
    end
    else begin
        case(state)
            S_IDLE: begin
                if(pos_vsync) begin
                    // 帧开始，进入扫描状态
                    state <= S_SCAN_FRAME;
                    max_col_count <= 11'd0;
                    max_col_index <= 11'd0;
                    scan_index <= 11'd0;
                end
            end
            
            S_SCAN_FRAME: begin
                // 一帧扫描完成，直接进入寻找列最大值状态
                if(neg_vsync) begin
                    state <= S_FIND_COL_MAX;
                    scan_index <= 11'd0;
                    max_col_count <= 11'd0;
                end
            end
            
            S_FIND_COL_MAX: begin
                // 寻找列最大值
                if(scan_index < COL) begin
                    if(col_counts[scan_index] > max_col_count) begin
                        max_col_count <= col_counts[scan_index];
                        max_col_index <= scan_index;
                    end
                    scan_index <= scan_index + 11'd1;
                end
                else begin
                    // 列最大值找到，等待下一帧
                    state <= S_IDLE;
                end
            end
            
            default: state <= S_IDLE;
        endcase
    end
end

//==========================================================================
//==    最终数据输出：红直线+黄色指示灯+二值图
//==========================================================================

// 定义颜色常量
localparam RED     = 16'b11111_000000_00000; // 红色
localparam YELLOW  = 16'b11111_111111_00000; // 黄色

// 计算直线的半宽，用于绘制21像素宽的直线
localparam HALF_WIDTH = (LINE_WIDTH - 1) / 2;

// 计算黄色指示灯的边界
localparam INDICATOR_CENTER_X = 11'd100;
localparam INDICATOR_CENTER_Y = 10'd100;
localparam INDICATOR_SIZE = 5'd20;
localparam INDICATOR_HALF = (INDICATOR_SIZE - 1) / 2;
localparam INDICATOR_LEFT   = INDICATOR_CENTER_X - INDICATOR_HALF;
localparam INDICATOR_RIGHT  = INDICATOR_CENTER_X + INDICATOR_HALF;
localparam INDICATOR_TOP    = INDICATOR_CENTER_Y - INDICATOR_HALF;
localparam INDICATOR_BOTTOM = INDICATOR_CENTER_Y + INDICATOR_HALF;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
    TFT_de    <= 1'b0;
    TFT_hsync <= 1'b1;
    TFT_vsync <= 1'b1;
    TFT_data  <= 16'b0;
    end
    else begin
        // 使用二值图的同步信号
        TFT_de    <= face_de;
        TFT_hsync <= face_hsync;
        TFT_vsync <= face_vsync;
        
        // 优先处理黄色指示灯区域
        if(face_de && (face_x >= INDICATOR_LEFT && face_x <= INDICATOR_RIGHT) && 
                     (face_y >= INDICATOR_TOP && face_y <= INDICATOR_BOTTOM)) begin
            TFT_data <= YELLOW;
        end
        // 处理白色像素最多的列（垂直红线）
        else if(face_de && (face_x >= max_col_index - HALF_WIDTH && 
                          face_x <= max_col_index + HALF_WIDTH)) begin
            TFT_data <= RED;
        end
        // 处理白色像素最多的行（水平红线）
        else if(face_de && (face_y >= max_row_index - HALF_WIDTH && 
                          face_y <= max_row_index + HALF_WIDTH)) begin
            TFT_data <= RED;
        end
        // 显示二值图
        else if(face_de) begin
            TFT_data <= face_data;
        end
        else begin
            TFT_data <= 16'b0;
        end
    end
end


endmodule
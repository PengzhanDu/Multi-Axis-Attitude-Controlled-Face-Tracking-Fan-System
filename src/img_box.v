  //**************************************************************************
// *** 名称 : img_box.v
// *** 作者 : hanshuo
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : 寻找白色像素最多的列和行，并在二值图上绘制红直线
//增加抖动阈值
//下一步优化：粗糙化之后，统计几帧之间的众数再显示，减少抖动
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
//最终输出 ------------------------------------------
output  reg                 TFT_de                  ,
output  reg                 TFT_hsync               ,   
output  reg                 TFT_vsync               ,
output  reg     [15:0]      TFT_data                ,
//人脸坐标输出 --------------------------------------
output  reg     [10:0]      face_center_x           ,  // 人脸中心X坐标
output  reg     [9:0]       face_center_y           ,  // 人脸中心Y坐标
output  reg                 face_valid              ,  // 人脸坐标有效信号
output  reg                 frame_end                  // 帧结束信号                 
);

//========================< 可调参数 >==========================================
parameter col_gap           = 5'd31                 ;//列采样间隔
parameter COL_JITTER_THRESHOLD  = 11'd100            ;//抖动阈值
parameter ROW_JITTER_THRESHOLD  = 11'd60        ;//抖动阈值
parameter LINE_WIDTH        = 5'd11                 ;//直线宽度
parameter COL               = 11'd1280              ;//图片长度
parameter ROW               = 11'd720               ;//图片高度

//动态参数
parameter JITTER_THRESHOLD_M           = 5'd3               ;
parameter JITTER_THRESHOLD_S            = 5'd2                 ;
reg [10:0] col_jitter_threshold  = 11'd100            ;
reg [10:0] row_jitter_threshold  = 11'd60        ;
//========================< 信号 >==========================================
reg                         face_vsync_r            ;//用于检测场同步信号的上升沿和下降沿
wire                        pos_vsync               ;//帧开始
wire                        neg_vsync               ;//帧结束
//---------------------------------------------------
reg     [10:0]              face_x                  ; 
wire                        add_face_x              ;
wire                        end_face_x              ;
reg     [ 9:0]              face_y                  ; 
wire                        add_face_y              ;
wire                        end_face_y              ;
//---------------------------------------------------
reg     [10:0]              col_counts [(COL/col_gap) - 1:0]; // 每列的白色像素计数
reg     [10:0]              max_col_count           ; // 列像素数
reg     [10:0]              max_col_index           ; // 列索引
reg     [10:0]              output_max_col_index    ;

reg     [10:0]              max_row_count           ; // 行像素数
reg     [ 9:0]              max_row_index           ; // 行索引
reg     [10:0]              current_row_count       ; // 当前行的白色像素计数
reg     [ 9:0]              output_max_row_index    ;

// 状态机变量
reg     [10:0]              scan_index              ; // 用于遍历列数组的索引
reg     [ 2:0]              state                   ; // 状态机状态
localparam S_IDLE           = 3'd0                  ; // 空闲状态
localparam S_SCAN_FRAME     = 3'd1                  ; // 扫描帧状态
localparam S_FIND_COL_MAX   = 3'd2                  ; // 寻找列最大值状态

//==========================================================================
//==    帧开始和结束标志
//==========================================================================
always @(posedge clk) begin
    face_vsync_r <= face_vsync;
end

assign pos_vsync =  ~face_vsync && face_vsync_r;
assign neg_vsync = face_vsync &&  ~face_vsync_r;

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
//==    白色像素统计和最大值查找
//==========================================================================
integer i;
// 在第157行附近可能存在的问题 - 检查always块的结束
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        current_row_count <= 11'd0;
        for(i = 0; i < (COL/col_gap); i = i + 1) begin
            col_counts[i] <= 11'd0;
        end
    end
    else if(pos_vsync) begin
        current_row_count <= 11'd0;
        max_row_count <= 11'd0;
        max_row_index <= 10'd0;
        for(i = 0; i < (COL/col_gap); i = i + 1) begin
                col_counts[i] <= 11'd0;
        end
    end
    // 在有效数据期间统计白色像素
    else if(!end_face_x && face_de && face_data == 16'hffff) begin
        // 增加当前行的计数
        current_row_count <= current_row_count + 11'd1;
        // 增加当前列的计数
        if (face_x % col_gap == 0) begin
            col_counts[face_x/col_gap] <= col_counts[face_x/col_gap] + 11'd1;
        end
    end
    else if(end_face_x) begin
        // 比较并更新行最大值
        if(current_row_count > max_row_count) begin
            max_row_count <= current_row_count;
            max_row_index <= face_y;
        end
        // 重置当前行计数
        current_row_count <= 11'd0;
    end
end  // 确保这个end正确匹配always块的开始

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
                end
            end
            
            S_SCAN_FRAME: begin
                if(neg_vsync) begin
                    // 帧结束，开始查找列最大值
                    state <= S_FIND_COL_MAX;
                    max_col_count <= 11'd0;
                    max_col_index <= 11'd0;
                    scan_index <= 11'd0;
                end
            end

            S_FIND_COL_MAX: begin
                if(scan_index < (COL/col_gap)) begin
                    if(col_counts[scan_index] > max_col_count) begin
                        max_col_count <= col_counts[scan_index];
                        max_col_index <= scan_index;
                    end
                    scan_index <= scan_index + 11'd1;
                end
                else begin
                    if((max_col_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M > row_jitter_threshold + row_jitter_threshold/4) || (max_col_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M < row_jitter_threshold - row_jitter_threshold/4)) begin
                        row_jitter_threshold <= max_col_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M;
                    end
                    if((max_row_index > output_max_row_index + row_jitter_threshold) || (max_row_index < output_max_row_index - row_jitter_threshold)) begin
                        output_max_row_index <= max_row_index;
                    end
                    if((max_row_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M > col_jitter_threshold + col_jitter_threshold/4) || (max_row_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M < col_jitter_threshold - col_jitter_threshold/4)) begin
                        col_jitter_threshold <= max_row_count*JITTER_THRESHOLD_S/JITTER_THRESHOLD_M; 
                    end
                    if((col_gap * max_col_index > output_max_col_index + col_jitter_threshold) || (col_gap * max_col_index < output_max_col_index - col_jitter_threshold)) begin
                        output_max_col_index  <= col_gap * max_col_index;
                    end
                    // 查找完成，回到空闲状态
                    state <= S_IDLE;
                end
            end
            default: state <= S_IDLE;
        endcase
    end
end

//==========================================================================
//==    最终数据输出
//==========================================================================

// 定义颜色常量
localparam RED     = 16'b11111_000000_00000; // 红色
localparam YELLOW  = 16'b11111_111111_00000; // 黄色

// 计算直线的半宽
localparam HALF_WIDTH = (LINE_WIDTH - 1) / 2;

reg [10:0] col_width;
reg [ 9:0] row_width;

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

        // 处理白色像素最多的列（垂直红线）
        if(face_de && (face_x >= output_max_col_index - HALF_WIDTH && face_x <= output_max_col_index + HALF_WIDTH)) begin
            TFT_data <= RED;
        end
        // 处理白色像素最多的行（水平红线）
        else if(face_de && (face_y >= output_max_row_index - HALF_WIDTH && face_y <= output_max_row_index + HALF_WIDTH)) begin
            TFT_data <= RED;
        end
        //方框
        else if(face_de && (face_y >= output_max_row_index + row_jitter_threshold - HALF_WIDTH && face_y <= output_max_row_index + row_jitter_threshold + HALF_WIDTH
                && face_x <= output_max_col_index + col_jitter_threshold + HALF_WIDTH&&face_x >= output_max_col_index - col_jitter_threshold - HALF_WIDTH)) begin
            TFT_data <= YELLOW;
        end
        else if(face_de && (face_y >= output_max_row_index - row_jitter_threshold - HALF_WIDTH && face_y <= output_max_row_index - row_jitter_threshold + HALF_WIDTH
                && face_x <= output_max_col_index + col_jitter_threshold + HALF_WIDTH&&face_x >= output_max_col_index - col_jitter_threshold - HALF_WIDTH)) begin
            TFT_data <= YELLOW;
        end
        else if(face_de && (face_x >= output_max_col_index + col_jitter_threshold - HALF_WIDTH && face_x <= output_max_col_index + col_jitter_threshold + HALF_WIDTH&&
                face_y >= output_max_row_index - row_jitter_threshold - HALF_WIDTH&& face_y <= output_max_row_index + row_jitter_threshold + HALF_WIDTH)) begin
            TFT_data <= YELLOW;
        end
        else if(face_de && (face_x >= output_max_col_index - col_jitter_threshold - HALF_WIDTH && face_x <= output_max_col_index - col_jitter_threshold + HALF_WIDTH&&face_y >= output_max_row_index - row_jitter_threshold - HALF_WIDTH&& face_y <= output_max_row_index + row_jitter_threshold + HALF_WIDTH)) begin
            TFT_data <= YELLOW;
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

// 人脸坐标计算逻辑
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        face_center_x <= 11'd0;
        face_center_y <= 10'd0;
        face_valid <= 1'b0;
        frame_end <= 1'b0;
    end
    else begin
        // 帧结束信号
        frame_end <= neg_vsync;
        // 在帧结束时输出人脸坐标
        if(neg_vsync) begin
            // 设置人脸坐标
            face_center_x <= output_max_col_index;
            face_center_y <= output_max_row_index;
            // 判断是否有效人脸（白色像素数超过阈值）
            if(max_col_count > 11'd100 && max_row_count > 11'd100) begin
                face_valid <= 1'b1;
            end
            else begin
                face_valid <= 1'b0;
            end
        end
    end
end


endmodule
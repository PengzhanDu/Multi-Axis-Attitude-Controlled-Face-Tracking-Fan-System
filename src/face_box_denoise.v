//**************************************************************************
// *** 名称 : face_box_denoise.v
// *** 描述 : 含噪点二值化人脸图的抗噪框选，输出带框纯净二值图
// *** 特性 : 连通区域面积过滤+4邻域标记+轻量化实现
//**************************************************************************

module face_box_denoise
(
    input   wire                clk                     , // 时钟信号
    input   wire                rst_n                   , // 复位信号（低有效）
    // 输入：含噪点的二值化人脸图（16'hffff=白色，16'h0000=黑色）
    input   wire                bin_de                  , // 数据有效
    input   wire                bin_hsync               , // 行同步
    input   wire                bin_vsync               , // 场同步
    input   wire    [15:0]      bin_data                , // 二值图数据
    // 输出：带矩形框的去噪后二值图
    output  reg                 out_de                  ,
    output  reg                 out_hsync               ,
    output  reg                 out_vsync               ,
    output  reg     [15:0]      out_data                  
);

//========================< 参数配置 >======================================
parameter COL           = 11'd1280               ; // 图像宽度
parameter ROW           = 11'd720                ; // 图像高度
parameter MIN_AREA      = 10'd1000               ; // 最小人脸面积阈值（过滤小噪点）
parameter BOX_COLOR     = 16'b11111_000000_00000 ; // 框颜色（红色，5R6G5B）
parameter WHITE         = 16'hffff               ; // 白色（人脸）
parameter BLACK         = 16'h0000               ; // 黑色（背景）

//========================< 信号定义 >======================================
// 1. 坐标计数器（跟踪当前像素位置）
reg     [10:0]  x_cnt                           ; // 列坐标（0~COL-1）
reg     [10:0]  y_cnt                           ; // 行坐标（0~ROW-1）
wire            add_x                            ;
wire            end_x                            ;
wire            add_y                            ;
wire            end_y                            ;

// 2. 场同步边沿（帧开始/结束）
reg             vsync_r                          ;
wire            pos_vsync                        ; // 帧开始（上升沿）
wire            neg_vsync                        ; // 帧结束（下降沿）

// 3. 连通区域标记（使用两行缓存的优化版）
reg     [7:0]   current_label                    ; // 当前分配的最大区域ID
reg     [7:0]   left_label                       ; // 左侧像素的区域ID
reg     [7:0]   up_label                         ; // 上方像素的区域ID

// 添加缺失的变量声明
reg             merge_en                         ; // 区域合并使能信号
reg     [7:0]   merge_label1                     ; // 待合并区域1的标签
reg     [7:0]   merge_label2                     ; // 待合并区域2的标签

// 两行缓存（当前行和上一行）
reg     [7:0]   curr_row_labels[COL-1:0]         ; // 当前行标签
reg     [7:0]   prev_row_labels[COL-1:0]         ; // 上一行标签

// 4. 面积统计和映射表
reg     [10:0]  area[255:0]                      ; // 每个区域的面积（0~255号区域）
reg     [7:0]   max_area_label                   ; // 最大面积区域的ID（人脸主体）

// 临时变量
reg     [7:0]   lab                              ;
reg     [10:0]  max_area                         ;
integer         i                                ;

// 5. 去噪后二值图（仅保留大面积区域）
reg             denoise_bin                      ; // 1=保留（人脸），0=过滤（噪点）

// 6. 人脸边界坐标（基于去噪后图像）
reg     [10:0]  x_min, x_max, y_min, y_max       ; // 实时计算
reg     [10:0]  x_min_r, x_max_r, y_min_r, y_max_r; // 帧结束锁存

//==========================================================================
//== 1. 坐标计数器及时序同步
//==========================================================================
// 列坐标计数
assign add_x = bin_de;
assign end_x = add_x && (x_cnt == COL - 1'b1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        x_cnt <= 11'd0;
    else if (add_x)
        x_cnt <= end_x ? 11'd0 : x_cnt + 11'd1;
end

// 行坐标计数
assign add_y = end_x;
assign end_y = add_y && (y_cnt == ROW - 1'b1);

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        y_cnt <= 11'd0;
    else if (add_y)
        y_cnt <= end_y ? 11'd0 : y_cnt + 11'd1;
end

// 场同步边沿检测
always @(posedge clk) begin
    vsync_r <= bin_vsync;
end
assign pos_vsync = bin_vsync && !vsync_r; // 帧开始
assign neg_vsync = !bin_vsync && vsync_r; // 帧结束

//==========================================================================
//== 2. 连通区域标记（使用两行缓存的优化版）
//== 逻辑：当前像素为白色时，取左/上像素的最小标记ID；若无则分配新ID
//==========================================================================
// 读取左侧和上方像素的标记（边界处理：边缘像素无左/上时标记为0）
always @(posedge clk) begin
    if (x_cnt == 11'd0)
        left_label <= 8'd0; // 第一列无左侧像素
    else
        left_label <= curr_row_labels[x_cnt - 11'd1]; // 左侧像素标记

    if (y_cnt == 11'd0)
        up_label <= 8'd0; // 第一行无上方像素
    else
        up_label <= prev_row_labels[x_cnt]; // 上方像素标记
end

// 分配当前像素的标记ID
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        current_label <= 8'd1; // 初始标记从1开始（0为背景）
        merge_en <= 1'b0;
    end
    else if (pos_vsync) begin // 新帧开始，重置标记
        current_label <= 8'd1;
        merge_en <= 1'b0;
        // 初始化两行缓存
        for (i = 0; i < COL; i = i + 1) begin
            curr_row_labels[i] <= 8'd0;
            prev_row_labels[i] <= 8'd0;
        end
    end
    else if (bin_de && bin_data == WHITE) begin // 当前像素为白色（需标记）
        // 默认不合并区域
        merge_en <= 1'b0;
        
        if (left_label != 8'd0 && up_label != 8'd0) begin
            // 左和上都有标记，取最小值（合并区域）
            curr_row_labels[x_cnt] <= (left_label < up_label) ? left_label : up_label;
            
            // 设置合并信号和标签，但不直接更新area数组
            if (left_label < up_label && left_label != up_label) begin
                merge_en <= 1'b1;
                merge_label1 <= up_label;
                merge_label2 <= left_label;
            end else if (up_label < left_label && left_label != up_label) begin
                merge_en <= 1'b1;
                merge_label1 <= left_label;
                merge_label2 <= up_label;
            end
        end
        else if (left_label != 8'd0) begin
            curr_row_labels[x_cnt] <= left_label; // 仅左侧有标记
        end
        else if (up_label != 8'd0) begin
            curr_row_labels[x_cnt] <= up_label; // 仅上方有标记
        end
        else begin
            curr_row_labels[x_cnt] <= current_label; // 无标记，分配新ID
            current_label <= current_label + 8'd1; // 下一个新ID
        end
        
        // 行结束时，将当前行数据移到上一行
        if (end_x) begin
            for (i = 0; i < COL; i = i + 1) begin
                prev_row_labels[i] <= curr_row_labels[i];
            end
        end
    end
    else begin
        merge_en <= 1'b0;
        curr_row_labels[x_cnt] <= 8'd0; // 黑色像素，无标记
        
        // 行结束时，将当前行数据移到上一行
        if (end_x) begin
            for (i = 0; i < COL; i = i + 1) begin
                prev_row_labels[i] <= curr_row_labels[i];
            end
        end
    end
end

//==========================================================================
//== 3. 面积统计与最大区域筛选
//== 逻辑：统计每个标记区域的像素数，帧结束时选面积超过阈值的最大区域
//==========================================================================
// 合并到单一always块的面积统计逻辑
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 256; i = i + 1)
            area[i] <= 11'd0;
    end
    else if (pos_vsync) begin // 新帧开始，清零面积
        for (i = 0; i < 256; i = i + 1)
            area[i] <= 11'd0;
    end
    else begin
        // 处理区域合并
        if (merge_en) begin
            area[merge_label1] <= area[merge_label1] + area[merge_label2];
            area[merge_label2] <= 11'd0;
        end
        // 实时统计各区域面积（如果没有合并操作）
        else if (bin_de && bin_data == WHITE) begin
            lab = curr_row_labels[x_cnt];
            if (lab != 8'd0)
                area[lab] <= area[lab] + 11'd1;
        end
    end
end

// 帧结束时筛选最大面积区域（超过阈值）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        max_area_label <= 8'd0;
    end
    else if (neg_vsync) begin // 帧结束，遍历所有区域找最大面积
        max_area = 11'd0;
        max_area_label = 8'd0;
        for (i = 1; i < 256; i = i + 1) begin // 从1开始（0是背景）
            if (area[i] > max_area && area[i] >= MIN_AREA) begin
                max_area = area[i];
                max_area_label = i[7:0];
            end
        end
    end
end

//==========================================================================
//== 4. 生成去噪后二值图（仅保留最大区域）
//==========================================================================
// 使用标签映射表代替帧缓存
reg [7:0] label_map[255:0]; // 标签映射表，用于标记有效的区域

// 构建标签映射表
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        for (i = 0; i < 256; i = i + 1) begin
            label_map[i] <= 8'd0;
        end
    end
    else if (neg_vsync) begin
        // 只标记最大面积的区域为有效
        for (i = 0; i < 256; i = i + 1) begin
            label_map[i] <= (i == max_area_label) ? 8'd1 : 8'd0;
        end
    end
end

// 生成去噪结果
always @(posedge clk) begin
    if (bin_de && bin_data == WHITE && label_map[curr_row_labels[x_cnt]] == 8'd1)
        denoise_bin <= 1'b1; // 属于最大区域，保留
    else
        denoise_bin <= 1'b0; // 噪点或背景，过滤
end

//==========================================================================
//== 5. 计算去噪后图像的人脸边界坐标
//==========================================================================
// 实时更新边界（仅基于去噪后的有效像素）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_min <= COL;
        x_max <= 11'd0;
        y_min <= ROW;
        y_max <= 11'd0;
    end
    else if (pos_vsync) begin // 新帧重置
        x_min <= COL;
        x_max <= 11'd0;
        y_min <= ROW;
        y_max <= 11'd0;
    end
    else if (bin_de && denoise_bin) begin // 去噪后的有效像素
        x_min <= (x_cnt < x_min) ? x_cnt : x_min;
        x_max <= (x_cnt > x_max) ? x_cnt : x_max;
        y_min <= (y_cnt < y_min) ? y_cnt : y_min;
        y_max <= (y_cnt > y_max) ? y_cnt : y_max;
    end
end

// 帧结束锁存边界坐标
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        x_min_r <= 11'd0;
        x_max_r <= 11'd0;
        y_min_r <= 11'd0;
        y_max_r <= 11'd0;
    end
    else if (neg_vsync) begin
        x_min_r <= x_min;
        x_max_r <= x_max;
        y_min_r <= y_min;
        y_max_r <= y_max;
    end
end

//==========================================================================
//== 6. 输出带框的去噪后二值图
//==========================================================================
reg [10:0] x_min_p;
reg [10:0] y_min_p;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        out_de <= 1'b0;
        out_hsync <= 1'b1;
        out_vsync <= 1'b1;
        out_data <= BLACK;
    end
    else begin
        // 同步控制信号
        out_de <= bin_de;
        out_hsync <= bin_hsync;
        out_vsync <= bin_vsync;

        // 边界保护（避免-1越界）
        x_min_p = (x_min_r > 11'd1) ? x_min_r - 11'd1 : 11'd0;
        y_min_p = (y_min_r > 11'd1) ? y_min_r - 11'd1 : 11'd0;

        // 判断是否在框内（3像素宽）
        if (bin_de && (
            (y_cnt >= y_min_p && y_cnt <= y_min_r + 11'd1 && x_cnt >= x_min_p && x_cnt <= x_max_r + 11'd1) ||
            (y_cnt >= y_max_r - 11'd1 && y_cnt <= y_max_r + 11'd1 && x_cnt >= x_min_p && x_cnt <= x_max_r + 11'd1) ||
            (x_cnt >= x_min_p && x_cnt <= x_min_r + 11'd1 && y_cnt >= y_min_p && y_cnt <= y_max_r + 11'd1) ||
            (x_cnt >= x_max_r - 11'd1 && x_cnt <= x_max_r + 11'd1 && y_cnt >= y_min_p && y_cnt <= y_max_r + 11'd1)
        )) begin
            out_data <= BOX_COLOR; // 输出框颜色
        end
        else begin
            // 输出去噪后二值图（保留区域为白色，其他黑色）
            out_data <= denoise_bin ? WHITE : BLACK;
        end
    end
end

endmodule
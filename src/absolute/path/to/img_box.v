//**************************************************************************
// *** 名称 : img_box.v
// *** 作者 : xianyu_FPGA
// *** 博客 : https://www.cnblogs.com/xianyufpga/
// *** 日期 : 2020年3月
// *** 描述 : 将目标框住，和原图一起输出
//**************************************************************************

module img_box
//========================< 端口 >==========================================
(
input   wire                clk                     ,
input   wire                rst_n                   ,
//key -----------------------------------------------
//input	wire				key_vld					, //按键切换显示效果
//侦差图像 ------------------------------------------
input   wire                face_de                 ,
input   wire                face_hsync              ,
input   wire                face_vsync              ,
input   wire    [15:0]      face_data               ,
//原图 ----------------------------------------------
input   wire                RGB_de                  ,
input   wire                RGB_hsync               ,
input   wire                RGB_vsync               ,
input   wire    [15:0]      RGB_data				,
//最终输出 ------------------------------------------
output  reg                 TFT_de                  ,
output  reg                 TFT_hsync               ,   
output  reg                 TFT_vsync               ,
output  reg     [15:0]      TFT_data                                 
);
parameter				key_num=1;
//========================< 参数 >==========================================
parameter COL               = 11'd1280               ; //图片长度
parameter ROW               = 11'd720               ; //图片高度
//========================< 信号 >==========================================
reg                         face_vsync_r            ;
wire                        pos_vsync               ;
wire                        neg_vsync               ;
//---------------------------------------------------
reg     [ 10:0]              face_x					; //显示驱动生成的坐标值
wire                        add_face_x             	;
wire                        end_face_x             	;
reg     [ 9:0]              face_y					;
wire                        add_face_y             	;
wire                        end_face_y             	;
//---------------------------------------------------
reg     [ 10:0]              x_min					; //图像实时坐标值，表示四个顶点坐标
reg     [ 10:0]              x_max					;
reg     [ 9:0]              y_min					;
reg     [ 9:0]              y_max					;
reg     [ 10:0]      		x_min_r					;
reg     [ 10:0]      		x_max_r					;
reg     [ 9:0]      		y_min_r					;
reg     [ 9:0]      		y_max_r					;
//---------------------------------------------------
reg     [ 10:0]              RGB_x					;
wire                        add_RGB_x             	;
wire                        end_RGB_x             	;
reg     [ 9:0]              RGB_y					;
wire                        add_RGB_y             	;
wire                        end_RGB_y             	;
//---------------------------------------------------

//==========================================================================
//==    帧开始和结束标志
//==========================================================================
always @(posedge clk) begin
    face_vsync_r <= face_vsync;
end

assign pos_vsync =  face_vsync && ~face_vsync_r;
assign neg_vsync = ~face_vsync &&  face_vsync_r;

	 

//==========================================================================
//==    利用显示驱动生成的行场计数器，得到人脸肤色处的横纵坐标
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
//==    帧运行：人脸框选
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x_min <= COL;
    end
    else if(pos_vsync) begin
        x_min <= COL;
    end
    else if(face_data==16'hffff && x_min > face_x && face_de) begin
        x_min <= face_x;
    end
end
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x_max <= 0;
    end
    else if(pos_vsync) begin
        x_max <= 0;
    end
    else if(face_data==16'hffff && x_max < face_x && face_de) begin
        x_max <= face_x;
    end
end
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        y_min <= ROW;
    end
    else if(pos_vsync) begin
        y_min <= ROW;
    end
    else if(face_data==16'hffff && y_min > face_y && face_de) begin
        y_min <= face_y;
    end
end
//---------------------------------------------------
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        y_max <= 0;
    end
    else if(pos_vsync) begin
        y_max <= 0;
    end
    else if(face_data==16'hffff && y_max < face_y && face_de) begin
        y_max <= face_y;
    end
end
//==========================================================================
//==    帧结束：保存坐标值
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
        x_min_r <= 0;
        x_max_r <= 0;
        y_min_r <= 0;
        y_max_r <= 0;
    end
    else if(neg_vsync) begin
        x_min_r <= x_min;
        x_max_r <= x_max;
        y_min_r <= y_min;
        y_max_r <= y_max;
    end
end
//==========================================================================
//==    原图的行列划分
//==========================================================================
always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        RGB_x <= 11'd0;
    else if(add_RGB_x) begin
        if(end_RGB_x)
            RGB_x <= 11'd0;
        else
            RGB_x <= RGB_x + 11'd1;
    end
end

assign add_RGB_x = RGB_de;
assign end_RGB_x = add_RGB_x && RGB_x== COL-11'd1;

always @(posedge clk or negedge rst_n) begin
    if(!rst_n)
        RGB_y <= 10'd0;
    else if(add_RGB_y) begin
        if(end_RGB_y)
            RGB_y <= 10'd0;
        else
            RGB_y <= RGB_y + 10'd1;
    end
end

assign add_RGB_y = end_RGB_x;
assign end_RGB_y = add_RGB_y && RGB_y== ROW-10'd1;
//==========================================================================
//==    最终数据输出：包围盒+图像
//==========================================================================


always @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
		TFT_de	  <= 1'b0;
		TFT_hsync <= 1'b0;
		TFT_vsync <= 1'b0;
		TFT_data  <= 16'b0;
	end
	else if(key_num==1'b0) begin  //按键按下，白色框和原图
		if((RGB_y >= y_min_r-1 && RGB_y <= y_min_r+1) && RGB_x >= x_min_r && RGB_x <= x_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((RGB_y >= y_max_r-1 && RGB_y <= y_max_r+1) && RGB_x >= x_min_r && RGB_x <= x_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((RGB_x >= x_min_r-1 && RGB_x <= x_min_r+1) && RGB_y >= y_min_r && RGB_y <= y_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((RGB_x >= x_max_r-1 && RGB_x <= x_max_r+1) && RGB_y >= y_min_r && RGB_y <= y_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else begin
			TFT_de    <= RGB_de;
			TFT_hsync <= RGB_hsync;
			TFT_vsync <= RGB_vsync;
			TFT_data  <= RGB_data;
		end
	end
    else if(key_num==1'b1) begin//按键释放，白色框和二值图
		if((face_y >= y_min_r-1 && face_y <= y_min_r+1) && face_x >= x_min_r && face_x <= x_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((face_y >= y_max_r-1 && face_y <= y_max_r+1) && face_x >= x_min_r && face_x <= x_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((face_x >= x_min_r-1 && face_x <= x_min_r+1) && face_y >= y_min_r && face_y <= y_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else if((face_x >= x_max_r-1 && face_x <= x_max_r+1) && face_y >= y_min_r && face_y <= y_max_r) begin
			TFT_data <= 16'b11111_000000_00000;
		end
		else begin
			TFT_de    <= face_de;
			TFT_hsync <= face_hsync;
			TFT_vsync <= face_vsync;
			TFT_data  <= face_data;
		end
	end
end


endmodule

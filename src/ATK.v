module ATK
(
	//全局时钟
	input				clk,                //50MHz
	input				rst_n,
//    input               pll_inst1_CLKOUT0,  //100MHz
//    input               pll_inst1_LOCKED,
	
	//用户接口
    
//    input wire signed [6:0] object_x,
//    input wire signed [6:0] object_y,
    
	input				fpga_rxd,		//从PC到FPGA的UART接收
	output				fpga_txd,		//从FPGA到PC的UART传输
    output  reg signed  [15:0]	yawo,
    output  reg signed  [15:0]	rolo,
    output  reg signed  [15:0]	pito
);
//wire    clk_ref = pll_inst1_CLKOUT0;    //100MHz
//wire    sys_rst_n = pll_inst1_LOCKED;


//------------------------------------
//精确时钟分频器
wire	divide_clken;
integer_divider	
#(
	.DEVIDE_CNT	(27)	//115200bps * 16   对应50M
	//.DEVIDE_CNT	(651)	//9600bps * 16
    //.DEVIDE_CNT	(27)	//115200bps * 16   对应50M
)
u_integer_devider
(
	//全局
	.clk				(clk),		//100MHz时钟
	.rst_n				(rst_n),    //全局复位
	
	//用户接口
	.divide_clken		(divide_clken)
);
	

wire	clken_16bps = divide_clken;
//---------------------------------
//数据接收：从PC到FPGA。
wire			rxd_flag;
wire	[7:0]	rxd_data;
uart_receiver	u_uart_receiver
(
	//全局时钟
	.clk			(clk),
	.rst_n			(rst_n),
	
	//UART接口
	.clken_16bps	(clken_16bps),	//时钟波特率 * 16
	.rxd			(fpga_rxd),		//UART接收接口
	
	//用户接口
	.rxd_data		(rxd_data),		//接收到的UART数据
	.rxd_flag		(rxd_flag)  	//UART数据接收完成标志
);
////************************************************************

reg imuready;
reg [3:0] state;
reg signed [7:0] data_sum;
reg [7:0] rolll, rollh, pitl, pith, yawl, yawh;
reg signed [15:0] roll, pitch, yaw;
//reg [15:0] yawo,rolo,pito;
reg [7:0] received_sum; // 用于存储接收到的校验和
reg [5:0] data_count; // 用于计数接收到的数据字节

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        // 初始化状态和寄存器
        state <= 4'b0000;
        data_sum <= 0;
        imuready <= 1'b0;
        data_count <= 0;
        received_sum <= 0;
    end else begin
        if (rxd_flag) begin
            case (state)
        4'b0000: begin                   // 等待帧头
            data_sum <= 0;
            imuready <= 1'b0;
            data_count <= 0;
            received_sum <= 0;
            if (rxd_data == 'h55) begin
                state <= 4'b0001;
                data_sum <= data_sum + 8'h55;
            end
        end
        4'b0001: begin
            if (rxd_data == 'h55) begin
                state <= 4'b0010;
                data_sum <= data_sum + 8'h55;
            end else begin
                state <= 4'b0000; // 重置状态
            end
        end
        4'b0010: begin
            if (rxd_data == 'h01) begin
                state <= 4'b1111;
                data_count <= 0; // 初始化数据计数
                data_sum <= data_sum + 8'h01;
            end else begin
                state <= 4'b0000; // 重置状态
            end
        end               
        4'b1111: begin
            if (rxd_data == 'h06) begin
                state <= 4'b0011;
                data_sum <= data_sum + 8'h06;
            end else begin
                state <= 4'b0000; // 重置状态
            end
        end
        4'b0011: begin
            rolll <= rxd_data;
            data_sum <= data_sum + rxd_data; // 计算校验和
            data_count <= data_count + 1;
            state <= 4'b0100;
        end
        4'b0100: begin
            rollh <= rxd_data;
            data_sum <= data_sum + rxd_data;
            data_count <= data_count + 1;
            state <= 4'b0101;
        end
        4'b0101: begin
            pitl <= rxd_data;
            data_sum <= data_sum + rxd_data;
            data_count <= data_count + 1;
            state <= 4'b0110;
        end
        4'b0110: begin
            pith <= rxd_data;
            data_sum <= data_sum + rxd_data;
            data_count <= data_count + 1;
            state <= 4'b0111;
        end
        4'b0111: begin
            yawl <= rxd_data;
            data_sum <= data_sum + rxd_data;
            data_count <= data_count + 1;
            state <= 4'b1000;
        end
        4'b1000: begin
            yawh <= rxd_data;
            data_sum <= data_sum + rxd_data;
            data_count <= data_count + 1;
            state <= 4'b0000;
            imuready <= 1'b1; // 数据有效
        end
        4'b1001: begin
            received_sum <= rxd_data; // 存储接收到的校验和
            //if (data_sum == received_sum) begin
            imuready <= 1'b1; // 数据有效                 
            state <= 4'b0000; // 进入结束状态
            //end
        end
        4'b1010: begin
            state <= 4'b0000; // 重置状态
        end
        default: state <= 4'b0000;
            endcase
        end
    end
end

always @(posedge clk ) begin

    if (imuready) begin
        // 合并高低字节并计算角度
        roll <= {rollh, rolll};
        pitch <= {pith, pitl};
        yaw <= {yawh, yawl};

        // 将值缩放到[-180, 180]范围
        yawo <= (yaw * 180) / 32768;    //绕z轴旋转   计算Yaw
        rolo <= (roll * 180)/ 32768;    //绕x轴旋转
        pito <= (pitch *180 )/32768;    //绕y轴旋转的是这个
        // 可以添加roll和pitch的计算
    end
end
//---------------------------------
//********************************************************************
//数据传输：从FPGA到PC。
wire enable = 1'b1;//一直发送
uart_transfer	u_uart_transfer
(
	//全局时钟
	.clk			(clk),
	.rst_n			(rst_n),
	
	//用户接口
	.clken_16bps	(clken_16bps),	//时钟波特率 * 16
	.txd			(fpga_txd),  	//UART传输接口
           
	//用户接口   
	//.txd_en			(rxd_flag),		//UART数据传输使能
    .txd_en			(rxd_flag),		//UART数据传输使能
	.txd_data		(rxd_data), 	//要传输的数据	
	.txd_flag		() 			    //UART数据传输完成标志
);
endmodule


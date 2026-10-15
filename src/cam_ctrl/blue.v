module blue (
    //全局时钟
	input				clk,                //50MHz
	input				rst,
    // input               pll_inst1_CLKOUT0,  //100MHz
    // input               pll_inst1_LOCKED,
	
	//用户接口
	input				fpga_rxd,		//从PC到FPGA的UART接收
	output				fpga_txd,		//从FPGA到PC的UART传输
    output  reg[15:0]    temp3,         //上舵机占空比输出
    output  reg[15:0]    temp4,         //下舵机占空比输出
    output  reg[15:0]    speed,         //风扇占空比输出
    // output  reg[3:0]     led_state
    output reg face_flag
);
//暂时不用锁相环
wire    clk_ref = clk;    //100MHz
wire    sys_rst_n = rst;

parameter servo1_max = 590;
parameter servo1_min = 310;
parameter servo2_max = 1090;
parameter servo2_min = 410;
parameter servo_dalta = 8'd10;

//reg [15:0] byt3e1 = (temp3 >> 8) & 0xFF; // 高8位
//reg [15:0] byt3e2 = temp3 & 0xFF;        // 低8位
//reg [15:0] byt4e1 = (temp4 >> 8) & 0xFF; // 高8位
//reg [15:0] byt4e2 = temp4 & 0xFF;        // 低8位

initial begin
    temp3 = 500;  // 初始化 temp3 为 500    对应上舵机
    temp4 = 750;  // 初始化 temp4 为 750    对应下舵机
    speed = 400;    // 如果需要，也可以初始化 speed
    //pwm = 20;
    face_flag=0;
end
//****************************************************************
//自增函数，检测是否能够传递参数
/*reg [31:0] count11;
reg div_clk;
always @(posedge clk_ref)
begin
    if(count11 == 32'd3_000_000)
    begin
        div_clk <=~div_clk;
        count11=0;
    end
    else begin
        count11 <= count11+1'd1;
    end
end

always @(posedge div_clk)begin
    if(pwm == 8'd250)
    begin
        pwm<=0;
    end
    else begin
        pwm <=pwm +1'd1;
    end
end
*/
//***************************************************************


//------------------------------------
//精确时钟分频器
wire	divide_clken;
integer_divider	
#(
	//.DEVIDE_CNT	(54)	//115200bps * 16
	.DEVIDE_CNT	(325)	//9600bps * 16
)
u_integer_devider
(
	//全局
	.clk				(clk_ref),		//50MHz时钟
	.rst_n				(sys_rst_n),    //全局复位
	
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
	.clk			(clk_ref),
	.rst_n			(sys_rst_n),
	
	//UART接口
	.clken_16bps	(clken_16bps),	//时钟波特率 * 16
	.rxd			(fpga_rxd),		//UART接收接口
	
	//用户接口
	.rxd_data		(rxd_data),		//接收到的UART数据
	.rxd_flag		(rxd_flag)  	//UART数据接收完成标志
);
//--------------------------------

reg [7:0] debug_data;
reg debug_flag;

always @(posedge clk_ref) begin
    if (rxd_flag) begin
        debug_data <= rxd_data;
        debug_flag <= 1'b1;
    end else begin
        debug_flag <= 1'b0;
    end
end

always @(posedge clk_ref) begin
    if (debug_flag) begin
        case (debug_data)
            8'd97: begin // 字母 'a'
                if (temp3 <= servo1_max)
                    temp3 <= temp3 + servo_dalta;
                else temp3 <= servo1_max;
                end
                //if(temp3 >= )
            8'd99: begin // 字母 'c'
                if (temp4 >= servo2_min)
                    temp4 <= temp4 - servo_dalta;   
                else temp4 <= servo2_min;
               end 
            8'd100: begin // 字母 'd'
                if (temp4 <= servo2_max)
                    temp4 <= temp4 + servo_dalta;   
                else temp4 <= servo2_max;
                
            end
            8'd98: begin // 字母 'b'
                if (temp3 >= servo1_min)
                    temp3 <= temp3 - servo_dalta;
                else temp3 <= servo1_min;
            end
            // 其他 case 代码省略
            8'd101:      //e
            begin
                temp3 <= 500;  // 初始化 temp3 为 500
                temp4 <= 750;  // 初始化 temp4 为 750   
            end
            8'd102:begin           //f
            speed <= speed+10;
            if(speed>700)begin
                speed <= 700;
                end
            end
            8'd103:begin          //g
            speed <= speed-10;
            if(speed<530)begin
                speed <= 530;
                end
            end
             8'd104:begin          //h
            speed <= 400;
            end
            8'd105:begin           //i
            speed <= 560;
            end

             8'd106:begin          //j,摄像头跟随开启
             face_flag <=1;
             end
             8'd107:begin          //k,摄像头跟随关闭
             face_flag <=0;
             end 
            
            
            
            
            default:begin
                //执行空指令
            
            end
        endcase
    end
end


//数据传输：从FPGA到PC。
//wire enable = 1'b1;//一直发送

uart_transfer	u_uart_transfer
(
	//全局时钟
	.clk			(clk_ref),
	.rst_n			(sys_rst_n),
	
	//用户接口
	.clken_16bps	(clken_16bps),	//时钟波特率 * 16
	.txd			(fpga_txd),  	//UART传输接口
           
	//用户接口   
	//.txd_en			(rxd_flag),		//UART数据传输使能
    .txd_en			(rxd_flag),		//UART数据传输使能
	.txd_data		(rxd_data), 	//要传输的数据	
	.txd_flag		() 			    //UART数据传输完成标志
);


endmodule //blue
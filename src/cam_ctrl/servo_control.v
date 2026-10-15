module servo_control (
    //全局时钟和复位
    input  wire clk,        //输入时钟信号   50MHz
    input  wire rst,        //复位

    //蓝牙串口接收、输出
    input  wire rx_blue,        //蓝牙信号接收
    output tx_blue,             //蓝牙信号发送

    //陀螺仪串口接收和输出
    input  wire rx_atk,        //陀螺仪信号接收
    output tx_atk,             //陀螺仪信号发送

    //控制信号的输入
    input  wire switch1,     //模式切换开关1
    input  wire switch2,     //模式切换开关2

    //摄像头舵机输入
    input   wire [15:0] temp1_cam,
    input   wire [15:0] temp2_cam,

    //PWM输出信号
    output wire pwm_out1,                   //舵机1 PWM输出
    output wire pwm_out2,                   //舵机2 PWM输出
    output wire pwm_out                     //速度控制 PWM输出
);

reg signed [15:0] temp1_gyro,temp2_gyro;      //陀螺仪模式下占空比计算
//reg signed [15:0] temp1_cam,temp2_cam;          //摄像头模式下占空比计算
wire signed [15:0] temp1_blue,temp2_blue;        //蓝牙获得的占空比
reg signed [15:0] FinalTemp1,FinalTemp2;//最终选择的占空比
wire signed [15:0] FinalSpeed;              //速度占空比
parameter SERVO_FREQ = 50;                  //舵机初始频率50Hz
parameter servo1_mid = 500;                   //舵机1初始值500
parameter servo2_mid = 750;                   //舵机2初始值750




wire face_flag;

//蓝牙模块例化
//舵机有初始化过程
blue u_blue (
    //全局时钟
	.clk(clk),                //50MHz
    .rst(rst),                //复位

	//用户接口
	.fpga_rxd(rx_blue),		//从PC到FPGA的UART接收    
	.fpga_txd(tx_blue),		//从FPGA到PC的UART传输
    .temp3(temp1_blue),     //最终上舵机的输出
    .temp4(temp2_blue),     //最终下舵机的输出
    .speed(FinalSpeed),     //风扇占空比输出
    .face_flag(face_flag)
);


//陀螺仪模块例化参数输出    
wire signed  [15:0]	yawo;   //z轴 范围±180 向左为正 90度
wire signed  [15:0]	rolo;   //x轴 没用上
wire signed  [15:0]	pito;   //y轴 范围±90 向上为负 90度

ATK u_ATK   //同时发送上位机数据到软件上位机
(
	//全局时钟
	.clk(clk),                //50MHZ
    .rst_n(rst),            //复位

    
	.fpga_rxd(rx_atk),		//从PC到FPGA的UART接收     //115200波特率
	.fpga_txd(tx_atk),		//从FPGA到PC的UART传输
    .yawo(yawo),	
    .rolo(rolo),    
    .pito(pito)
); 

// //======================================================
// //陀螺仪模式下占空比的计算
// //角度与增量的映射关系 增量=角度*3.7,取整数3 
// //控制范围：舵机1（690-970），舵机2（490-670）
// //======================================================
//对舵机的控制逻辑是根据舵机朝外的，与蓝牙的逻辑是相反的
reg [15:0] temp_val1, temp_val2;  // 位宽根据实际情况调整

always @(posedge clk , negedge rst) begin
     if (!rst) begin
         temp1_gyro <= servo1_mid;//居中
         temp2_gyro <= servo2_mid;//居中   
     end else begin
         // 上舵机的控制
         temp_val1 = servo1_mid - pito * 4;  // 使用阻塞赋值计算
         // 限幅判断
         if (temp_val1 > 590) begin
             temp1_gyro <= 590;     //上限保护
         end else if (temp_val1 < 310) begin
             temp1_gyro <= 310;     //下限保护
         end else begin
             temp1_gyro <= temp_val1; // 正常赋值
         end
         
         // 下舵机的控制
         temp_val2 = 750 + yawo * 4;  // 使用阻塞赋值计算
         // 限幅判断
         if (temp_val2 > 1050) begin
             temp2_gyro <= 1050;      // 上限保护
         end else if (temp_val2 < 410) begin
             temp2_gyro <= 410;      // 下限保护
         end else begin
             temp2_gyro <= temp_val2; // 正常赋值
         end
     end
 end
//=======================================================
//控制逻辑的选择
//=======================================================
always @( *) begin
    case ({switch1, switch2})
        2'b00: begin//模式0：默认模式
            FinalTemp1 <= servo1_mid;
            FinalTemp2 <= servo2_mid;
        end 
        2'b01: begin//模式1：陀螺仪控制模式
            FinalTemp1 <= temp1_gyro;
            FinalTemp2 <= temp2_gyro;
        end
      /*  2'b10: begin//模式2：摄像头控制模式
            FinalTemp1 <= temp1_cam;
            FinalTemp2 <= temp2_cam;
        end*/
        2'b11:begin//模式3：蓝牙控制模式
if(face_flag==1'd1)begin
            FinalTemp1 <= temp1_cam;
            FinalTemp2 <= temp2_cam;
end
        else begin
            FinalTemp1 <= temp1_blue;
            FinalTemp2 <= temp2_blue;
        end

        end
        default: begin//默认情况
            FinalTemp1 <= servo1_mid;
            FinalTemp2 <= servo2_mid;
        end
    endcase
end


//舵机1PWM生成
PWM_Generator u_servo1_pwm (
    .clk(clk),              //时钟
    .rst(rst),
    .duty_cycle({16'h0000, FinalTemp1}),          //占空比输入
    .frequency(SERVO_FREQ),         //50Hz舵机标准频率
    .PWM_OUT(pwm_out1)      //pwm输出
);

//舵机2PWM生成
PWM_Generator u_servo2_pwm (
    .clk(clk),              //时钟
    .rst(rst),
    .duty_cycle({16'h0000, FinalTemp2}),          //占空比输入
    .frequency(SERVO_FREQ),         //50Hz舵机标准频率
    .PWM_OUT(pwm_out2)      //pwm输出
);

//速度控制PWM生成
PWM_Generator u_speed_pwm (
    .clk(clk),              //时钟
    .rst(rst),
    .duty_cycle({16'h0000, FinalSpeed}),          //占空比输入
    .frequency(SERVO_FREQ),         //50Hz舵机标准频率
    .PWM_OUT(pwm_out)      //pwm输出
);

endmodule //servo_control
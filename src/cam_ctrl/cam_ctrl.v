/*
输入端口：时钟、复位、获得的x轴坐标、获得的y轴坐标（用像素点的位置代表的）、帧结束标志位
输出端口：x轴舵机的占空比、y轴舵机的占空比、x轴舵机有效信号、y轴舵机有效信号、是否跟踪信号、跟踪指令表示
连线：只要连x轴y轴舵机占空比输出和5个输入就行
*******************************************************************
最好能加一个face_valid(识别有效的信号)，
拿x、y坐标都能找到简单代替也行，
感觉我们的有没有都一样
*/


module cam_ctrl (
    input  wire clk,
    input  wire rst_n,
    input wire [10:0] face_x,         // 人脸中心X坐标输入 (0-1279)
    input wire [10:0] face_y,         // 人脸中心Y坐标输入 (0-719) 
    input  wire frame_end,
    // input  wire face_valid,
/*
    output wire servo_x_pwm,          // X轴舵机PWM输出
    output wire servo_y_pwm,          // Y轴舵机PWM输出
*/
    output reg servo_x_valid,
    output reg servo_y_valid,
    output reg tracking_active,       // 跟踪激活状态
    output reg [3:0] tracking_quality, // 跟踪质量指示

    output reg [15:0] servo_x_duty,
    output reg [15:0] servo_y_duty
);


// 图像参数定义
parameter IMG_WIDTH = 1280;
parameter IMG_HEIGHT = 720;

// X轴舵机占空比参数
parameter X_DUTY_MIN = 490;           // 最左边
parameter X_DUTY_MID = 750;           // 中间位置
parameter X_DUTY_MAX = 1090;          // 最右边
parameter X_DUTY_RANGE = X_DUTY_MAX - X_DUTY_MIN;

// Y轴舵机占空比参数  
parameter Y_DUTY_MIN = 310;           // 最低位置 (低下30°)
parameter Y_DUTY_MID = 500;           // 水平位置
parameter Y_DUTY_MAX = 590;           // 最高位置 (抬起60°)
parameter Y_DUTY_RANGE = Y_DUTY_MAX - Y_DUTY_MIN;

// 角度范围参数
parameter ANGLE_MIN = 0;              // 最小角度
parameter ANGLE_MID = 90;             // 中间角度
parameter ANGLE_MAX = 180;             // 最大角度
parameter ANGLE_RANGE = ANGLE_MAX - ANGLE_MIN;

// 跟踪状态机定义
parameter STATE_IDLE = 2'b00;
parameter STATE_TRACKING = 2'b01;
parameter STATE_LOST = 2'b10;


// 舵机PWM参数
parameter SERVO_FREQUENCY = 50;       // 舵机PWM频率50Hz
parameter PWM_SCALE = 10000;          // PWM占空比缩放因子


reg [1:0] state;
reg [3:0] lost_counter;              // 丢失计数器
reg [3:0] tracking_counter;          // 跟踪计数器

// 目标角度寄存器
reg [10:0] target_x_angle;
reg [10:0] target_y_angle;
reg [10:0] current_x_angle;
reg [10:0] current_y_angle;




// PWM占空比转换（0-10000范围）
// wire [31:0] servo_x_duty_pwm = servo_x_duty * PWM_SCALE;  // 转换为0-10000范围
// wire [31:0] servo_y_duty_pwm = servo_y_duty * PWM_SCALE;  // 转换为0-10000范围


// 坐标映射函数 - 将显示屏坐标映射到舵机角度
function [10:0] map_coord_to_angle;
    input [10:0] coord;
    input is_x_axis;
    begin
        if (is_x_axis) begin
            // X坐标: 0-1279 -> 0-180度
            map_coord_to_angle = (coord * ANGLE_RANGE) / IMG_WIDTH;
        end else begin
            // Y坐标: 0-719 -> 0-180度
            map_coord_to_angle = 180 - (coord * ANGLE_RANGE) / IMG_HEIGHT;
        end
    end
endfunction

// 角度到占空比转换函数 - 线性映射
// 这个里面的0-180度不代表真的度数，只是一个换算比例
function [10:0] angle_to_duty;
    input [10:0] angle;
    input is_x_axis;
    begin
        if (is_x_axis) begin
            // X轴: 角度0-180 -> 占空比490-1090
            angle_to_duty = X_DUTY_MIN + angle * X_DUTY_RANGE / ANGLE_RANGE;
//            if (angle <= ANGLE_MID) begin
//                 0-90度: 490-750 (线性)
//                angle_to_duty = X_DUTY_MIN + ((angle * (X_DUTY_MID - X_DUTY_MIN) + ANGLE_MID/2) / ANGLE_MID);
            
//            end else begin
//                 90-180度: 750-1090 (线性)
//                angle_to_duty = X_DUTY_MID + (((angle - ANGLE_MID) * (X_DUTY_MAX - X_DUTY_MID) + ANGLE_MID/2) / ANGLE_MID);
//            end
        end else begin
            // Y轴: 角度0-180 -> 占空比310-590
            angle_to_duty = Y_DUTY_MIN + angle * Y_DUTY_RANGE / ANGLE_RANGE;
//            if (angle <= ANGLE_MID) begin
//                 0-90度: 310-500 (低下30°到水平)
//                angle_to_duty = Y_DUTY_MIN + ((angle * (Y_DUTY_MID - Y_DUTY_MIN)) / ANGLE_MID);
//            end else begin
//                 90-180度: 500-590 (水平到抬起60°)
//                angle_to_duty = Y_DUTY_MID + (((angle - ANGLE_MID) * (Y_DUTY_MAX - Y_DUTY_MID)) / ANGLE_MID);
//            end
        end
    end
endfunction

// 角度边界限制函数
function [10:0] limit_angle;
    input [10:0] angle;
    begin
        if (angle < ANGLE_MIN) 
            limit_angle = ANGLE_MIN;
        else if (angle > ANGLE_MAX) 
            limit_angle = ANGLE_MAX;
        else 
            limit_angle = angle;
    end
endfunction

// 占空比边界限制函数
function [10:0] limit_duty;
    input [10:0] duty;
    input is_x_axis;
    begin
        if (is_x_axis) begin
            if (duty < X_DUTY_MIN) 
                limit_duty = X_DUTY_MIN;
            else if (duty > X_DUTY_MAX) 
                limit_duty = X_DUTY_MAX;
            else 
                limit_duty = duty;
        end else begin
            if (duty < Y_DUTY_MIN) 
                limit_duty = Y_DUTY_MIN;
            else if (duty > Y_DUTY_MAX) 
                limit_duty = Y_DUTY_MAX;
            else 
                limit_duty = duty;
        end
    end
endfunction

parameter face_valid = 1;

// 跟踪部分
// 角度增量参数 - 平滑移动步长
parameter ANGLE_DELTA = 5;

// 跟踪状态机和舵机控制逻辑合并到一个always块中
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state <= STATE_IDLE;
        lost_counter <= 0;
        tracking_counter <= 0;
        tracking_active <= 0;
        tracking_quality <= 0;
        target_x_angle <= ANGLE_MID;
        target_y_angle <= ANGLE_MID;
        current_x_angle <= ANGLE_MID;
        current_y_angle <= ANGLE_MID;
        servo_x_duty <= X_DUTY_MID;
        servo_y_duty <= Y_DUTY_MID;
        servo_x_valid <= 0;
        servo_y_valid <= 0;
    end else if (frame_end) begin
        // 状态机逻辑
        case (state)
            STATE_IDLE: begin
                if (face_valid) begin
                    state <= STATE_TRACKING;
                    tracking_counter <= 1;
                    tracking_active <= 1;
                    tracking_quality <= 1;
                end
            end
            
            STATE_TRACKING: begin
                if (face_valid) begin
                    // 持续跟踪，增加跟踪质量
                    if (tracking_counter < 15) 
                        tracking_counter <= tracking_counter + 1;
                    
                    if (tracking_quality < 15 && tracking_counter > 3)
                        tracking_quality <= tracking_quality + 1;
                    
                    lost_counter <= 0;
                    
                    // 计算目标角度（带边界限制）
                    target_x_angle <= limit_angle(map_coord_to_angle(face_x, 1));
                    target_y_angle <= limit_angle(map_coord_to_angle(face_y, 0));
                end else begin
                    // 丢失目标
                    lost_counter <= lost_counter + 1;
                    if (lost_counter > 7) begin  // 连续8帧丢失
                        state <= STATE_LOST;
                        tracking_active <= 0;
                        tracking_quality <= 0;
                    end
                end
            end
            
            STATE_LOST: begin
                if (face_valid) begin
                    // 重新检测到目标
                    state <= STATE_TRACKING;
                    tracking_counter <= 1;
                    tracking_active <= 1;
                    tracking_quality <= 1;
                    lost_counter <= 0;
                end else begin
                    // 目标丢失，设置目标角度为中间位置
                    target_x_angle <= ANGLE_MID;
                    target_y_angle <= ANGLE_MID;
                end
            end
        endcase
        
        // 舵机控制逻辑
        if (state == STATE_TRACKING && face_valid) begin
        // 平滑移动 - 防止舵机抖动，添加精确停止判断
        if (current_x_angle != target_x_angle) begin
            if (current_x_angle < target_x_angle) 
                current_x_angle <= (target_x_angle - current_x_angle <= ANGLE_DELTA) ? target_x_angle : current_x_angle + ANGLE_DELTA;
            else 
                current_x_angle <= (current_x_angle - target_x_angle <= ANGLE_DELTA) ? target_x_angle : current_x_angle - ANGLE_DELTA;
            
            // 转换角度为占空比
            servo_x_duty <= limit_duty(angle_to_duty(current_x_angle, 1), 1) + 80;
            servo_x_valid <= 1;
        end else begin
            servo_x_valid <= 0;
        end
            
            if (current_y_angle != target_y_angle) begin
                if (current_y_angle < target_y_angle) 
                    current_y_angle <= current_y_angle + ANGLE_DELTA;
                else 
                    current_y_angle <= current_y_angle - ANGLE_DELTA;
                
                // 转换角度为占空比
                servo_y_duty <= limit_duty(angle_to_duty(current_y_angle, 0), 0) + 100;
                servo_y_valid <= 1;
            end else begin
                servo_y_valid <= 0;
            end
        end else if (state == STATE_LOST) begin
            // 目标丢失，缓慢回到中心位置
            if (current_x_angle != ANGLE_MID) begin
                if (current_x_angle < ANGLE_MID) 
                    current_x_angle <= current_x_angle + ANGLE_DELTA;
                else 
                    current_x_angle <= current_x_angle - ANGLE_DELTA;
                
                servo_x_duty <= limit_duty(angle_to_duty(current_x_angle, 1), 1) + 80;
                servo_x_valid <= 1;
            end else begin
                servo_x_valid <= 0;
            end
            
            if (current_y_angle != ANGLE_MID) begin
                if (current_y_angle < ANGLE_MID) 
                    current_y_angle <= current_y_angle + ANGLE_DELTA;
                else 
                    current_y_angle <= current_y_angle - ANGLE_DELTA;
                
                servo_y_duty <= limit_duty(angle_to_duty(current_y_angle, 0), 0) + 100;
                servo_y_valid <= 1;
            end else begin
                servo_y_valid <= 0;
            end
        end else begin
            servo_x_valid <= 0;
            servo_y_valid <= 0;
        end
    end
end

/*
// PWM生成器实例化
PWM_Generator u_pwm_x (
    .clk(clk),
    .rst(rst_n),                    // PWM模块使用高电平复位
    .duty_cycle(servo_x_duty),   // 占空比输入
    .frequency(SERVO_FREQUENCY),     // 50Hz频率
    .PWM_OUT(servo_x_pwm)            // PWM输出
);


PWM_Generator u_pwm_y (
    .clk(clk),
    .rst(rst_n),                    // PWM模块使用高电平复位
    .duty_cycle(servo_y_duty),   // 占空比输入
    .frequency(SERVO_FREQUENCY),     // 50Hz频率
    .PWM_OUT(servo_y_pwm)            // PWM输出
);

*/
endmodule //cam_ctrl
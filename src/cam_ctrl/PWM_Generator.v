module PWM_Generator (
    input clk,                    //时钟信号  50MHz
    input rst,                  //清零信号，低电平有效
    input [31:0] duty_cycle,             //占空比，范围 0-100000
    input [31:0] frequency,              //目标频率（单位：Hz）
    output reg PWM_OUT                 //pwm输出信号
    
);

reg [31:0] CNT;             //计数器
reg [31:0] period;          //计算得到的周期
parameter CLOCK_FREQ = 50_000_000;   //时钟频率 

//根据输入的目标频率计算周期
always @( *) begin
    if (frequency > 0 ) begin
        
        period = CLOCK_FREQ / frequency;//计算对应频率的周期
        
    end else begin
        period = 1;
    end
end

//PWM产生逻辑
always @(posedge clk) begin
    //计数器递增并处理溢出
    if (CNT < period - 1) begin
        
        CNT <= CNT + 1;

    end else begin
        CNT <= 32'b0;
    end

    //根据计数器和占空比设置 PWM 输出
    if (CNT < (duty_cycle * period) / 10000) begin
        PWM_OUT <= 1'b1;   
    end else begin
        PWM_OUT <= 1'b0;
    end
end

endmodule //PWM_Generator
module integer_divider 
#(
	parameter		DEVIDE_CNT = 16'd651	//9600bps * 16
)
(
    input  wire clk,        //50MHz时钟
    input  wire rst_n,      //低电平复位

    output wire divide_clken 

);
//计数器逻辑实现分频
reg	[31:0]	cnt;
always@(posedge clk or negedge rst_n)
begin
	if(!rst_n)
		cnt <= 0;
	else
		cnt <= (cnt < DEVIDE_CNT - 1'b1) ? cnt + 1'b1 : 16'd0;		
end

assign divide_clken = (cnt == DEVIDE_CNT - 1'b1) ? 1'b1 : 1'b0;

endmodule //integer_divider
`timescale 1ns / 1ps

module Gemm#(
	parameter WeightMemAddr = 64'h0,
	parameter ShareMemAddr0 = 64'h200,
	parameter ShareMemAddr1 = 64'h400
)(
	input  clk,
	input  rstn,
	
	input  [9:0] Height_i,
	input  [9:0] Channels_i,
	input  CoreEnable_i,
	input  AccuEn_i,
	
	input  Req_i,
	output reg Ack_o,
	
	output reg [63:0] AvalonAddr_o,
	output reg AvalonRead_o,
	output reg AvalonWrite_o,
	output wire [63:0] AvalonByteEnable_o,
	output reg [511:0] AvalonWriteData_o,
	input   [511:0] AvalonReadData_i,
	
	output AvalonLock_o,
	input  AvalonWaitReq_i
);
	localparam 	IDLE  = 5'd0,  
				RDWT  = 5'd1,  
				NONE0 = 5'd2,  NONE1 = 5'd3,  NONE2 = 5'd4, 
				NONE3 = 5'd5,  NONE4 = 5'd6,  NONE5 = 5'd7, 
				NONE6 = 5'd8,  NONE7 = 5'd9,  NONE8 = 5'd10, 
				CONV0 = 5'd11, CONV1 = 5'd12, CONV2 = 5'd13, CONV3 = 5'd14, 
				CONV4 = 5'd15, CONV5 = 5'd16, CONV6 = 5'd17, CONV7 = 5'd18, 
				CONV8 = 5'd19, CONV9 = 5'd20, CONVa = 5'd21, CONVb = 5'd22, 
				CONVc = 5'd23, CONVd = 5'd24, CONVe = 5'd25, CONVf = 5'd26,
				WRFM  = 5'd27, 
				WAIT  = 5'd28,
				SKIP  = 5'd29,
				FINAL = 5'd30; 
	reg [4: 0] state;
	reg [9: 0] height, in_height, out_height, channels_cnt;
	reg [511: 0] in_data, weight;
	wire [31:0]out_data;
	wire equ_in_height  = in_height  == height;
	wire equ_out_height = out_height == height[9:4]*(channels_cnt+1'b1);
	wire equ_channels = channels_cnt == WeightMemAddr + Channels_i - 1'b1;
	wire start = (Req_i&&CoreEnable_i);
	wire enable_i = ~(AvalonWrite_o || AvalonWaitReq_i);
	assign AvalonByteEnable_o = {64{1'b1}};
	assign AvalonLock_o = AvalonRead_o|AvalonWrite_o;

	always@(posedge clk)begin
		if(~rstn)
            state <= IDLE;
        else case(state)
            IDLE : state <= start? RDWT: IDLE;
            RDWT : state <= AvalonWaitReq_i? RDWT: NONE0;
			NONE0: state <= AvalonWaitReq_i? NONE0: NONE1;
            NONE1: state <= AvalonWaitReq_i? NONE1: NONE2;
            NONE2: state <= AvalonWaitReq_i? NONE2: NONE3;
            NONE3: state <= AvalonWaitReq_i? NONE3: NONE4;
            NONE4: state <= AvalonWaitReq_i? NONE4: NONE5;
            NONE5: state <= AvalonWaitReq_i? NONE5: NONE6;
			NONE6: state <= AvalonWaitReq_i? NONE6: NONE7;
			NONE7: state <= AvalonWaitReq_i? NONE7: NONE8;
			NONE8: state <= AvalonWaitReq_i? NONE8: CONV0;
            CONV0: state <= AvalonWaitReq_i? CONV0: CONV1;
            CONV1: state <= AvalonWaitReq_i? CONV1: CONV2;
            CONV2: state <= AvalonWaitReq_i? CONV2: CONV3;
            CONV3: state <= AvalonWaitReq_i? CONV3: CONV4;
            CONV4: state <= AvalonWaitReq_i? CONV4: CONV5;
            CONV5: state <= AvalonWaitReq_i? CONV5: CONV6;
            CONV6: state <= AvalonWaitReq_i? CONV6: CONV7;
            CONV7: state <= AvalonWaitReq_i? CONV7: CONV8;
            CONV8: state <= AvalonWaitReq_i? CONV8: CONV9;
            CONV9: state <= AvalonWaitReq_i? CONV9: CONVa;
            CONVa: state <= AvalonWaitReq_i? CONVa: CONVb;
            CONVb: state <= AvalonWaitReq_i? CONVb: CONVc;
            CONVc: state <= AvalonWaitReq_i? CONVc: CONVd;
            CONVd: state <= AvalonWaitReq_i? CONVd: CONVe;
            CONVe: state <= AvalonWaitReq_i? CONVe: CONVf;
            CONVf: state <= AvalonWaitReq_i? CONVf: WRFM;
            WRFM : state <= AvalonWaitReq_i? WRFM : WAIT;
			WAIT : state <= AvalonWaitReq_i? WRFM :(equ_out_height? (equ_channels? FINAL:SKIP): CONV0);
			SKIP : state <= AvalonWaitReq_i? SKIP : RDWT;
			FINAL: state <= AvalonWaitReq_i? FINAL: IDLE;
            default: state <= IDLE;
        endcase
	
		case(state) 
			IDLE : 
				height <= start? {(Height_i[9: 4]+(Height_i[3: 0]!=4'h0)), 4'h0}: 0;
			default: height <= height;
		endcase
	
		//count height
		case(state)
			IDLE: begin
				in_height  <= ShareMemAddr0;
				out_height <= ShareMemAddr1;
			end
			SKIP:
				in_height  <= ShareMemAddr0;
			RDWT,
			NONE0, NONE1, NONE2,
			NONE3, NONE4, NONE5,
			NONE6, NONE7, NONE8, WAIT:
				in_height  <= AvalonWaitReq_i? in_height :(equ_in_height?in_height : in_height+1'b1);
			CONV0, CONV1, CONV2, CONV3, 
			CONV4, CONV5, CONV6, CONV7, 
			CONV8, CONV9, CONVa, CONVb, 
			CONVc, CONVd, WRFM:
				in_height  <= AvalonWaitReq_i? in_height :(equ_in_height?in_height : in_height+1'b1);
			CONVf: 
				out_height <= AvalonWaitReq_i? out_height:out_height+1'b1;
			default: begin
				in_height  <= in_height;
				out_height <= out_height;
			end
		endcase
		
		//count channels
		case(state)
			IDLE : channels_cnt <= WeightMemAddr;
			WAIT : channels_cnt <= AvalonWaitReq_i? channels_cnt :(equ_out_height? (equ_channels? channels_cnt:channels_cnt+1'b1): channels_cnt);
			default: channels_cnt <= channels_cnt;
		endcase
		
		//AvalonAddr_o
		case(state)
			IDLE, SKIP: AvalonAddr_o <= channels_cnt;
			RDWT, 
			NONE0, NONE1, NONE2, 
			NONE3, NONE4, NONE5,
			NONE6, NONE7, NONE8,
			CONV0, CONV1, CONV2, CONV3, 
			CONV4, CONV5, CONV6, CONV7, 
			CONV8, CONV9, CONVa, CONVb, 
			CONVc, CONVd, CONVe, WAIT: 
				AvalonAddr_o <= in_height;
			CONVf: AvalonAddr_o <= AccuEn_i?out_height+{1'b1,63'b0}: out_height;
			WRFM : AvalonAddr_o <= AvalonWaitReq_i?AvalonAddr_o: in_height;
			default: AvalonAddr_o <= AvalonAddr_o;
		endcase
	
		//AvalonRead_o
		case(state)
			IDLE: AvalonRead_o <= start? 1'b1: 1'b0; 
			SKIP , RDWT ,
			NONE0, NONE1, NONE2, 
			NONE3, NONE4, NONE5,
			NONE6, NONE7, NONE8,
			CONV0, CONV1, CONV2, CONV3, 
			CONV4, CONV5, CONV6, CONV7, 
			CONV8, CONV9, CONVa, CONVb, 
			CONVc, CONVd: 
				AvalonRead_o <= 1'b1;
			WRFM, WAIT:
				AvalonRead_o <= AvalonWaitReq_i?1'b0 : (equ_in_height? 1'b0: 1'b1);
			default: AvalonRead_o <= 0;
		endcase
		
		//weight
		case(state)
			IDLE, SKIP: weight <= 0; 
			NONE0: weight <= AvalonWaitReq_i? weight : AvalonReadData_i;
			default: weight <= weight;
      endcase
		
		//input data
		case(state)
			IDLE, SKIP: in_data <= 0;
			NONE1, NONE2, 
			NONE3, NONE4, NONE5,
			NONE6, NONE7, NONE8,
			CONV0, CONV1, CONV2, CONV3, 
			CONV4, CONV5, CONV6, CONV7, 
			CONV8, CONV9, CONVa, CONVb, 
			CONVc, CONVd, CONVe, CONVf: 
				in_data <= AvalonWaitReq_i? in_data : AvalonReadData_i;
			default: in_data <= in_data;
		endcase
		
		//output data
		if(AvalonWaitReq_i)
			AvalonWriteData_o <= AvalonWriteData_o;
		else case(state)
				IDLE, RDWT, SKIP: AvalonWriteData_o <= 0;
				CONV0: AvalonWriteData_o[32* 0 +: 32] <= out_data;
				CONV1: AvalonWriteData_o[32* 1 +: 32] <= out_data;
				CONV2: AvalonWriteData_o[32* 2 +: 32] <= out_data;
				CONV3: AvalonWriteData_o[32* 3 +: 32] <= out_data;
				CONV4: AvalonWriteData_o[32* 4 +: 32] <= out_data;
				CONV5: AvalonWriteData_o[32* 5 +: 32] <= out_data;
				CONV6: AvalonWriteData_o[32* 6 +: 32] <= out_data;
				CONV7: AvalonWriteData_o[32* 7 +: 32] <= out_data;
				CONV8: AvalonWriteData_o[32* 8 +: 32] <= out_data;
				CONV9: AvalonWriteData_o[32* 9 +: 32] <= out_data;
				CONVa: AvalonWriteData_o[32*10 +: 32] <= out_data;
				CONVb: AvalonWriteData_o[32*11 +: 32] <= out_data;
				CONVc: AvalonWriteData_o[32*12 +: 32] <= out_data;
				CONVd: AvalonWriteData_o[32*13 +: 32] <= out_data;
				CONVe: AvalonWriteData_o[32*14 +: 32] <= out_data;
				CONVf: AvalonWriteData_o[32*15 +: 32] <= out_data;
				default: AvalonWriteData_o <= AvalonWriteData_o; 
			endcase
		
		//AvalonWrite_o
		case(state)
			CONVf: AvalonWrite_o <= 1'b1;
			WRFM : AvalonWrite_o <= AvalonWaitReq_i?1'b1:1'b0;
			default: AvalonWrite_o <= 1'b0;
		endcase
		
		//Ack_o
		case(state)
			IDLE : Ack_o <= 0;
			FINAL: Ack_o <= 1;
			default: Ack_o <= Ack_o;
		endcase
	end
	
	mac_new mac_inst(
        .clk(clk),
        .rstn(rstn),
        .enable_i(enable_i),
        .weight(weight),
        .in_data(in_data),
        
        .out_data(out_data)
    );
	
endmodule
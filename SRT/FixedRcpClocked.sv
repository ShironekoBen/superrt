`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Clocked version of FixedRcp, latency 4 cycles, throughput 1 cycle

`default_nettype none

import Maths::*;

localparam signed [31:0] onePointFive = 32'sh00006000; // 1.5f in fixed point

module FixedRcpClocked(
	input wire clock,
	input wire signed [31:0] rcpIn, // Input
	output wire signed [31:0] result); // Result

// Cycle 1
always @(posedge clock) begin
	reg signed [31:0] absRcpIn;

	c2_signBit <= rcpIn[31];

	// Strip sign
	absRcpIn = rcpIn[31] ? (-rcpIn) : rcpIn;
	
	c2_absRcpIn <= absRcpIn;

	// First-guess lookup based on number of leading zeroes

	if (absRcpIn[30]) c2_sqrtFirstGuess <= 32'sh00000034;
	else if (absRcpIn[29]) c2_sqrtFirstGuess <= 32'sh00000049;
	else if (absRcpIn[28]) c2_sqrtFirstGuess <= 32'sh00000068;
	else if (absRcpIn[27]) c2_sqrtFirstGuess <= 32'sh00000093;
	else if (absRcpIn[26]) c2_sqrtFirstGuess <= 32'sh000000d1;
	else if (absRcpIn[25]) c2_sqrtFirstGuess <= 32'sh00000127;
	else if (absRcpIn[24]) c2_sqrtFirstGuess <= 32'sh000001a2;
	else if (absRcpIn[23]) c2_sqrtFirstGuess <= 32'sh0000024f;
	else if (absRcpIn[22]) c2_sqrtFirstGuess <= 32'sh00000344;
	else if (absRcpIn[21]) c2_sqrtFirstGuess <= 32'sh0000049e;
	else if (absRcpIn[20]) c2_sqrtFirstGuess <= 32'sh00000688;
	else if (absRcpIn[19]) c2_sqrtFirstGuess <= 32'sh0000093c;
	else if (absRcpIn[18]) c2_sqrtFirstGuess <= 32'sh00000d10;
	else if (absRcpIn[17]) c2_sqrtFirstGuess <= 32'sh00001279;
	else if (absRcpIn[16]) c2_sqrtFirstGuess <= 32'sh00001a20;
	else if (absRcpIn[15]) c2_sqrtFirstGuess <= 32'sh000024f3;
	else if (absRcpIn[14]) c2_sqrtFirstGuess <= 32'sh00003441;
	else if (absRcpIn[13]) c2_sqrtFirstGuess <= 32'sh000049e6;
	else if (absRcpIn[12]) c2_sqrtFirstGuess <= 32'sh00006882;
	else if (absRcpIn[11]) c2_sqrtFirstGuess <= 32'sh000093cd;
	else if (absRcpIn[10]) c2_sqrtFirstGuess <= 32'sh0000d105;
	else if (absRcpIn[9]) c2_sqrtFirstGuess <= 32'sh0001279a;
	else if (absRcpIn[8]) c2_sqrtFirstGuess <= 32'sh0001a20b;
	else if (absRcpIn[7]) c2_sqrtFirstGuess <= 32'sh00024f34;
	else if (absRcpIn[6]) c2_sqrtFirstGuess <= 32'sh00034417;
	else if (absRcpIn[5]) c2_sqrtFirstGuess <= 32'sh00049e69;
	else if (absRcpIn[4]) c2_sqrtFirstGuess <= 32'sh0006882f;
	else if (absRcpIn[3]) c2_sqrtFirstGuess <= 32'sh00093cd3;
	else if (absRcpIn[2]) c2_sqrtFirstGuess <= 32'sh000d105e;
	else if (absRcpIn[1]) c2_sqrtFirstGuess <= 32'sh001279a7;
	else c2_sqrtFirstGuess <= 32'sh00200000;
	
	c2_inputZero <= (rcpIn == 32'h0);
end

reg signed [31:0] c2_absRcpIn;
reg signed [31:0] c2_sqrtFirstGuess; // First guess (table-based)
reg c2_signBit; // Sign bit of source
reg c2_inputZero; // Was the input zero?

// Cycle 2
always @(posedge clock) begin
	// Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))

	// First iteration	
	c3_sqrtIntermediate <= FixedMul(c2_sqrtFirstGuess, onePointFive - FixedMul(c2_absRcpIn >> 1, FixedMul(c2_sqrtFirstGuess, c2_sqrtFirstGuess)));

	c3_signBit <= c2_signBit;
	c3_inputZero <= c2_inputZero;
	c3_absRcpIn <= c2_absRcpIn;
end

reg c3_signBit;
reg c3_inputZero;
reg signed [31:0] c3_absRcpIn;
reg signed [31:0] c3_sqrtIntermediate; // Result of first Newton iteration

// Cycle 3
always @(posedge clock) begin
	// Second iteration
	c4_sqrtRcpResult <= FixedMul(c3_sqrtIntermediate, onePointFive - FixedMul(c3_absRcpIn >> 1, FixedMul(c3_sqrtIntermediate, c3_sqrtIntermediate)));

	c4_signBit <= c3_signBit;
	c4_inputZero <= c3_inputZero;
end

reg c4_signBit;
reg c4_inputZero;
reg signed [31:0] c4_sqrtRcpResult; // Result of second Newton iteration

// Cycle 4
always @(posedge clock) begin
	reg signed [31:0] absResult;
	
	// Convert 1/sqrt(x) to 1/x
	absResult = FixedMul(c4_sqrtRcpResult, c4_sqrtRcpResult);
	
	if (c4_inputZero) begin
		result <= 32'h7FFFFFFF; // Return largest possible number for 0
	end else begin
		// Reapply sign
		result <= c4_signBit ? (-absResult) : absResult;
	end	
end
	
endmodule
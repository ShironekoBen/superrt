`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Manage debug display stuff

// Number of systems we want to display debug data for
`define NUM_SYSTEMS 4

module DebugManager(
	input wire clock,
	input wire reset,
	
	// Joypad input
	input wire inJoypadUp_tick,
	input wire inJoypadDown_tick,
	
	// System status
	input wire [7:0] statusInfo,
	
	// System debug values
	input wire [63:0] inDebugA[`NUM_SYSTEMS - 1: 0],
	input wire [63:0] inDebugB[`NUM_SYSTEMS - 1: 0],
	input wire [63:0] inDebugC[`NUM_SYSTEMS - 1: 0],
	input wire [63:0] inDebugD[`NUM_SYSTEMS - 1: 0],
	
	// Outputs
	output wire [63:0] outDebugA,
	output wire [63:0] outDebugB,
	output wire [63:0] outDebugC,
	output wire [63:0] outDebugD,
	output wire [63:0] outDebugE
);

// System selection

reg [3:0] selectedSystem;

always @(posedge clock) begin
	if (reset) begin
		selectedSystem <= 0;
	end else begin
		if (inJoypadUp_tick) begin
			selectedSystem <= (selectedSystem < (`NUM_SYSTEMS - 1)) ? (selectedSystem + 1) : selectedSystem;
		end else if (inJoypadDown_tick) begin
			selectedSystem <= (selectedSystem > 0) ? (selectedSystem - 1) : 0;
		end
	end
end

// Status display

assign outDebugA = { 8'(selectedSystem), 48'h0, statusInfo };

// Multiplexer

always @(*) begin
	outDebugB = inDebugA[selectedSystem];
	outDebugC = inDebugB[selectedSystem];
	outDebugD = inDebugC[selectedSystem];
	outDebugE = inDebugD[selectedSystem];
end

endmodule
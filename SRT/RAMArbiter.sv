`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Arbitrate RAM access between multiple subsystems

module RAMArbiter(
	// HDMI scanout
	input wire scanoutEnable,
	input wire [15:0] scanoutAddr,
	output wire [31:0] scanoutData,
	
	// Renderer (guaranteed not to clash with PPU converter)
	output wire rendererOK,
	input wire rendererEnable,
	input wire [15:0] rendererAddr,
	input wire [31:0] rendererData,
	
	// PPU converter (guaranteed not to clash with renderer)
	output wire ppuConverterOK,
	input wire ppuConverterActive,
	input wire [15:0] ppuConverterAddr,
	output wire [31:0] ppuConverterData,

	// Connection to actual RAM module
	output wire [15:0] ramAddr,
	input wire [31:0] ramDataRead,
	output wire [31:0] ramDataWrite,
	output wire ramWriteEnable
);

// Scanout gets priority over the renderer

assign ramAddr = scanoutEnable ? scanoutAddr : (ppuConverterActive ? ppuConverterAddr : rendererAddr);
assign scanoutData = ramDataRead;
assign ppuConverterData = ramDataRead;
assign ramDataWrite = rendererData;
assign ramWriteEnable = scanoutEnable ? 1'b0 : rendererEnable;
assign rendererOK = (~scanoutEnable) && (~ppuConverterActive);
assign ppuConverterOK = ~scanoutEnable;

endmodule
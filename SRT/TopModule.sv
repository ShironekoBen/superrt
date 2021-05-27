`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// This is the main module

`default_nettype none

module SRT(
	input wire clock,
	input wire reset_n,
	output wire [7:0] led,
	input wire switchR, switchG, switchB,
	input wire key0_n, key1_n,
	
	// SNES cartridge bus
	input wire [15:0] cartAddressBus,
	input wire cartCS_n, // ROM chip select signal from SNES (aka RD from cart bus)
	input wire cartOE_n, // ROM output enable signal from SNES
	output wire [7:0] cartDataBus,
	output wire cartDataBusOE_n
	
`ifdef ENABLE_DEBUG_DISPLAY
	,
	// Megadrive pad
	input wire joypadUp,
	input wire joypadDown,
	
  // ********************************** //
  // ** HDMI CONNECTIONS **

  // AUDIO
  // SPDIF va desconectado
  output wire HDMI_I2S0,  // dont care, no se usan
  output wire HDMI_MCLK,  // dont care, no se usan
  output wire HDMI_LRCLK, // dont care, no se usan
  output wire HDMI_SCLK,   // dont care, no se usan

  // VIDEO
  output wire [23:0] HDMI_TX_D, // RGBchannel
  output wire HDMI_TX_VS,  // vsync
  output wire HDMI_TX_HS,  // hsync
  output wire HDMI_TX_DE,  // dataEnable
  output wire HDMI_TX_CLK, // vgaClock

  // REGISTERS AND CONFIG LOGIC
  // HPD viene del conector
  input wire HDMI_TX_INT,
  inout wire HDMI_I2C_SDA,  // HDMI i2c data
  output wire HDMI_I2C_SCL // HDMI i2c clock
`endif
);

import Maths::*;

`ifdef ENABLE_DEBUG_DISPLAY	
wire hdmiClock; // 25Mhz for HDMI output
`endif
wire romClock; // 100Mhz for SNES cart interface
wire pllLocked;
`ifdef ENABLE_DEBUG_DISPLAY	
wire hdmiDataEnable;
`endif
reg reset;
reg key0;
reg key1;
`ifdef ENABLE_DEBUG_DISPLAY	
assign HDMI_TX_DE = hdmiDataEnable;
`endif

always @(*) begin
	reset = ~reset_n;
	key0 = ~key0_n;
	key1 = ~key1_n;
end

`ifdef ENABLE_DEBUG_DISPLAY	
// Overall debug display registers

reg [63:0] debugA[3:0];
reg [63:0] debugB[3:0];
reg [63:0] debugC[3:0];
reg [63:0] debugD[3:0];

// Output debug display registers

reg [63:0] displayDebugA;
reg [63:0] displayDebugB;
reg [63:0] displayDebugC;
reg [63:0] displayDebugD;
reg [63:0] displayDebugE;
`endif

// PLL
MainPLL MainPLL_inst(
  .refclk(clock),
  .rst(reset),

  .outclk_0(romClock), // 100Mhz for SNES cart interface
`ifdef ENABLE_DEBUG_DISPLAY	  
  .outclk_1(hdmiClock), // 25Mhz for HDMI output
`endif
  .locked(pllLocked)
);

// Flow controller

// Triggered from the SNES to request a new frame (note: may be ignored if a frame is already in progress)
wire startRequest_tick_romClock;
wire startRequest_tick;

// Triggered when a new frame starts
wire frameStart_tick;
wire frameStart_tick_romClock;

// Renderer start/done
wire startRenderer_tick;
wire rendererDone_tick;
wire startPPUConverter_tick;

// PPU converter start/done
wire ppuConverterDone_tick;
wire startPPUConverter_tick_romClock;
wire ppuConverterDone_tick_romClock;

// Marshal ticks across clock domains
ClockDomainTickMarshaller startRequest_tick_marshaller(
	.inClock(romClock),
	.outClock(clock),
	.reset(reset),
	.inTick(startRequest_tick_romClock),
	.outTick(startRequest_tick)
);

ClockDomainTickMarshaller frameStart_tick_marshaller(
	.inClock(clock),
	.outClock(romClock),
	.reset(reset),
	.inTick(frameStart_tick),
	.outTick(frameStart_tick_romClock)
);

ClockDomainTickMarshaller startPPUConverter_tick_marshaller(
	.inClock(clock),
	.outClock(romClock),
	.reset(reset),
	.inTick(startPPUConverter_tick),
	.outTick(startPPUConverter_tick_romClock)
);

ClockDomainTickMarshaller ppuConverterDone_tick_marshaller(
	.inClock(romClock),
	.outClock(clock),
	.reset(reset),
	.inTick(ppuConverterDone_tick_romClock),
	.outTick(ppuConverterDone_tick)
);

// Overall system status

reg [7:0] statusInfo; // Status information register (exposed to SNES)

// Bit 0 = Renderer busy flag
// Bits 1-7 = Unused (zero)

always @(*) begin
	statusInfo = { 7'h0, renderFlowControllerBusy};
end

`ifdef ENABLE_DEBUG_DISPLAY
// Performance counters

reg [31:0] lastTotalCycleCount;
reg [31:0] lastRenderCycleCount;
reg [31:0] lastPPUConversionCycleCount;

// Show performance counters on flow controller debug display
assign debugC[0] = { 32'h0, lastTotalCycleCount };
assign debugD[0] = { lastRenderCycleCount, lastPPUConversionCycleCount };
`endif

wire renderFlowControllerBusy;

// Main flow controller
RenderFlowController RenderFlowController_inst(
	// Fundamentals
	.reset(reset),
	.clock(clock),
	
	// Main trigger
	.startRequest_tick(startRequest_tick),
	
	// Sub-triggers
	.frameStart_tick(frameStart_tick),
	.startRenderer_tick(startRenderer_tick),
	.rendererDone_tick(rendererDone_tick),
	.startPPUConverter_tick(startPPUConverter_tick),
	.ppuConverterDone_tick(ppuConverterDone_tick),	

`ifdef ENABLE_DEBUG_DISPLAY	
	// Performance
	.lastTotalCycleCount(lastTotalCycleCount),
	.lastRenderCycleCount(lastRenderCycleCount),
	.lastPPUConversionCycleCount(lastPPUConversionCycleCount),
`endif
	
	// Status
	.busy(renderFlowControllerBusy),
	
`ifdef ENABLE_DEBUG_DISPLAY
	// Debug
	.debug(debugA[0])
`endif
);


`ifdef ENABLE_DEBUG_DISPLAY
// HDMI interface
  
// Pull high  
assign HDMI_I2S0  = 1'b z;
assign HDMI_MCLK  = 1'b z;
assign HDMI_LRCLK = 1'b z;
assign HDMI_SCLK  = 1'b z;

wire hdmiRAMRequest; // 1 when HDMI scanout wants to read data from RAM
wire [15:0] hdmiRAMAddr;
wire [15:0] hdmiRAMData;

 // **VGA MAIN CONTROLLER**
vgaHdmi vgaHdmi (
  // input
  .clock      (hdmiClock),
  .clock50    (clock),
  .reset      (~pllLocked),
  .hsync      (HDMI_TX_HS),
  .vsync      (HDMI_TX_VS),
  .switchR    (switchR),
  .switchG    (switchG),
  .switchB    (switchB),
  .enableRendererDisplay (switchR),
  .key0		  (key0),
  .key1		  (key1),
  .fbROMData  (hdmiRAMData),
  .debugA	  (displayDebugA),
  .debugB	  (displayDebugB),
  .debugC	  (displayDebugC),
  .debugD	  (displayDebugD),
  .debugE	  (displayDebugE),

  // output  
  .readRequest(hdmiRAMRequest),
  .vgaClock   (HDMI_TX_CLK),
  .RGBchannel (HDMI_TX_D),
  .fbROMAddr  (hdmiRAMAddr),
  .dataEnable (hdmiDataEnable)
);

// **I2C Interface for ADV7513 initial config**

reg hdmiReady;

I2C_HDMI_Config #(
  .CLK_Freq (50000000), // trabajamos con reloj de 50MHz
  .I2C_Freq (20000)    // reloj de 20kHz for i2c clock
  )

  I2C_HDMI_Config (
  .iCLK        (clock),
  .iRST_N      (reset_n),
  .I2C_SCLK    (HDMI_I2C_SCL),
  .I2C_SDAT    (HDMI_I2C_SDA),
  .HDMI_TX_INT (HDMI_TX_INT),
  .READY       (hdmiReady)
);
`endif

// Main framebuffer

wire [15:0] ramAddr;
wire [15:0] ramDataRead;
wire [15:0] ramDataWrite;
wire ramWriteEnable;

FrameBufferRAM FBRAM_inst (
	.address(ramAddr),
	.clock(clock),
	.q(ramDataRead),
	.data(ramDataWrite),
	.wren(ramWriteEnable)
);

wire [15:0] rendererWriteAddr;
wire [15:0] rendererWriteData;
wire rendererWrite;
wire rendererOK;

wire ppuConverterReadActive;
wire [15:0] ppuConverterReadAddr;
wire [31:0] ppuConverterReadData;
wire ppuConverterReadOK;

RAMArbiter FBRAMArbiter_inst(
`ifdef ENABLE_DEBUG_DISPLAY	
	// Scanout interface
	.scanoutEnable(hdmiRAMRequest),
	.scanoutAddr(hdmiRAMAddr),
	.scanoutData(hdmiRAMData),
`else
	.scanoutEnable(0),
`endif
	
	// Renderer write interface
	.rendererOK(rendererOK),
	.rendererEnable(rendererWrite),
	.rendererAddr(rendererWriteAddr),
	.rendererData(rendererWriteData),
	
	// PPU converter read interface
	.ppuConverterOK(ppuConverterReadOK),
	.ppuConverterActive(ppuConverterReadActive),
	.ppuConverterAddr(ppuConverterReadAddr),
	.ppuConverterData(ppuConverterReadData),

	// Connection to actual RAM module
	.ramAddr(ramAddr),
	.ramDataRead(ramDataRead),
	.ramDataWrite(ramDataWrite),
	.ramWriteEnable(ramWriteEnable)
);

reg signed [31:0] snesRayStartX;
reg signed [31:0] snesRayStartY;
reg signed [31:0] snesRayStartZ;
reg signed [15:0] snesRayDirX;
reg signed [15:0] snesRayDirY;
reg signed [15:0] snesRayDirZ;
reg signed [15:0] snesRayXStepX;
reg signed [15:0] snesRayXStepY;
reg signed [15:0] snesRayXStepZ;
reg signed [15:0] snesRayYStepX;
reg signed [15:0] snesRayYStepY;
reg signed [15:0] snesRayYStepZ;
reg signed [15:0] snesLightDirX;
reg signed [15:0] snesLightDirY;
reg signed [15:0] snesLightDirZ;

reg [15:0] commandBufferWriteAddress_ROMClock;
reg [15:0] commandBufferWriteAddress;
reg [63:0] commandBufferWriteData_ROMClock;
reg [63:0] commandBufferWriteData;
wire commandBufferWriteEN_ROMClock;
wire commandBufferWriteEN;

// Marshal ROM write enable across clock domains
ClockDomainTickMarshaller commandBufferWriteEN_marshaller(
	.inClock(romClock),
	.outClock(clock),
	.reset(reset),
	.inTick(commandBufferWriteEN_ROMClock),
	.outTick(commandBufferWriteEN)
);

// Marshal ROM write address and data across clock domains
ClockDomainMarshaller #(16) commandBufferWriteAddress_marshaller(
	.inClock(romClock),
	.outClock(clock),
	.reset(reset),
	.inData(commandBufferWriteAddress_ROMClock),
	.outData(commandBufferWriteAddress)
);
ClockDomainMarshaller #(64) commandBufferWriteData_marshaller(
	.inClock(romClock),
	.outClock(clock),
	.reset(reset),
	.inData(commandBufferWriteData_ROMClock),
	.outData(commandBufferWriteData)
);

Renderer Renderer_inst(
	// Fundamentals
	.clock(clock),
	.reset(reset),
	
	// Triggers
	.start_tick(startRenderer_tick),
	.done_tick(rendererDone_tick),
	
	// Framebuffer RAM write
	.rendererOK(rendererOK),
	.rendererWrite(rendererWrite),
	.rendererWriteAddr(rendererWriteAddr),
	.rendererWriteData(rendererWriteData),
	
	.commandBufferWriteAddress(commandBufferWriteAddress),
	.commandBufferWriteData(commandBufferWriteData),
	.commandBufferWriteEN(commandBufferWriteEN),
	
	.snesRayStartX(snesRayStartX),
	.snesRayStartY(snesRayStartY),
	.snesRayStartZ(snesRayStartZ),
	.snesRayDirX(snesRayDirX),
	.snesRayDirY(snesRayDirY),
	.snesRayDirZ(snesRayDirZ),
	.snesRayXStepX(snesRayXStepX),
	.snesRayXStepY(snesRayXStepY),
	.snesRayXStepZ(snesRayXStepZ),
	.snesRayYStepX(snesRayYStepX),
	.snesRayYStepY(snesRayYStepY),
	.snesRayYStepZ(snesRayYStepZ),
	.snesLightDirX(snesLightDirX),
	.snesLightDirY(snesLightDirY),
	.snesLightDirZ(snesLightDirZ),
		
`ifdef ENABLE_DEBUG_DISPLAY
	// Debug	output
	.debugA(debugA[1]),
	.debugB(debugB[1]),
	.debugC(debugC[1]),
	.debugD(debugD[1]),
	.rayEngineDebugA(debugA[2]),
	.rayEngineDebugB(debugB[2]),
	.rayEngineDebugC(debugC[2]),
	.rayEngineDebugD(debugD[2])
`endif
);

// SNES interface

SNESInterface SNESInterface_inst(
	.clock(clock),
	.romClock(romClock),
	.reset(reset),
	
	// External cartirdge bus
	.cartAddressBus(cartAddressBus),
	.cartCS_n(cartCS_n),
	.cartOE_n(cartOE_n),
	.cartDataBus(cartDataBus),
	.cartDataBusOE_n(cartDataBusOE_n),
	
	// SNES triggers
	.snesNewFrameTrigger_tick(startRequest_tick_romClock),
	.frameStart_tick(frameStart_tick_romClock),
	
	// SNES framebuffer RAM access	
	.snesFramebufferWriteAddress(ppuConverterOutWriteAddress),
	.snesFramebufferWriteEN(ppuConverterOutWriteEN),
	.snesFramebufferWriteData(ppuConverterOutWriteData),
	
	// Status
	.statusInfo(statusInfo),
	
	// Command buffer RAM access	
	.commandBufferWriteAddress(commandBufferWriteAddress_ROMClock),
	.commandBufferWriteData(commandBufferWriteData_ROMClock),
	.commandBufferWriteEN(commandBufferWriteEN_ROMClock),
	
	// Renderer configuration parameters
	.snesRayStartX(snesRayStartX),
	.snesRayStartY(snesRayStartY),
	.snesRayStartZ(snesRayStartZ),
	.snesRayDirX(snesRayDirX),
	.snesRayDirY(snesRayDirY),
	.snesRayDirZ(snesRayDirZ),
	.snesRayXStepX(snesRayXStepX),
	.snesRayXStepY(snesRayXStepY),
	.snesRayXStepZ(snesRayXStepZ),
	.snesRayYStepX(snesRayYStepX),
	.snesRayYStepY(snesRayYStepY),
	.snesRayYStepZ(snesRayYStepZ),
	.snesLightDirX(snesLightDirX),
	.snesLightDirY(snesLightDirY),
	.snesLightDirZ(snesLightDirZ),	
	
`ifdef ENABLE_DEBUG_DISPLAY		
	// Debug
	.debugA(debugA[3]),
	.debugB(debugB[3]),
	.debugC(debugC[3]),
	.debugD(debugD[3])
`ifdef ENABLE_BUS_TRACING
	.debugScrollUp(key1),
	.debugScrollDown(key0),
	.debugExt(debugExt)
`endif
`endif
);

// PPU converter

reg [63:0] debugA_ppuConverter;
reg [63:0] debugB_ppuConverter;
reg [63:0] debugC_ppuConverter;
reg [63:0] debugD_ppuConverter;

reg [14:0] ppuConverterOutWriteAddress;
reg ppuConverterOutWriteEN;
reg [7:0] ppuConverterOutWriteData;

PPUConverter PPUConverter_inst(
	.clock(romClock),
	.reset(reset),
	.start_tick(startPPUConverter_tick_romClock),
	.done_tick(ppuConverterDone_tick_romClock),
	.active(ppuConverterReadActive),
	.inReadAddress(ppuConverterReadAddr),
	.inReadData(ppuConverterReadData),
	.inReadOK(ppuConverterReadOK),
	.outWriteAddress(ppuConverterOutWriteAddress),
	.outWriteEN(ppuConverterOutWriteEN),
	.outWriteData(ppuConverterOutWriteData),
`ifdef ENABLE_DEBUG_DISPLAY		
	.debug(debugB[0])
`endif
);

`ifdef ENABLE_DEBUG_DISPLAY
// Joypad handling

reg joypadUp_tick;
reg joypadDown_tick;

JoypadInputHandler JoypadInputHandler_up(
	.clock(clock),
	.reset(reset),
	
	.inPressed(joypadUp),
	.outPressed_tick(joypadUp_tick)
);

JoypadInputHandler JoypadInputHandler_down(
	.clock(clock),
	.reset(reset),
	
	.inPressed(joypadDown),
	.outPressed_tick(joypadDown_tick)
);

// Debug manager

DebugManager DebugManager_inst(
	.clock(clock),
	.reset(reset),
	
	// Joypad input
	.inJoypadUp_tick(joypadUp_tick),
	.inJoypadDown_tick(joypadDown_tick),
	
	// System status
	.statusInfo(statusInfo),
	
	// System debug values
	.inDebugA(debugA),
	.inDebugB(debugB),
	.inDebugC(debugC),
	.inDebugD(debugD),
	
	// Outputs
	.outDebugA(displayDebugA),
	.outDebugB(displayDebugB),
	.outDebugC(displayDebugC),
	.outDebugD(displayDebugD),
	.outDebugE(displayDebugE)
);
`endif

endmodule
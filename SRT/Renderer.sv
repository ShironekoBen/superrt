`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// This is the core renderer logic, which calculates ray directions and submits rays to the execution engines

`default_nettype none

module Renderer(
	// Fundamentals
	input wire clock,
	input wire reset,
	
	// Triggers
	input wire start_tick,
	output wire done_tick,
	
	// SNES interface data	
	input wire signed [31:0] snesRayStartX,
	input wire signed [31:0] snesRayStartY,
	input wire signed [31:0] snesRayStartZ,
	input wire signed [15:0] snesRayDirX,
	input wire signed [15:0] snesRayDirY,
	input wire signed [15:0] snesRayDirZ,
	input wire signed [15:0] snesRayXStepX,
	input wire signed [15:0] snesRayXStepY,
	input wire signed [15:0] snesRayXStepZ,
	input wire signed [15:0] snesRayYStepX,
	input wire signed [15:0] snesRayYStepY,
	input wire signed [15:0] snesRayYStepZ,
	input wire signed [15:0] snesLightDirX,
	input wire signed [15:0] snesLightDirY,
	input wire signed [15:0] snesLightDirZ,
	
	// Command buffer access (only safe when not executing!)
	input wire [15:0] commandBufferWriteAddress,
	input wire [63:0] commandBufferWriteData,
	input wire commandBufferWriteEN,
	
	// Framebuffer RAM write
	input wire rendererOK,
	output wire rendererWrite,
	output wire [15:0] rendererWriteAddr,
	output wire [15:0] rendererWriteData,
	
	// Debug	output
	output wire [63:0] debugA,
	output wire [63:0] debugB,
	output wire [63:0] debugC,
	output wire [63:0] debugD,
	output wire [63:0] rayEngineDebugA,
	output wire [63:0] rayEngineDebugB,
	output wire [63:0] rayEngineDebugC,
	output wire [63:0] rayEngineDebugD
);

import Maths::*;
 
reg [15:0] renderPixel; // The pixel index we are currently rendering
reg [7:0] renderPixelX;
reg [7:0] renderPixelY;

reg signed [31:0] primaryRayStartX;
reg signed [31:0] primaryRayStartY;
reg signed [31:0] primaryRayStartZ;
reg signed [15:0] primaryRayDirX; // This is the normalised version of currentRayDir
reg signed [15:0] primaryRayDirY;
reg signed [15:0] primaryRayDirZ;
reg signed [15:0] lineStartRayDirX;
reg signed [15:0] lineStartRayDirY;
reg signed [15:0] lineStartRayDirZ;
reg signed [15:0] currentRayDirX;
reg signed [15:0] currentRayDirY;
reg signed [15:0] currentRayDirZ;
reg signed [15:0] rayXStepX;
reg signed [15:0] rayXStepY;
reg signed [15:0] rayXStepZ;
reg signed [15:0] rayYStepX;
reg signed [15:0] rayYStepY;
reg signed [15:0] rayYStepZ;

// Light dir

reg signed [15:0] lightDirX;
reg signed [15:0] lightDirY;
reg signed [15:0] lightDirZ;

// Write scheduler

wire [2:0] execUnitWriteOK;
wire [2:0] execUnitWrite_tick;
wire [15:0] execUnitWriteAddr[2:0];
wire [15:0] execUnitWriteData[2:0];
wire renderWriteSchedulerBusy;

RendererWriteScheduler RendererWriteScheduler_inst(
	.clock(clock),
	.reset(reset),
	
	.execUnitWriteOK(execUnitWriteOK),
	.execUnitWrite_tick(execUnitWrite_tick),
	.execUnitWriteAddr(execUnitWriteAddr),
	.execUnitWriteData(execUnitWriteData),	
	
	// Framebuffer RAM interface
	.ramOK(rendererOK),
	.ramWrite(rendererWrite),
	.ramWriteAddr(rendererWriteAddr),
	.ramWriteData(rendererWriteData),	
	
	.busy(renderWriteSchedulerBusy),
	.debug(debugB)
);

// Ray Execution engines

reg [2:0] execEngineStart_tick;
reg [2:0] execEngineBusy;

// Execution engine unit 0

RayEngine RayEngine_Unit0(
	.clock(clock),
	.reset(reset),
	
	// Triggers
	.start_tick(execEngineStart_tick[0]),
	.busy(execEngineBusy[0]),
	
	// Inputs
	.inputRayStartX(primaryRayStartX),
   .inputRayStartY(primaryRayStartY),
	.inputRayStartZ(primaryRayStartZ),
	.inputRayDirX(primaryRayDirX),
	.inputRayDirY(primaryRayDirY),
	.inputRayDirZ(primaryRayDirZ),
	.inputLightDirX(lightDirX),
	.inputLightDirY(lightDirY),
	.inputLightDirZ(lightDirZ),	
	.inputPixelAddress(renderPixel),
	.inputPixelX(renderPixelX),
	.inputPixelY(renderPixelY),
	
	// Command buffer access
	.commandBufferWriteAddress(commandBufferWriteAddress),
	.commandBufferWriteData(commandBufferWriteData),
	.commandBufferWriteEN(commandBufferWriteEN),
	
	// Framebuffer RAM interface
	.fbWriteOK(execUnitWriteOK[0]),
	.fbWrite(execUnitWrite_tick[0]),
	.fbWriteAddr(execUnitWriteAddr[0]),
	.fbWriteData(execUnitWriteData[0]),
	
`ifdef TINT_EXECUTION_UNITS
	.pixelTintR(8'd255),
	.pixelTintG(8'd0),
	.pixelTintB(8'd0),
`endif
	
	// Debug
	.debugA(rayEngineDebugA),
	.debugB(rayEngineDebugB),
	.debugC(rayEngineDebugC),
	.debugD(rayEngineDebugD)
);

`ifdef ENABLE_EXECUTION_UNIT_1

// Execution engine unit 1

RayEngine RayEngine_Unit1(
	.clock(clock),
	.reset(reset),
	
	// Triggers
	.start_tick(execEngineStart_tick[1]),
	.busy(execEngineBusy[1]),
	
	// Inputs
	.inputRayStartX(primaryRayStartX),
   .inputRayStartY(primaryRayStartY),
	.inputRayStartZ(primaryRayStartZ),
	.inputRayDirX(primaryRayDirX),
	.inputRayDirY(primaryRayDirY),
	.inputRayDirZ(primaryRayDirZ),
	.inputLightDirX(lightDirX),
	.inputLightDirY(lightDirY),
	.inputLightDirZ(lightDirZ),	
	.inputPixelAddress(renderPixel),
	.inputPixelX(renderPixelX),
	.inputPixelY(renderPixelY),	
	
	// Command buffer access
	.commandBufferWriteAddress(commandBufferWriteAddress),
	.commandBufferWriteData(commandBufferWriteData),
	.commandBufferWriteEN(commandBufferWriteEN),	
	
	// Framebuffer RAM interface
	.fbWriteOK(execUnitWriteOK[1]),
	.fbWrite(execUnitWrite_tick[1]),
	.fbWriteAddr(execUnitWriteAddr[1]),
	.fbWriteData(execUnitWriteData[1])
	
`ifdef TINT_EXECUTION_UNITS
	.pixelTintR(8'd0),
	.pixelTintG(8'd255),
	.pixelTintB(8'd0),
`endif	
	
	// Debug
	//.debugA(debugB)
);

`else

assign execEngineBusy[1] = 1'b1; // Disabled execution units are treated as always busy
assign execUnitWrite_tick[1] = 0;
assign execUnitWriteAddr[1] = 16'h0;
assign execUnitWriteData[1] = 16'h0;

`endif

`ifdef ENABLE_EXECUTION_UNIT_2

// Execution engine unit 2

RayEngine RayEngine_Unit2(
	.clock(clock),
	.reset(reset),
	
	// Triggers
	.start_tick(execEngineStart_tick[2]),
	.busy(execEngineBusy[2]),
	
	// Inputs
	.inputRayStartX(primaryRayStartX),
   .inputRayStartY(primaryRayStartY),
	.inputRayStartZ(primaryRayStartZ),
	.inputRayDirX(primaryRayDirX),
	.inputRayDirY(primaryRayDirY),
	.inputRayDirZ(primaryRayDirZ),
	.inputLightDirX(lightDirX),
	.inputLightDirY(lightDirY),
	.inputLightDirZ(lightDirZ),	
	.inputPixelAddress(renderPixel),	
	.inputPixelX(renderPixelX),
	.inputPixelY(renderPixelY),	
	
	// Command buffer access
	.commandBufferWriteAddress(commandBufferWriteAddress),
	.commandBufferWriteData(commandBufferWriteData),
	.commandBufferWriteEN(commandBufferWriteEN),	
	
	// Framebuffer RAM interface
	.fbWriteOK(execUnitWriteOK[2]),
	.fbWrite(execUnitWrite_tick[2]),
	.fbWriteAddr(execUnitWriteAddr[2]),
	.fbWriteData(execUnitWriteData[2]),
	
`ifdef TINT_EXECUTION_UNITS
	.pixelTintR(8'd0),
	.pixelTintG(8'd0),
	.pixelTintB(8'd255),
`endif	
);

`else

assign execEngineBusy[2] = 1'b1; // Disabled execution units are treated as always busy
assign execUnitWrite_tick[2] = 0;
assign execUnitWriteAddr[2] = 16'h0;
assign execUnitWriteData[2] = 16'h0;

`endif

// Normalising ray direction

always @(*) begin
	FixedNormalise16Bit(currentRayDirX, currentRayDirY, currentRayDirZ, primaryRayDirX, primaryRayDirY, primaryRayDirZ);
end

// Index of first currently idle execution engine unit, or 7 for none

reg [2:0] firstFreeExecUnit;

always @(*) begin
	if (!execEngineBusy[0])
		firstFreeExecUnit = 0;
	else if (!execEngineBusy[1])
		firstFreeExecUnit = 1;
	else if (!execEngineBusy[2])
		firstFreeExecUnit = 2;
	else
		firstFreeExecUnit = 7;
end

// State machine

typedef enum
{
	RP_Start = 0,
	RP_LoadSetupData,
	RP_BeginPixel,
	RP_BeginPixelWaitState,
	RP_BeginPixelWaitState2,
	RP_StartTrace,
	RP_WaitForStart,
	RP_WaitForStart2,
	RP_FinishPixel,
	RP_FinishFrame
} RendererPhase;

RendererPhase renderPhase = RP_Start;

assign debugA = { 16'h0, 16'(renderPixel), 8'h0, 8'(renderPhase), 8'(execEngineBusy), 8'(execUnitWrite_tick) };

always @(posedge clock or posedge reset) begin
  if (reset) begin
	renderPixel <= 0;
	renderPixelX <= 0;
	renderPixelY <= 0;
	currentRayDirX <= 0;
	currentRayDirY <= 0;
	currentRayDirZ <= 0;
	lineStartRayDirX <= 0;
	lineStartRayDirY <= 0;
	lineStartRayDirZ <= 0;
	rayXStepX <= 0;
	rayXStepY <= 0;
	rayXStepZ <= 0;
	rayYStepX <= 0;
	rayYStepY <= 0;
	rayYStepZ <= 0;
	execEngineStart_tick <= 'h0;
	
	renderPhase <= RP_Start;
	done_tick <= 0;
  end else begin
	done_tick <= 0;
	execEngineStart_tick <= 'h0;
  
	case(renderPhase)
	   RP_Start: begin
			// Wait for start signal	
			
			if (start_tick) begin
				renderPhase <= renderPhase.next;
			end else begin
				renderPhase <= RP_Start;			
			end
		end
		RP_LoadSetupData: begin		
			renderPixel <= 0;
			renderPixelX <= 0;
			renderPixelY <= 0;
			
			// Load in data from SNES
			
			primaryRayStartX <= snesRayStartX;
			primaryRayStartY <= snesRayStartY;
			primaryRayStartZ <= snesRayStartZ;
			currentRayDirX <= snesRayDirX;
			currentRayDirY <= snesRayDirY;
			currentRayDirZ <= snesRayDirZ;
			lineStartRayDirX <= snesRayDirX;
			lineStartRayDirY <= snesRayDirY;
			lineStartRayDirZ <= snesRayDirZ;
			rayXStepX <= snesRayXStepX;
			rayXStepY <= snesRayXStepY;
			rayXStepZ <= snesRayXStepZ;
			rayYStepX <= snesRayYStepX;
			rayYStepY <= snesRayYStepY;
			rayYStepZ <= snesRayYStepZ;
			lightDirX <= snesLightDirX;
			lightDirY <= snesLightDirY;
			lightDirZ <= snesLightDirZ;
		
			renderPhase <= renderPhase.next;
		end
		RP_BeginPixel: begin
			// Pause to wait for the ray dir normalisation to occur
			renderPhase <= renderPhase.next;
		end
		RP_BeginPixelWaitState: renderPhase <= renderPhase.next;
		RP_BeginPixelWaitState2: renderPhase <= renderPhase.next;
		RP_StartTrace: begin
			// Start the first free execution engine

			renderPhase <= renderPhase.next;
			
			// We don't need an ifdef guard here because disabled units are always busy
			case(firstFreeExecUnit)
				0:	execEngineStart_tick[0] <= 1;
				1:	execEngineStart_tick[1] <= 1;
				2:	execEngineStart_tick[2] <= 1;
				default:	renderPhase <= RP_StartTrace; // Wait until a unit becomes free
			endcase
		end
		RP_WaitForStart: begin
			// This is just a wait state to give the execution engine time to latch in the input data
			renderPhase <= renderPhase.next;
		end
		RP_WaitForStart2: renderPhase <= renderPhase.next; // Wait state for 3 exec unit operation
		RP_FinishPixel: begin
		  // Ready the setup for the next pixel
		  		  
		  if (renderPixelX == (200 - 1)) begin
				// End of line
				renderPixelX <= 0;
				
				currentRayDirX <= lineStartRayDirX + rayYStepX;
				currentRayDirY <= lineStartRayDirY + rayYStepY;
				currentRayDirZ <= lineStartRayDirZ + rayYStepZ;
				lineStartRayDirX <= lineStartRayDirX + rayYStepX;
				lineStartRayDirY <= lineStartRayDirY + rayYStepY;
				lineStartRayDirZ <= lineStartRayDirZ + rayYStepZ;
				
				if (renderPixelY == (160 - 1)) begin
					// End of frame									
					renderPhase <= RP_FinishFrame;
				end else begin
					// Middle of frame
					renderPixelY <= renderPixelY + 1;
					renderPixel <= renderPixel + 1;
					renderPhase <= RP_BeginPixel;
				end			
		  end else begin
				// Middle of line
				renderPixelX <= renderPixelX + 1;
				renderPixel <= renderPixel + 1;
				currentRayDirX <= currentRayDirX + rayXStepX;
				currentRayDirY <= currentRayDirY + rayXStepY;
				currentRayDirZ <= currentRayDirZ + rayXStepZ;
				renderPhase <= RP_BeginPixel;
		  end
		end
		RP_FinishFrame: begin
			// Wait for all enabled execution units (and the write scheduler) to finish before we report we're done
			
			if (renderWriteSchedulerBusy
				 || execEngineBusy[0]
`ifdef ENABLE_EXECUTION_UNIT_1
				 || execEngineBusy[1]
`endif
`ifdef ENABLE_EXECUTION_UNIT_2
				 || execEngineBusy[2]
`endif
			) begin
				// Still waiting for one of the execution units to finish
				renderPhase <= RP_FinishFrame;
			end else begin
				// All done!
				renderPhase <= RP_Start;
				done_tick <= 1;			
			end
		end
		default: begin
		end
	 endcase
  end
end

endmodule
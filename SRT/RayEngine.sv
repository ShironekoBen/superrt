`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// A single ray execution engine (handles primary and secondary rays, and colour calculation, with the exec engine doing the actual intersection)

`default_nettype none

module RayEngine(
	input wire clock,
	input wire reset,
	
	// Triggers
	input wire start_tick,
	output wire busy,
	
	// Inputs
	input wire signed [31:0] inputRayStartX,
   input wire signed [31:0] inputRayStartY,
	input wire signed [31:0] inputRayStartZ,
	input wire signed [15:0] inputRayDirX,
	input wire signed [15:0] inputRayDirY,
	input wire signed [15:0] inputRayDirZ,
	input wire signed [15:0] inputLightDirX,
	input wire signed [15:0] inputLightDirY,
	input wire signed [15:0] inputLightDirZ,	
	input wire [15:0] inputPixelAddress,
	input wire [7:0] inputPixelX,
	input wire [7:0] inputPixelY,
	
	// Command buffer access (only safe when not executing!)
	input wire [15:0] commandBufferWriteAddress,
	input wire [63:0] commandBufferWriteData,
	input wire commandBufferWriteEN,
	
`ifdef ENABLE_TINT_PIXEL	
	// Debug colour
	input wire [7:0] pixelTintR,
	input wire [7:0] pixelTintG,
	input wire [7:0] pixelTintB,
`endif
	
	// Framebuffer RAM interface
	input wire fbWriteOK,
	output wire fbWrite,
	output wire [15:0] fbWriteAddr,
	output wire [15:0] fbWriteData,
	
	// Debug
	output wire [63:0] debugA,
	output wire [63:0] debugB,
	output wire [63:0] debugC,
	output wire [63:0] debugD
);

import Maths::*;

`include "RayEngine-ColourCalculator.sv"
`include "RayEngine-FinalColourCalculator.sv"
`include "RayEngine-SecondaryRayDirectionCalculator.sv"

// Execution engine

wire execEngineStart_tick;
wire execEngineBusy;

// Rcp engine, only usable when exec engine is not busy
wire signed [31:0] execEngineRcpIn;
wire signed [31:0] execEngineRcpOut;

// Execution engine outputs
reg execEngineHit;
reg signed [31:0] execEngineHitDepth;
reg signed [31:0] execEngineHitX;
reg signed [31:0] execEngineHitY;
reg signed [31:0] execEngineHitZ;
reg signed [15:0] execEngineHitNormalX;
reg signed [15:0] execEngineHitNormalY;
reg signed [15:0] execEngineHitNormalZ;
reg [15:0] execEngineHitAlbedo;
reg [7:0] execEngineHitReflectiveness;

ExecEngine ExecEngine_inst(
	.clock(clock),
	.reset(reset),
	
	.x_start_tick(execEngineStart_tick),
	.x_busy(execEngineBusy),
	
	// Inputs
	.u_rayStartX(rayStartX),
   .u_rayStartY(rayStartY),
	.u_rayStartZ(rayStartZ),
	.u_rayDirX(rayDirX),
	.u_rayDirY(rayDirY),
	.u_rayDirZ(rayDirZ),
	.u_rayDirRcpX(rayDirRcpX),
	.u_rayDirRcpY(rayDirRcpY),
	.u_rayDirRcpZ(rayDirRcpZ),
	.u_doingShadowRay(currentPhaseIsShadow),
	.u_doingSecondaryRay(~currentPhaseIsPrimary),
		
	// Command buffer access
	.x_commandBufferWriteAddress(commandBufferWriteAddress),
	.x_commandBufferWriteData(commandBufferWriteData),
	.x_commandBufferWriteEN(commandBufferWriteEN),
	
	// Rcp module
	.x_rcpIn(execEngineRcpIn),
	.x_rcpOut(execEngineRcpOut),
	
	// Outputs	
	.s14_regHit(execEngineHit),
	.s14_regHitDepth(execEngineHitDepth),
	.s14_regHitX(execEngineHitX),
	.s14_regHitY(execEngineHitY),
	.s14_regHitZ(execEngineHitZ),
	.s14_regHitNormalX(execEngineHitNormalX),
	.s14_regHitNormalY(execEngineHitNormalY),
	.s14_regHitNormalZ(execEngineHitNormalZ),
	.s14_regHitAlbedo(execEngineHitAlbedo),
	.s14_regHitReflectiveness(execEngineHitReflectiveness),
	
	// Debug
	//.debugA(debugA),
	.debugB(execUnitDebugB),
	.debugC(execUnitDebugC),
	.debugD(execUnitDebugD),
	
	.branchPredictionHits(execUnitBranchPredictionHits),
	.branchPredictionMisses(execUnitBranchPredictionMisses),
	.instructionDispatched(instructionDispatched),
	.cycleCount(cycleCount),
);

wire [31:0] execUnitBranchPredictionHits;
wire [31:0] execUnitBranchPredictionMisses;
wire [63:0] execUnitDebugB;
wire [63:0] execUnitDebugC;
wire [63:0] execUnitDebugD;
wire [31:0] instructionDispatched;
wire [31:0] cycleCount;

// Locals

// Primary ray (i.e. the one we were first executed with) position/direction
reg signed [31:0] primaryRayStartX;
reg signed [31:0] primaryRayStartY;
reg signed [31:0] primaryRayStartZ;
reg signed [15:0] primaryRayDirX;
reg signed [15:0] primaryRayDirY;
reg signed [15:0] primaryRayDirZ;
reg signed [15:0] lightDirX; // Light direction
reg signed [15:0] lightDirY;
reg signed [15:0] lightDirZ;	
reg [15:0] pixelAddress; // The address of the pixel we are going to write to
reg [7:0] pixelX; // The location of the pixel we are going to write to
reg [7:0] pixelY;

// Current ray information
reg signed [31:0] rayStartX;
reg signed [31:0] rayStartY;
reg signed [31:0] rayStartZ;
reg signed [15:0] rayDirX;
reg signed [15:0] rayDirY;
reg signed [15:0] rayDirZ;
reg signed [31:0] rayDirRcpX;
reg signed [31:0] rayDirRcpY;
reg signed [31:0] rayDirRcpZ;

// Registered hit information for each phase 

reg regPrimaryHit;
reg signed [31:0] regPrimaryHitDepth;
reg signed [31:0] regPrimaryHitX;
reg signed [31:0] regPrimaryHitY;
reg signed [31:0] regPrimaryHitZ;
reg signed [15:0] regPrimaryHitNormalX;
reg signed [15:0] regPrimaryHitNormalY;
reg signed [15:0] regPrimaryHitNormalZ;
reg [15:0] regPrimaryHitAlbedo;
reg [7:0] regPrimaryHitReflectiveness;

reg regPrimaryShadowHit; // Shadow rays only require hit/no hit determination

reg regSecondaryHit;
reg signed [31:0] regSecondaryHitDepth;
reg signed [31:0] regSecondaryHitX;
reg signed [31:0] regSecondaryHitY;
reg signed [31:0] regSecondaryHitZ;
reg signed [15:0] regSecondaryHitNormalX;
reg signed [15:0] regSecondaryHitNormalY;
reg signed [15:0] regSecondaryHitNormalZ;
reg [15:0] regSecondaryHitAlbedo;

reg regSecondaryShadowHit;

reg [31:0] branchPredictionHits;
reg [31:0] branchPredictionMisses;

// Result colours
reg [7:0] primaryRayColourR;
reg [7:0] primaryRayColourG;
reg [7:0] primaryRayColourB;
reg [7:0] secondaryRayColourR;
reg [7:0] secondaryRayColourG;
reg [7:0] secondaryRayColourB;

integer signed MinTraceStart = 32'shfff60000; // FixedMaths.FloatToFixed(-40.0f);
integer signed MaxTraceStart = 32'sh000a0000; // FixedMaths.FloatToFixed(50.0f);
integer unsigned secondaryRayBiasShift = 8'd4; // Bias for shadow/secondary rays, in terms of a shift of the vector (so 4 == /16)

// For debug only
integer ScreenWidth = 200;
integer ScreenHeight = 160;
integer DebugPixelLocation = 100 + (120 * 200);

// Execution phases

typedef enum
{
	EEP_PrimaryRay,
	EEP_PrimaryShadow,
	EEP_SecondaryRay,
	EEP_SecondaryShadow
} ExecEnginePhase;

ExecEnginePhase phase;

// Execution states

typedef enum
{
	EES_WaitingToStart,
	EES_StartingPhase,
	EES_ExecEngineSetup1,
	EES_ExecEngineSetup2,
	EES_ExecEngineSetup3,
	EES_ExecEngineSetup4,
	EES_ExecEngineSetup5,
	EES_ExecEngineSetup6,
	EES_ExecEngineStart,
	EES_ExecEngineStartWait,
	EES_ExecEngineWait,
	EES_ExecEngineFinished,
	EES_FinishingPhase,
	EES_WritePixel1,
	EES_WritePixel2
} ExecEngineState;

ExecEngineState state;

// Is the current phase for a primary or secondary ray?

reg currentPhaseIsPrimary;

always @(*) begin
	currentPhaseIsPrimary = ((phase != EEP_SecondaryRay) && (phase != EEP_SecondaryShadow));
end

// Is the current phase for a shadow ray?

reg currentPhaseIsShadow;

always @(*) begin
	currentPhaseIsShadow = ((phase == EEP_PrimaryShadow) || (phase == EEP_SecondaryShadow));
end

// Light facing-ness for the current phase

reg signed [15:0] currentPhaseNormalDotLight;

always @(*) begin
	currentPhaseNormalDotLight = 16'(FixedMul16x16(lightDirX, currentPhaseIsPrimary ? regPrimaryHitNormalX : regSecondaryHitNormalX)) + 16'(FixedMul16x16(lightDirY, currentPhaseIsPrimary ? regPrimaryHitNormalY : regSecondaryHitNormalY)) + 16'(FixedMul16x16(lightDirZ, currentPhaseIsPrimary ? regPrimaryHitNormalZ : regSecondaryHitNormalZ));
end

// Debug

always @(*) begin
	debugA = { 16'(pixelAddress), 16'(0), 4'(execEngineBusy), 4'(execEngineStart_tick), 4'(currentPhaseIsPrimary), 4'(busy), 8'(phase), 8'(state) };
end

// Main state machine

always @(posedge clock or posedge reset) begin
	if (reset) begin
		busy <= 1;
		fbWrite <= 0;

		primaryRayStartX <= 0;
		primaryRayStartY <= 0;
		primaryRayStartZ <= 0;
		primaryRayDirX <= 0;
		primaryRayDirY <= 0;
		primaryRayDirZ <= 0;
		lightDirX <= 0;
		lightDirY <= 0;
		lightDirZ <= 0;
		pixelAddress <= 0;
		execEngineStart_tick <= 0;
		execEngineRcpIn <= 0;
		
		state <= EES_WaitingToStart;
		phase <= EEP_PrimaryRay;
	end else begin
		busy <= 1;
		fbWrite <= 0;
		execEngineStart_tick <= 0;
		execEngineRcpIn <= 0;

		case(state)
		
			// Idle state
		
			EES_WaitingToStart: begin
				if (start_tick) begin				
					// Latch in our setup data
					primaryRayStartX <= inputRayStartX;
					primaryRayStartY <= inputRayStartY;
					primaryRayStartZ <= inputRayStartZ;
					primaryRayDirX <= inputRayDirX;
					primaryRayDirY <= inputRayDirY;
					primaryRayDirZ <= inputRayDirZ;
					lightDirX <= inputLightDirX;
					lightDirY <= inputLightDirY;
					lightDirZ <= inputLightDirZ;
					pixelAddress <= inputPixelAddress;
					pixelX <= inputPixelX;
					pixelY <= inputPixelY;
					
					// Set up initial tracer state
					rayStartX <= inputRayStartX;
					rayStartY <= inputRayStartY;
					rayStartZ <= inputRayStartZ;
					rayDirX <= inputRayDirX;
					rayDirY <= inputRayDirY;
					rayDirZ <= inputRayDirZ;
					regPrimaryHit <= 0;
					regPrimaryShadowHit <= 0;
					regSecondaryHit <= 0;
					regSecondaryShadowHit <= 0;
					
					branchPredictionHits <= 0;
					branchPredictionMisses <= 0;
					
					if ((pixelAddress == DebugPixelLocation) && (phase == EEP_PrimaryRay)) begin
						//debugA <= 64'h0;
						debugB <= 64'h0;
						debugC <= 64'h0;
						//debugC <= 64'h0;
						//debugD <= 64'h0;
					end
			
					phase <= EEP_PrimaryRay;
					state <= state.next;
				end else begin
					busy <= 0;
				end
			end
			
			// Startup state
			
			EES_StartingPhase: begin
				// If the ray start point is a very large value, we get overflows that cause all sorts of weirdness
				// (generally with shadows/reflections), so just assume rays starting out of bounds never hit anything
				// (this is also a reasonably significant performance optimisation)
				
				if ((rayStartX < MinTraceStart) || (rayStartX > MaxTraceStart) ||
					(rayStartY < MinTraceStart) || (rayStartY > MaxTraceStart) ||
					(rayStartZ < MinTraceStart) || (rayStartZ > MaxTraceStart)) begin
					state <= EES_FinishingPhase;					
				end else begin
					execEngineRcpIn <= $signed({{16{rayDirX[15]}}, rayDirX});
					state <= EES_ExecEngineSetup1;
				end
			end
			
			// Perform 1/RayDir calculations, stealing the exec engine's RCP module to do it
			// (which is fine, because the exec engine doesn't use it when not running)
			
			EES_ExecEngineSetup1: begin
				execEngineRcpIn <= $signed({{16{rayDirY[15]}}, rayDirY});
				state <= state.next;
			end 
			EES_ExecEngineSetup2: begin
				execEngineRcpIn <= $signed({{16{rayDirZ[15]}}, rayDirZ});
				state <= state.next;
			end 			
			EES_ExecEngineSetup3: begin
				state <= state.next;
			end
			EES_ExecEngineSetup4: begin
				state <= state.next;
			end
			EES_ExecEngineSetup5: begin
				rayDirRcpX <= execEngineRcpOut;
				state <= state.next;
			end 
			EES_ExecEngineSetup6: begin
				rayDirRcpY <= execEngineRcpOut;
				state <= state.next;
			end 			
			EES_ExecEngineStart: begin
				rayDirRcpZ <= execEngineRcpOut;
				execEngineStart_tick <= 1;
				state <= EES_ExecEngineStartWait;
			end

			// One cycle wait for exec engine to begin executing
			EES_ExecEngineStartWait: state <= state.next;
			
			EES_ExecEngineWait: begin
				state <= execEngineBusy ? EES_ExecEngineWait : EES_ExecEngineFinished;
			end
			
			EES_ExecEngineFinished: begin
			
				// Record results from exec engine
				
				branchPredictionHits <= branchPredictionHits + execUnitBranchPredictionHits;
				branchPredictionMisses <= branchPredictionMisses + execUnitBranchPredictionMisses;
				
				if ((pixelAddress == DebugPixelLocation) && (phase == EEP_PrimaryRay)) begin
					debugB <= execUnitDebugB;
					debugC <= execUnitDebugC;
					debugD <= execUnitDebugD;
					//debugC <= { execUnitBranchPredictionHits, execUnitBranchPredictionMisses };
				end
				
				case(phase)
					EEP_PrimaryRay: begin
						regPrimaryHit <= execEngineHit;
						regPrimaryHitDepth <= execEngineHitDepth;
						regPrimaryHitX <= execEngineHitX;
						regPrimaryHitY <= execEngineHitY;
						regPrimaryHitZ <= execEngineHitZ;
						regPrimaryHitNormalX <= execEngineHitNormalX;
						regPrimaryHitNormalY <= execEngineHitNormalY;
						regPrimaryHitNormalZ <= execEngineHitNormalZ;
						regPrimaryHitAlbedo <= execEngineHitAlbedo;
						regPrimaryHitReflectiveness <= execEngineHitReflectiveness;
					end
					EEP_PrimaryShadow: begin
						regPrimaryShadowHit <= execEngineHit;
					end
					EEP_SecondaryRay: begin
						regSecondaryHit <= execEngineHit;
						regSecondaryHitDepth <= execEngineHitDepth;
						regSecondaryHitX <= execEngineHitX;
						regSecondaryHitY <= execEngineHitY;
						regSecondaryHitZ <= execEngineHitZ;
						regSecondaryHitNormalX <= execEngineHitNormalX;
						regSecondaryHitNormalY <= execEngineHitNormalY;
						regSecondaryHitNormalZ <= execEngineHitNormalZ;
						regSecondaryHitAlbedo <= execEngineHitAlbedo;
					end
					EEP_SecondaryShadow: begin
						regSecondaryShadowHit <= execEngineHit;
					end					
				endcase
				
				state <= EES_FinishingPhase;
			end
			
			EES_FinishingPhase: begin
				// Latch in result colour from colour calculation module

				if (currentPhaseIsPrimary) begin
					primaryRayColourR <= colourCalculator_RayR;
					primaryRayColourG <= colourCalculator_RayG;
					primaryRayColourB <= colourCalculator_RayB;
				end else begin
					secondaryRayColourR <= colourCalculator_RayR;
					secondaryRayColourG <= colourCalculator_RayG;
					secondaryRayColourB <= colourCalculator_RayB;
				end
				
				// Now figure out what to do next				

				// Default to being done tracing and ready to write the pixel
				state <= EES_WritePixel1;

				// See if we have any more phases to do
				case(phase)
					EEP_PrimaryRay: begin
						if (regPrimaryHit) begin
							if (currentPhaseNormalDotLight > 0) begin // Only do shadow rays for pixels that point towards the light
								// Do shadow phase
								rayStartX <= secondaryRayDirectionCalculator_ShadowRayStartX;
								rayStartY <= secondaryRayDirectionCalculator_ShadowRayStartY;
								rayStartZ <= secondaryRayDirectionCalculator_ShadowRayStartZ;
								rayDirX <= secondaryRayDirectionCalculator_ShadowRayDirX;
								rayDirY <= secondaryRayDirectionCalculator_ShadowRayDirY;
								rayDirZ <= secondaryRayDirectionCalculator_ShadowRayDirZ;

								phase <= EEP_PrimaryShadow;
								state <= EES_StartingPhase;
							end else if (regPrimaryHitReflectiveness != 0) begin
								// Skip to secondary ray
								regPrimaryShadowHit <= 1; // Presume shadowing for anything pointing away from the light

								rayStartX <= secondaryRayDirectionCalculator_ReflectionRayStartX;
								rayStartY <= secondaryRayDirectionCalculator_ReflectionRayStartY;
								rayStartZ <= secondaryRayDirectionCalculator_ReflectionRayStartZ;
								rayDirX <= secondaryRayDirectionCalculator_ReflectionRayDirX;
								rayDirY <= secondaryRayDirectionCalculator_ReflectionRayDirY;
								rayDirZ <= secondaryRayDirectionCalculator_ReflectionRayDirZ;

								phase <= EEP_SecondaryRay;
								state <= EES_StartingPhase;
							end else begin
								regPrimaryShadowHit <= 1; // Presume shadowing for anything pointing away from the light
							end
						end
					end
					EEP_PrimaryShadow: begin
						// No need to check regPrimaryHit here because a hit would be required to trigger the shadow phase
						if (regPrimaryHitReflectiveness != 0) begin
							// Do secondary ray

							rayStartX <= secondaryRayDirectionCalculator_ReflectionRayStartX;
							rayStartY <= secondaryRayDirectionCalculator_ReflectionRayStartY;
							rayStartZ <= secondaryRayDirectionCalculator_ReflectionRayStartZ;
							rayDirX <= secondaryRayDirectionCalculator_ReflectionRayDirX;
							rayDirY <= secondaryRayDirectionCalculator_ReflectionRayDirY;
							rayDirZ <= secondaryRayDirectionCalculator_ReflectionRayDirZ;

							phase <= EEP_SecondaryRay;
							state <= EES_StartingPhase;
						end
					end
					EEP_SecondaryRay: begin
						if (regSecondaryHit) begin
							if (currentPhaseNormalDotLight > 0) begin // Only do shadow rays for pixels that point towards the light
								// Do shadow phase
								rayStartX <= secondaryRayDirectionCalculator_ShadowRayStartX;
								rayStartY <= secondaryRayDirectionCalculator_ShadowRayStartY;
								rayStartZ <= secondaryRayDirectionCalculator_ShadowRayStartZ;
								rayDirX <= secondaryRayDirectionCalculator_ShadowRayDirX;
								rayDirY <= secondaryRayDirectionCalculator_ShadowRayDirY;
								rayDirZ <= secondaryRayDirectionCalculator_ShadowRayDirZ;

								phase <= EEP_SecondaryShadow;
								state <= EES_StartingPhase;
							end else begin
								regSecondaryShadowHit <= 1; // Presume shadowing for anything pointing away from the light
							end
						end
					end
				endcase
			end
			EES_WritePixel1: begin
				// Set up write data
				
				//if (pixelAddress == DebugPixelLocation) begin
				//	debugD <= { 8'(regPrimaryHit), 8'(regPrimaryShadowHit), 8'(regSecondaryHit), 8'(regSecondaryShadowHit), regPrimaryHitDepth };
				//end			
				
				fbWriteAddr <= pixelAddress;
				
				// Convert to 15bpp RGB on writing
				fbWriteData <= { 1'b0, finalColourCalculator_B[7:3], finalColourCalculator_G[7:3], finalColourCalculator_R[7:3] };

				
`ifdef ENABLE_DEBUG_PIXEL
				if ((pixelAddress == (DebugPixelLocation - 1)) || (pixelAddress == (DebugPixelLocation + 1)) ||
				    (pixelAddress == (DebugPixelLocation - ScreenWidth)) || (pixelAddress == (DebugPixelLocation + ScreenWidth))) begin
					 fbWriteData <= 16'hFFFF; // Crosshair around central pixel
				end
`endif
			
				// Wait for it to be OK to write
				if (fbWriteOK) begin
					state <= state.next;
				end
			end
			EES_WritePixel2: begin
				// Perform write
				fbWrite <= 1;				
				
				// Execution is complete
				state <= EES_WaitingToStart;
			end
		endcase
	end
end

endmodule
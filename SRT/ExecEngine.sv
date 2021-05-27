`include "Config.sv"

// SuperRT by Ben Carter (c) 2021
// Execute a command list for a single ray

`default_nettype none

module ExecEngine(
	input wire clock,
	input wire reset,
	
	// Triggers
	input wire x_start_tick,
	output reg x_busy,
	
	// Inputs
	input wire signed [31:0] u_rayStartX,
   input wire signed [31:0] u_rayStartY,
	input wire signed [31:0] u_rayStartZ,
	input wire signed [15:0] u_rayDirX,
	input wire signed [15:0] u_rayDirY,
	input wire signed [15:0] u_rayDirZ,
	input wire signed [31:0] u_rayDirRcpX,
	input wire signed [31:0] u_rayDirRcpY,
	input wire signed [31:0] u_rayDirRcpZ,
	input wire u_doingShadowRay,
	input wire u_doingSecondaryRay,
	
	// Command buffer access (only safe when not executing!)
	input wire [15:0] x_commandBufferWriteAddress,
	input wire [63:0] x_commandBufferWriteData,
	input wire x_commandBufferWriteEN,
	
	// Rcp engine (only safe to use when not executing!)
	// Throughput 1 cycle, latency 4 cycles
	input wire signed [31:0] x_rcpIn,
	output wire signed [31:0] x_rcpOut,
	
	// Outputs	
	output wire s14_regHit,
	output wire signed [31:0] s14_regHitDepth,
	output wire signed [31:0] s14_regHitX,
	output wire signed [31:0] s14_regHitY,
	output wire signed [31:0] s14_regHitZ,
	output wire signed [15:0] s14_regHitNormalX,
	output wire signed [15:0] s14_regHitNormalY,
	output wire signed [15:0] s14_regHitNormalZ,
	output wire [15:0] s14_regHitAlbedo,
	output wire [7:0] s14_regHitReflectiveness,
	
	// Debug
	output wire [63:0] debugA,
	output wire [63:0] debugB,
	output wire [63:0] debugC,
	output wire [63:0] debugD,
	
	output reg [31:0] branchPredictionHits,
	output reg [31:0] branchPredictionMisses,
	output reg [31:0] cycleCount,
	output reg [31:0] instructionDispatched
);

import Maths::*;

// Sub-components

`include "ExecEngine-RaySphereAndPlane.sv"
`include "ExecEngine-RayAABB.sv"

// Onboard command buffer RAM
CommandBufferRAM CommandBufferRAM_inst(
	.address(x_busy ? s1_fetchPC : x_commandBufferWriteAddress),
	.clock(clock),
	.data(x_commandBufferWriteData),
	.wren(x_commandBufferWriteEN && (!x_busy)), // Disallow writes when busy
	.q(x_commandBufferRAMReadOutput)
);

reg [15:0] numCommandBufferWrites;

always @(posedge clock) begin
	if (reset) begin
		numCommandBufferWrites <= 0;
	end else begin
		if (x_commandBufferWriteEN) begin
			numCommandBufferWrites <= numCommandBufferWrites + 1;
		end
	end
end

reg [31:0] debugCounter;
reg [63:0] debugData;

always @(posedge clock) begin
	if (reset) begin
		debugCounter <= 0;
	end else begin
		debugCounter <= debugCounter + 1;
	end
end

always @(*) begin
	debugC = { numCommandBufferWrites, x_commandBufferWriteAddress, 32'(debugCounter[31:25]) };
	debugD = debugData;
end

reg [63:0] x_commandBufferRAMReadOutput;

// Branch prediction cache
BranchPredictionCacheRAM BranchPredictionCacheRAM_inst(
	.clock(clock),
	.data(s14_branchPredictionCacheWriteInput),
	.wraddress(s14_branchPredictionCacheWriteAddr),
	.wren(s14_branchPredictionCacheWriteEnable),
	.rdaddress(s1_fetchPC[15:1]), // We have one prediction cache entry for every two instructions, hence dropping the bottom bit
	.q(x_branchPredictionCacheReadOutput)
);

reg [3:0] x_branchPredictionCacheReadOutput;
	
// Command buffer definitions

typedef enum
{
	I_NOP = 0, // NOP must be instruction 0
	
	// Sphere and plane are carefully set up here so that sphere instructions will have bit 0 set, and planes bit 0 clear
	I_Sphere, // Arguments: X, Y, Z, Rad, InvRad
	I_Plane, // Arguments Normal X/Y/Z, Distance
	I_SphereSub,
	I_PlaneSub,
	I_SphereAnd,
	I_PlaneAnd,
	
	I_AABB, // Arguments Min X, Y, Z, Max X, Y, Z
	I_AABBSub,
	I_AABBAnd,
	I_RegisterHit, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15)
	I_RegisterHitNoReset, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15), does not reset hit state
	I_Checkerboard, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15) (should be used after RegisterHit with an OH modifier)
	I_ResetHitState,
	I_Jump, // Arguments: Target address (bits 8-23)
   I_ResetHitStateAndJump, // Arguments: Target address (bits 8-23), unconditionally resets hit state
	I_Origin, // Arguments: X, Y, Z
   I_Start,
	I_End
} Instruction;

typedef enum // 2 bits
{
	C_AL = 0, // Always
	C_OH = 1, // On hit
	C_NH = 2, // No hit
	C_ORH = 3 // On registered hit
} Condition;

// Active branch prediction cache bit mask
reg [3:0] u_branchPredictionCacheBitMask;
always @(*) begin
	u_branchPredictionCacheBitMask[0] = (~u_doingShadowRay) && (~u_doingSecondaryRay);
	u_branchPredictionCacheBitMask[1] = (u_doingShadowRay) && (~u_doingSecondaryRay);
	u_branchPredictionCacheBitMask[2] = (~u_doingShadowRay) && (u_doingSecondaryRay);
	u_branchPredictionCacheBitMask[3] = (u_doingShadowRay) && (u_doingSecondaryRay);
end

// Debug

always @(*) begin
	debugA = { 16'(s1_fetchPC), 16'(c1_newPC), 8'(c1_loadNewPC_tick), 8'(c1_finished_tick), 8'(x_start_tick), 8'(x_busy) };
end

reg [15:0] s1_fetchPC; // Program counter (technically two cycles ahead of the current PC, as this is where we are fetching from)
reg [15:0] s1_pcFIFO; // FIFO for tracking actual PC
reg [15:0] s1_actualPC; // The actual PC of the executing instruction
reg [1:0] s1_romLatencyCycleFlags;
reg c1_loadNewPC_tick; // Request to load new program counter, written from final cycle
reg [15:0] c1_newPC; // New program counter, written from final cycle
reg c1_finished_tick; // Finished event tick, written from final cycle

// Cycle 1
always @(posedge clock) begin

	if (reset) begin
		
		// Reset logic
		x_busy <= 0;
		
	end else if (x_start_tick) begin
		
		// Starting execution
		s1_fetchPC <= 0;
		s1_romLatencyCycleFlags <= 2'h3; // Need to wait two cycles before we start getting valid data from the ROM
		c2_instructionWord <= 0; // NOP
		x_busy <= 1;
		cycleCount <= 0;
		debugData <= 64'hC0DEC0DEC0DEC0DE;
		
	end else if (c1_finished_tick) begin
	
		// Finished
		x_busy <= 0;
		
	end else if (c1_loadNewPC_tick) begin
		
		// Loading new PC due to jump
      s1_fetchPC <= c1_newPC;
      s1_romLatencyCycleFlags <= 2'h3; // Need to wait two cycles before we start getting valid data from the ROM		
      c2_instructionWord <= 0; // NOP
		
	end else begin
	
		s1_romLatencyCycleFlags[0] <= s1_romLatencyCycleFlags[1];
		s1_romLatencyCycleFlags[1] <= 0;
		
		if (!x_busy) begin
		
			// When not busy, just push NOPs into the pipeline
			c2_instructionWord <= 0; // NOP
			
		end else begin
		
			cycleCount <= cycleCount + 1;
		
			// Normal operation
		
			s1_fetchPC <= s1_fetchPC + 1; // Default to going to the next instruction
		
			if (s1_romLatencyCycleFlags[0] == 0) begin
						
				// Read next instruction
				c2_instructionWord <= x_commandBufferRAMReadOutput;
				
				if (s1_actualPC[6:0] == debugCounter[31:25]) begin
					debugData <= x_commandBufferRAMReadOutput;
				end
				
				// Branch prediction
				
				case(x_commandBufferRAMReadOutput[5:0])
					I_Jump, I_ResetHitStateAndJump: begin					
						case (x_commandBufferRAMReadOutput[7:6])
							C_AL: begin
								// Unconditional branch, always taken
								s1_fetchPC <= x_commandBufferRAMReadOutput[23:8];
								s1_romLatencyCycleFlags <= 2'h3; // Need to wait two cycles before we start getting valid data from the ROM again	
							end
							default: begin
								// Conditional branch, needs prediction
								
								// We store one prediction per pair of instructions, with the prediction result inverting for odd PC addresses
								// This halves the necessary storage by using the fact that pairs of branches are rare, and when they do appear they're almost
								// always the conditional inverse of each other.
								// Note that this code must match the same logic in the execution cycle.
			
								if (((x_branchPredictionCacheReadOutput & u_branchPredictionCacheBitMask) != 0) != s1_actualPC[0]) begin
									// We're predicting that the branch will be taken
									s1_fetchPC <= x_commandBufferRAMReadOutput[23:8];
									s1_romLatencyCycleFlags <= 2'h3; // Need to wait two cycles before we start getting valid data from the ROM again	
								end
								
								// If we predict that it won't be taken, we don't need to do anything and just continue to the next instruction as normal									
							end
						endcase
					end
				endcase
				
			end else begin
				// Waiting for the ROM
				c2_instructionWord <= 0; // NOP
			end
		end
	end
	
	// Update PC FIFO
	
	s1_pcFIFO <= s1_fetchPC;
	s1_actualPC <= s1_pcFIFO;
		
	c2_pc <= s1_actualPC;
	c2_branchPredictionData <= x_branchPredictionCacheReadOutput;
end

reg [63:0] c2_instructionWord;
reg [3:0] c2_branchPredictionData;
reg [15:0] c2_pc;

// Cycle 2
always @(posedge clock) begin
	c3_instructionWord <= c2_instructionWord;
	c3_branchPredictionData <= c2_branchPredictionData;
	c3_pc <= c2_pc;
end

reg [63:0] c3_instructionWord;
reg [3:0] c3_branchPredictionData;
reg [15:0] c3_pc;
reg signed [31:0] s3_originX;
reg signed [31:0] s3_originY;
reg signed [31:0] s3_originZ;
reg c3_loadNewOrigin_tick; // Set from cycle 14
reg signed [31:0] c3_newOriginX; // Set from cycle 14
reg signed [31:0] c3_newOriginY;
reg signed [31:0] c3_newOriginZ; 

// Cycle 3
always @(posedge clock) begin

	if (c3_loadNewOrigin_tick) begin
		// Load a new origin (generally actually an old origin) when requested by cycle 14
		// This happens when the pipeline is flushed due to a branch mispredict, to restore
		// the old origin state
		s3_originX <= c3_newOriginX;
		s3_originY <= c3_newOriginY;
		s3_originZ <= c3_newOriginZ;
	end 
		
	if (!x_instructionInvalidated[3]) begin
		// Update origin if required

		case(c3_instructionWord[5:0])
			I_Start: begin
				s3_originX <= 0;
				s3_originY <= 0;
				s3_originZ <= 0;
			end
			I_Origin: begin					
				s3_originX <= ConvertFrom8dot7(c3_instructionWord[22:8]);
				s3_originY <= ConvertFrom8dot7(c3_instructionWord[37:23]);
				s3_originZ <= ConvertFrom8dot7(c3_instructionWord[52:38]);
			end
		endcase
	end

	c4_instructionWord <= c3_instructionWord;
	c4_branchPredictionData <= c3_branchPredictionData;
	c4_pc <= c3_pc;
	// Keep track of the previous origin so we can reset it upon a pipeline flush
	c4_oldOriginX <= s3_originX;
	c4_oldOriginY <= s3_originY;
	c4_oldOriginZ <= s3_originZ;	
end

reg [63:0] c4_instructionWord;
reg [3:0] c4_branchPredictionData;
reg [15:0] c4_pc;
reg signed [31:0] c4_oldOriginX;
reg signed [31:0] c4_oldOriginY;
reg signed [31:0] c4_oldOriginZ;

// Cycle 4
always @(posedge clock) begin
	c5_instructionWord <= c4_instructionWord;
	c5_branchPredictionData <= c4_branchPredictionData;
	c5_pc <= c4_pc;
	c5_oldOriginX <= c4_oldOriginX;
	c5_oldOriginY <= c4_oldOriginY;
	c5_oldOriginZ <= c4_oldOriginZ;
end

reg [63:0] c5_instructionWord;
reg [3:0] c5_branchPredictionData;
reg [15:0] c5_pc;
reg signed [31:0] c5_oldOriginX;
reg signed [31:0] c5_oldOriginY;
reg signed [31:0] c5_oldOriginZ;

// Cycle 5
always @(posedge clock) begin
	c6_instructionWord <= c5_instructionWord;
	c6_branchPredictionData <= c5_branchPredictionData;
	c6_pc <= c5_pc;
	c6_oldOriginX <= c5_oldOriginX;
	c6_oldOriginY <= c5_oldOriginY;
	c6_oldOriginZ <= c5_oldOriginZ;
end

reg [63:0] c6_instructionWord;
reg [3:0] c6_branchPredictionData;
reg [15:0] c6_pc;
reg signed [31:0] c6_oldOriginX;
reg signed [31:0] c6_oldOriginY;
reg signed [31:0] c6_oldOriginZ;

// Cycle 6
always @(posedge clock) begin
	c7_instructionWord <= c6_instructionWord;
	c7_branchPredictionData <= c6_branchPredictionData;
	c7_pc <= c6_pc;
	c7_oldOriginX <= c6_oldOriginX;
	c7_oldOriginY <= c6_oldOriginY;
	c7_oldOriginZ <= c6_oldOriginZ;
end

reg [63:0] c7_instructionWord;
reg [3:0] c7_branchPredictionData;
reg [15:0] c7_pc;
reg signed [31:0] c7_oldOriginX;
reg signed [31:0] c7_oldOriginY;
reg signed [31:0] c7_oldOriginZ;

// Cycle 7
always @(posedge clock) begin
	c8_instructionWord <= c7_instructionWord;
	c8_branchPredictionData <= c7_branchPredictionData;
	c8_pc <= c7_pc;
	c8_oldOriginX <= c7_oldOriginX;
	c8_oldOriginY <= c7_oldOriginY;
	c8_oldOriginZ <= c7_oldOriginZ;
end

reg [63:0] c8_instructionWord;
reg [3:0] c8_branchPredictionData;
reg [15:0] c8_pc;
reg signed [31:0] c8_oldOriginX;
reg signed [31:0] c8_oldOriginY;
reg signed [31:0] c8_oldOriginZ;

// Cycle 8
always @(posedge clock) begin
	c9_instructionWord <= c8_instructionWord;
	c9_branchPredictionData <= c8_branchPredictionData;
	c9_pc <= c8_pc;
	c9_oldOriginX <= c8_oldOriginX;
	c9_oldOriginY <= c8_oldOriginY;
	c9_oldOriginZ <= c8_oldOriginZ;
end

reg [63:0] c9_instructionWord;
reg [3:0] c9_branchPredictionData;
reg [15:0] c9_pc;
reg signed [31:0] c9_oldOriginX;
reg signed [31:0] c9_oldOriginY;
reg signed [31:0] c9_oldOriginZ;

// Cycle 9
always @(posedge clock) begin
	c10_instructionWord <= c9_instructionWord;
	c10_branchPredictionData <= c9_branchPredictionData;
	c10_pc <= c9_pc;
	c10_oldOriginX <= c9_oldOriginX;
	c10_oldOriginY <= c9_oldOriginY;
	c10_oldOriginZ <= c9_oldOriginZ;
end

reg [63:0] c10_instructionWord;
reg [3:0] c10_branchPredictionData;
reg [15:0] c10_pc;
reg signed [31:0] c10_oldOriginX;
reg signed [31:0] c10_oldOriginY;
reg signed [31:0] c10_oldOriginZ;

// Cycle 10
always @(posedge clock) begin
	c11_instructionWord <= c10_instructionWord;
	c11_branchPredictionData <= c10_branchPredictionData;
	c11_pc <= c10_pc;
	c11_oldOriginX <= c10_oldOriginX;
	c11_oldOriginY <= c10_oldOriginY;
	c11_oldOriginZ <= c10_oldOriginZ;
end

reg [63:0] c11_instructionWord;
reg [3:0] c11_branchPredictionData;
reg [15:0] c11_pc;
reg signed [31:0] c11_oldOriginX;
reg signed [31:0] c11_oldOriginY;
reg signed [31:0] c11_oldOriginZ;

// Cycle 11
always @(posedge clock) begin
	c12_instructionWord <= c11_instructionWord;
	c12_branchPredictionData <= c11_branchPredictionData;
	c12_pc <= c11_pc;
	c12_oldOriginX <= c11_oldOriginX;
	c12_oldOriginY <= c11_oldOriginY;
	c12_oldOriginZ <= c11_oldOriginZ;
end

reg [63:0] c12_instructionWord;
reg [3:0] c12_branchPredictionData;
reg [15:0] c12_pc;
reg signed [31:0] c12_oldOriginX;
reg signed [31:0] c12_oldOriginY;
reg signed [31:0] c12_oldOriginZ;

// Cycle 12
always @(posedge clock) begin
	c13_instructionWord <= c12_instructionWord;
	c13_branchPredictionData <= c12_branchPredictionData;
	c13_pc <= c12_pc;
	c13_oldOriginX <= c12_oldOriginX;
	c13_oldOriginY <= c12_oldOriginY;
	c13_oldOriginZ <= c12_oldOriginZ;
end

reg [63:0] c13_instructionWord;
reg [3:0] c13_branchPredictionData;
reg [15:0] c13_pc;
reg signed [31:0] c13_oldOriginX;
reg signed [31:0] c13_oldOriginY;
reg signed [31:0] c13_oldOriginZ;

// Cycle 13
always @(posedge clock) begin
	c14_instructionWord <= c13_instructionWord;
	c14_branchPredictionData <= c13_branchPredictionData;
	c14_pc <= c13_pc;
	c14_oldOriginX <= c13_oldOriginX;
	c14_oldOriginY <= c13_oldOriginY;
	c14_oldOriginZ <= c13_oldOriginZ;
end

// Hit information
// If HitEntryDepth < HitExitDepth then the ray hit something
reg signed [31:0] s14_hitEntryDepth; // Depth of the hit (entering the object)
reg signed [31:0] s14_hitExitDepth; // Depth of the hit (exiting the object)
reg signed [15:0] s14_hitNormalX; // Hit normal
reg signed [15:0] s14_hitNormalY;
reg signed [15:0] s14_hitNormalZ;
reg signed [31:0] s14_hitX; // Hit position (updates a cycle late)
reg signed [31:0] s14_hitY;
reg signed [31:0] s14_hitZ;
reg s14_objRegisteredHit; // Has this object registered a hit?
// One bit for each pipeline stage indicating if the instruction currently at that stage is valid (1 = invalid)
// This is x_ because it can be read from any pipeline stage (provided they check the right bit)
reg [14:1] x_instructionInvalidated;
reg [3:0] s14_branchPredictionCacheWriteInput;
reg s14_branchPredictionCacheWriteEnable;
reg [14:0] s14_branchPredictionCacheWriteAddr;

reg [63:0] c14_instructionWord;
reg [3:0] c14_branchPredictionData;
reg [15:0] c14_pc;
reg signed [31:0] c14_oldOriginX;
reg signed [31:0] c14_oldOriginY;
reg signed [31:0] c14_oldOriginZ;

// Cycle 14
always @(posedge clock) begin
	reg currentInstructionShouldExecute;
	reg signed [31:0] entryDepth;
	reg signed [31:0] exitDepth;
	reg signed [15:0] entryNormalX;
	reg signed [15:0] entryNormalY;
	reg signed [15:0] entryNormalZ;
	reg signed [15:0] exitNormalX;
	reg signed [15:0] exitNormalY;
	reg signed [15:0] exitNormalZ;
	reg signed [31:0] newEntryDepth;

	// Default values
	
	c1_finished_tick <= 0;
	c1_loadNewPC_tick <= 0;
	s14_branchPredictionCacheWriteEnable <= 0;
	s14_branchPredictionCacheWriteInput <= 0;
	s14_branchPredictionCacheWriteAddr <= 0;
	c3_loadNewOrigin_tick <= 0;
	
	// Decode condition
	
	case (c14_instructionWord[7:6])
		C_AL: begin
			currentInstructionShouldExecute = 1;
		end
		C_OH: begin
			currentInstructionShouldExecute = s14_hitEntryDepth < s14_hitExitDepth;
		end
		C_NH: begin
			currentInstructionShouldExecute = ~(s14_hitEntryDepth < s14_hitExitDepth);
		end
		C_ORH: begin
			currentInstructionShouldExecute = s14_objRegisteredHit;
		end
		default: begin
			currentInstructionShouldExecute = 0;
		end
	endcase
	
	// Update instruction invalidity FIFO

	x_instructionInvalidated[14:2] <= x_instructionInvalidated[13:1];
	x_instructionInvalidated[1] <= 0;
		
	if (!x_instructionInvalidated[14]) begin
	
		if (c14_instructionWord[5:0] != I_NOP) begin
			// Track valid instructions
			debugB[63:4] <= debugB[59:0];
			debugB[3:0] <= c14_pc[3:0];
			
			instructionDispatched <= instructionDispatched + 1;
		end
	
		case(c14_instructionWord[5:0])
			I_Start: begin
				if (currentInstructionShouldExecute) begin
					s14_hitEntryDepth = 32'h7FFFFFFF;
               s14_hitExitDepth = 0;
               s14_objRegisteredHit = 0;
               s14_regHit = 0;
					branchPredictionHits <= 0;
					branchPredictionMisses <= 0;
					instructionDispatched <= 1;
					debugB <= 'h0;
				end
			end
			I_Sphere, I_SphereSub, I_SphereAnd, I_Plane, I_PlaneSub, I_PlaneAnd, I_AABB, I_AABBSub, I_AABBAnd: begin
				if (currentInstructionShouldExecute) begin
				
					// Retrieve data from intersection units
				
					case(c14_instructionWord[5:0])
						I_Sphere, I_SphereSub, I_SphereAnd: begin
							entryDepth = c14_raySphere_EntryDepth;
							exitDepth = c14_raySphere_ExitDepth;
							entryNormalX = c14_raySphere_EntryNormalX;
							entryNormalY = c14_raySphere_EntryNormalY;
							entryNormalZ = c14_raySphere_EntryNormalZ;
							exitNormalX = c14_raySphere_ExitNormalX;
							exitNormalY = c14_raySphere_ExitNormalY;
							exitNormalZ = c14_raySphere_ExitNormalZ;
						end
						I_Plane, I_PlaneSub, I_PlaneAnd: begin
							entryDepth = c14_rayPlane_EntryDepth;
							exitDepth = c14_rayPlane_ExitDepth;
							entryNormalX = c14_rayPlane_EntryNormalX;
							entryNormalY = c14_rayPlane_EntryNormalY;
							entryNormalZ = c14_rayPlane_EntryNormalZ;
							exitNormalX = c14_rayPlane_ExitNormalX;
							exitNormalY = c14_rayPlane_ExitNormalY;
							exitNormalZ = c14_rayPlane_ExitNormalZ;
						end
						I_AABB, I_AABBSub, I_AABBAnd: begin
							entryDepth = c14_rayAABB_EntryDepth;
							exitDepth = c14_rayAABB_ExitDepth;
							entryNormalX = c14_rayAABB_EntryNormalX;
							entryNormalY = c14_rayAABB_EntryNormalY;
							entryNormalZ = c14_rayAABB_EntryNormalZ;
							exitNormalX = c14_rayAABB_ExitNormalX;
							exitNormalY = c14_rayAABB_ExitNormalY;
							exitNormalZ = c14_rayAABB_ExitNormalZ;
						end
					endcase
					
					// Merge
					
					newEntryDepth = s14_hitEntryDepth;
					
					case(c14_instructionWord[5:0])
						I_Sphere, I_Plane, I_AABB: begin
							// Normal object

							if (entryDepth < exitDepth) begin
								if (s14_hitEntryDepth >= s14_hitExitDepth) begin
									// No existing shape, just write our data to the buffer

									newEntryDepth = entryDepth;
									s14_hitExitDepth <= exitDepth;

									s14_hitNormalX <= entryNormalX;
									s14_hitNormalY <= entryNormalY;
									s14_hitNormalZ <= entryNormalZ;
								end else begin
									if (entryDepth < s14_hitEntryDepth) begin
										// Update entry point
										newEntryDepth = entryDepth;
										s14_hitNormalX <= entryNormalX;
										s14_hitNormalY <= entryNormalY;
										s14_hitNormalZ <= entryNormalZ;
									end

									if (exitDepth > s14_hitExitDepth) begin
										// Update exit point
										s14_hitExitDepth <= exitDepth;
									end
								end
							end
						end
						I_SphereSub, I_PlaneSub, I_AABBSub: begin
							// Subtractive object
							// This isn't completely accurate - we don't support clipping out the middle of an object,
							// which isn't an issue with only one subtraction but can cause problems if multiple subtractions
							// are performed.

							if (s14_hitEntryDepth < s14_hitExitDepth) begin // Only do this if there is an existing shape
								if ((entryDepth <= s14_hitEntryDepth) && (exitDepth >= s14_hitExitDepth)) begin
									// Clipping the entire shape
									newEntryDepth = 32'sh7FFFFFFF;
									s14_hitExitDepth <= 32'sh0;
								end else if ((entryDepth < s14_hitEntryDepth) && (exitDepth > s14_hitEntryDepth) && (exitDepth <= s14_hitExitDepth)) begin
									// Clipping the front part of the shape

									newEntryDepth = exitDepth;

									// Normal will be the inverse of our exit normal

									s14_hitNormalX <= -exitNormalX;
									s14_hitNormalY <= -exitNormalY;
									s14_hitNormalZ <= -exitNormalZ;
								end else if ((entryDepth > s14_hitEntryDepth) && (entryDepth < s14_hitExitDepth) && (exitDepth >= s14_hitExitDepth)) begin
									// Clipping the rear part of the shape

									s14_hitExitDepth <= entryDepth;
								end
							end
						end
						I_SphereAnd, I_PlaneAnd, I_AABBAnd: begin
							// ANDing object
							// This isn't completely accurate - we don't support clipping out the middle/rear of an object,
							// which isn't an issue with only one subtraction but can cause problems if multiple subtractions
							// are performed.

							if (s14_hitEntryDepth < s14_hitExitDepth) begin // Only do this if there is an existing shape
								if (entryDepth >= exitDepth) begin
									newEntryDepth = 32'sh7FFFFFFF;
									s14_hitExitDepth <= 32'sh0;
								end else begin
									if (entryDepth > s14_hitEntryDepth) begin
										newEntryDepth = entryDepth;

										s14_hitNormalX <= entryNormalX;
										s14_hitNormalY <= entryNormalY;
										s14_hitNormalZ <= entryNormalZ;
									end

									if (exitDepth < s14_hitExitDepth) begin
										s14_hitExitDepth <= exitDepth;
									end
								end
							end
						end
					endcase
		
					s14_hitEntryDepth <= newEntryDepth;
					
					// Update hit position
	
					s14_hitX <= u_rayStartX + FixedMul(u_rayDirX, newEntryDepth);
					s14_hitY <= u_rayStartY + FixedMul(u_rayDirY, newEntryDepth);
					s14_hitZ <= u_rayStartZ + FixedMul(u_rayDirZ, newEntryDepth);					
				end
			end
			I_Checkerboard: begin
				if (currentInstructionShouldExecute) begin					
					if (s14_hitX[fixedShift] ^ s14_hitZ[fixedShift]) begin
						s14_regHitAlbedo <= c14_instructionWord[31:16];
						s14_regHitReflectiveness <= c14_instructionWord[15:8];
					end
				end
			end
			I_RegisterHit, I_RegisterHitNoReset: begin
				if (currentInstructionShouldExecute) begin
					s14_objRegisteredHit <= 0;

					if (s14_hitEntryDepth < s14_hitExitDepth) begin
						if ((!s14_regHit) || (s14_hitEntryDepth < s14_regHitDepth)) begin
							s14_regHit <= 1;
							s14_regHitDepth <= s14_hitEntryDepth;
							s14_regHitX <= s14_hitX;
							s14_regHitY <= s14_hitY;
							s14_regHitZ <= s14_hitZ;
							s14_regHitNormalX <= s14_hitNormalX;
							s14_regHitNormalY <= s14_hitNormalY;
							s14_regHitNormalZ <= s14_hitNormalZ;
							s14_regHitAlbedo <= c14_instructionWord[31:16];
							s14_regHitReflectiveness <= c14_instructionWord[15:8];
							s14_objRegisteredHit <= 1;
							if (u_doingShadowRay) begin
								// Once we have a shadow ray hit we can early-out (invalidating the rest of the pipeline as we do so)
                        x_instructionInvalidated <= 'hFFFFFFFF;
                        c1_finished_tick <= 1;
							end
						end
						
						if (c14_instructionWord[5:0] != I_RegisterHitNoReset) begin
							// Reset hit state
										  
							s14_hitEntryDepth <= 32'sh7FFFFFFF;
							s14_hitExitDepth <= 32'sh0;
						end							
					end
				end
			end
			I_ResetHitState: begin
				if (currentInstructionShouldExecute) begin
					s14_hitEntryDepth <= 32'sh7FFFFFFF;
					s14_hitExitDepth <= 32'sh0;
				end
			end
			I_Jump, I_ResetHitStateAndJump: begin
			
				// Reset hit state before jumping (or not)
				if (c14_instructionWord[5:0] == I_ResetHitStateAndJump) begin
					s14_hitEntryDepth <= 32'sh7FFFFFFF;
					s14_hitExitDepth <= 32'sh0;
				end
				
				// See the dispatcher for why we test for != c14_pc[0]
				// If this logic changes the dispatcher needs to change too
				if (currentInstructionShouldExecute == (((c14_branchPredictionData & u_branchPredictionCacheBitMask) != 0) != c14_pc[0])) begin
					// Branch was predicted correctly, so nothing to do
					branchPredictionHits <= branchPredictionHits + 1;
				end else begin
					// Branch was mispredicted, so we need to tell the dispatcher to load the right PC value
				
					c1_loadNewPC_tick <= 1;
					
               // The target will either be the real branch target (if we are taking it), or the instruction after the
               // branch (if we aren't taking it but the dispatcher mis-predicted that we would)
					c1_newPC <= currentInstructionShouldExecute ? c14_instructionWord[23:8] : (c14_pc + 1);

					// Invalidate all current instructions in the pipeline
					x_instructionInvalidated <= 'hFFFFFFFF;
					
					// We also need to restore the previous origin value, as cycle 3 may have changed it due to a (now invalidated)
					// origin instruction

					c3_loadNewOrigin_tick <= 1;
					c3_newOriginX <= c14_oldOriginX;
					c3_newOriginY <= c14_oldOriginY;
					c3_newOriginZ <= c14_oldOriginZ;					
					
					// Finally, we need to write an updated prediction into the cache
					// We can cheat slightly to make the update simpler - we know the prediction is wrong, so we simply flip the
					// corresponding bit without actually calculating what we think the right value is					
					s14_branchPredictionCacheWriteInput <= c14_branchPredictionData ^ u_branchPredictionCacheBitMask;
					s14_branchPredictionCacheWriteEnable <= 1;
					s14_branchPredictionCacheWriteAddr <= c14_pc[15:1]; // Strip bottom bit as the cache references pairs of instructions
					
					branchPredictionMisses <= branchPredictionMisses + 1;
				end
			end
			I_End: begin
				if (currentInstructionShouldExecute) begin
					// Invalidate all current instructions in the pipeline
					x_instructionInvalidated <= 'hFFFFFFFF;
               c1_finished_tick <= 1;
				end
			end
		endcase				
	
	end
	
end

endmodule
`include "Config.sv"

`default_nettype none
//`define ENABLE_BUS_TRACING

module SNESInterface(
	// Fundamentals
	input wire clock,
	input wire romClock,
	input wire reset,
	
	// External cartirdge bus
	input wire [15:0] cartAddressBus,
	input wire cartCS_n, // ROM chip select signal from SNES (aka RD from cart bus)
	input wire cartOE_n, // ROM output enable signal from SNES
	output wire [7:0] cartDataBus,
	output wire cartDataBusOE_n,
	
	// SNES triggers
	output wire snesNewFrameTrigger_tick, // Goes high for one romClock clock when the SNES asks for a new frame to start
	input wire frameStart_tick, // Goes high for one romClock clock when a new frame actually starts
	
	// SNES framebuffer RAM access	
	input wire [14:0] snesFramebufferWriteAddress,
	input wire snesFramebufferWriteEN,
	input wire [7:0] snesFramebufferWriteData,
	
	// Status information
	input wire [8:0] statusInfo,
	
	// Command buffer RAM access
	output reg [15:0] commandBufferWriteAddress,
	output reg [63:0] commandBufferWriteData,
	output wire commandBufferWriteEN,
	
	// Renderer configuration data output
	output wire signed [31:0] snesRayStartX,
	output wire signed [31:0] snesRayStartY,
	output wire signed [31:0] snesRayStartZ,
	output wire signed [15:0] snesRayDirX,
	output wire signed [15:0] snesRayDirY,
	output wire signed [15:0] snesRayDirZ,
	output wire signed [15:0] snesRayXStepX,
	output wire signed [15:0] snesRayXStepY,
	output wire signed [15:0] snesRayXStepZ,
	output wire signed [15:0] snesRayYStepX,
	output wire signed [15:0] snesRayYStepY,
	output wire signed [15:0] snesRayYStepZ,
	output wire signed [15:0] snesLightDirX,
	output wire signed [15:0] snesLightDirY,
	output wire signed [15:0] snesLightDirZ,	
	
	// Debug
	output wire [63:0] debugA,
	output wire [63:0] debugB,
	output wire [63:0] debugC,
	output wire [63:0] debugD
`ifdef ENABLE_BUS_TRACING
	,input wire debugScrollUp,
	input wire debugScrollDown,
	output wire [63:0] debugExt[16]
`endif
);

always @(*) begin
	//debugB = { 8'h0, snesRayXStepX, snesRayXStepY, snesRayXStepZ };
	debugA = { 8'(currentSNESFramebufferReadBank), 24'h0, snesFramebufferWriteAddress, 8'h0, snesFramebufferWriteData };
	//debugB = { multOut, snesRayDirX, snesRayDirZ };
end	

import Maths::*;

reg [15:0] romReadAddr;
reg [7:0] romData;

// Test (i.e. program) ROM (64K)
TestROM64K TestROM64K_inst(
	.address(romReadAddr[14:0]), // Mask top bit because we want to map the bottom 32K twice for now
	.clock(romClock),
	.q(romData)
	);
	
reg currentSNESFramebufferReadBank; // Which of the banks are we reading from?
	
reg [7:0] snesFramebufferData_0;
reg [7:0] snesFramebufferData_1;
reg [7:0] snesFramebufferData;

always @(*) begin
	snesFramebufferData = currentSNESFramebufferReadBank ? snesFramebufferData_1 : snesFramebufferData_0;
end

// SNES framebuffer RAM

reg [14:0] snesFramebufferBank0Addr;
reg [14:0] snesFramebufferBank1Addr;

reg ioRegionMapLowerFB; // Are we mapping the lower framebuffer region (i.e. starting from address 16000)?
reg [14:0] snesFramebufferReadAddr;

assign snesFramebufferReadAddr = 15'(romReadAddr[13:0]) + (ioRegionMapLowerFB ? 15'd16000 : 15'd0);

always @(*) snesFramebufferBank0Addr = currentSNESFramebufferReadBank ? snesFramebufferWriteAddress : snesFramebufferReadAddr;
always @(*) snesFramebufferBank1Addr = (~currentSNESFramebufferReadBank) ? snesFramebufferWriteAddress : snesFramebufferReadAddr;

SNESFramebuffer SNESFramebuffer_bank0(
	.address(snesFramebufferBank0Addr),
	.clock(romClock),
	.data(snesFramebufferWriteData),
	.wren(currentSNESFramebufferReadBank & snesFramebufferWriteEN),
	.q(snesFramebufferData_0)
	);
	
SNESFramebuffer SNESFramebuffer_bank1(
	.address(snesFramebufferBank1Addr),
	.clock(romClock),
	.data(snesFramebufferWriteData),
	.wren((~currentSNESFramebufferReadBank) & snesFramebufferWriteEN),
	.q(snesFramebufferData_1)
	);
	

// Multiplication unit
// We use a full 32-bit multiplier here for simplicity/expandability but at present only
// the lower 16 bits of multA and multB are exposed to the SNES

reg signed [31:0] multA;
reg signed [31:0] multB;
reg signed [31:0] multOut;

always @(*) begin
	multOut = FixedMul(multA, multB);
end	

`ifdef ENABLE_BUS_TRACING

// Trace RAM

reg [10:0] traceWriteAddr;
reg [10:0] nextTraceWriteAddr;
reg [9:0] traceReadAddr;
reg [9:0] nextTraceReadAddr;
reg wantTraceWrite;
reg traceWR;
reg [63:0] traceDataIn;
reg [63:0] traceDataOut;
	
TraceRAM TraceRAM_inst(
	.clock(romClock),
	.data(traceDataIn),
	.rdaddress(traceReadAddr),
	.wraddress(traceWriteAddr[9:0]),
	.wren(traceWR),
	.q(traceDataOut)
	);	
`endif

// Filter and delay SNES input signals

reg [15:0] cartAddressFilter[7:0];

always @(posedge romClock) begin
	cartAddressFilter[7] <= cartAddressFilter[6];
	cartAddressFilter[6] <= cartAddressFilter[5];
	cartAddressFilter[5] <= cartAddressFilter[4];
	cartAddressFilter[4] <= cartAddressFilter[3];
	cartAddressFilter[3] <= cartAddressFilter[2];
	cartAddressFilter[2] <= cartAddressFilter[1];
	cartAddressFilter[1] <= cartAddressFilter[0];
	cartAddressFilter[0] <= cartAddressBus;
end

// OE is the ROM select signal
reg [7:0] oeFilter;
reg cartOE_n_filtered;

always @(posedge romClock) oeFilter = { oeFilter[6:0], cartOE_n };

// CS is the read signal
reg [7:0] csFilter;
reg cartCS_n_filtered;

always @(posedge romClock) csFilter = { csFilter[6:0], cartCS_n };

assign cartOE_n_filtered = oeFilter[0] | oeFilter[1] | oeFilter[2] | oeFilter[3] | oeFilter[4] | oeFilter[5] | oeFilter[6];
assign cartCS_n_filtered = csFilter[0] | csFilter[1] | csFilter[2] | csFilter[3] | csFilter[4] | csFilter[5] | csFilter[6];

// Is the SNES reading from ROM?
reg cartDoingROMRead;

always @(*) begin
	cartDoingROMRead = (~cartOE_n_filtered) & (~cartCS_n_filtered);
end

// Output to the data bus when the SNES is doing a read
assign cartDataBusOE_n = ~cartDoingROMRead;

reg wasCartDoingROMRead;

reg romReadInProgress; // Is a read happening? (only goes high once address is fully latched in)
reg cartRead_tick; // One clock signal when a read starts

// Latch in ROM address when a read starts
always @(posedge romClock or posedge reset) begin
	if (reset) begin
		wasCartDoingROMRead <= 0;
		romReadInProgress <= 0;
		cartRead_tick <= 0;
	end else begin
		// Use wasCartDoingROMRead so that we latch in on the first clock of the read, not the clock before
		romReadInProgress <= 0;
		cartRead_tick <= 0;
		if ((~cartDoingROMRead) || (~wasCartDoingROMRead)) begin
			// Get the first stable address from the last few addresses, because otherwise we get occasional glitches :-(
			if (cartAddressFilter[0] == cartAddressFilter[1]) begin
				romReadAddr <= cartAddressFilter[0];
			end else if (cartAddressFilter[1] == cartAddressFilter[2]) begin
				romReadAddr <= cartAddressFilter[1];
			end else if (cartAddressFilter[2] == cartAddressFilter[3]) begin
				romReadAddr <= cartAddressFilter[2];
			end else if (cartAddressFilter[3] == cartAddressFilter[4]) begin
				romReadAddr <= cartAddressFilter[3];
			end else begin
				romReadAddr <= cartAddressFilter[0]; // Give up
			end
			
			cartRead_tick <= ~romReadInProgress;
			romReadInProgress <= 1;			
		end
		wasCartDoingROMRead <= cartDoingROMRead;
	end	
end

always @(*) begin
	if (cartDoingROMRead == 0) begin
		cartDataBus = 8'h00;
	end else if (romReadAddr[14] == 0) begin
		// Lower 16K - IO region		
		
		case (romReadAddr)
			// Multiplier output
			SRTIO_MulO0: begin
				cartDataBus = multOut[7:0];
			end
			SRTIO_MulO1: begin
				cartDataBus = multOut[15:8];
			end
			SRTIO_MulO2: begin
				cartDataBus = multOut[23:16];
			end
			SRTIO_MulO3: begin
				cartDataBus = multOut[31:24];
			end
			
			// Status
			SRTIO_Status: begin
				cartDataBus = statusInfo;
			end
			
			// Framebuffer
			default: begin
				cartDataBus = snesFramebufferData;
			end
		endcase
	end else begin
		// Upper 16K - mapped to ROM
		cartDataBus = romData;
	end
end

// IO registers for communication

integer SRTIO_RegStart = 16'hBE80;
integer SRTIO_RegEnd = 16'hBEFF;

// Frame management
integer SRTIO_NewFrame = 16'hBE80;
integer SRTIO_MapUpperFB = 16'hBE81;
integer SRTIO_MapLowerFB = 16'hBE82;

// Ray parameters
integer SRTIO_RayStartX0 = 16'hBE83;
integer SRTIO_RayStartX1 = 16'hBE84;
integer SRTIO_RayStartX2 = 16'hBE85;
integer SRTIO_RayStartX3 = 16'hBE86;
integer SRTIO_RayStartY0 = 16'hBE87;
integer SRTIO_RayStartY1 = 16'hBE88;
integer SRTIO_RayStartY2 = 16'hBE89;
integer SRTIO_RayStartY3 = 16'hBE8A;
integer SRTIO_RayStartZ0 = 16'hBE8B;
integer SRTIO_RayStartZ1 = 16'hBE8C;
integer SRTIO_RayStartZ2 = 16'hBE8D;
integer SRTIO_RayStartZ3 = 16'hBE8E;
integer SRTIO_RayDirXL = 16'hBE8F;
integer SRTIO_RayDirXH = 16'hBE90;
integer SRTIO_RayDirYL = 16'hBE91;
integer SRTIO_RayDirYH = 16'hBE92;
integer SRTIO_RayDirZL = 16'hBE93;
integer SRTIO_RayDirZH = 16'hBE94;
integer SRTIO_RayDirXStepXL = 16'hBE95;
integer SRTIO_RayDirXStepXH = 16'hBE96;
integer SRTIO_RayDirXStepYL = 16'hBE97;
integer SRTIO_RayDirXStepYH = 16'hBE98;
integer SRTIO_RayDirXStepZL = 16'hBE99;
integer SRTIO_RayDirXStepZH = 16'hBE9A;
integer SRTIO_RayDirYStepXL = 16'hBE9B;
integer SRTIO_RayDirYStepXH = 16'hBE9C;
integer SRTIO_RayDirYStepYL = 16'hBE9D;
integer SRTIO_RayDirYStepYH = 16'hBE9E;
integer SRTIO_RayDirYStepZL = 16'hBE9F;
integer SRTIO_RayDirYStepZH = 16'hBEA0;

// Multiplication unit (O = A * B)
integer SRTIO_MulAL = 16'hBEA1;
integer SRTIO_MulAH = 16'hBEA2;
integer SRTIO_MulBL = 16'hBEA3;
integer SRTIO_MulBH = 16'hBEA4;
integer SRTIO_MulO0 = 16'hBEA5;
integer SRTIO_MulO1 = 16'hBEA6;
integer SRTIO_MulO2 = 16'hBEA7;
integer SRTIO_MulO3 = 16'hBEA8;

// Command buffer write
integer SRTIO_CmdWriteAddrL = 16'hBEA9; // Write address low byte
integer SRTIO_CmdWriteAddrH = 16'hBEAA; // Write address high byte
integer SRTIO_CmdWriteData1 = 16'hBEAB; // Write 1 bit of command data
integer SRTIO_CmdWriteData2 = 16'hBEAC; // Write 2 bits of command data
integer SRTIO_CmdWriteData3 = 16'hBEAD; // Write 3 bits of command data
integer SRTIO_CmdWriteData4 = 16'hBEAE; // Write 4 bits of command data
integer SRTIO_CmdWriteData5 = 16'hBEAF; // Write 5 bits of command data
integer SRTIO_CmdWriteData6 = 16'hBEB0; // Write 6 bits of command data
integer SRTIO_CmdWriteData7 = 16'hBEB1; // Write 7 bits of command data
integer SRTIO_CmdWriteData8 = 16'hBEB2; // Write 8 bits of command data

// Lighting
integer SRTIO_LightDirXL = 16'hBEB3;
integer SRTIO_LightDirXH = 16'hBEB4;
integer SRTIO_LightDirYL = 16'hBEB5;
integer SRTIO_LightDirYH = 16'hBEB6;
integer SRTIO_LightDirZL = 16'hBEB7;
integer SRTIO_LightDirZH = 16'hBEB8;

// Status information
integer SRTIO_Status = 16'hBEB9;

// Writes are done using reads from 0xBF00 to 0xBFFF
integer SRTIO_WriteProxyStart = 16'hBF00;
integer SRTIO_WriteProxyEnd = 16'hBFFF;

// The lower 7 bits of the last IO register read from (which will be the target for writes)
// Auto-increments after each write
reg [6:0] lastIOReg;

reg [15:0] debugCommandWriteCount;
reg [15:0] debugAddrWriteCount;
reg [5:0] commandBufferWriteValidBits; // How many bits of the current command being written are valid?

// IO register logic
always @(posedge romClock) begin
	if (reset) begin
		snesNewFrameTrigger_tick <= 0;
		ioRegionMapLowerFB <= 0;
		lastIOReg <= 0;
		multA <= 0;
		multB <= 0;
		snesRayStartX <= 0;
		snesRayStartY <= 0;
		snesRayStartZ <= 0;
		snesRayDirX <= 0;
		snesRayDirY <= 0;
		snesRayDirZ <= 0;
		snesRayXStepX <= 0;
		snesRayXStepY <= 0;
		snesRayXStepZ <= 0;
		snesRayYStepX <= 0;
		snesRayYStepY <= 0;
		snesRayYStepZ <= 0;
		snesLightDirX <= 0;
		snesLightDirY <= 0;
		snesLightDirZ <= 0;
		commandBufferWriteAddress <= 0;
		commandBufferWriteData <= 0;
		commandBufferWriteEN <= 0;
		commandBufferWriteValidBits <= 0;
		debugCommandWriteCount <= 0;
		debugAddrWriteCount <= 0;
	end else begin
		
		snesNewFrameTrigger_tick <= 0;
		commandBufferWriteEN <= 0;
		
		if (cartRead_tick) begin
		
			// Update last read register
			// We specifically exclude SRTIO_MapUpperFB and SRTIO_MapLowerFB from this because the SNES-side
			// code has to call them from the HBlank interrupt when it sets up the DMA, and if we update lastIOReg
			// then that can mess with regular code that was trying to perform other operations when the HBlank
			// occurred
			if ((romReadAddr >= SRTIO_RegStart) && (romReadAddr <= SRTIO_RegEnd) &&
			    (romReadAddr != SRTIO_MapUpperFB) && (romReadAddr != SRTIO_MapLowerFB)) begin
				lastIOReg <= romReadAddr[6:0];
			end
		
			if ((romReadAddr >= SRTIO_WriteProxyStart) && (romReadAddr <= SRTIO_WriteProxyEnd)) begin
				// Proxied write
				// Increment write address by default
				lastIOReg <= lastIOReg + 1;
				// Note that because lastIOReg only records the low 7 bits of the register index, we need to truncate the 
				// case statement constants here				
				case (lastIOReg)
					// Multiplication
					SRTIO_MulAL[6:0]: begin
						multA <= { multA[31:8], romReadAddr[7:0] };
					end
					SRTIO_MulAH[6:0]: begin
						// Sign-extend to cover the upper 16 bits
						multA <= { {16{romReadAddr[7]}}, romReadAddr[7:0], multA[7:0] };
					end
					SRTIO_MulBL[6:0]: begin
						multB <= { multB[31:8], romReadAddr[7:0] };
					end
					SRTIO_MulBH[6:0]: begin
						// Sign-extend to cover the upper 16 bits
						multB <= { {16{romReadAddr[7]}}, romReadAddr[7:0], multB[7:0] };
					end					
					// Ray parameters
					SRTIO_RayStartX0[6:0]: begin
						snesRayStartX <= { snesRayStartX[31:8], romReadAddr[7:0] };
					end
					SRTIO_RayStartX1[6:0]: begin
						snesRayStartX <= { snesRayStartX[31:16], romReadAddr[7:0], snesRayStartX[7:0] };
					end
					SRTIO_RayStartX2[6:0]: begin
						snesRayStartX <= { snesRayStartX[31:24], romReadAddr[7:0], snesRayStartX[15:0] };
					end
					SRTIO_RayStartX3[6:0]: begin
						snesRayStartX <= { romReadAddr[7:0], snesRayStartX[23:0] };
					end
					SRTIO_RayStartY0[6:0]: begin
						snesRayStartY <= { snesRayStartY[31:8], romReadAddr[7:0] };
					end
					SRTIO_RayStartY1[6:0]: begin
						snesRayStartY <= { snesRayStartY[31:16], romReadAddr[7:0], snesRayStartY[7:0] };
					end
					SRTIO_RayStartY2[6:0]: begin
						snesRayStartY <= { snesRayStartY[31:24], romReadAddr[7:0], snesRayStartY[15:0] };
					end
					SRTIO_RayStartY3[6:0]: begin
						snesRayStartY <= { romReadAddr[7:0], snesRayStartY[23:0] };
					end
					SRTIO_RayStartZ0[6:0]: begin
						snesRayStartZ <= { snesRayStartZ[31:8], romReadAddr[7:0] };					
					end
					SRTIO_RayStartZ1[6:0]: begin
						snesRayStartZ <= { snesRayStartZ[31:16], romReadAddr[7:0], snesRayStartZ[7:0] };
					end
					SRTIO_RayStartZ2[6:0]: begin
						snesRayStartZ <= { snesRayStartZ[31:24], romReadAddr[7:0], snesRayStartZ[15:0] };
					end
					SRTIO_RayStartZ3[6:0]: begin
						snesRayStartZ <= { romReadAddr[7:0], snesRayStartZ[23:0] };
					end
					SRTIO_RayDirXL[6:0]: begin
						snesRayDirX <= { snesRayDirX[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirXH[6:0]: begin
						snesRayDirX <= { romReadAddr[7:0], snesRayDirX[7:0] };
					end
					SRTIO_RayDirYL[6:0]: begin
						snesRayDirY <= { snesRayDirY[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirYH[6:0]: begin
						snesRayDirY <= { romReadAddr[7:0], snesRayDirY[7:0] };
					end
					SRTIO_RayDirZL[6:0]: begin
						snesRayDirZ <= { snesRayDirZ[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirZH[6:0]: begin
						snesRayDirZ <= { romReadAddr[7:0], snesRayDirZ[7:0] };
					end
					SRTIO_RayDirXStepXL[6:0]: begin
						snesRayXStepX <= { snesRayXStepX[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirXStepXH[6:0]: begin
						snesRayXStepX <= { romReadAddr[7:0], snesRayXStepX[7:0] };
					end
					SRTIO_RayDirXStepYL[6:0]: begin
						snesRayXStepY <= { snesRayXStepY[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirXStepYH[6:0]: begin
						snesRayXStepY <= { romReadAddr[7:0], snesRayXStepY[7:0] };
					end
					SRTIO_RayDirXStepZL[6:0]: begin
						snesRayXStepZ <= { snesRayXStepZ[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirXStepZH[6:0]: begin
						snesRayXStepZ <= { romReadAddr[7:0], snesRayXStepZ[7:0] };
					end
					SRTIO_RayDirYStepXL[6:0]: begin
						snesRayYStepX <= { snesRayYStepX[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirYStepXH[6:0]: begin
						snesRayYStepX <= { romReadAddr[7:0], snesRayYStepX[7:0] };
					end
					SRTIO_RayDirYStepYL[6:0]: begin
						snesRayYStepY <= { snesRayYStepY[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirYStepYH[6:0]: begin
						snesRayYStepY <= { romReadAddr[7:0], snesRayYStepY[7:0] };
					end
					SRTIO_RayDirYStepZL[6:0]: begin
						snesRayYStepZ <= { snesRayYStepZ[15:8], romReadAddr[7:0] };
					end
					SRTIO_RayDirYStepZH[6:0]: begin
						snesRayYStepZ <= { romReadAddr[7:0], snesRayYStepZ[7:0] };
					end
					// Light direction
					SRTIO_LightDirXL[6:0]: begin
						snesLightDirX <= { snesLightDirX[15:8], romReadAddr[7:0] };
					end
					SRTIO_LightDirXH[6:0]: begin
						snesLightDirX <= { romReadAddr[7:0], snesLightDirX[7:0] };
					end
					SRTIO_LightDirYL[6:0]: begin
						snesLightDirY <= { snesLightDirY[15:8], romReadAddr[7:0] };
					end
					SRTIO_LightDirYH[6:0]: begin
						snesLightDirY <= { romReadAddr[7:0], snesLightDirY[7:0] };
					end
					SRTIO_LightDirZL[6:0]: begin
						snesLightDirZ <= { snesLightDirZ[15:8], romReadAddr[7:0] };
					end
					SRTIO_LightDirZH[6:0]: begin
						snesLightDirZ <= { romReadAddr[7:0], snesLightDirZ[7:0] };
					end
					// Command buffer writes
					SRTIO_CmdWriteAddrL[6:0]: begin
						commandBufferWriteAddress <= { commandBufferWriteAddress[15:8], romReadAddr[7:0] };
						commandBufferWriteValidBits <= 0; // Writing address register resets data
						debugAddrWriteCount <= debugAddrWriteCount + 1;						
					end
					SRTIO_CmdWriteAddrH[6:0]: begin
						commandBufferWriteAddress <= { romReadAddr[7:0], commandBufferWriteAddress[7:0] };
						commandBufferWriteValidBits <= 0; // Writing address register resets data
						debugAddrWriteCount <= debugAddrWriteCount + 1;
					end				
					SRTIO_CmdWriteData1[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[62:0], romReadAddr[0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 1)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 1;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData2[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[61:0], romReadAddr[1:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 2)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 2;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData3[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[60:0], romReadAddr[2:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 3)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 3;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData4[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[59:0], romReadAddr[3:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 4)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 4;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData5[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[58:0], romReadAddr[4:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 5)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 5;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData6[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[57:0], romReadAddr[5:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 6)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 6;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData7[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[56:0], romReadAddr[6:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 7)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 7;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
					SRTIO_CmdWriteData8[6:0]: begin
						commandBufferWriteData <= { commandBufferWriteData[55:0], romReadAddr[7:0] }; // Push data into shift register
						
						if (commandBufferWriteValidBits == (64 - 8)) begin
							// We have a full word, so write it
							commandBufferWriteEN <= 1; // Initiate write
							commandBufferWriteAddress <= commandBufferWriteAddress + 1; // Increment write address
							commandBufferWriteValidBits <= 0;
						end else begin
							// Increment accumulated bit count
							commandBufferWriteValidBits <= commandBufferWriteValidBits + 8;
						end
						
						debugAddrWriteCount <= debugAddrWriteCount + 1;
						lastIOReg <= lastIOReg; // Inhibit address increment
					end
				endcase
			end else begin
				// Actual register read
				case (romReadAddr)
					SRTIO_NewFrame: begin
						snesNewFrameTrigger_tick <= 1;
					end
					SRTIO_MapUpperFB: begin
						ioRegionMapLowerFB <= 0;
					end
					SRTIO_MapLowerFB: begin
						ioRegionMapLowerFB <= 1;
					end
					default: begin
					end
				endcase
			end
		end		
	end
end

// Buffer swap on frame start
always @(posedge romClock) begin
	if (reset) begin
		currentSNESFramebufferReadBank <= 0;
	end else begin
		if (frameStart_tick) begin
			currentSNESFramebufferReadBank <= ~currentSNESFramebufferReadBank;
		end
	end
end

always @(*) begin
	debugB = { debugCommandWriteCount, debugAddrWriteCount, commandBufferWriteAddress, 16'hC0DE };
	debugC = { commandBufferWriteData };
end

`ifdef ENABLE_BUS_TRACING

// This code is for tracking down bus errors, and isn't hugely useful without dedicated test code on the SNES side

reg [15:0] lastRomReadAddr[1:0];
reg [15:0] expectedNextROMAddr;

always @(posedge cartDoingROMRead) begin
	lastRomReadAddr[1] <= lastRomReadAddr[0];
	lastRomReadAddr[0] <= romReadAddr;
end

always @(negedge cartDoingROMRead) begin
	expectedNextROMAddr <= romReadAddr + 1;
end

always @(*) begin
	wantTraceWrite = (traceWriteAddr < 1024);
end

reg[3:0] traceWriteStep;
reg[3:0] nextTraceWriteStep;

reg [15:0] traceCycleCounter;

reg hadInterestingData;

always @(posedge romClock) begin
	if (reset) begin
		traceWriteAddr = 0;
		nextTraceWriteStep = 0;
		traceCycleCounter = 0;
		hadInterestingData = 0;
	end else begin
		// 4 steps per capture cycle means we are capturing at 25Mhz (absent any trigger stuff)
		case (traceWriteStep)
			0: begin
				// Waiting for trigger
				if (wantTraceWrite) begin
					nextTraceWriteStep = 1;
				end else begin
					nextTraceWriteStep = 0;
				end
			end
			1: begin
				// Starting write
				traceWR = 1;
				traceDataIn = { 	romReadAddr, // 16 bits
										cartAddressBus, // 16 bits
										cartDataBus, // 8 bits
										testCount, //4'h0, // 4 bits
										hadInterestingData ? 4'h1 : 4'h0, // 4 bits
										cartDoingROMRead ? 4'h1 : 4'h0,// 4 bits
										cartDataBusOE_n ? 4'h1 : 4'h0, // 4 bits
										cartOE_n ? 4'h1 : 4'h0, // 4 bits
										cartCS_n ? 4'h1 : 4'h0 // 4 bits
								  };
				
				// Read of ROM 0xFFFF is the trigger from the SNES to indicate that something went wrong
				if ((cartDoingROMRead) && (romReadAddr == 16'hFFFF)) begin
					hadInterestingData = 1;
				end
				
				nextTraceWriteStep = 2;
			end
			2: begin
				// Finishing write
				traceWR = 0;
				nextTraceWriteStep = 3;
			end
			3: begin
				// Updating address
				if ((traceWriteAddr >= 800) && (~hadInterestingData)) begin
					traceWriteAddr = 0; // Keep wrapping until we get interesting data
				end else begin
					traceWriteAddr = nextTraceWriteAddr;
				end
/*				nextTraceWriteStep = 4;
			end
			4: begin*/
				// Waiting for trigger to end
				nextTraceWriteStep = 0;
				/*if (wantTraceWrite == 0) begin
					nextTraceWriteStep = 0;
				end else begin
					nextTraceWriteStep = 4;
				end*/
			end
		endcase
		
		traceCycleCounter <= traceCycleCounter + 1;
	end
end

always @(negedge romClock) begin
	traceWriteStep <= nextTraceWriteStep;
end

always @(*) begin
	nextTraceWriteAddr = traceWriteAddr + 1;
end

reg[3:0] readOutPhase;
reg[3:0] nextReadOutPhase;
reg[7:0] currentExtSlot;
reg[7:0] nextCurrentExtSlot;
reg[9:0] currentReadOffset;
reg[9:0] nextCurrentReadOffset;

always @(posedge romClock) begin
	if (reset) begin
		nextReadOutPhase = 0;
		nextCurrentExtSlot = 0;
		nextTraceReadAddr = currentReadOffset;
	end else begin	
		if (readOutPhase == 0) begin
			// Wait for RAM read to complete
			nextReadOutPhase = 1;
		end else if (readOutPhase == 1) begin
			// Wait for RAM read to complete
			nextReadOutPhase = 2;
		end else if (readOutPhase == 2) begin
			debugExt[currentExtSlot] =	traceDataOut;//{ traceDataOut[31:24], 8'h0, currentExtSlot, traceReadAddr };
			nextReadOutPhase = 3;
		end else if (readOutPhase == 3) begin
			if (currentExtSlot < 16) begin
				nextCurrentExtSlot = currentExtSlot + 1;			
				nextTraceReadAddr = traceReadAddr + 1;
			end else begin
				nextCurrentExtSlot = 0;
				nextTraceReadAddr = currentReadOffset;
			end
			nextReadOutPhase = 0;
		end
	end
end

always @(negedge romClock) begin
	readOutPhase <= nextReadOutPhase;
end

always @(negedge romClock) begin
	traceReadAddr <= nextTraceReadAddr;
end

always @(negedge romClock) begin
	currentExtSlot <= nextCurrentExtSlot;
end

reg oldKeyDown;
reg oldKeyUp;

always @(posedge romClock) begin
	oldKeyDown <= debugScrollDown;
	oldKeyUp <= debugScrollUp;
end

reg key0Pressed, key1Pressed;

assign key0Pressed = debugScrollDown & ~oldKeyDown;
assign key1Pressed = debugScrollUp & ~oldKeyUp;

always @(*) begin
	if (key0Pressed) begin
		nextCurrentReadOffset <= currentReadOffset + 16;
	end else if (key1Pressed) begin
		nextCurrentReadOffset <= currentReadOffset - 16;
	end else begin
		nextCurrentReadOffset <= currentReadOffset;
	end
end

always @(posedge romClock) begin
	if (reset) begin
		currentReadOffset = 0;
	end else begin
		currentReadOffset <= nextCurrentReadOffset;
	end
end

always @(*) begin
	debugD = { 32'h0, currentReadOffset };
end
`endif
/*
always @(*) begin	
	debugA = { proxyWriteCount, 8'h0, 8'(lastIOReg), cartAddressBus, 8'h0, cartDataBus };
end
*/
endmodule
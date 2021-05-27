`default_nettype none

// SuperRT by Ben Carter (c) 2021
// Marshal writes from multiple execution units to the RAM

// Note that some things are manually unrolled inline, so just changing this is not enough to alter the number of supported execution units
localparam integer NUM_EXEC_UNITS = 3;

module RendererWriteScheduler(
	// Fundamentals
	input wire clock,
	input wire reset,	
	
	// Connections to execution units
	output wire [(NUM_EXEC_UNITS - 1):0] execUnitWriteOK,
	input wire [(NUM_EXEC_UNITS - 1):0] execUnitWrite_tick,
	input wire [15:0] execUnitWriteAddr[(NUM_EXEC_UNITS - 1):0],
	input wire [15:0] execUnitWriteData[(NUM_EXEC_UNITS - 1):0],
	
	// Connections to framebuffer RAM
	input wire ramOK,
	output wire ramWrite,
	output wire [15:0] ramWriteAddr,
	output wire [15:0] ramWriteData,
	
	// Status output
	output wire busy,
	output wire [63:0] debug
);

// One-deep FIFO for each exec unit
reg [(NUM_EXEC_UNITS - 1):0] writePending; // Is there a write pending?
reg [(NUM_EXEC_UNITS - 1):0] writeExecute_tick; // Is the pending write being executed?
reg [15:0] pendingWriteAddr[(NUM_EXEC_UNITS - 1):0];
reg [15:0] pendingWriteData[(NUM_EXEC_UNITS - 1):0];
reg [$clog2(NUM_EXEC_UNITS):0] selectedExecUnit; // The exec unit we are currently writing for

// Exec units can write as long as there isn't anything in the FIFO

genvar j;
generate
	for (j = 0; j < NUM_EXEC_UNITS; j++) begin : writeOKAssignments
		assign execUnitWriteOK[j] = !writePending[j];
	end
endgenerate

// We are busy if there is any pending write

always @(*) begin
	busy = (writePending != '0);
end
	
// Latch in pending writes

always @(posedge clock or posedge reset) begin
	integer i;
	if (reset) begin
		writePending <= 'h0;
	end else begin
		for (i = 0; i < NUM_EXEC_UNITS; i++) begin
			if (execUnitWrite_tick[i]) begin
				pendingWriteAddr[i] <= execUnitWriteAddr[i];
				pendingWriteData[i] <= execUnitWriteData[i];
				writePending[i] <= 1;
			end else if (writeExecute_tick[i]) begin
				// Write has begun
				writePending[i] <= 0;
			end
		end
	end
end

// Multiplex the write address/data buses

always @(*) begin
	// Manually unrolled because Verilog :-(
	case(selectedExecUnit)
		0: begin
			ramWriteAddr = pendingWriteAddr[0];
			ramWriteData = pendingWriteData[0];
		end
		1: begin
			ramWriteAddr = pendingWriteAddr[1];
			ramWriteData = pendingWriteData[1];
		end
		2: begin
			ramWriteAddr = pendingWriteAddr[2];
			ramWriteData = pendingWriteData[2];
		end
		default: begin
			ramWriteAddr = pendingWriteAddr[0];
			ramWriteData = pendingWriteData[0];
		end
	endcase
end

// Write FIFO entries to RAM

typedef enum
{
	WP_Start = 0,
	WP_Write,
	WP_WriteWait
} WritePhase;

WritePhase writePhase = WP_Start;

reg [31:0] writeCount[(NUM_EXEC_UNITS-1):0];

assign debug = { writeCount[0], writeCount[2] };

always @(posedge clock or posedge reset) begin
	integer i;
	if (reset) begin
		writePhase <= WP_Start;
		writeExecute_tick <= '0;
		ramWrite <= 0;
		selectedExecUnit <= 0;
		for (i = 0; i < NUM_EXEC_UNITS; i++) begin
			writeCount[i] <= '0;
		end
	end else begin	
		writeExecute_tick <= '0;
		ramWrite <= 0;
	
		case (writePhase)
			WP_Start: begin
			
				writePhase <= WP_Start;
			
				// Wait for it to be OK to write to RAM, and for us to have something to write
				if (ramOK) begin
					// Manually unrolled because Verilog :-(
					
					if (writePending[0]) begin
						selectedExecUnit <= 'd0;
						writeCount[0] <= writeCount[0] + 1;
						writePhase <= WP_Write;
					end else if (writePending[1]) begin
						selectedExecUnit <= 'd1;
						writeCount[1] <= writeCount[1] + 1;
						writePhase <= WP_Write;
					end else if (writePending[2]) begin
						selectedExecUnit <= 'd2;
						writeCount[2] <= writeCount[2] + 1;
						writePhase <= WP_Write;
					end
				end
			end
			WP_Write: begin
				// Perform write
				ramWrite <= 1;
				writePhase <= WP_WriteWait;
			end
			WP_WriteWait: begin				
				// Signal write completion
				
				case(selectedExecUnit)
					'd0: writeExecute_tick[0] <= 1;
					'd1: writeExecute_tick[1] <= 1;
					'd2: writeExecute_tick[2] <= 1;					
				endcase				

				writePhase <= WP_Start;
			end
		endcase

	end
end

endmodule
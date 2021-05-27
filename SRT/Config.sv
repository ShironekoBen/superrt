`ifndef CONFIG_SV
`define CONFIG_SV

// Execution unit 0 is always enabled
`define ENABLE_EXECUTION_UNIT_1
`define ENABLE_EXECUTION_UNIT_2

// Turn on the HDMI debug display
//`define ENABLE_DEBUG_DISPLAY

// Turns out the pixel debug function
//`define ENABLE_DEBUG_PIXEL

// Set this to tint pixels according to which execution unit they came from
//`define TINT_EXECUTION_UNITS

`ifdef TINT_EXECUTION_UNITS
	// Enables tinting pixels to identify execution units
	`define ENABLE_TINT_PIXEL
`endif

`endif
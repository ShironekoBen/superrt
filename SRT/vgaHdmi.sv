`include "Config.sv"

/**
Descripcion,
Modulo que sincroniza las senales (hsync y vsync)
de un controlador VGA de 640x480 60hz, funciona con un reloj de 25Mhz

Ademas tiene las coordenadas de los pixeles H (eje x),
y de los pixeles V (eje y). Para enviar la senal RGB correspondiente
a cada pixel

-----------------------------------------------------------------------------
Author : Nicolas Hasbun, nhasbun@gmail.com
File   : vgaHdmi.v
Create : 2017-06-15 15:07:05
Editor : sublime text3, tab size (2)
-----------------------------------------------------------------------------

 2020-ish, Heavily modified by Ben Carter for SuperRT 

*/

//`define ENABLE_EXT_DEBUG

// **Info Source**
// https://eewiki.net/pages/viewpage.action?pageId=15925278

module vgaHdmi(
  // **input**
  input clock, clock50, reset,
  input switchR, switchG, switchB,
  input key0, key1,
  input enableRendererDisplay,
  input [15:0] fbROMData,
  input [63:0] debugA, // 64-bit debug values to display
  input [63:0] debugB,
  input [63:0] debugC,
  input [63:0] debugD,
  input [63:0] debugE,
`ifdef ENABLE_EXT_DEBUG  
  input [63:0] debugExt[16],
`endif

  // **output**
  output reg hsync, vsync,
  output reg dataEnable,
  output reg vgaClock,
  output reg [23:0] RGBchannel,
  output reg [15:0] fbROMAddr,
  output reg readRequest // High when making a read request
);

reg [9:0]pixelH, pixelV; // estado interno de pixeles del modulo

initial begin
  hsync      = 1;
  vsync      = 1;
  pixelH     = 0;
  pixelV     = 0;
  dataEnable = 0;
  vgaClock   = 0;
end

`ifdef ENABLE_EXT_DEBUG
reg [63:0] debugVal[21]; // Debug values to display
`else
reg [63:0] debugVal[5]; // Debug values to display
`endif
reg [6:0] charIndex; // 640px screen gives us 0-40
reg [7:0] smallCharIndex; // 640px screen gives us 0-80
reg [4:0] lineIndex;
reg [5:0] smallLineIndex;
reg [3:0] char;
reg [2:0] charX;
reg [2:0] charY;
wire charPixel;
`ifdef ENABLE_EXT_DEBUG
reg [3:0] smallChar;
reg [2:0] smallCharX;
reg [2:0] smallCharY;
wire smallCharPixel;
`endif

CharROM charROM(
	.char(char),
	.x(charX),
	.y(charY),
	.pixel(charPixel)
);

`ifdef ENABLE_EXT_DEBUG
CharROM smallCharROM(
	.char(smallChar),
	.x(smallCharX),
	.y(smallCharY),
	.pixel(smallCharPixel)
);
`endif

// Scan position/sync

always @(posedge clock or posedge reset) begin
  if(reset) begin
    hsync  <= 1;
    vsync  <= 1;
    pixelH <= 0;
    pixelV <= 0;
  end
  else begin
    // Display Horizontal
    if(pixelH==0 && pixelV!=524) begin
      pixelH<=pixelH+1'b1; // Move to next line
      pixelV<=pixelV+1'b1;
    end
    else if(pixelH==0 && pixelV==524) begin
      pixelH <= pixelH + 1'b1; // Back to start frame
      pixelV <= 0; // pixel 525
		// Latch in debug values at frame start
      debugVal[0] <= debugA;
      debugVal[1] <= debugB;
		debugVal[2] <= debugC;
		debugVal[3] <= debugD;
		debugVal[4] <= debugE;
`ifdef ENABLE_EXT_DEBUG
		debugVal[5] <= debugExt[1];
		debugVal[6] <= debugExt[2];
		debugVal[7] <= debugExt[3];
		debugVal[8] <= debugExt[4];
		debugVal[9] <= debugExt[5];
		debugVal[10] <= debugExt[6];
		debugVal[11] <= debugExt[7];
		debugVal[12] <= debugExt[8];
		debugVal[13] <= debugExt[9];
		debugVal[14] <= debugExt[10];
		debugVal[15] <= debugExt[11];
		debugVal[16] <= debugExt[12];
		debugVal[17] <= debugExt[13];
		debugVal[18] <= debugExt[14];
		debugVal[19] <= debugExt[15];
		debugVal[20] <= debugExt[16];
`endif
    end
    else if(pixelH<=640) pixelH <= pixelH + 1'b1; // Front Porch
    else if(pixelH<=656) pixelH <= pixelH + 1'b1; // Sync Pulse
    else if(pixelH<=752) begin
      pixelH <= pixelH + 1'b1; // HBlank area
      hsync  <= 0;
    end
    else if(pixelH<799) begin // Back Porch
      pixelH <= pixelH+1'b1;
      hsync  <= 1;
    end
    else pixelH<=0; // pixel 800	

    // Set VSync
    if(pixelV == 491 || pixelV == 492)
      vsync <= 0;
    else
      vsync <= 1;		
  end
end

//reg [15:0] scanoutFetchAddr;

//assign fbROMAddr = dataEnable ? scanoutFetchAddr : 'bz;

localparam displayWidth = 200 * 2;
localparam displayHeight = 160 * 2;
localparam displayX = (640 - displayWidth) / 2;
localparam displayY = (480 - displayHeight) / 2;		

reg [8:0] x = 0;
reg [8:0] y = 0;

// dataEnable signal
always @(posedge clock or posedge reset) begin
  if(reset)
    begin
      dataEnable <= 0;
	   readRequest <= 0;
	 end
  else begin
    if(pixelH >= 0 && pixelH < 640 && pixelV >= 0 && pixelV < 480)
	   begin
        dataEnable <= 1;
		  
		  // Output format is RRGGBB (24-bit)
		  
		  readRequest <= 0;
		  RGBchannel <= lineIndex[0] ? 24'h2080FF : 24'h104080; // Background alternates every line
		  		  
		  // Read data from ROM into RGB out
		  
		  if ((pixelV >= displayY) && (pixelV < (displayY + displayHeight)))
			  begin
				 y <= pixelV - displayY;
				 // It takes two clocks for us to get data back from the framebuffer, so we have to start two pixels early
				  
				 if ((pixelH >= (displayX - 2)) && (pixelH < (displayX + displayWidth)) && enableRendererDisplay)
					begin
					  if (pixelH >= displayX)
						  // Source framebuffer format is RGB (15 bits/pixel), so we duplicate the lowest bit
						  RGBchannel <= { fbROMData[4:0],   fbROMData[0],  fbROMData[0],  fbROMData[0], // R
											   fbROMData[9:5],   fbROMData[5],  fbROMData[5],  fbROMData[5], // G
												fbROMData[14:10], fbROMData[10], fbROMData[10], fbROMData[10] }; // B
					  else
						 RGBchannel <= 24'h000000; // Background
					  // Set address for next pixel (two pixels in advance)
					  if (pixelH == (displayX - 2))
						 x <= 0;
					  else
						 x <= x + 1;
					  readRequest <= 1;
					  fbROMAddr <= (y[8:1] * 200) + x[8:1]; // Strip bit 0 to scale up by 2
					end
			  end
			 
			if ((charIndex < 16) && (lineIndex == 0)) begin
		    // Debug display block #0 (register 0)
		    char <= debugVal[lineIndex] >> ((15 - charIndex) << 2);
			 RGBchannel <= charPixel ? (((charIndex & 4) != 0) ? 24'h20FF80 : 24'hFFFFFF) : 24'h000000;
			end else if ((charIndex < 16) && (lineIndex < 5)) begin
		    // Debug display block #1 (registers 1-4)
		    char <= debugVal[lineIndex] >> ((15 - charIndex) << 2);
			 RGBchannel <= charPixel ? (((charIndex & 4) != 0) ? 24'hFFFFFF : 24'hFF8020) : 24'h000000;
`ifdef ENABLE_EXT_DEBUG			 
		   end else if ((charIndex < 17) && (lineIndex >= 6) && (lineIndex < 22)) begin
		    // Debug display block #2 (registers 5-20)
		    char <= debugVal[(lineIndex - 6) + 4] >> ((15 - charIndex) << 2);
			 RGBchannel <= charPixel ? (((charIndex & 4) != 0) ? 24'hFFFFFF : 24'hFF8020) : 24'h000000;
			end else if ((smallCharIndex >= 34) && (smallCharIndex < (20 + 32)) && (lineIndex >= 5) &&  (lineIndex < 21)) begin
		    // Debug display block #3 (binary in two small stacked rows)
		    smallChar <= debugVal[((lineIndex - 5) + 4)][63 - (((smallLineIndex[0] == 1) ? 31 : 0) + (smallCharIndex - 34))] ? 1 : 0;
			 // Alternate colour for blocks of four bits
 			 RGBchannel <= smallCharPixel ? ((((smallCharIndex - 34) & 4) != 0) ? 24'hFFFFFF : 24'hFF8020) : 24'h000000;
`endif
		  end			 
		end
    else
	   begin
        dataEnable <= 0;
		  readRequest <= 0;
		end
  end
end

always @(*) begin
    charIndex <= pixelH[9:4];	 
    lineIndex <= pixelV[8:4];
	 charX <= pixelH[3:1];
	 charY <= pixelV[3:1];
`ifdef ENABLE_EXT_DEBUG
	 smallCharIndex <= pixelH[9:3];
	 smallLineIndex <= pixelV[8:3];
	 smallCharX <= pixelH[2:0];
	 smallCharY <= pixelV[2:0];
`endif
end

// VGA pixeClock signal
// Los clocks no deben manejar salidas directas, se debe usar un truco
initial vgaClock = 0;

always @(posedge clock50 or posedge reset) begin
  if(reset) vgaClock <= 0;
  else      vgaClock <= ~vgaClock;
end

endmodule
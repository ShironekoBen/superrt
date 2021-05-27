// SuperRT by Ben Carter (c) 2021
// Calculates ray-AABB intersection

reg signed [31:0] c14_rayAABB_EntryDepth;
reg signed [31:0] c14_rayAABB_ExitDepth;
reg signed [15:0] c14_rayAABB_EntryNormalX;
reg signed [15:0] c14_rayAABB_EntryNormalY;
reg signed [15:0] c14_rayAABB_EntryNormalZ;
reg signed [15:0] c14_rayAABB_ExitNormalX;
reg signed [15:0] c14_rayAABB_ExitNormalY;
reg signed [15:0] c14_rayAABB_ExitNormalZ;

// Cycle 2
always @(posedge clock) begin
	c3_ra_objMinX <= ConvertFrom8dot1(c2_instructionWord[16:8]);
	c3_ra_objMinY <= ConvertFrom8dot1(c2_instructionWord[25:17]);
	c3_ra_objMinZ <= ConvertFrom8dot1(c2_instructionWord[34:26]);
	c3_ra_objMaxX <= ConvertFrom8dot1(c2_instructionWord[43:35]);
	c3_ra_objMaxY <= ConvertFrom8dot1(c2_instructionWord[52:44]);
	c3_ra_objMaxZ <= ConvertFrom8dot1(c2_instructionWord[61:53]);
end

reg signed [31:0] c3_ra_objMinX;
reg signed [31:0] c3_ra_objMinY;
reg signed [31:0] c3_ra_objMinZ;
reg signed [31:0] c3_ra_objMaxX;
reg signed [31:0] c3_ra_objMaxY;
reg signed [31:0] c3_ra_objMaxZ;

// Cycle 3
always @(posedge clock) begin
	c4_ra_t0PosX <= (c3_ra_objMinX + s3_originX) - u_rayStartX;
	c4_ra_t0PosY <= (c3_ra_objMinY + s3_originY) - u_rayStartY;
	c4_ra_t0PosZ <= (c3_ra_objMinZ + s3_originZ) - u_rayStartZ;
	c4_ra_t1PosX <= (c3_ra_objMaxX + s3_originX) - u_rayStartX;
	c4_ra_t1PosY <= (c3_ra_objMaxY + s3_originY) - u_rayStartY;
	c4_ra_t1PosZ <= (c3_ra_objMaxZ + s3_originZ) - u_rayStartZ;
end

reg signed [31:0] c4_ra_t0PosX;
reg signed [31:0] c4_ra_t0PosY;
reg signed [31:0] c4_ra_t0PosZ;
reg signed [31:0] c4_ra_t1PosX;
reg signed [31:0] c4_ra_t1PosY;
reg signed [31:0] c4_ra_t1PosZ;

// Cycle 4
always @(posedge clock) begin
	c5_ra_t0x <= FixedMul48(c4_ra_t0PosX, u_rayDirRcpX);
	c5_ra_t0y <= FixedMul48(c4_ra_t0PosY, u_rayDirRcpY);
	c5_ra_t0z <= FixedMul48(c4_ra_t0PosZ, u_rayDirRcpZ);
	c5_ra_t1x <= FixedMul48(c4_ra_t1PosX, u_rayDirRcpX);
	c5_ra_t1y <= FixedMul48(c4_ra_t1PosY, u_rayDirRcpY);
	c5_ra_t1z <= FixedMul48(c4_ra_t1PosZ, u_rayDirRcpZ);
	
	c5_ra_t0PosX <= c4_ra_t0PosX;
	c5_ra_t0PosY <= c4_ra_t0PosY;
	c5_ra_t0PosZ <= c4_ra_t0PosZ;
	c5_ra_t1PosX <= c4_ra_t1PosX;
	c5_ra_t1PosY <= c4_ra_t1PosY;
	c5_ra_t1PosZ <= c4_ra_t1PosZ;
end


reg signed [31:0] c5_ra_t0x;
reg signed [31:0] c5_ra_t0y;
reg signed [31:0] c5_ra_t0z;
reg signed [31:0] c5_ra_t1x;
reg signed [31:0] c5_ra_t1y;
reg signed [31:0] c5_ra_t1z;
reg signed [31:0] c5_ra_t0PosX;
reg signed [31:0] c5_ra_t0PosY;
reg signed [31:0] c5_ra_t0PosZ;
reg signed [31:0] c5_ra_t1PosX;
reg signed [31:0] c5_ra_t1PosY;
reg signed [31:0] c5_ra_t1PosZ;

// Cycle 5
always @(posedge clock) begin
	c6_ra_tMinX <= (c5_ra_t0x < c5_ra_t1x) ? c5_ra_t0x : c5_ra_t1x;
	c6_ra_tMinY <= (c5_ra_t0y < c5_ra_t1y) ? c5_ra_t0y : c5_ra_t1y;
	c6_ra_tMinZ <= (c5_ra_t0z < c5_ra_t1z) ? c5_ra_t0z : c5_ra_t1z;
	
	c6_ra_tMaxX <= (c5_ra_t0x > c5_ra_t1x) ? c5_ra_t0x : c5_ra_t1x;
	c6_ra_tMaxY <= (c5_ra_t0y > c5_ra_t1y) ? c5_ra_t0y : c5_ra_t1y;
	c6_ra_tMaxZ <= (c5_ra_t0z > c5_ra_t1z) ? c5_ra_t0z : c5_ra_t1z;
	
	c6_ra_t0PosX <= c5_ra_t0PosX;
	c6_ra_t0PosY <= c5_ra_t0PosY;
	c6_ra_t0PosZ <= c5_ra_t0PosZ;
	c6_ra_t1PosX <= c5_ra_t1PosX;
	c6_ra_t1PosY <= c5_ra_t1PosY;
	c6_ra_t1PosZ <= c5_ra_t1PosZ;
end

reg signed [31:0] c6_ra_tMinX;
reg signed [31:0] c6_ra_tMinY;
reg signed [31:0] c6_ra_tMinZ;
reg signed [31:0] c6_ra_tMaxX;
reg signed [31:0] c6_ra_tMaxY;
reg signed [31:0] c6_ra_tMaxZ;
reg signed [31:0] c6_ra_t0PosX;
reg signed [31:0] c6_ra_t0PosY;
reg signed [31:0] c6_ra_t0PosZ;
reg signed [31:0] c6_ra_t1PosX;
reg signed [31:0] c6_ra_t1PosY;
reg signed [31:0] c6_ra_t1PosZ;

// Cycle 6
always @(posedge clock) begin
	// Bit-twiddling here with the normals works because -1 is 0xC000 and +1 is 0x4000, with only the sign bit differing
	
	reg signed [31:0] exitDepth;
	reg rayDirXIsEffectivelyZero;
	reg rayDirYIsEffectivelyZero;
	reg rayDirZIsEffectivelyZero;
	
	if ((c6_ra_tMaxX < c6_ra_tMaxY) && (c6_ra_tMaxX < c6_ra_tMaxZ)) begin
		exitDepth = c6_ra_tMaxX;
		c7_rayAABB_ExitNormalX <= { u_rayDirX[15], 15'h4000 }; // -1 or +1 according to ray direction
		c7_rayAABB_ExitNormalY <= 16'h0;
		c7_rayAABB_ExitNormalZ <= 16'h0;	
	end else if (c6_ra_tMaxY < c6_ra_tMaxZ) begin
		exitDepth = c6_ra_tMaxY;
		c7_rayAABB_ExitNormalX <= 16'h0;
		c7_rayAABB_ExitNormalY <= { u_rayDirY[15], 15'h4000 }; // -1 or +1 according to ray direction
		c7_rayAABB_ExitNormalZ <= 16'h0;	
	end else begin
		exitDepth = c6_ra_tMaxZ;
		c7_rayAABB_ExitNormalX <= 16'h0;
		c7_rayAABB_ExitNormalY <= 16'h0;	
		c7_rayAABB_ExitNormalZ <= { u_rayDirZ[15], 15'h4000 }; // -1 or +1 according to ray direction
	end

	// When rayDir is too small 1/rayDir is huge and overflows our 48-bit multiply, so ignore those values
   rayDirXIsEffectivelyZero = (u_rayDirX[15:8] == 8'h0) || (u_rayDirX[15:8] == 8'hFF);
   rayDirYIsEffectivelyZero = (u_rayDirY[15:8] == 8'h0) || (u_rayDirY[15:8] == 8'hFF);
   rayDirZIsEffectivelyZero = (u_rayDirZ[15:8] == 8'h0) || (u_rayDirZ[15:8] == 8'hFF);
	
	if ((exitDepth < 0) ||
		((rayDirXIsEffectivelyZero) && ((~c6_ra_t0PosX[31]) || (c6_ra_t1PosX[31]))) || // This is checking ((ra_t0PosX >= 0) || (ra_t1PosX < 0))
		((rayDirYIsEffectivelyZero) && ((~c6_ra_t0PosY[31]) || (c6_ra_t1PosY[31]))) ||
		((rayDirZIsEffectivelyZero) && ((~c6_ra_t0PosZ[31]) || (c6_ra_t1PosZ[31])))) begin
		
		// AABB entirely behind camera, or one of the ray direction components is zero and we're entirely outside the AABB on that axis
		c7_rayAABB_EntryDepth <= 32'h7FFFFFFF;
		c7_rayAABB_ExitDepth <= 32'h0;
		c7_rayAABB_EntryNormalX <= 16'h0;
		c7_rayAABB_EntryNormalY <= 16'h0;
		c7_rayAABB_EntryNormalZ <= 16'h0;			
	end else if ((c6_ra_tMinX > c6_ra_tMinY) && (c6_ra_tMinX > c6_ra_tMinZ)) begin
		c7_rayAABB_EntryDepth <= (c6_ra_tMinX > 0) ? c6_ra_tMinX : 0;
		c7_rayAABB_ExitDepth <= exitDepth;
		c7_rayAABB_EntryNormalX <= { ~u_rayDirX[15], 15'h4000 }; // -1 or +1 according to ray direction
		c7_rayAABB_EntryNormalY <= 16'h0;
		c7_rayAABB_EntryNormalZ <= 16'h0;	
	end else if (c6_ra_tMinY > c6_ra_tMinZ) begin
		c7_rayAABB_EntryDepth <= (c6_ra_tMinY > 0) ? c6_ra_tMinY : 0;
		c7_rayAABB_ExitDepth <= exitDepth;
		c7_rayAABB_EntryNormalX <= 16'h0;
		c7_rayAABB_EntryNormalY <= { ~u_rayDirY[15], 15'h4000 }; // -1 or +1 according to ray direction
		c7_rayAABB_EntryNormalZ <= 16'h0;	
	end else begin
		c7_rayAABB_EntryDepth <= (c6_ra_tMinZ > 0) ? c6_ra_tMinZ : 0;
		c7_rayAABB_ExitDepth <= exitDepth;
		c7_rayAABB_EntryNormalX <= 16'h0;
		c7_rayAABB_EntryNormalY <= 16'h0;	
		c7_rayAABB_EntryNormalZ <= { ~u_rayDirZ[15], 15'h4000 }; // -1 or +1 according to ray direction
	end
end

reg signed [31:0] c7_rayAABB_EntryDepth;
reg signed [31:0] c7_rayAABB_ExitDepth;
reg signed [15:0] c7_rayAABB_EntryNormalX;
reg signed [15:0] c7_rayAABB_EntryNormalY;
reg signed [15:0] c7_rayAABB_EntryNormalZ;
reg signed [15:0] c7_rayAABB_ExitNormalX;
reg signed [15:0] c7_rayAABB_ExitNormalY;
reg signed [15:0] c7_rayAABB_ExitNormalZ;

// Cycle 7
always @(posedge clock) begin
	c8_rayAABB_EntryDepth <= c7_rayAABB_EntryDepth;
	c8_rayAABB_ExitDepth <= c7_rayAABB_ExitDepth;
	c8_rayAABB_EntryNormalX <= c7_rayAABB_EntryNormalX;
	c8_rayAABB_EntryNormalY <= c7_rayAABB_EntryNormalY;
	c8_rayAABB_EntryNormalZ <= c7_rayAABB_EntryNormalZ;
	c8_rayAABB_ExitNormalX <= c7_rayAABB_ExitNormalX;
	c8_rayAABB_ExitNormalY <= c7_rayAABB_ExitNormalY;
	c8_rayAABB_ExitNormalZ <= c7_rayAABB_ExitNormalZ;
end

reg signed [31:0] c8_rayAABB_EntryDepth;
reg signed [31:0] c8_rayAABB_ExitDepth;
reg signed [15:0] c8_rayAABB_EntryNormalX;
reg signed [15:0] c8_rayAABB_EntryNormalY;
reg signed [15:0] c8_rayAABB_EntryNormalZ;
reg signed [15:0] c8_rayAABB_ExitNormalX;
reg signed [15:0] c8_rayAABB_ExitNormalY;
reg signed [15:0] c8_rayAABB_ExitNormalZ;

// Cycle 8
always @(posedge clock) begin
	c9_rayAABB_EntryDepth <= c8_rayAABB_EntryDepth;
	c9_rayAABB_ExitDepth <= c8_rayAABB_ExitDepth;
	c9_rayAABB_EntryNormalX <= c8_rayAABB_EntryNormalX;
	c9_rayAABB_EntryNormalY <= c8_rayAABB_EntryNormalY;
	c9_rayAABB_EntryNormalZ <= c8_rayAABB_EntryNormalZ;
	c9_rayAABB_ExitNormalX <= c8_rayAABB_ExitNormalX;
	c9_rayAABB_ExitNormalY <= c8_rayAABB_ExitNormalY;
	c9_rayAABB_ExitNormalZ <= c8_rayAABB_ExitNormalZ;
end

reg signed [31:0] c9_rayAABB_EntryDepth;
reg signed [31:0] c9_rayAABB_ExitDepth;
reg signed [15:0] c9_rayAABB_EntryNormalX;
reg signed [15:0] c9_rayAABB_EntryNormalY;
reg signed [15:0] c9_rayAABB_EntryNormalZ;
reg signed [15:0] c9_rayAABB_ExitNormalX;
reg signed [15:0] c9_rayAABB_ExitNormalY;
reg signed [15:0] c9_rayAABB_ExitNormalZ;

// Cycle 9
always @(posedge clock) begin
	c10_rayAABB_EntryDepth <= c9_rayAABB_EntryDepth;
	c10_rayAABB_ExitDepth <= c9_rayAABB_ExitDepth;
	c10_rayAABB_EntryNormalX <= c9_rayAABB_EntryNormalX;
	c10_rayAABB_EntryNormalY <= c9_rayAABB_EntryNormalY;
	c10_rayAABB_EntryNormalZ <= c9_rayAABB_EntryNormalZ;
	c10_rayAABB_ExitNormalX <= c9_rayAABB_ExitNormalX;
	c10_rayAABB_ExitNormalY <= c9_rayAABB_ExitNormalY;
	c10_rayAABB_ExitNormalZ <= c9_rayAABB_ExitNormalZ;
end

reg signed [31:0] c10_rayAABB_EntryDepth;
reg signed [31:0] c10_rayAABB_ExitDepth;
reg signed [15:0] c10_rayAABB_EntryNormalX;
reg signed [15:0] c10_rayAABB_EntryNormalY;
reg signed [15:0] c10_rayAABB_EntryNormalZ;
reg signed [15:0] c10_rayAABB_ExitNormalX;
reg signed [15:0] c10_rayAABB_ExitNormalY;
reg signed [15:0] c10_rayAABB_ExitNormalZ;

// Cycle 10
always @(posedge clock) begin
	c11_rayAABB_EntryDepth <= c10_rayAABB_EntryDepth;
	c11_rayAABB_ExitDepth <= c10_rayAABB_ExitDepth;
	c11_rayAABB_EntryNormalX <= c10_rayAABB_EntryNormalX;
	c11_rayAABB_EntryNormalY <= c10_rayAABB_EntryNormalY;
	c11_rayAABB_EntryNormalZ <= c10_rayAABB_EntryNormalZ;
	c11_rayAABB_ExitNormalX <= c10_rayAABB_ExitNormalX;
	c11_rayAABB_ExitNormalY <= c10_rayAABB_ExitNormalY;
	c11_rayAABB_ExitNormalZ <= c10_rayAABB_ExitNormalZ;
end

reg signed [31:0] c11_rayAABB_EntryDepth;
reg signed [31:0] c11_rayAABB_ExitDepth;
reg signed [15:0] c11_rayAABB_EntryNormalX;
reg signed [15:0] c11_rayAABB_EntryNormalY;
reg signed [15:0] c11_rayAABB_EntryNormalZ;
reg signed [15:0] c11_rayAABB_ExitNormalX;
reg signed [15:0] c11_rayAABB_ExitNormalY;
reg signed [15:0] c11_rayAABB_ExitNormalZ;

// Cycle 11
always @(posedge clock) begin
	c12_rayAABB_EntryDepth <= c11_rayAABB_EntryDepth;
	c12_rayAABB_ExitDepth <= c11_rayAABB_ExitDepth;
	c12_rayAABB_EntryNormalX <= c11_rayAABB_EntryNormalX;
	c12_rayAABB_EntryNormalY <= c11_rayAABB_EntryNormalY;
	c12_rayAABB_EntryNormalZ <= c11_rayAABB_EntryNormalZ;
	c12_rayAABB_ExitNormalX <= c11_rayAABB_ExitNormalX;
	c12_rayAABB_ExitNormalY <= c11_rayAABB_ExitNormalY;
	c12_rayAABB_ExitNormalZ <= c11_rayAABB_ExitNormalZ;
end

reg signed [31:0] c12_rayAABB_EntryDepth;
reg signed [31:0] c12_rayAABB_ExitDepth;
reg signed [15:0] c12_rayAABB_EntryNormalX;
reg signed [15:0] c12_rayAABB_EntryNormalY;
reg signed [15:0] c12_rayAABB_EntryNormalZ;
reg signed [15:0] c12_rayAABB_ExitNormalX;
reg signed [15:0] c12_rayAABB_ExitNormalY;
reg signed [15:0] c12_rayAABB_ExitNormalZ;

// Cycle 12
always @(posedge clock) begin
	c13_rayAABB_EntryDepth <= c12_rayAABB_EntryDepth;
	c13_rayAABB_ExitDepth <= c12_rayAABB_ExitDepth;
	c13_rayAABB_EntryNormalX <= c12_rayAABB_EntryNormalX;
	c13_rayAABB_EntryNormalY <= c12_rayAABB_EntryNormalY;
	c13_rayAABB_EntryNormalZ <= c12_rayAABB_EntryNormalZ;
	c13_rayAABB_ExitNormalX <= c12_rayAABB_ExitNormalX;
	c13_rayAABB_ExitNormalY <= c12_rayAABB_ExitNormalY;
	c13_rayAABB_ExitNormalZ <= c12_rayAABB_ExitNormalZ;
end

reg signed [31:0] c13_rayAABB_EntryDepth;
reg signed [31:0] c13_rayAABB_ExitDepth;
reg signed [15:0] c13_rayAABB_EntryNormalX;
reg signed [15:0] c13_rayAABB_EntryNormalY;
reg signed [15:0] c13_rayAABB_EntryNormalZ;
reg signed [15:0] c13_rayAABB_ExitNormalX;
reg signed [15:0] c13_rayAABB_ExitNormalY;
reg signed [15:0] c13_rayAABB_ExitNormalZ;

// Cycle 13
always @(posedge clock) begin
	c14_rayAABB_EntryDepth <= c13_rayAABB_EntryDepth;
	c14_rayAABB_ExitDepth <= c13_rayAABB_ExitDepth;
	c14_rayAABB_EntryNormalX <= c13_rayAABB_EntryNormalX;
	c14_rayAABB_EntryNormalY <= c13_rayAABB_EntryNormalY;
	c14_rayAABB_EntryNormalZ <= c13_rayAABB_EntryNormalZ;
	c14_rayAABB_ExitNormalX <= c13_rayAABB_ExitNormalX;
	c14_rayAABB_ExitNormalY <= c13_rayAABB_ExitNormalY;
	c14_rayAABB_ExitNormalZ <= c13_rayAABB_ExitNormalZ;
end
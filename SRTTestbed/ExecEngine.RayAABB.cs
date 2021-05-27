using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    partial class ExecEngine
    {
        int c14_RayAABB_EntryDepth;
        int c14_RayAABB_ExitDepth;
        Int16 c14_RayAABB_EntryNormalX;
        Int16 c14_RayAABB_EntryNormalY;
        Int16 c14_RayAABB_EntryNormalZ;
        Int16 c14_RayAABB_ExitNormalX;
        Int16 c14_RayAABB_ExitNormalY;
        Int16 c14_RayAABB_ExitNormalZ;

        void RayAABB_Tick(ExecEngine destData)
        {
            RayAABB_Cycle2(destData);
            RayAABB_Cycle3(destData);
            RayAABB_Cycle4(destData);
            RayAABB_Cycle5(destData);
            RayAABB_Cycle6(destData);
            RayAABB_Cycle7(destData);
            RayAABB_Cycle8(destData);
            RayAABB_Cycle9(destData);
            RayAABB_Cycle10(destData);
            RayAABB_Cycle11(destData);
            RayAABB_Cycle12(destData);
            RayAABB_Cycle13(destData);
        }

        void RayAABB_Cycle2(ExecEngine destData)
        {
            destData.c3_ra_ObjMinX = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 8) & 0x1FF));
            destData.c3_ra_ObjMinY = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 17) & 0x1FF));
            destData.c3_ra_ObjMinZ = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 26) & 0x1FF));
            destData.c3_ra_ObjMaxX = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 35) & 0x1FF));
            destData.c3_ra_ObjMaxY = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 44) & 0x1FF));
            destData.c3_ra_ObjMaxZ = FixedMaths.ConvertFrom8Dot1((UInt16)((c2_InstructionWord >> 53) & 0x1FF));

            x_PipelineTracer?.AppendLine(2, "  AABB " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMinX) + ", " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMinY) + ", " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMinZ) + " - " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMaxX) + ", " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMaxY) + ", " + FixedMaths.FixedToFloat(destData.c3_ra_ObjMaxZ));
        }

        int c3_ra_ObjMinX;
        int c3_ra_ObjMinY;
        int c3_ra_ObjMinZ;
        int c3_ra_ObjMaxX;
        int c3_ra_ObjMaxY;
        int c3_ra_ObjMaxZ;

        void RayAABB_Cycle3(ExecEngine destData)
        {
            // Perform AABB intersection

            destData.c4_ra_t0PosX = (c3_ra_ObjMinX + s3_originX) - u_RayStartX;
            destData.c4_ra_t0PosY = (c3_ra_ObjMinY + s3_originY) - u_RayStartY;
            destData.c4_ra_t0PosZ = (c3_ra_ObjMinZ + s3_originZ) - u_RayStartZ;
            destData.c4_ra_t1PosX = (c3_ra_ObjMaxX + s3_originX) - u_RayStartX;
            destData.c4_ra_t1PosY = (c3_ra_ObjMaxY + s3_originY) - u_RayStartY;
            destData.c4_ra_t1PosZ = (c3_ra_ObjMaxZ + s3_originZ) - u_RayStartZ;
        }

        int c4_ra_t0PosX;
        int c4_ra_t0PosY;
        int c4_ra_t0PosZ;
        int c4_ra_t1PosX;
        int c4_ra_t1PosY;
        int c4_ra_t1PosZ;

        void RayAABB_Cycle4(ExecEngine destData)
        {
            x_PipelineTracer?.AppendLine(4, "    AABB t0PosX = " + FixedMaths.FixedToFloat(c4_ra_t0PosX) + ", " + FixedMaths.FixedToFloat(c4_ra_t0PosY) + ", " + FixedMaths.FixedToFloat(c4_ra_t0PosZ));
            x_PipelineTracer?.AppendLine(4, "    AABB t1PosX = " + FixedMaths.FixedToFloat(c4_ra_t1PosX) + ", " + FixedMaths.FixedToFloat(c4_ra_t1PosY) + ", " + FixedMaths.FixedToFloat(c4_ra_t1PosZ));
            x_PipelineTracer?.AppendLine(4, "    AABB RayDir = " + FixedMaths.FixedToFloat(u_RayDirX) + ", " + FixedMaths.FixedToFloat(u_RayDirY) + ", " + FixedMaths.FixedToFloat(u_RayDirZ));
            x_PipelineTracer?.AppendLine(4, "    AABB RayDirRcp = " + FixedMaths.FixedToFloat(u_RayDirRcpX) + ", " + FixedMaths.FixedToFloat(u_RayDirRcpY) + ", " + FixedMaths.FixedToFloat(u_RayDirRcpZ));

            destData.c5_ra_t0x = FixedMaths.FixedMul48(c4_ra_t0PosX, u_RayDirRcpX);
            destData.c5_ra_t0y = FixedMaths.FixedMul48(c4_ra_t0PosY, u_RayDirRcpY);
            destData.c5_ra_t0z = FixedMaths.FixedMul48(c4_ra_t0PosZ, u_RayDirRcpZ);
            destData.c5_ra_t1x = FixedMaths.FixedMul48(c4_ra_t1PosX, u_RayDirRcpX);
            destData.c5_ra_t1y = FixedMaths.FixedMul48(c4_ra_t1PosY, u_RayDirRcpY);
            destData.c5_ra_t1z = FixedMaths.FixedMul48(c4_ra_t1PosZ, u_RayDirRcpZ);

            x_PipelineTracer?.AppendLine(4, "    AABB t0x = " + FixedMaths.FixedToFloat(destData.c5_ra_t0x) + ", " + FixedMaths.FixedToFloat(destData.c5_ra_t0y) + ", " + FixedMaths.FixedToFloat(destData.c5_ra_t0z));
            x_PipelineTracer?.AppendLine(4, "    AABB t1x = " + FixedMaths.FixedToFloat(destData.c5_ra_t1x) + ", " + FixedMaths.FixedToFloat(destData.c5_ra_t1y) + ", " + FixedMaths.FixedToFloat(destData.c5_ra_t1z));

            destData.c5_ra_t0PosX = c4_ra_t0PosX;
            destData.c5_ra_t0PosY = c4_ra_t0PosY;
            destData.c5_ra_t0PosZ = c4_ra_t0PosZ;
            destData.c5_ra_t1PosX = c4_ra_t1PosX;
            destData.c5_ra_t1PosY = c4_ra_t1PosY;
            destData.c5_ra_t1PosZ = c4_ra_t1PosZ;
        }

        int c5_ra_t0x;
        int c5_ra_t0y;
        int c5_ra_t0z;
        int c5_ra_t1x;
        int c5_ra_t1y;
        int c5_ra_t1z;
        int c5_ra_t0PosX;
        int c5_ra_t0PosY;
        int c5_ra_t0PosZ;
        int c5_ra_t1PosX;
        int c5_ra_t1PosY;
        int c5_ra_t1PosZ;

        void RayAABB_Cycle5(ExecEngine destData)
        {
            destData.c6_ra_tMinX = Math.Min(c5_ra_t0x, c5_ra_t1x);
            destData.c6_ra_tMinY = Math.Min(c5_ra_t0y, c5_ra_t1y);
            destData.c6_ra_tMinZ = Math.Min(c5_ra_t0z, c5_ra_t1z);

            destData.c6_ra_tMaxX = Math.Max(c5_ra_t0x, c5_ra_t1x);
            destData.c6_ra_tMaxY = Math.Max(c5_ra_t0y, c5_ra_t1y);
            destData.c6_ra_tMaxZ = Math.Max(c5_ra_t0z, c5_ra_t1z);

            x_PipelineTracer?.AppendLine(5, "    AABB t0   = " + FixedMaths.FixedToFloat(c5_ra_t0x) + ", " + FixedMaths.FixedToFloat(c5_ra_t0y) + ", " + FixedMaths.FixedToFloat(c5_ra_t0z));
            x_PipelineTracer?.AppendLine(5, "    AABB t1   = " + FixedMaths.FixedToFloat(c5_ra_t1x) + ", " + FixedMaths.FixedToFloat(c5_ra_t1y) + ", " + FixedMaths.FixedToFloat(c5_ra_t1z));
            x_PipelineTracer?.AppendLine(5, "    AABB tMin = " + FixedMaths.FixedToFloat(destData.c6_ra_tMinX) + ", " + FixedMaths.FixedToFloat(destData.c6_ra_tMinY) + ", " + FixedMaths.FixedToFloat(destData.c6_ra_tMinZ));
            x_PipelineTracer?.AppendLine(5, "    AABB tMax = " + FixedMaths.FixedToFloat(destData.c6_ra_tMaxX) + ", " + FixedMaths.FixedToFloat(destData.c6_ra_tMaxY) + ", " + FixedMaths.FixedToFloat(destData.c6_ra_tMaxZ));

            destData.c6_ra_t0PosX = c5_ra_t0PosX;
            destData.c6_ra_t0PosY = c5_ra_t0PosY;
            destData.c6_ra_t0PosZ = c5_ra_t0PosZ;
            destData.c6_ra_t1PosX = c5_ra_t1PosX;
            destData.c6_ra_t1PosY = c5_ra_t1PosY;
            destData.c6_ra_t1PosZ = c5_ra_t1PosZ;
        }

        int c6_ra_tMinX;
        int c6_ra_tMinY;
        int c6_ra_tMinZ;
        int c6_ra_tMaxX;
        int c6_ra_tMaxY;
        int c6_ra_tMaxZ;
        int c6_ra_t0PosX;
        int c6_ra_t0PosY;
        int c6_ra_t0PosZ;
        int c6_ra_t1PosX;
        int c6_ra_t1PosY;
        int c6_ra_t1PosZ;

        void RayAABB_Cycle6(ExecEngine destData)
        {
            Int16 fixedOne = (Int16)FixedMaths.FloatToFixed(1.0f);
            Int16 fixedMinusOne = (Int16)FixedMaths.FloatToFixed(-1.0f);

            int exitDepth;

            if ((c6_ra_tMaxX < c6_ra_tMaxY) && (c6_ra_tMaxX < c6_ra_tMaxZ))
            {
                // Ray hit X side of box
                exitDepth = c6_ra_tMaxX;
                destData.c7_RayAABB_ExitNormalX = (u_RayDirX > 0) ? fixedOne : fixedMinusOne;
                destData.c7_RayAABB_ExitNormalY = 0;
                destData.c7_RayAABB_ExitNormalZ = 0;
            }
            else if (c6_ra_tMaxY < c6_ra_tMaxZ)
            {
                // Ray hit Y side of box
                exitDepth = c6_ra_tMaxY;
                destData.c7_RayAABB_ExitNormalX = 0;
                destData.c7_RayAABB_ExitNormalY = (u_RayDirY > 0) ? fixedOne : fixedMinusOne;
                destData.c7_RayAABB_ExitNormalZ = 0;
            }
            else
            {
                // Ray hit Z side of box
                exitDepth = c6_ra_tMaxZ;
                destData.c7_RayAABB_ExitNormalX = 0;
                destData.c7_RayAABB_ExitNormalY = 0;
                destData.c7_RayAABB_ExitNormalZ = (u_RayDirZ > 0) ? fixedOne : fixedMinusOne;
            }

            // When rayDir is too small 1/rayDir is huge and overflows our multiply, so ignore those values
            bool rayDirXIsEffectivelyZero = ((u_RayDirX & 0xFF00) == 0) || ((u_RayDirX & 0xFF00) == 0xFF00);
            bool rayDirYIsEffectivelyZero = ((u_RayDirY & 0xFF00) == 0) || ((u_RayDirY & 0xFF00) == 0xFF00);
            bool rayDirZIsEffectivelyZero = ((u_RayDirZ & 0xFF00) == 0) || ((u_RayDirZ & 0xFF00) == 0xFF00);

            if ((exitDepth < 0) ||
                ((rayDirXIsEffectivelyZero) && ((c6_ra_t0PosX >= 0) || (c6_ra_t1PosX < 0))) ||
                ((rayDirYIsEffectivelyZero) && ((c6_ra_t0PosY >= 0) || (c6_ra_t1PosY < 0))) ||
                ((rayDirZIsEffectivelyZero) && ((c6_ra_t0PosZ >= 0) || (c6_ra_t1PosZ < 0))))
            {
                // AABB entirely behind camera, or one of the ray direction components is zero and we're entirely outside the AABB on that axis
                destData.c7_RayAABB_EntryDepth = 0x7FFFFFFF;
                destData.c7_RayAABB_ExitDepth = 0;
            }
            else if ((c6_ra_tMinX > c6_ra_tMinY) && (c6_ra_tMinX > c6_ra_tMinZ))
            {
                // Ray hit X side of box
                destData.c7_RayAABB_ExitDepth = exitDepth;
                destData.c7_RayAABB_EntryDepth = Math.Max(c6_ra_tMinX, 0);
                destData.c7_RayAABB_EntryNormalX = (u_RayDirX < 0) ? fixedOne : fixedMinusOne;
                destData.c7_RayAABB_EntryNormalY = 0;
                destData.c7_RayAABB_EntryNormalZ = 0;
            }
            else if (c6_ra_tMinY > c6_ra_tMinZ)
            {
                // Ray hit Y side of box
                destData.c7_RayAABB_ExitDepth = exitDepth;
                destData.c7_RayAABB_EntryDepth = Math.Max(c6_ra_tMinY, 0);
                destData.c7_RayAABB_EntryNormalX = 0;
                destData.c7_RayAABB_EntryNormalY = (u_RayDirY < 0) ? fixedOne : fixedMinusOne;
                destData.c7_RayAABB_EntryNormalZ = 0;
            }
            else
            {
                // Ray hit Z side of box
                destData.c7_RayAABB_ExitDepth = exitDepth;
                destData.c7_RayAABB_EntryDepth = Math.Max(c6_ra_tMinZ, 0);
                destData.c7_RayAABB_EntryNormalX = 0;
                destData.c7_RayAABB_EntryNormalY = 0;
                destData.c7_RayAABB_EntryNormalZ = (u_RayDirZ < 0) ? fixedOne : fixedMinusOne;
            }
        }

        int c7_RayAABB_EntryDepth;
        int c7_RayAABB_ExitDepth;
        Int16 c7_RayAABB_EntryNormalX;
        Int16 c7_RayAABB_EntryNormalY;
        Int16 c7_RayAABB_EntryNormalZ;
        Int16 c7_RayAABB_ExitNormalX;
        Int16 c7_RayAABB_ExitNormalY;
        Int16 c7_RayAABB_ExitNormalZ;

        void RayAABB_Cycle7(ExecEngine destData)
        {
            destData.c8_RayAABB_EntryDepth = c7_RayAABB_EntryDepth;
            destData.c8_RayAABB_ExitDepth = c7_RayAABB_ExitDepth;
            destData.c8_RayAABB_EntryNormalX = c7_RayAABB_EntryNormalX;
            destData.c8_RayAABB_EntryNormalY = c7_RayAABB_EntryNormalY;
            destData.c8_RayAABB_EntryNormalZ = c7_RayAABB_EntryNormalZ;
            destData.c8_RayAABB_ExitNormalX = c7_RayAABB_ExitNormalX;
            destData.c8_RayAABB_ExitNormalY = c7_RayAABB_ExitNormalY;
            destData.c8_RayAABB_ExitNormalZ = c7_RayAABB_ExitNormalZ;
        }

        int c8_RayAABB_EntryDepth;
        int c8_RayAABB_ExitDepth;
        Int16 c8_RayAABB_EntryNormalX;
        Int16 c8_RayAABB_EntryNormalY;
        Int16 c8_RayAABB_EntryNormalZ;
        Int16 c8_RayAABB_ExitNormalX;
        Int16 c8_RayAABB_ExitNormalY;
        Int16 c8_RayAABB_ExitNormalZ;

        void RayAABB_Cycle8(ExecEngine destData)
        {
            destData.c9_RayAABB_EntryDepth = c8_RayAABB_EntryDepth;
            destData.c9_RayAABB_ExitDepth = c8_RayAABB_ExitDepth;
            destData.c9_RayAABB_EntryNormalX = c8_RayAABB_EntryNormalX;
            destData.c9_RayAABB_EntryNormalY = c8_RayAABB_EntryNormalY;
            destData.c9_RayAABB_EntryNormalZ = c8_RayAABB_EntryNormalZ;
            destData.c9_RayAABB_ExitNormalX = c8_RayAABB_ExitNormalX;
            destData.c9_RayAABB_ExitNormalY = c8_RayAABB_ExitNormalY;
            destData.c9_RayAABB_ExitNormalZ = c8_RayAABB_ExitNormalZ;
        }

        int c9_RayAABB_EntryDepth;
        int c9_RayAABB_ExitDepth;
        Int16 c9_RayAABB_EntryNormalX;
        Int16 c9_RayAABB_EntryNormalY;
        Int16 c9_RayAABB_EntryNormalZ;
        Int16 c9_RayAABB_ExitNormalX;
        Int16 c9_RayAABB_ExitNormalY;
        Int16 c9_RayAABB_ExitNormalZ;

        void RayAABB_Cycle9(ExecEngine destData)
        {
            destData.c10_RayAABB_EntryDepth = c9_RayAABB_EntryDepth;
            destData.c10_RayAABB_ExitDepth = c9_RayAABB_ExitDepth;
            destData.c10_RayAABB_EntryNormalX = c9_RayAABB_EntryNormalX;
            destData.c10_RayAABB_EntryNormalY = c9_RayAABB_EntryNormalY;
            destData.c10_RayAABB_EntryNormalZ = c9_RayAABB_EntryNormalZ;
            destData.c10_RayAABB_ExitNormalX = c9_RayAABB_ExitNormalX;
            destData.c10_RayAABB_ExitNormalY = c9_RayAABB_ExitNormalY;
            destData.c10_RayAABB_ExitNormalZ = c9_RayAABB_ExitNormalZ;
        }

        int c10_RayAABB_EntryDepth;
        int c10_RayAABB_ExitDepth;
        Int16 c10_RayAABB_EntryNormalX;
        Int16 c10_RayAABB_EntryNormalY;
        Int16 c10_RayAABB_EntryNormalZ;
        Int16 c10_RayAABB_ExitNormalX;
        Int16 c10_RayAABB_ExitNormalY;
        Int16 c10_RayAABB_ExitNormalZ;

        void RayAABB_Cycle10(ExecEngine destData)
        {
            destData.c11_RayAABB_EntryDepth = c10_RayAABB_EntryDepth;
            destData.c11_RayAABB_ExitDepth = c10_RayAABB_ExitDepth;
            destData.c11_RayAABB_EntryNormalX = c10_RayAABB_EntryNormalX;
            destData.c11_RayAABB_EntryNormalY = c10_RayAABB_EntryNormalY;
            destData.c11_RayAABB_EntryNormalZ = c10_RayAABB_EntryNormalZ;
            destData.c11_RayAABB_ExitNormalX = c10_RayAABB_ExitNormalX;
            destData.c11_RayAABB_ExitNormalY = c10_RayAABB_ExitNormalY;
            destData.c11_RayAABB_ExitNormalZ = c10_RayAABB_ExitNormalZ;
        }

        int c11_RayAABB_EntryDepth;
        int c11_RayAABB_ExitDepth;
        Int16 c11_RayAABB_EntryNormalX;
        Int16 c11_RayAABB_EntryNormalY;
        Int16 c11_RayAABB_EntryNormalZ;
        Int16 c11_RayAABB_ExitNormalX;
        Int16 c11_RayAABB_ExitNormalY;
        Int16 c11_RayAABB_ExitNormalZ;

        void RayAABB_Cycle11(ExecEngine destData)
        {
            destData.c12_RayAABB_EntryDepth = c11_RayAABB_EntryDepth;
            destData.c12_RayAABB_ExitDepth = c11_RayAABB_ExitDepth;
            destData.c12_RayAABB_EntryNormalX = c11_RayAABB_EntryNormalX;
            destData.c12_RayAABB_EntryNormalY = c11_RayAABB_EntryNormalY;
            destData.c12_RayAABB_EntryNormalZ = c11_RayAABB_EntryNormalZ;
            destData.c12_RayAABB_ExitNormalX = c11_RayAABB_ExitNormalX;
            destData.c12_RayAABB_ExitNormalY = c11_RayAABB_ExitNormalY;
            destData.c12_RayAABB_ExitNormalZ = c11_RayAABB_ExitNormalZ;
        }

        int c12_RayAABB_EntryDepth;
        int c12_RayAABB_ExitDepth;
        Int16 c12_RayAABB_EntryNormalX;
        Int16 c12_RayAABB_EntryNormalY;
        Int16 c12_RayAABB_EntryNormalZ;
        Int16 c12_RayAABB_ExitNormalX;
        Int16 c12_RayAABB_ExitNormalY;
        Int16 c12_RayAABB_ExitNormalZ;

        void RayAABB_Cycle12(ExecEngine destData)
        {
            destData.c13_RayAABB_EntryDepth = c12_RayAABB_EntryDepth;
            destData.c13_RayAABB_ExitDepth = c12_RayAABB_ExitDepth;
            destData.c13_RayAABB_EntryNormalX = c12_RayAABB_EntryNormalX;
            destData.c13_RayAABB_EntryNormalY = c12_RayAABB_EntryNormalY;
            destData.c13_RayAABB_EntryNormalZ = c12_RayAABB_EntryNormalZ;
            destData.c13_RayAABB_ExitNormalX = c12_RayAABB_ExitNormalX;
            destData.c13_RayAABB_ExitNormalY = c12_RayAABB_ExitNormalY;
            destData.c13_RayAABB_ExitNormalZ = c12_RayAABB_ExitNormalZ;
        }

        int c13_RayAABB_EntryDepth;
        int c13_RayAABB_ExitDepth;
        Int16 c13_RayAABB_EntryNormalX;
        Int16 c13_RayAABB_EntryNormalY;
        Int16 c13_RayAABB_EntryNormalZ;
        Int16 c13_RayAABB_ExitNormalX;
        Int16 c13_RayAABB_ExitNormalY;
        Int16 c13_RayAABB_ExitNormalZ;

        void RayAABB_Cycle13(ExecEngine destData)
        {
            destData.c14_RayAABB_EntryDepth = c13_RayAABB_EntryDepth;
            destData.c14_RayAABB_ExitDepth = c13_RayAABB_ExitDepth;
            destData.c14_RayAABB_EntryNormalX = c13_RayAABB_EntryNormalX;
            destData.c14_RayAABB_EntryNormalY = c13_RayAABB_EntryNormalY;
            destData.c14_RayAABB_EntryNormalZ = c13_RayAABB_EntryNormalZ;
            destData.c14_RayAABB_ExitNormalX = c13_RayAABB_ExitNormalX;
            destData.c14_RayAABB_ExitNormalY = c13_RayAABB_ExitNormalY;
            destData.c14_RayAABB_ExitNormalZ = c13_RayAABB_ExitNormalZ;
        }
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using Instruction = SRTTestbed.ExecEngine.Instruction;
using Condition = SRTTestbed.ExecEngine.Condition;
using ObjectMergeType = SRTTestbed.ExecEngine.ObjectMergeType;

namespace SRTTestbed
{
    public static class CommandListDisassembler
    {
        public static string Disassemble(UInt64[] commands, int[] editPoints)
        {
            StringBuilder result = new StringBuilder();

            for (int i = 0; i < commands.Length; i++)
            {
                UInt64 instructionWord = commands[i];

                Condition condition = (Condition)((instructionWord >> 6) & 3);
                Instruction inst = (Instruction)(instructionWord & 0x3F);

                result.Append(i.ToString("0000") + " ");

                if (condition != Condition.AL)
                {
                    result.Append(inst + " " + condition);
                }
                else
                {
                    result.Append(inst);
                }

                switch (inst)
                {
                    case Instruction.Sphere:
                    case Instruction.SphereSub:
                    case Instruction.SphereAnd:
                    {
                        int objX = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 8) & 0x7FFF));
                        int objY = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 23) & 0x7FFF));
                        int objZ = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 38) & 0x7FFF));
                        int objRad = FixedMaths.ConvertFrom4Dot7((UInt16)((instructionWord >> 53) & 0x7FF));

                        result.Append(" " + FixedMaths.FixedToFloat(objX) + ", " + FixedMaths.FixedToFloat(objY) + ", " + FixedMaths.FixedToFloat(objZ) + ", Rad=" + FixedMaths.FixedToFloat(objZ));

                        break;
                    }
                    case Instruction.Plane:
                    case Instruction.PlaneSub:
                    case Instruction.PlaneAnd:
                    {
                        Int16 objNormalX = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 8) & 0xFFF));
                        Int16 objNormalY = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 20) & 0xFFF));
                        Int16 objNormalZ = FixedMaths.ConvertFrom2Dot10((UInt16)((instructionWord >> 32) & 0xFFF));
                        int objNormalDist = FixedMaths.ConvertFrom8Dot12((UInt32)((instructionWord >> 44) & 0xFFFFF));

                        result.Append(" " + FixedMaths.FixedToFloat(objNormalX) + ", " + FixedMaths.FixedToFloat(objNormalY) + ", " + FixedMaths.FixedToFloat(objNormalZ) + ", Dist=" + FixedMaths.FixedToFloat(objNormalDist));

                        break;
                    }
                    case Instruction.AABB:
                    case Instruction.AABBSub:
                    case Instruction.AABBAnd:
                    {
                        int objMinX = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 8) & 0x1FF));
                        int objMinY = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 17) & 0x1FF));
                        int objMinZ = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 26) & 0x1FF));
                        int objMaxX = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 35) & 0x1FF));
                        int objMaxY = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 44) & 0x1FF));
                        int objMaxZ = FixedMaths.ConvertFrom8Dot1((UInt16)((instructionWord >> 53) & 0x1FF));

                        result.Append(" " + FixedMaths.FixedToFloat(objMinX) + ", " + FixedMaths.FixedToFloat(objMinY) + ", " + FixedMaths.FixedToFloat(objMinZ) + ",    " + FixedMaths.FixedToFloat(objMaxX) + ", " + FixedMaths.FixedToFloat(objMaxY) + ", " + FixedMaths.FixedToFloat(objMaxZ));

                        break;
                    }
                    case Instruction.Checkerboard:
                    case Instruction.RegisterHit:
                    case Instruction.RegisterHitNoReset:
                    {
                        UInt16 albedo = (UInt16)((instructionWord >> 16) & 0xFFFF);
                        byte reflectiveness = (byte)((instructionWord >> 8) & 0xFF);

                        result.Append(" " + ExecEngine.RGB15ToString(albedo) + ", Reflectiveness=" + reflectiveness);

                        break;
                    }
                    case Instruction.Jump:
                    case Instruction.ResetHitStateAndJump:
                    {
                        int pc = (int)((instructionWord >> 8) & 0xFFFF);

                        result.Append(" " + pc);

                        break;
                    }
                    case Instruction.Origin:
                    {
                        int objX = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 8) & 0x7FFF));
                        int objY = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 23) & 0x7FFF));
                        int objZ = FixedMaths.ConvertFrom8Dot7((UInt32)((instructionWord >> 38) & 0x7FFF));

                        result.Append(" " + FixedMaths.FixedToFloat(objX) + ", " + FixedMaths.FixedToFloat(objY) + ", " + FixedMaths.FixedToFloat(objZ));

                        break;
                    }
                    default:
                    {
                        break;
                    }
                }

                if (editPoints != null)
                {
                    for (int j = 0; j < editPoints.Length; j++)
                    {
                        if ((editPoints[j] > 0) && (editPoints[j] == i))
                        {
                            result.Append(" // Edit point " + j);
                        }
                    }
                }

                result.AppendLine();
            }

            return result.ToString();
        }
    }
}

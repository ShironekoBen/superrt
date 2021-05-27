using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    // RT microcode execution engine
    partial class ExecEngine
    {
        // Variable annotation
        // u_ (uniform) indicates that the value is uniform across one full execution of the buffer, and so can be used from any cycle
        // c<#>_ (cycle) indicates that the value can only be read from the cycle indicated, and can only be written from the cycle before it
        // s<#>_ (state) indicates that the value is internal state for a cycle, and can only be read/written from that cycle
        // x_ indicates that the variable does not follow these conventions for some reason (and must be treated with extreme care)

        // Inputs
        public bool x_Start_tick;
        public UInt64[] u_CommandBuffer;

        // Current ray information
        public int u_RayStartX;
        public int u_RayStartY;
        public int u_RayStartZ;
        public Int16 u_RayDirX;
        public Int16 u_RayDirY;
        public Int16 u_RayDirZ;
        public int u_RayDirRcpX;
        public int u_RayDirRcpY;
        public int u_RayDirRcpZ;
        public bool u_ShadowRay;
        public bool u_SecondaryRay;

        // Outputs
        public bool x_Busy;

        // Performance counters
        public int p_CycleCount;
        public int p_BranchPredictionHits;
        public int p_BranchPredictionMisses;
        public int p_InstructionsExecuted;
        public int p_InstructionsAbandoned;

        public void ResetPerfCounters()
        {
            p_CycleCount = 0;
            p_BranchPredictionHits = 0;
            p_BranchPredictionMisses = 0;
            p_InstructionsExecuted = 0;
            p_InstructionsAbandoned = 0;
        }

        // Latency-respecting memory access
        MemoryAccessClocked<UInt64> memoryAccess = new MemoryAccessClocked<UInt64>();

        // Branch prediction cache
        public byte[] x_BranchPredictionCache; // Technically four bits wide, one per ray type, with one entry per pair of instructions
        MemoryAccessClocked<byte> branchPredictionCacheReadAccess = new MemoryAccessClocked<byte>();

        byte u_branchPredictionCacheBitMask;

        // Trace results for merging

        public enum ObjectMergeType
        {
            Add, // Additive merge (normal)
            Sub, // Subtractive merge (remove parts of current shape)
            And // AND merge (logical AND of existing and new shapes)
        }

        // Debug
        public StringBuilder x_TraceDebug = null;
        PipelineTracer x_PipelineTracer = null;

        public enum Instruction
        {
            NOP = 0, // NOP must be instruction 0
            // Sphere and plane are carefully set up here so that sphere instructions will have bit 0 set, and planes bit 0 clear
            Sphere, // Arguments: X, Y, Z, Rad, InvRad
            Plane, // Arguments Normal X/Y/Z, Distance
            SphereSub,
            PlaneSub,
            SphereAnd,
            PlaneAnd,

            AABB, // Arguments X, Y, Z, size X, size Y, size Z
            AABBSub,
            AABBAnd,
            RegisterHit, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15)
            RegisterHitNoReset, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15), does not reset hit state
            Checkerboard, // Arguments: Albedo (high 16 bits of command), Reflectiveness (bits 8-15) (should be used after RegisterHit with an OH modifier)
            ResetHitState,
            Jump, // Arguments: Target address (bits 8-23)
            ResetHitStateAndJump, // Arguments: Target address (bits 8-23), unconditionally resets hit state
            Origin, // Arguments: X, Y, Z
            Start,
            End
        }

        public enum Condition // 2 bits
        {
            AL = 0, // Always
            OH = 1, // On hit
            NH = 2, // No hit
            ORH = 3, // On registered hit
        }

        public static UInt64 BuildInstruction(Instruction inst, Condition cond = Condition.AL, UInt64 extraBits = 0)
        {
            return ((UInt64)inst) | (((UInt64)cond) << 6) | extraBits;
        }

        public static String RGB15ToString(UInt16 col)
        {
            int r = ((col & 0x1F) << 3);
            int g = (((col >> 5) & 0x1F) << 3);
            int b = (((col >> 10) & 0x1F) << 3);

            return "" + r + ", " + g + ", " + b;
        }

        // Reset state
        public void Reset()
        {
            x_Busy = false;
            c1_Finished_tick = false;
        }
        
        // Perform a single execution tick
        // Returns the mutated engine state
        public ExecEngine Tick()
        {
            if ((x_TraceDebug != null) != (x_PipelineTracer != null))
            {
                if (x_TraceDebug != null)
                {
                    x_PipelineTracer = new PipelineTracer();
                }
                else
                {
                    x_PipelineTracer = null;
                }
            }

            ExecEngine destData = (ExecEngine)this.MemberwiseClone();

            destData.p_CycleCount++;

            // Make sure branch prediction cache is the right size

            if ((x_BranchPredictionCache == null) || (x_BranchPredictionCache.Length != (u_CommandBuffer.Length + 1) >> 1))
            {
                x_BranchPredictionCache = new byte[(u_CommandBuffer.Length + 1) >> 1];
                destData.x_BranchPredictionCache = x_BranchPredictionCache;
            }

            // Calculate branch prediction cache bit mask
            u_branchPredictionCacheBitMask = 0;
            u_branchPredictionCacheBitMask |= (byte)(((!u_ShadowRay) && (!u_SecondaryRay)) ? 1 : 0);
            u_branchPredictionCacheBitMask |= (byte)(((u_ShadowRay) && (!u_SecondaryRay)) ? 2 : 0);
            u_branchPredictionCacheBitMask |= (byte)(((!u_ShadowRay) && (u_SecondaryRay)) ? 4 : 0);
            u_branchPredictionCacheBitMask |= (byte)(((u_ShadowRay) && (u_SecondaryRay)) ? 8 : 0);

            destData.memoryAccess = memoryAccess.Tick();
            destData.branchPredictionCacheReadAccess = branchPredictionCacheReadAccess.Tick();

            RaySphereAndPlane_Tick(destData);
            RayAABB_Tick(destData);
            Cycle1(destData);
            Cycle2(destData);
            Cycle3(destData);
            Cycle4(destData);
            Cycle5(destData);
            Cycle6(destData);
            Cycle7(destData);
            Cycle8(destData);
            Cycle9(destData);
            Cycle10(destData);
            Cycle11(destData);
            Cycle12(destData);
            Cycle13(destData);
            Cycle14(destData);

            x_PipelineTracer?.Update();

            return destData;
        }

        int s1_fetchPC; // Program counter (technically two cycles ahead of the current PC, as this is where we are fetching from)
        int s1_pcFIFO; // FIFO for tracking actual PC
        int s1_actualPC; // The actual PC of the executing instruction
        UInt32 s1_romLatencyCycleFlags;
        bool c1_loadNewPC_tick; // Request to load new program counter, written from final cycle
        int c1_newPC; // New program counter, written from final cycle
        bool c1_Finished_tick; // Indicates that execution is complete, written from final cycle

        public void Cycle1(ExecEngine destData)
        {
            destData.c2_branchPredictionData = 0; // Set default value, not strictly necessary but keeps things neater for debugging

            if (x_Start_tick)
            {
                // Start execution
                destData.s1_fetchPC = 0;
                destData.s1_romLatencyCycleFlags = 0x3; // Need to wait two cycles before we start getting valid data from the ROM
                destData.c2_InstructionWord = BuildInstruction(Instruction.NOP);
                destData.x_Busy = true;
            }
            else if (c1_Finished_tick)
            {
                // End execution
                destData.x_Busy = false;
            }
            else if (c1_loadNewPC_tick)
            {
                // Loading new PC due to jump
                destData.s1_fetchPC = c1_newPC;
                destData.s1_romLatencyCycleFlags = 0x3; // Need to wait two cycles before we start getting valid data from the ROM
                destData.c2_InstructionWord = BuildInstruction(Instruction.NOP);
            }
            else
            {
                destData.s1_romLatencyCycleFlags = s1_romLatencyCycleFlags >> 1;

                if (!x_Busy)
                {
                    // When not busy, just push NOPs into the pipeline
                    destData.c2_InstructionWord = BuildInstruction(Instruction.NOP);
                    x_PipelineTracer?.AppendLine(1, "  Instruction in [idle]: NOP");
                }
                else
                {
                    destData.s1_fetchPC = s1_fetchPC + 1; // Default to going to the next instruction

                    if ((s1_romLatencyCycleFlags & 1) == 0)
                    {
                        UInt64 instructionWord = memoryAccess.outData;

                        destData.c2_InstructionWord = instructionWord;
                        x_PipelineTracer?.AppendLine(1, "  Instruction in [" + s1_actualPC + "]" + ": " + destData.c2_InstructionWord.ToString("x8"));

                        // For safety check that we are reading the memory address we think we're reading
                        if (s1_actualPC != memoryAccess.outDataAddressForDebugging)
                        {
                            throw new Exception("Expected address does not match memory read address!");
                        }

                        // Branch prediction

                        Instruction inst = (Instruction)(instructionWord & 0x3F);

                        switch (inst)
                        {
                            case Instruction.Jump:
                            case Instruction.ResetHitStateAndJump:
                            {
                                Condition condition = (Condition)((instructionWord >> 6) & 3);

                                destData.c1_Finished_tick = false;
                                destData.c1_loadNewPC_tick = false;

                                switch (condition)
                                {
                                    default:
                                    case Condition.AL:
                                    {
                                        destData.s1_fetchPC = (int)((instructionWord >> 8) & 0xFFFF);
                                        destData.s1_romLatencyCycleFlags = 0x3; // Need to wait two cycles before we start getting valid data again from the ROM

                                        x_PipelineTracer?.AppendLine(1, "    Unconditional branch, jumping to " + destData.s1_fetchPC + " (PC " + s1_actualPC + ")");
                                        break;
                                    }
                                    case Condition.OH:
                                    case Condition.NH:
                                    case Condition.ORH:
                                    {
                                        // Conditional branch, use prediction

                                        byte branchPrediction = branchPredictionCacheReadAccess.outData;

                                        destData.c2_branchPredictionData = branchPrediction;

                                        int predictionBit = 1 << ((u_SecondaryRay ? 2 : 0) | (u_ShadowRay ? 1 : 0));

                                        // We store one prediction per pair of instructions, with the prediction result inverting for odd PC addresses
                                        // This halves the necessary storage by using the fact that pairs of branches are rare, and when they do appear they're almost
                                        // always the conditional inverse of each other.
                                        // Note that this code must match the same logic in the execution cycle.
                                        if (((branchPrediction & u_branchPredictionCacheBitMask) != 0) != ((s1_actualPC & 1) != 0))
                                        {
                                            // If we predict that the branch will be taken, move the PC now
                                            destData.s1_fetchPC = (int)((instructionWord >> 8) & 0xFFFF);
                                            destData.s1_romLatencyCycleFlags = 0x3; // Need to wait two cycles before we start getting valid data again from the ROM

                                            x_PipelineTracer?.AppendLine(1, "    Predicted branch will be taken, jumping to " + destData.s1_fetchPC + " (PC " + s1_actualPC + ", prediction data 0x" + branchPrediction.ToString("x2") + ")");
                                        }
                                        else
                                        {
                                            x_PipelineTracer?.AppendLine(1, "    Predicted branch will not be taken (PC " + s1_actualPC + ", prediction data 0x" + branchPrediction.ToString("x2") + ")");
                                        }

                                        break;
                                    }
                                }
                                break;
                            }
                            default: break;
                        }
                    }
                    else
                    {
                        destData.c2_InstructionWord = BuildInstruction(Instruction.NOP); // Still waiting for the ROM
                        x_PipelineTracer?.AppendLine(1, "  Instruction in [ROM wait]: NOP");
                    }
                }
            }

            // Update PC FIFO

            destData.s1_pcFIFO = s1_fetchPC;
            destData.s1_actualPC = s1_pcFIFO;

            destData.memoryAccess.inMemoryBuffer = u_CommandBuffer;
            destData.memoryAccess.inAddress = destData.s1_fetchPC; // No latency on setting PC
            destData.branchPredictionCacheReadAccess.inMemoryBuffer = x_BranchPredictionCache;
            destData.branchPredictionCacheReadAccess.inAddress = destData.s1_fetchPC >> 1;
            destData.c2_PC = s1_actualPC;
        }

        UInt64 c2_InstructionWord;
        byte c2_branchPredictionData;
        int c2_PC;

        public void Cycle2(ExecEngine destData)
        {
            destData.c3_InstructionWord = c2_InstructionWord;
            destData.c3_branchPredictionData = c2_branchPredictionData;
            destData.c3_PC = c2_PC;
        }

        UInt64 c3_InstructionWord;
        byte c3_branchPredictionData;
        int c3_PC;
        int s3_originX, s3_originY, s3_originZ;
        bool c3_loadNewOrigin_tick; // Set from cycle 14
        int c3_newOriginX, c3_newOriginY, c3_newOriginZ; // Set from cycle 14

        public void Cycle3(ExecEngine destData)
        {
            if (c3_loadNewOrigin_tick)
            {
                // Load a new origin (generally actually an old origin) when requested by cycle 14
                // This happens when the pipeline is flushed due to a branch mispredict, to restore
                // the old origin state
                destData.s3_originX = c3_newOriginX;
                destData.s3_originY = c3_newOriginY;
                destData.s3_originZ = c3_newOriginZ;
            }

            bool currentInstructionInvalidated = (x_InstructionInvalidated & (1 << (3 - 1))) != 0; // -1 because cycle indices start at 1

            if (!currentInstructionInvalidated)
            {
                Instruction inst = (Instruction)(c3_InstructionWord & 0x3F);

                if (inst == Instruction.Start)
                {
                    destData.s3_originX = 0;
                    destData.s3_originY = 0;
                    destData.s3_originZ = 0;
                }
                else if (inst == Instruction.Origin)
                {
                    destData.s3_originX = FixedMaths.ConvertFrom8Dot7((UInt32)((c3_InstructionWord >> 8) & 0x7FFF));
                    destData.s3_originY = FixedMaths.ConvertFrom8Dot7((UInt32)((c3_InstructionWord >> 23) & 0x7FFF));
                    destData.s3_originZ = FixedMaths.ConvertFrom8Dot7((UInt32)((c3_InstructionWord >> 38) & 0x7FFF));

                    x_PipelineTracer?.AppendLine(3, "    Set origin to " + FixedMaths.FixedToFloat(destData.s3_originX) + ", " + FixedMaths.FixedToFloat(destData.s3_originY) + ", " + FixedMaths.FixedToFloat(destData.s3_originZ));
                }
            }

            // Keep track of the previous origin so we can reset it upon a pipeline flush
            destData.c4_oldOriginX = s3_originX;
            destData.c4_oldOriginY = s3_originY;
            destData.c4_oldOriginZ = s3_originZ;

            destData.c4_InstructionWord = c3_InstructionWord;
            destData.c4_branchPredictionData = c3_branchPredictionData;
            destData.c4_PC = c3_PC;
        }

        UInt64 c4_InstructionWord;
        byte c4_branchPredictionData;
        int c4_PC;
        int c4_oldOriginX;
        int c4_oldOriginY;
        int c4_oldOriginZ;

        public void Cycle4(ExecEngine destData)
        {
            destData.c5_InstructionWord = c4_InstructionWord;
            destData.c5_branchPredictionData = c4_branchPredictionData;
            destData.c5_PC = c4_PC;
            destData.c5_oldOriginX = c4_oldOriginX;
            destData.c5_oldOriginY = c4_oldOriginY;
            destData.c5_oldOriginZ = c4_oldOriginZ;
        }

        UInt64 c5_InstructionWord;
        byte c5_branchPredictionData;
        int c5_PC;
        int c5_oldOriginX;
        int c5_oldOriginY;
        int c5_oldOriginZ;

        public void Cycle5(ExecEngine destData)
        {
            destData.c6_InstructionWord = c5_InstructionWord;
            destData.c6_branchPredictionData = c5_branchPredictionData;
            destData.c6_PC = c5_PC;
            destData.c6_oldOriginX = c5_oldOriginX;
            destData.c6_oldOriginY = c5_oldOriginY;
            destData.c6_oldOriginZ = c5_oldOriginZ;
        }

        UInt64 c6_InstructionWord;
        byte c6_branchPredictionData;
        int c6_PC;
        int c6_oldOriginX;
        int c6_oldOriginY;
        int c6_oldOriginZ;

        public void Cycle6(ExecEngine destData)
        {
            destData.c7_InstructionWord = c6_InstructionWord;
            destData.c7_branchPredictionData = c6_branchPredictionData;
            destData.c7_PC = c6_PC;
            destData.c7_oldOriginX = c6_oldOriginX;
            destData.c7_oldOriginY = c6_oldOriginY;
            destData.c7_oldOriginZ = c6_oldOriginZ;
        }

        UInt64 c7_InstructionWord;
        byte c7_branchPredictionData;
        int c7_PC;
        int c7_oldOriginX;
        int c7_oldOriginY;
        int c7_oldOriginZ;

        public void Cycle7(ExecEngine destData)
        {
            destData.c8_InstructionWord = c7_InstructionWord;
            destData.c8_branchPredictionData = c7_branchPredictionData;
            destData.c8_PC = c7_PC;
            destData.c8_oldOriginX = c7_oldOriginX;
            destData.c8_oldOriginY = c7_oldOriginY;
            destData.c8_oldOriginZ = c7_oldOriginZ;
        }

        UInt64 c8_InstructionWord;
        byte c8_branchPredictionData;
        int c8_PC;
        int c8_oldOriginX;
        int c8_oldOriginY;
        int c8_oldOriginZ;

        public void Cycle8(ExecEngine destData)
        {
            destData.c9_InstructionWord = c8_InstructionWord;
            destData.c9_branchPredictionData = c8_branchPredictionData;
            destData.c9_PC = c8_PC;
            destData.c9_oldOriginX = c8_oldOriginX;
            destData.c9_oldOriginY = c8_oldOriginY;
            destData.c9_oldOriginZ = c8_oldOriginZ;
        }

        UInt64 c9_InstructionWord;
        byte c9_branchPredictionData;
        int c9_PC;
        int c9_oldOriginX;
        int c9_oldOriginY;
        int c9_oldOriginZ;

        public void Cycle9(ExecEngine destData)
        {
            destData.c10_InstructionWord = c9_InstructionWord;
            destData.c10_branchPredictionData = c9_branchPredictionData;
            destData.c10_PC = c9_PC;
            destData.c10_oldOriginX = c9_oldOriginX;
            destData.c10_oldOriginY = c9_oldOriginY;
            destData.c10_oldOriginZ = c9_oldOriginZ;
        }

        UInt64 c10_InstructionWord;
        byte c10_branchPredictionData;
        int c10_PC;
        int c10_oldOriginX;
        int c10_oldOriginY;
        int c10_oldOriginZ;

        public void Cycle10(ExecEngine destData)
        {
            destData.c11_InstructionWord = c10_InstructionWord;
            destData.c11_branchPredictionData = c10_branchPredictionData;
            destData.c11_PC = c10_PC;
            destData.c11_oldOriginX = c10_oldOriginX;
            destData.c11_oldOriginY = c10_oldOriginY;
            destData.c11_oldOriginZ = c10_oldOriginZ;
        }

        UInt64 c11_InstructionWord;
        byte c11_branchPredictionData;
        int c11_PC;
        int c11_oldOriginX;
        int c11_oldOriginY;
        int c11_oldOriginZ;

        public void Cycle11(ExecEngine destData)
        {
            destData.c12_InstructionWord = c11_InstructionWord;
            destData.c12_branchPredictionData = c11_branchPredictionData;
            destData.c12_PC = c11_PC;
            destData.c12_oldOriginX = c11_oldOriginX;
            destData.c12_oldOriginY = c11_oldOriginY;
            destData.c12_oldOriginZ = c11_oldOriginZ;
        }

        UInt64 c12_InstructionWord;
        byte c12_branchPredictionData;
        int c12_PC;
        int c12_oldOriginX;
        int c12_oldOriginY;
        int c12_oldOriginZ;

        public void Cycle12(ExecEngine destData)
        {
            destData.c13_InstructionWord = c12_InstructionWord;
            destData.c13_branchPredictionData = c12_branchPredictionData;
            destData.c13_PC = c12_PC;
            destData.c13_oldOriginX = c12_oldOriginX;
            destData.c13_oldOriginY = c12_oldOriginY;
            destData.c13_oldOriginZ = c12_oldOriginZ;
        }

        UInt64 c13_InstructionWord;
        byte c13_branchPredictionData;
        int c13_PC;
        int c13_oldOriginX;
        int c13_oldOriginY;
        int c13_oldOriginZ;

        public void Cycle13(ExecEngine destData)
        {
            destData.c14_InstructionWord = c13_InstructionWord;
            destData.c14_branchPredictionData = c13_branchPredictionData;
            destData.c14_PC = c13_PC;
            destData.c14_oldOriginX = c13_oldOriginX;
            destData.c14_oldOriginY = c13_oldOriginY;
            destData.c14_oldOriginZ = c13_oldOriginZ;
        }

        UInt64 c14_InstructionWord;
        byte c14_branchPredictionData;
        int c14_PC;
        int c14_oldOriginX;
        int c14_oldOriginY;
        int c14_oldOriginZ;

        // Hit information
        // If HitEntryDepth < HitExitDepth then the ray hit something
        int s14_HitEntryDepth; // Depth of the hit (entering the object)
        int s14_HitExitDepth; // Depth of the hit (exiting the object)
        Int16 s14_HitNormalX; // Hit normal
        Int16 s14_HitNormalY;
        Int16 s14_HitNormalZ;
        bool s14_ObjRegisteredHit; // Has this object registered a hit?
        int s14_HitCalculation_HitX;
        int s14_HitCalculation_HitY;
        int s14_HitCalculation_HitZ;

        // Externally visible outputs
        public bool s14_RegHit;
        public int s14_RegHitDepth;
        public int s14_RegHitX;
        public int s14_RegHitY;
        public int s14_RegHitZ;
        public Int16 s14_RegHitNormalX;
        public Int16 s14_RegHitNormalY;
        public Int16 s14_RegHitNormalZ;
        public UInt16 s14_RegHitAlbedo;
        public byte s14_RegHitReflectiveness;
        // One bit for each pipeline stage indicating if the instruction currently at that stage is valid
        // Can be read from any stage as long as the right bit is read
        public UInt32 x_InstructionInvalidated = 0;

        public void Cycle14(ExecEngine destData)
        {
            Condition condition = (Condition)((c14_InstructionWord >> 6) & 3);

            destData.c1_Finished_tick = false;
            destData.c1_loadNewPC_tick = false;
            destData.c3_loadNewOrigin_tick = false;

            bool execute;

            switch (condition)
            {
                default:
                case Condition.AL:
                    execute = true;
                    break;
                case Condition.OH:
                    execute = s14_HitEntryDepth < s14_HitExitDepth;
                    break;
                case Condition.NH:
                    execute = !(s14_HitEntryDepth < s14_HitExitDepth);
                    break;
                case Condition.ORH:
                    execute = s14_ObjRegisteredHit;
                    break;
            }

            Instruction inst = (Instruction)(c14_InstructionWord & 0x3F);

            // Update instruction invalidity FIFO

            destData.x_InstructionInvalidated = x_InstructionInvalidated << 1;

            bool currentInstructionInvalidated = (x_InstructionInvalidated & (1 << (14 - 1))) != 0; // -1 because cycle indices start at 1

            if ((currentInstructionInvalidated) && (inst != Instruction.NOP))
            {
                x_TraceDebug?.AppendLine("  Skipping invalidated " + inst + " " + condition);
                return;
            }

            if (inst != Instruction.NOP)
            {
                x_TraceDebug?.AppendLine("  Dispatching " + inst + " " + condition + (execute ? "" : " (not executing)"));
            }

            if (((execute) || (inst == Instruction.Jump) || (inst == Instruction.ResetHitStateAndJump)) && (inst != Instruction.NOP) && (x_TraceDebug != null))
            {
                string data = x_PipelineTracer.Emit(14);
                if (data != null)
                {
                    x_TraceDebug.Append(data);
                }
            }

            if (execute && (inst != Instruction.NOP))
            {
                destData.p_InstructionsExecuted++;
            }
            else
            {
                destData.p_InstructionsAbandoned++;
            }

            switch (inst)
            {
                case Instruction.Start:
                {
                    if (execute)
                    {
                        destData.s14_HitEntryDepth = 0x7FFFFFFF;
                        destData.s14_HitExitDepth = 0;
                        destData.s14_ObjRegisteredHit = false;
                        destData.s14_RegHit = false;
                    }
                    break;
                }
                case Instruction.Sphere:
                case Instruction.SphereSub:
                case Instruction.SphereAnd:
                case Instruction.Plane:
                case Instruction.PlaneSub:
                case Instruction.PlaneAnd:
                case Instruction.AABB:
                case Instruction.AABBSub:
                case Instruction.AABBAnd:
                {
                    if (execute)
                    {
                        // Retrieve data from intersection units

                        int entryDepth;
                        int exitDepth;
                        Int16 entryNormalX;
                        Int16 entryNormalY;
                        Int16 entryNormalZ;
                        Int16 exitNormalX;
                        Int16 exitNormalY;
                        Int16 exitNormalZ;

                        switch (inst)
                        {
                            case Instruction.Sphere:
                            case Instruction.SphereSub:
                            case Instruction.SphereAnd:
                            {
                                entryDepth = c14_RaySphere_EntryDepth;
                                exitDepth = c14_RaySphere_ExitDepth;
                                entryNormalX = c14_RaySphere_EntryNormalX;
                                entryNormalY = c14_RaySphere_EntryNormalY;
                                entryNormalZ = c14_RaySphere_EntryNormalZ;
                                exitNormalX = c14_RaySphere_ExitNormalX;
                                exitNormalY = c14_RaySphere_ExitNormalY;
                                exitNormalZ = c14_RaySphere_ExitNormalZ;
                                break;
                            }
                            case Instruction.Plane:
                            case Instruction.PlaneSub:
                            case Instruction.PlaneAnd:
                            {
                                entryDepth = c14_RayPlane_EntryDepth;
                                exitDepth = c14_RayPlane_ExitDepth;
                                entryNormalX = c14_RayPlane_EntryNormalX;
                                entryNormalY = c14_RayPlane_EntryNormalY;
                                entryNormalZ = c14_RayPlane_EntryNormalZ;
                                exitNormalX = c14_RayPlane_ExitNormalX;
                                exitNormalY = c14_RayPlane_ExitNormalY;
                                exitNormalZ = c14_RayPlane_ExitNormalZ;
                                break;
                            }
                            case Instruction.AABB:
                            case Instruction.AABBSub:
                            case Instruction.AABBAnd:
                            {
                                entryDepth = c14_RayAABB_EntryDepth;
                                exitDepth = c14_RayAABB_ExitDepth;
                                entryNormalX = c14_RayAABB_EntryNormalX;
                                entryNormalY = c14_RayAABB_EntryNormalY;
                                entryNormalZ = c14_RayAABB_EntryNormalZ;
                                exitNormalX = c14_RayAABB_ExitNormalX;
                                exitNormalY = c14_RayAABB_ExitNormalY;
                                exitNormalZ = c14_RayAABB_ExitNormalZ;
                                break;
                            }
                            default:
                            {
                                throw new NotImplementedException();
                            }
                        }

                        // Merge

                        x_TraceDebug?.AppendLine("   Intersection range " + FixedMaths.FixedToFloat(entryDepth) + " to " + FixedMaths.FixedToFloat(exitDepth));

                        if (entryDepth >= exitDepth)
                        {
                            // No intersection

                            x_TraceDebug?.AppendLine("   No intersection");
                        }
                        else
                        {
                            // Intersection occurred

                            x_TraceDebug?.AppendLine("   Ray intersects from " + FixedMaths.FixedToFloat(entryDepth) + " - " + FixedMaths.FixedToFloat(exitDepth));
                            x_TraceDebug?.AppendLine("   Entry normal " + FixedMaths.FixedToFloat(entryNormalX) + ", " + FixedMaths.FixedToFloat(entryNormalY) + ", " + FixedMaths.FixedToFloat(entryNormalZ));
                            x_TraceDebug?.AppendLine("   Exit normal " + FixedMaths.FixedToFloat(exitNormalX) + ", " + FixedMaths.FixedToFloat(exitNormalY) + ", " + FixedMaths.FixedToFloat(exitNormalZ));
                        }

                        ObjectMergeType objMergeType;

                        if ((inst == Instruction.PlaneSub) || (inst == Instruction.SphereSub) || (inst == Instruction.AABBSub))
                            objMergeType = ObjectMergeType.Sub;
                        else if ((inst == Instruction.PlaneAnd) || (inst == Instruction.SphereAnd) || (inst == Instruction.AABBAnd))
                            objMergeType = ObjectMergeType.And;
                        else
                            objMergeType = ObjectMergeType.Add;

                        x_TraceDebug?.AppendLine("   Performing " + objMergeType + " merge");
                        x_TraceDebug?.AppendLine("    Hit depth range " + FixedMaths.FixedToFloat(entryDepth) + " - " + FixedMaths.FixedToFloat(exitDepth));
                        x_TraceDebug?.AppendLine("    Existing shape depth range " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " - " + FixedMaths.FixedToFloat(s14_HitExitDepth));

                        int newEntryDepth = s14_HitEntryDepth;

                        switch (objMergeType)
                        {
                            case ObjectMergeType.Add:
                            {
                                // Normal object

                                if (entryDepth < exitDepth)
                                {
                                    if (s14_HitEntryDepth >= s14_HitExitDepth)
                                    {
                                        // No existing shape, just write our data to the buffer

                                        newEntryDepth = entryDepth;
                                        destData.s14_HitExitDepth = exitDepth;

                                        destData.s14_HitNormalX = entryNormalX;
                                        destData.s14_HitNormalY = entryNormalY;
                                        destData.s14_HitNormalZ = entryNormalZ;
                                    }
                                    else
                                    {
                                        if (entryDepth < s14_HitEntryDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Updating entry depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));

                                            newEntryDepth = entryDepth;

                                            destData.s14_HitNormalX = entryNormalX;
                                            destData.s14_HitNormalY = entryNormalY;
                                            destData.s14_HitNormalZ = entryNormalZ;
                                        }
                                        else
                                        {
                                            x_TraceDebug?.AppendLine("     Depth test failed - " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " > " + FixedMaths.FixedToFloat(entryDepth));
                                        }

                                        if (exitDepth > s14_HitExitDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Updating exit depth " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));
                                            destData.s14_HitExitDepth = exitDepth;
                                        }
                                    }
                                }
                                break;
                            }
                            case ObjectMergeType.Sub:
                            {
                                // Subtractive object
                                // This isn't completely accurate - we don't support clipping out the middle of an object,
                                // which isn't an issue with only one subtraction but can cause problems if multiple subtractions
                                // are performed.

                                if (s14_HitEntryDepth < s14_HitExitDepth) // Only do this if there is an existing shape
                                {
                                    if ((entryDepth <= s14_HitEntryDepth) && (exitDepth >= s14_HitExitDepth))
                                    {
                                        // Clipping the entire shape
                                        x_TraceDebug?.AppendLine("     Clipping entire shape");
                                        newEntryDepth = 0x7FFFFFFF;
                                        destData.s14_HitExitDepth = 0;
                                    }
                                    else if ((entryDepth < s14_HitEntryDepth) && (exitDepth > s14_HitEntryDepth) && (exitDepth <= s14_HitExitDepth))
                                    {
                                        // Clipping the front part of the shape

                                        x_TraceDebug?.AppendLine("     Clipping front of shape " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));

                                        newEntryDepth = exitDepth;

                                        // Normal will be the inverse of our exit normal

                                        destData.s14_HitNormalX = (Int16)(-exitNormalX);
                                        destData.s14_HitNormalY = (Int16)(-exitNormalY);
                                        destData.s14_HitNormalZ = (Int16)(-exitNormalZ);
                                    }
                                    else if ((entryDepth > s14_HitEntryDepth) && (entryDepth < s14_HitExitDepth) && (exitDepth >= s14_HitExitDepth))
                                    {
                                        // Clipping the rear part of the shape

                                        x_TraceDebug?.AppendLine("     Clipping rear of shape " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));

                                        destData.s14_HitExitDepth = entryDepth;
                                    }

                                    if (newEntryDepth < destData.s14_HitExitDepth)
                                        x_TraceDebug?.AppendLine("     Post-clip shape depth range " + FixedMaths.FixedToFloat(newEntryDepth) + " - " + FixedMaths.FixedToFloat(destData.s14_HitExitDepth));
                                    else
                                        x_TraceDebug?.AppendLine("     Post-clip shape hit was removed");
                                }
                                break;
                            }
                            case ObjectMergeType.And:
                            {
                                // ANDing object
                                // This isn't completely accurate - we don't support clipping out the middle/rear of an object,
                                // which isn't an issue with only one subtraction but can cause problems if multiple subtractions
                                // are performed.

                                if (s14_HitEntryDepth < s14_HitExitDepth) // Only do this if there is an existing shape
                                {
                                    if (entryDepth >= exitDepth)
                                    {
                                        x_TraceDebug?.AppendLine("     Operation removed entire shape");
                                        newEntryDepth = 0x7FFFFFFF;
                                        destData.s14_HitExitDepth = 0;
                                    }
                                    else
                                    {
                                        if (entryDepth > s14_HitEntryDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Updating entry depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " -> " + FixedMaths.FixedToFloat(entryDepth));
                                            newEntryDepth = entryDepth;

                                            destData.s14_HitNormalX = entryNormalX;
                                            destData.s14_HitNormalY = entryNormalY;
                                            destData.s14_HitNormalZ = entryNormalZ;
                                        }

                                        if (exitDepth < s14_HitExitDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Updating exit depth " + FixedMaths.FixedToFloat(s14_HitExitDepth) + " -> " + FixedMaths.FixedToFloat(exitDepth));
                                            destData.s14_HitExitDepth = exitDepth;
                                        }

                                        if (newEntryDepth >= destData.s14_HitExitDepth)
                                        {
                                            x_TraceDebug?.AppendLine("     Operation removed entire shape");
                                        }
                                    }
                                }
                                break;
                            }
                        }

                        destData.s14_HitEntryDepth = newEntryDepth;

                        x_TraceDebug?.AppendLine("    Post-clip depth range " + FixedMaths.FixedToFloat(newEntryDepth) + " - " + FixedMaths.FixedToFloat(destData.s14_HitExitDepth));

                        // Update hit position
                        destData.s14_HitCalculation_HitX = u_RayStartX + FixedMaths.FixedMul(u_RayDirX, newEntryDepth);
                        destData.s14_HitCalculation_HitY = u_RayStartY + FixedMaths.FixedMul(u_RayDirY, newEntryDepth);
                        destData.s14_HitCalculation_HitZ = u_RayStartZ + FixedMaths.FixedMul(u_RayDirZ, newEntryDepth);

                        x_TraceDebug?.AppendLine("    Pos-clip hit pos " + FixedMaths.FixedToFloat(destData.s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(destData.s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(destData.s14_HitCalculation_HitZ));
                    }
                    break;
                }
                case Instruction.Checkerboard:
                {
                    if (execute)
                    {
                        x_TraceDebug?.AppendLine("   Checkerboard hit pos " + FixedMaths.FixedToFloat(s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitZ));

                        bool tile = (((s14_HitCalculation_HitX >> FixedMaths.FixedShift) & 1) != 0) ^ (((s14_HitCalculation_HitZ >> FixedMaths.FixedShift) & 1) != 0);

                        if (tile)
                        {
                            UInt16 albedo = (UInt16)((c14_InstructionWord >> 16) & 0xFFFF);
                            byte reflectiveness = (byte)((c14_InstructionWord >> 8) & 0xFF);

                            x_TraceDebug?.AppendLine("   Checkerboard updating albedo to " + RGB15ToString(albedo) + " reflectiveness " + reflectiveness);

                            destData.s14_RegHitAlbedo = albedo;
                            destData.s14_RegHitReflectiveness = reflectiveness;
                        }
                    }

                    break;
                }
                case Instruction.RegisterHit:
                case Instruction.RegisterHitNoReset:
                {
                    if (execute)
                    {
                        destData.s14_ObjRegisteredHit = false;

                        if (s14_HitEntryDepth < s14_HitExitDepth)
                        {
                            UInt16 albedo = (UInt16)((c14_InstructionWord >> 16) & 0xFFFF);
                            byte reflectiveness = (byte)((c14_InstructionWord >> 8) & 0xFF);

                            if ((!s14_RegHit) || (s14_HitEntryDepth < s14_RegHitDepth))
                            {
                                x_TraceDebug?.AppendLine("  Registering primary hit with albedo " + RGB15ToString(albedo) + " reflectiveness " + reflectiveness);
                                x_TraceDebug?.AppendLine("   Hit depth " + FixedMaths.FixedToFloat(s14_HitEntryDepth) + " pos " + FixedMaths.FixedToFloat(s14_HitCalculation_HitX) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitY) + ", " + FixedMaths.FixedToFloat(s14_HitCalculation_HitZ));

                                destData.s14_RegHit = true;
                                destData.s14_RegHitDepth = s14_HitEntryDepth;
                                destData.s14_RegHitX = s14_HitCalculation_HitX;
                                destData.s14_RegHitY = s14_HitCalculation_HitY;
                                destData.s14_RegHitZ = s14_HitCalculation_HitZ;
                                destData.s14_RegHitNormalX = s14_HitNormalX;
                                destData.s14_RegHitNormalY = s14_HitNormalY;
                                destData.s14_RegHitNormalZ = s14_HitNormalZ;
                                destData.s14_RegHitAlbedo = albedo;
                                destData.s14_RegHitReflectiveness = reflectiveness;
                                destData.s14_ObjRegisteredHit = true;

                                if (u_ShadowRay)
                                {
                                    // Once we have a shadow ray hit we can early-out (invalidating the rest of the pipeline as we do so)
                                    destData.x_InstructionInvalidated = 0xFFFFFFFF;
                                    destData.c1_Finished_tick = true;
                                }
                            }
                            else
                            {
                                x_TraceDebug?.AppendLine("  Not registering hit because Z-test failed");
                            }

                            if (inst != Instruction.RegisterHitNoReset)
                            {
                                // Reset hit state
                                x_TraceDebug?.AppendLine("  Reset hit state");
                                destData.s14_HitEntryDepth = 0x7FFFFFFF;
                                destData.s14_HitExitDepth = 0;
                            }
                        }
                        else
                        {
                            x_TraceDebug?.AppendLine("  No hit to register");
                        }
                    }

                    break;
                }
                case Instruction.ResetHitState:
                {
                    if (execute)
                    {
                        destData.s14_HitEntryDepth = 0x7FFFFFFF;
                        destData.s14_HitExitDepth = 0;
                    }

                    break;
                }

                case Instruction.Jump:
                case Instruction.ResetHitStateAndJump:
                {
                    // The reset happens even if the jump isn't taken
                    if (inst == Instruction.ResetHitStateAndJump)
                    {
                        destData.s14_HitEntryDepth = 0x7FFFFFFF;
                        destData.s14_HitExitDepth = 0;
                    }

                    // Figure out if the dispatcher predicted this branch correctly

                    int predictionBit = 1 << ((u_SecondaryRay ? 2 : 0) | (u_ShadowRay ? 1 : 0));

                    // We store one prediction per pair of instructions, with the prediction result inverting for odd PC addresses
                    // This halves the necessary storage by using the fact that pairs of branches are rare, and when they do appear they're almost
                    // always the conditional inverse of each other.
                    // Note that this code must match the same logic in the dispatcher.
                    bool branchPredicted = ((c14_branchPredictionData & predictionBit) != 0) ^ ((c14_PC & 1) != 0);

                    if (execute == (((c14_branchPredictionData & u_branchPredictionCacheBitMask) != 0) != ((c14_PC & 1) != 0)))
                    {
                        // Branch was predicted correctly, so nothing to do
                        x_TraceDebug?.AppendLine("  Branch predicted correctly");
                        destData.p_BranchPredictionHits++;
                    }
                    else
                    {
                        // Branch mis-predicted, so we need to correct that

                        x_TraceDebug?.AppendLine("  Branch mis-predicted (predicted " + (branchPredicted ? "taken" : "not taken") + ", was actually " + (execute ? "taken" : "not taken") + ")");

                        // The target will either be the real branch target (if we are taking it), or the instruction after the
                        // branch (if we aren't taking it but the dispatcher mis-predicted that we would)
                        int branchTarget = execute ? (int)((c14_InstructionWord >> 8) & 0xFFFF) : (c14_PC + 1);

                        x_TraceDebug?.AppendLine("    Jumping to " + branchTarget + " to correct");

                        // Tell the dispatcher to load the new PC value

                        destData.c1_loadNewPC_tick = true;
                        destData.c1_newPC = branchTarget;

                        // Invalidate all current instructions in the pipeline

                        destData.x_InstructionInvalidated = 0xFFFFFFFF;

                        // We also need to restore the previous origin value, as cycle 3 may have changed it due to a (now invalidated)
                        // origin instruction

                        destData.c3_loadNewOrigin_tick = true;
                        destData.c3_newOriginX = c14_oldOriginX;
                        destData.c3_newOriginY = c14_oldOriginY;
                        destData.c3_newOriginZ = c14_oldOriginZ;

                        // Finally, we need to write an updated prediction into the cache
                        // We can cheat slightly to make the update simpler - we know the prediction is wrong, so we simply flip the
                        // corresponding bit without actually calculating what we think the right value is
                        byte newCacheData = (byte)(c14_branchPredictionData ^ u_branchPredictionCacheBitMask);
                        x_TraceDebug?.AppendLine("  Updated branch prediction cache for PC " + c14_PC + " 0x" + x_BranchPredictionCache[c14_PC >> 1].ToString("x2") + " -> 0x" + newCacheData.ToString("x2"));
                        x_BranchPredictionCache[c14_PC >> 1] = newCacheData;

                        destData.p_BranchPredictionMisses++;
                    }

                    break;
                }
                case Instruction.End:
                {
                    if (execute)
                    {
                        // Invalidate all instructions in the pipeline

                        destData.x_InstructionInvalidated = 0xFFFFFFFF;

                        destData.c1_Finished_tick = true;
                    }
                    break;
                }
            }
        }
    }
}

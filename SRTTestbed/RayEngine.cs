#define USE_EXEC_EMULATOR

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    // Ray execution engine
    partial class RayEngine
    {
        // Inputs
        public bool Start_tick;
        public UInt64[] CommandBuffer;

        public int PrimaryRayStartX;
        public int PrimaryRayStartY;
        public int PrimaryRayStartZ;
        public Int16 PrimaryRayDirX;
        public Int16 PrimaryRayDirY;
        public Int16 PrimaryRayDirZ;
        public Int16 LightDirX;
        public Int16 LightDirY;
        public Int16 LightDirZ;

        public bool DebugShowBranchPredictorHitRate = false;

        // Outputs
        public byte ResultR;
        public byte ResultG;
        public byte ResultB;

        // Current ray information
        int RayStartX;
        int RayStartY;
        int RayStartZ;
        Int16 RayDirX;
        Int16 RayDirY;
        Int16 RayDirZ;

        // Registered hit information for each phase 

        bool RegPrimaryHit;
        int RegPrimaryHitDepth;
        int RegPrimaryHitX;
        int RegPrimaryHitY;
        int RegPrimaryHitZ;
        Int16 RegPrimaryHitNormalX;
        Int16 RegPrimaryHitNormalY;
        Int16 RegPrimaryHitNormalZ;
        UInt16 RegPrimaryHitAlbedo;
        byte RegPrimaryHitReflectiveness;

        bool RegPrimaryShadowHit; // Shadow rays only require hit/no hit determination

        bool RegSecondaryHit;
        int RegSecondaryHitDepth;
        int RegSecondaryHitX;
        int RegSecondaryHitY;
        int RegSecondaryHitZ;
        Int16 RegSecondaryHitNormalX;
        Int16 RegSecondaryHitNormalY;
        Int16 RegSecondaryHitNormalZ;
        UInt16 RegSecondaryHitAlbedo;

        bool RegSecondaryShadowHit;

        // Result colours
        byte PrimaryRayColourR;
        byte PrimaryRayColourG;
        byte PrimaryRayColourB;
        byte SecondaryRayColourR;
        byte SecondaryRayColourG;
        byte SecondaryRayColourB;

        // Performance
        int BranchPredictionHits;
        int BranchPredictionMisses;

        // Debug
        public StringBuilder TraceDebug = null;

        // 1/RayDir calculation modules
        FixedRcpClocked RayDirX_RCPModule = new FixedRcpClocked();
        FixedRcpClocked RayDirY_RCPModule = new FixedRcpClocked();
        FixedRcpClocked RayDirZ_RCPModule = new FixedRcpClocked();

#if USE_EXEC_EMULATOR
        ExecEngineEmulator Engine = new ExecEngineEmulator();
#else
        ExecEngine Engine = new ExecEngine();
#endif

        enum ExecEnginePhase
        {
            PrimaryRay,
            PrimaryShadow,
            SecondaryRay,
            SecondaryShadow
        }

        enum ExecEngineState
        {
            WaitingToStart,
            StartingPhase,
            ExecEngineSetup1,
            ExecEngineSetup2,
            ExecEngineSetup3,
            ExecEngineStart,
            ExecEngineWait,
            ExecEngineFinished,
            FinishingPhase,
            WritePixel
        }

        ExecEnginePhase Phase;
        ExecEngineState State;

        public void Run()
        {
            Engine.x_TraceDebug = TraceDebug;
            Engine.u_CommandBuffer = CommandBuffer;
            int clockIndex = 0;
            Reset();
            Start_tick = true;
            TraceDebug?.AppendLine("Clock " + clockIndex + " ray engine phase " + Phase + " state " + State + " exec engine busy " + Engine.x_Busy);
            Tick();
            clockIndex++;
            Start_tick = false;
            while (State != ExecEngineState.WaitingToStart)
            {
                TraceDebug?.AppendLine("Clock " + clockIndex + " ray engine phase " + Phase + " state " + State + " exec engine busy " + Engine.x_Busy);
                Tick();
                clockIndex++;
            }
        }

        // Reset state
        public void Reset()
        {
            State = ExecEngineState.WaitingToStart;
        }

        // Perform a single execution tick
        public void Tick()
        {
            Engine = Engine.Tick();

            // Slight bodge - we do these before the RCP module ticks to get the correct timing on when these are set
            Engine.u_RayDirRcpX = RayDirX_RCPModule.result;
            Engine.u_RayDirRcpY = RayDirY_RCPModule.result;
            Engine.u_RayDirRcpZ = RayDirZ_RCPModule.result;

            ColourCalculator_Tick();
            SecondaryRayDirectionCalculator_Tick();
            FinalColourCalculator_Tick();
            RayDirX_RCPModule = RayDirX_RCPModule.Tick();
            RayDirY_RCPModule = RayDirY_RCPModule.Tick();
            RayDirZ_RCPModule = RayDirZ_RCPModule.Tick();

            Engine.x_Start_tick = false;
            Engine.u_RayDirX = RayDirX;
            Engine.u_RayDirY = RayDirY;
            Engine.u_RayDirZ = RayDirZ;
            Engine.u_RayStartX = RayStartX;
            Engine.u_RayStartY = RayStartY;
            Engine.u_RayStartZ = RayStartZ;
            Engine.u_ShadowRay = (Phase == ExecEnginePhase.PrimaryShadow) || (Phase == ExecEnginePhase.SecondaryShadow);
            Engine.u_SecondaryRay = (Phase == ExecEnginePhase.SecondaryRay) || (Phase == ExecEnginePhase.SecondaryShadow);

            switch (State)
            {
                case ExecEngineState.WaitingToStart:
                {
                    if (Start_tick)
                    {
                        RayStartX = PrimaryRayStartX;
                        RayStartY = PrimaryRayStartY;
                        RayStartZ = PrimaryRayStartZ;
                        RayDirX = PrimaryRayDirX;
                        RayDirY = PrimaryRayDirY;
                        RayDirZ = PrimaryRayDirZ;
                        RegPrimaryHit = false;
                        RegPrimaryShadowHit = false;
                        RegSecondaryHit = false;
                        RegSecondaryShadowHit = false;
                        BranchPredictionHits = 0;
                        BranchPredictionMisses = 0;

                        Phase = ExecEnginePhase.PrimaryRay;
                        State = ExecEngineState.StartingPhase;
                    }
                    break;
                }
                case ExecEngineState.StartingPhase:
                {
                    // If the ray start point is a very large value, we get overflows that cause all sorts of weirdness
                    // (generally with shadows/reflections), so just assume rays starting out of bounds never hit anything
                    // (this is also a reasonably significant performance optimisation)
                    //int minTraceStart = FixedMaths.FloatToFixed(-35.0f);
                    //int maxTraceStart = FixedMaths.FloatToFixed(35.0f);
                    int minTraceStart = FixedMaths.FloatToFixed(-40.0f);
                    int maxTraceStart = FixedMaths.FloatToFixed(40.0f);

                    Engine.ResetPerfCounters();

                    if ((RayStartX < minTraceStart) || (RayStartX > maxTraceStart) ||
                        (RayStartY < minTraceStart) || (RayStartY > maxTraceStart) ||
                        (RayStartZ < minTraceStart) || (RayStartZ > maxTraceStart))
                    {
                        State = ExecEngineState.FinishingPhase;
                    }
                    else
                    {
                        RayDirX_RCPModule.rcpIn = RayDirX;
                        RayDirY_RCPModule.rcpIn = RayDirY;
                        RayDirZ_RCPModule.rcpIn = RayDirZ;

                        State = ExecEngineState.ExecEngineSetup1;
                    }

                    break;
                }
                // Wait for 1/RayDir calculation to complete
                case ExecEngineState.ExecEngineSetup1: State = ExecEngineState.ExecEngineSetup2; break;
                case ExecEngineState.ExecEngineSetup2: State = ExecEngineState.ExecEngineSetup3; break;
                case ExecEngineState.ExecEngineSetup3: State = ExecEngineState.ExecEngineStart; break;
                // Start exec engine
                case ExecEngineState.ExecEngineStart:
                {
                    Engine.x_Start_tick = true;
                    State = ExecEngineState.ExecEngineWait;
                    break;
                }
                case ExecEngineState.ExecEngineWait:
                {
                    if (!Engine.x_Busy)
                    {
                        State = ExecEngineState.ExecEngineFinished;
                    }

                    break;
                }                
                case ExecEngineState.ExecEngineFinished:
                {
                    // Copy results from exec engine

                    TraceDebug?.AppendLine(Phase + " results:");
                    TraceDebug?.AppendLine(Engine.s14_RegHit ? "  Hit" : "  No hit");
                    if (Engine.s14_RegHit)
                    {
                        TraceDebug?.AppendLine("  Depth: " + FixedMaths.FixedToFloat(Engine.s14_RegHitDepth));
                        TraceDebug?.AppendLine("  Pos: " + FixedMaths.FixedToFloat(Engine.s14_RegHitX) + ", " + FixedMaths.FixedToFloat(Engine.s14_RegHitY) + ", " + FixedMaths.FixedToFloat(Engine.s14_RegHitZ));
                        TraceDebug?.AppendLine("  Normal: " + FixedMaths.FixedToFloat(Engine.s14_RegHitNormalX) + ", " + FixedMaths.FixedToFloat(Engine.s14_RegHitNormalY) + ", " + FixedMaths.FixedToFloat(Engine.s14_RegHitNormalZ));
                        TraceDebug?.AppendLine("  Albedo: " + ExecEngine.RGB15ToString(Engine.s14_RegHitAlbedo) + ", Reflectiveness: " + Engine.s14_RegHitReflectiveness);
                    }

                    TraceDebug?.AppendLine("Performance:");
                    TraceDebug?.AppendLine("Cycles: " + Engine.p_CycleCount);
                    TraceDebug?.AppendLine("Instructions executed: " + Engine.p_InstructionsExecuted);
                    TraceDebug?.AppendLine("Instructions abandoned: " + Engine.p_InstructionsAbandoned);
                    TraceDebug?.AppendLine("Branch prediction hits: " + Engine.p_BranchPredictionHits);
                    TraceDebug?.AppendLine("Branch prediction misses: " + Engine.p_BranchPredictionMisses);

                    BranchPredictionHits += Engine.p_BranchPredictionHits;
                    BranchPredictionMisses += Engine.p_BranchPredictionMisses;

                    switch (Phase)
                    {
                        case ExecEnginePhase.PrimaryRay:
                        {
                            RegPrimaryHit = Engine.s14_RegHit;
                            RegPrimaryHitDepth = Engine.s14_RegHitDepth;
                            RegPrimaryHitX = Engine.s14_RegHitX;
                            RegPrimaryHitY = Engine.s14_RegHitY;
                            RegPrimaryHitZ = Engine.s14_RegHitZ;
                            RegPrimaryHitNormalX = Engine.s14_RegHitNormalX;
                            RegPrimaryHitNormalY = Engine.s14_RegHitNormalY;
                            RegPrimaryHitNormalZ = Engine.s14_RegHitNormalZ;
                            RegPrimaryHitAlbedo = Engine.s14_RegHitAlbedo;
                            RegPrimaryHitReflectiveness = Engine.s14_RegHitReflectiveness;
                            break;
                        }
                        case ExecEnginePhase.PrimaryShadow:
                        {
                            RegPrimaryShadowHit = Engine.s14_RegHit;
                            break;
                        }
                        case ExecEnginePhase.SecondaryRay:
                        {
                            RegSecondaryHit = Engine.s14_RegHit;
                            RegSecondaryHitDepth = Engine.s14_RegHitDepth;
                            RegSecondaryHitX = Engine.s14_RegHitX;
                            RegSecondaryHitY = Engine.s14_RegHitY;
                            RegSecondaryHitZ = Engine.s14_RegHitZ;
                            RegSecondaryHitNormalX = Engine.s14_RegHitNormalX;
                            RegSecondaryHitNormalY = Engine.s14_RegHitNormalY;
                            RegSecondaryHitNormalZ = Engine.s14_RegHitNormalZ;
                            RegSecondaryHitAlbedo = Engine.s14_RegHitAlbedo;
                            break;
                        }
                        case ExecEnginePhase.SecondaryShadow:
                        {
                            RegSecondaryShadowHit = Engine.s14_RegHit;
                            break;
                        }
                    }

                    State = ExecEngineState.FinishingPhase;

                    break;
                }
                case ExecEngineState.FinishingPhase:
                {
                    // Calculate ray result colour

                    bool secondaryPhase = ((Phase == ExecEnginePhase.SecondaryRay) || (Phase == ExecEnginePhase.SecondaryShadow));
                    
                    // Store colour

                    if (!secondaryPhase)
                    {
                        TraceDebug?.AppendLine("   Setting primary ray colour to " + ColourCalculator_RayR + ", " + ColourCalculator_RayG + ", " + ColourCalculator_RayB);
                        PrimaryRayColourR = ColourCalculator_RayR;
                        PrimaryRayColourG = ColourCalculator_RayG;
                        PrimaryRayColourB = ColourCalculator_RayB;
                    }
                    else
                    {
                        TraceDebug?.AppendLine("   Setting secondary ray colour to " + ColourCalculator_RayR + ", " + ColourCalculator_RayG + ", " + ColourCalculator_RayB);
                        SecondaryRayColourR = ColourCalculator_RayR;
                        SecondaryRayColourG = ColourCalculator_RayG;
                        SecondaryRayColourB = ColourCalculator_RayB;
                    }

                    // Now figure out what to do next

                    int secondaryRayBias = FixedMaths.FloatToFixed(0.1f); // Bias for shadow/secondary rays

                    // Default to being done tracing and ready to write the pixel
                    State = ExecEngineState.WritePixel;

                    // See if we have any more phases to do
                    switch (Phase)
                    {
                        case ExecEnginePhase.PrimaryRay:
                        {
                            if (RegPrimaryHit)
                            {
                                int normalDotLight = FixedMaths.FixedMul16x16(LightDirX, RegPrimaryHitNormalX) + FixedMaths.FixedMul16x16(LightDirY, RegPrimaryHitNormalY) + FixedMaths.FixedMul16x16(LightDirZ, RegPrimaryHitNormalZ);

                                if (normalDotLight > 0) // Only do shadow rays for pixels that point towards the light
                                {
                                    // Do shadow phase
                                    RayStartX = SecondaryRayDirectionCalculator_ShadowRayStartX;
                                    RayStartY = SecondaryRayDirectionCalculator_ShadowRayStartY;
                                    RayStartZ = SecondaryRayDirectionCalculator_ShadowRayStartZ;
                                    RayDirX = SecondaryRayDirectionCalculator_ShadowRayDirX;
                                    RayDirY = SecondaryRayDirectionCalculator_ShadowRayDirY;
                                    RayDirZ = SecondaryRayDirectionCalculator_ShadowRayDirZ;

                                    Phase = ExecEnginePhase.PrimaryShadow;
                                    State = ExecEngineState.StartingPhase;
                                }
                                else if (RegPrimaryHitReflectiveness != 0)
                                {
                                    // Skip to secondary ray
                                    RegPrimaryShadowHit = true; // Presume shadowing for anything pointing away from the light

                                    RayStartX = SecondaryRayDirectionCalculator_ReflectionRayStartX;
                                    RayStartY = SecondaryRayDirectionCalculator_ReflectionRayStartY;
                                    RayStartZ = SecondaryRayDirectionCalculator_ReflectionRayStartZ;
                                    RayDirX = SecondaryRayDirectionCalculator_ReflectionRayDirX;
                                    RayDirY = SecondaryRayDirectionCalculator_ReflectionRayDirY;
                                    RayDirZ = SecondaryRayDirectionCalculator_ReflectionRayDirZ;

                                    Phase = ExecEnginePhase.SecondaryRay;
                                    State = ExecEngineState.StartingPhase;
                                }
                                else
                                {
                                    RegPrimaryShadowHit = true; // Presume shadowing for anything pointing away from the light
                                }
                            }
                            break;
                        }
                        case ExecEnginePhase.PrimaryShadow:
                        {
                            // No need to check RegPrimaryHit here because a hit would be required to trigger the shadow phase
                            if (RegPrimaryHitReflectiveness != 0)
                            {
                                // Do secondary ray

                                RayStartX = SecondaryRayDirectionCalculator_ReflectionRayStartX;
                                RayStartY = SecondaryRayDirectionCalculator_ReflectionRayStartY;
                                RayStartZ = SecondaryRayDirectionCalculator_ReflectionRayStartZ;
                                RayDirX = SecondaryRayDirectionCalculator_ReflectionRayDirX;
                                RayDirY = SecondaryRayDirectionCalculator_ReflectionRayDirY;
                                RayDirZ = SecondaryRayDirectionCalculator_ReflectionRayDirZ;

                                Phase = ExecEnginePhase.SecondaryRay;
                                State = ExecEngineState.StartingPhase;
                            }
                            break;
                        }
                        case ExecEnginePhase.SecondaryRay:
                        {
                            if (RegSecondaryHit)
                            {
                                int normalDotLight = FixedMaths.FixedMul16x16(LightDirX, RegSecondaryHitNormalX) + FixedMaths.FixedMul16x16(LightDirY, RegSecondaryHitNormalY) + FixedMaths.FixedMul16x16(LightDirZ, RegSecondaryHitNormalZ);

                                if (normalDotLight > 0) // Only do shadow rays for pixels that point towards the light
                                {
                                    // Do shadow phase
                                    RayStartX = SecondaryRayDirectionCalculator_ShadowRayStartX;
                                    RayStartY = SecondaryRayDirectionCalculator_ShadowRayStartY;
                                    RayStartZ = SecondaryRayDirectionCalculator_ShadowRayStartZ;
                                    RayDirX = SecondaryRayDirectionCalculator_ShadowRayDirX;
                                    RayDirY = SecondaryRayDirectionCalculator_ShadowRayDirY;
                                    RayDirZ = SecondaryRayDirectionCalculator_ShadowRayDirZ;

                                    Phase = ExecEnginePhase.SecondaryShadow;
                                    State = ExecEngineState.StartingPhase;
                                }
                                else
                                {
                                    RegSecondaryShadowHit = true; // Presume shadowing for anything pointing away from the light
                                }
                            }
                            break;
                        }
                        default:
                        {
                            break;
                        }
                    }

                    break;
                }
                case ExecEngineState.WritePixel:
                {
                    TraceDebug?.AppendLine("Total branch prediction hits: " + BranchPredictionHits);
                    TraceDebug?.AppendLine("Total branch prediction misses: " + BranchPredictionMisses);

                    // Store to pixel

                    ResultR = FinalColourCalculator_R;
                    ResultG = FinalColourCalculator_G;
                    ResultB = FinalColourCalculator_B;

                    // Debug colouring if requested

                    if (DebugShowBranchPredictorHitRate)
                    {
                        int totalBranches = BranchPredictionHits + BranchPredictionMisses;

                        if (totalBranches > 0)
                        {
                            float hitRate = (float)BranchPredictionHits / (float)totalBranches;

                            // Lerp between red for all misses and green for all hits

                            ResultR = (byte)((1.0f - hitRate) * 255); 
                            ResultG = (byte)(hitRate * 255);
                            ResultB = 0;
                        }
                        else
                        {
                            // No branches
                            ResultR = 0;
                            ResultG = 0;
                            ResultB = 0;
                        }                        
                    }

                    // Execution is complete
                    State = ExecEngineState.WaitingToStart;
                    break;
                }
                default:
                {
                    break;
                }
            }
        }        
    }
}

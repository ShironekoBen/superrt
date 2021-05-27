#define USE_THREADING

// SuperRT by Ben Carter (c) 2021

using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Data;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.Windows.Forms;
using System.Runtime.InteropServices;
using System.IO;
using System.Diagnostics;
using System.Collections.Concurrent;

namespace SRTTestbed
{
    public partial class Form1 : Form
    {
        PaletteGenerator Palette;
        public int CameraX = 0;
        public int CameraY = 0x1800;
        public int CameraZ = 0;
        public int CameraYaw = 0;
        public int DebugX = -1;
        public int DebugY = -1;

        string SourceFilename = "../../Scene.txt";
        DateTime LastSourceTimestamp;
        UInt64[] OriginalCommandBuffer = null;
        UInt64[] CommandBuffer = null;
        int[] EditPoints = null;
        string LastCompileMessages = "";

        public Form1()
        {
            InitializeComponent();
        }

        private void Form1_Load(object sender, EventArgs e)
        {
            BuildTables();

            Bitmap image = Trace();

            Palette = new PaletteGenerator();
            Palette.AddFixedColour(0, Color.Black);
            Palette.AddFixedColour(1, Color.White);
            Palette.AddImage(image, ditherCheckbox.Checked);
            Palette.GeneratePalette();

            Bitmap palImage = Palette.ConvertBitmap(image, ditherCheckbox.Checked);

            pictureBox1.Image = palImage;
            pictureBox2.Image = Palette.GeneratePaletteBitmap();
        }

        const int width = 200;
        const int height = 160;
        const float halfFOV = 45.0f;
        int lightDirX;
        int lightDirY;
        int lightDirZ;

        void BuildTables()
        {
            FixedMaths.BuildSqrtTable();
            FixedMaths.BuildSinTable();

            // Write out sin table

            {
                byte[] rawTable = new byte[FixedMaths.SinTable.Length * sizeof(short)];

                Buffer.BlockCopy(FixedMaths.SinTable, 0, rawTable, 0, rawTable.Length);

                File.WriteAllBytes(@"../../../SRT-SNES/Data/SinTable.bin", rawTable);
            }        
        }        

        void SaveCommandBuffer(UInt64[] commandArray, string filename)
        {
            byte[] rawTable = new byte[commandArray.Length * sizeof(UInt64)];
            Buffer.BlockCopy(commandArray, 0, rawTable, 0, rawTable.Length);

            ByteSwap64(rawTable);

            File.WriteAllBytes(filename, rawTable);
        }

        // Byte-swap a buffer full of 32-bit values
        void ByteSwap32(byte[] buffer)
        {
            for (int i = 0; i < buffer.Length; i += 4)
            {
                byte temp = buffer[i];
                buffer[i] = buffer[i + 3];
                buffer[i + 3] = temp;
                temp = buffer[i + 1];
                buffer[i + 1] = buffer[i + 2];
                buffer[i + 2] = temp;
            }
        }

        // Byte-swap a buffer full of 64-bit values
        void ByteSwap64(byte[] buffer)
        {
            byte temp;
            for (int i = 0; i < buffer.Length; i += 8)
            {
                temp = buffer[i];
                buffer[i] = buffer[i + 7];
                buffer[i + 7] = temp;

                temp = buffer[i + 1];
                buffer[i + 1] = buffer[i + 6];
                buffer[i + 6] = temp;

                temp = buffer[i + 2];
                buffer[i + 2] = buffer[i + 5];
                buffer[i + 5] = temp;

                temp = buffer[i + 3];
                buffer[i + 3] = buffer[i + 4];
                buffer[i + 4] = temp;
            }
        }

        void RotateVector(ref int x, ref int y, ref int z, int yaw)
        {
            int sinYaw = FixedMaths.FloatToFixed((float)Math.Sin(FixedMaths.FixedToFloat(yaw)));
            int cosYaw = FixedMaths.FloatToFixed((float)Math.Cos(FixedMaths.FixedToFloat(yaw)));

            int nx = FixedMaths.FixedMul(x, cosYaw) + FixedMaths.FixedMul(z, sinYaw);
            int nz = FixedMaths.FixedMul(z, cosYaw) - FixedMaths.FixedMul(x, sinYaw);

            x = nx;
            z = nz;
        }

        // Create a valid-but-blank command buffer
        UInt64[] CreateBlankCommandBuffer()
        {
            UInt64[] commandBuffer = new UInt64[2];
            commandBuffer[0] = ExecEngine.BuildInstruction(ExecEngine.Instruction.Start);
            commandBuffer[1] = ExecEngine.BuildInstruction(ExecEngine.Instruction.End);
            return commandBuffer;
        }

        static Int16[] AnimY = new Int16[4];
        static Int16[] AnimYVel = new Int16[4];
        static Int16 AnimGrav = (Int16)FixedMaths.FloatToFixed(0.05f);
        static Int16 AnimFloor = (Int16)FixedMaths.FloatToFixed(1.5f);
        static Int16 AnimTermVel = (Int16)FixedMaths.FloatToFixed(0.4f);
        static int AnimBoxYaw = 0;
        static int AnimBoxYawSpeed = FixedMaths.FloatToFixed((8.0f / 180.0f) * 3.14f);
        static Int16[] BubbleY = new Int16[4];
        static Int16[] BubbleYVel = new Int16[4];
        static int ShipBobAngle = 0;
        static int ShipBobSpeed = FixedMaths.FloatToFixed((8.0f / 180.0f) * 3.14f);
        static int ShipBobCentre = FixedMaths.FloatToFixed(0.95f);

        void StartAnimation()
        {
            for (int i = 0; i < 4; i++)
            {
                AnimY[i] = (Int16)FixedMaths.FloatToFixed(0.5f * i);
                BubbleYVel[i] = (Int16)FixedMaths.FloatToFixed(-0.02f * (i + 1));
            }

            ShipBobAngle = 0;
            AnimBoxYaw = 0;
        }

        void ApplyAnimation()
        {
            if ((CommandBuffer == null) || (EditPoints == null))
                return;

            // Spheres

            for (int i = 0; i < 4; i++)
            {
                AnimY[i] += AnimYVel[i];
                AnimYVel[i] += AnimGrav;
                if (AnimY[i] > AnimFloor)
                {
                    AnimY[i] = AnimFloor;
                    AnimYVel[i] = (Int16)(-AnimYVel[i]);
                }
                if (AnimYVel[i] > AnimTermVel)
                {
                    AnimYVel[i] = AnimTermVel;
                }

                if ((EditPoints.Length > i) && (EditPoints[i] > 0))
                {
                    int editPoint = EditPoints[i];
                    UInt64 inst = OriginalCommandBuffer[editPoint];

                    UInt64 packedY = (UInt64)((AnimY[i] >> 7) & 0x7FFF); // //unchecked((UInt64)FixedMaths.ConvertTo8Dot7(AnimY[i]));

                    inst &= 0xFFFFFFC0007FFFFFUL;
                    inst |= packedY << 23;

                    CommandBuffer[editPoint] = inst;
                }
            }

            for (int i = 0; i < 4; i++)
            {
                // We cheat here and let the 16-bit value wrap do some of the work
                BubbleY[i] += BubbleYVel[i];

                if ((EditPoints.Length > (i + 6)) && (EditPoints[i + 6] > 0))
                {
                    int editPoint = EditPoints[i + 6];
                    UInt64 inst = OriginalCommandBuffer[editPoint];

                    UInt64 packedY = (UInt64)((BubbleY[i] >> 7) & 0x7FFF); // //unchecked((UInt64)FixedMaths.ConvertTo8Dot7(AnimY[i]));

                    inst &= 0xFFFFFFC0007FFFFFUL;
                    inst |= packedY << 23;

                    CommandBuffer[editPoint] = inst;
                }
            }

            // Rotating boxes

            AnimBoxYaw += AnimBoxYawSpeed;

            for (int i = 4; i <= 5; i++)
            {
                if ((EditPoints.Length > i) && (EditPoints[i] > 0))
                {
                    for (int j = 0; j < 6; j++)
                    {
                        int editPoint = EditPoints[i] + j;
                        UInt64 inst = OriginalCommandBuffer[editPoint];

                        int normalX = FixedMaths.ConvertFrom2Dot10((UInt16)((inst >> 8) & 0xFFF));
                        int normalY = FixedMaths.ConvertFrom2Dot10((UInt16)((inst >> 20) & 0xFFF));
                        int normalZ = FixedMaths.ConvertFrom2Dot10((UInt16)((inst >> 32) & 0xFFF));

                        RotateVector(ref normalX, ref normalY, ref normalZ, AnimBoxYaw);

                        UInt64 packedNormalX = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(normalX));
                        UInt64 packedNormalY = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(normalY));
                        UInt64 packedNormalZ = unchecked((UInt64)FixedMaths.ConvertTo2Dot10(normalZ));

                        inst &= 0xFFFFF000000000FFUL;
                        inst |= (packedNormalX << 8) | (packedNormalY << 20) | (packedNormalZ << 32);

                        CommandBuffer[editPoint] = inst;
                    }
                }
            }

            // Ship bob

            ShipBobAngle += ShipBobSpeed;

            int sinBobAngle = FixedMaths.FloatToFixed((float)Math.Sin(FixedMaths.FixedToFloat(ShipBobAngle)));
            int shipBobPos = ShipBobCentre + (sinBobAngle >> 2);

            if ((EditPoints.Length > 10) && (EditPoints[10] > 0))
            {
                int editPoint = EditPoints[10];
                UInt64 inst = OriginalCommandBuffer[editPoint];

                UInt64 packedY = (UInt64)((shipBobPos >> 7) & 0x7FFF);

                inst &= 0xFFFFFFC0007FFFFFUL;
                inst |= packedY << 23;

                CommandBuffer[editPoint] = inst;
            }
        }

        Bitmap Trace(bool noTrace = false)
        {
            lightDirX = FixedMaths.FloatToFixed(0.5f);
            lightDirY = FixedMaths.FloatToFixed(-1.0f);
            lightDirZ = FixedMaths.FloatToFixed(-0.5f);

            FixedMaths.Normalise(ref lightDirX, ref lightDirY, ref lightDirZ);

            Bitmap result = new Bitmap(width, height);

            DateTime fileTime = File.GetLastWriteTimeUtc(SourceFilename);
            if ((fileTime != LastSourceTimestamp) || (CommandBuffer == null))
            {
                LastSourceTimestamp = fileTime;
                string source = File.ReadAllText(SourceFilename);

                SceneCompiler compiler = new SceneCompiler();
                if (!compiler.Compile(source, out CommandBuffer, out EditPoints, out LastCompileMessages, visualiseCullingCheckBox.Checked))
                {
                    // Create a dummy command buffer
                    CommandBuffer = CreateBlankCommandBuffer();
                    EditPoints = null;
                }

                StringBuilder builder = new StringBuilder();
                builder.AppendLine(LastCompileMessages);
                builder.AppendLine("Command buffer:");
                builder.AppendLine();
                builder.AppendLine(CommandListDisassembler.Disassemble(CommandBuffer, EditPoints));
                LastCompileMessages = builder.ToString();

                OriginalCommandBuffer = new UInt64[CommandBuffer.Length];
                Array.Copy(CommandBuffer, OriginalCommandBuffer, CommandBuffer.Length);

                StartAnimation();
            }

            if (animateCheckBox.Checked)
            {
                ApplyAnimation();
            }

            // Calculate camera frustum

            int tlRayDirX, tlRayDirY, tlRayDirZ;
            int trRayDirX, trRayDirY, trRayDirZ;
            int blRayDirX, blRayDirY, blRayDirZ;

            float halfTanHalfFov = (float)Math.Tan(halfFOV * 3.14f / 180.0f) * 0.5f;

            tlRayDirX = FixedMaths.FloatToFixed(-halfTanHalfFov);
            tlRayDirY = FixedMaths.FloatToFixed(-halfTanHalfFov);
            tlRayDirZ = FixedMaths.FloatToFixed(1.0f);

            trRayDirX = FixedMaths.FloatToFixed(halfTanHalfFov);
            trRayDirY = FixedMaths.FloatToFixed(-halfTanHalfFov);
            trRayDirZ = FixedMaths.FloatToFixed(1.0f);

            blRayDirX = FixedMaths.FloatToFixed(-halfTanHalfFov);
            blRayDirY = FixedMaths.FloatToFixed(halfTanHalfFov);
            blRayDirZ = FixedMaths.FloatToFixed(1.0f);

            FixedMaths.Normalise(ref tlRayDirX, ref tlRayDirY, ref tlRayDirZ);
            FixedMaths.Normalise(ref trRayDirX, ref trRayDirY, ref trRayDirZ);
            FixedMaths.Normalise(ref blRayDirX, ref blRayDirY, ref blRayDirZ);

            // Rotate

            RotateVector(ref tlRayDirX, ref tlRayDirY, ref tlRayDirZ, CameraYaw);
            RotateVector(ref trRayDirX, ref trRayDirY, ref trRayDirZ, CameraYaw);
            RotateVector(ref blRayDirX, ref blRayDirY, ref blRayDirZ, CameraYaw);

            // Because we normalise the ray vector later, we can cheese a little extra accuracy out for no cost by scaling the fustrum
            // (currently disabled because it causes issues, both "normally" and due to the use of 16-bit registers to hold direction data)
            int scaleForAccuracy = FixedMaths.FloatToFixed(1.0f);

            tlRayDirX = FixedMaths.FixedMul(tlRayDirX, scaleForAccuracy);
            tlRayDirY = FixedMaths.FixedMul(tlRayDirY, scaleForAccuracy);
            tlRayDirZ = FixedMaths.FixedMul(tlRayDirZ, scaleForAccuracy);

            trRayDirX = FixedMaths.FixedMul(trRayDirX, scaleForAccuracy);
            trRayDirY = FixedMaths.FixedMul(trRayDirY, scaleForAccuracy);
            trRayDirZ = FixedMaths.FixedMul(trRayDirZ, scaleForAccuracy);

            blRayDirX = FixedMaths.FixedMul(blRayDirX, scaleForAccuracy);
            blRayDirY = FixedMaths.FixedMul(blRayDirY, scaleForAccuracy);
            blRayDirZ = FixedMaths.FixedMul(blRayDirZ, scaleForAccuracy);

            Int16 rayXStepX = (Int16)FixedMaths.FixedDiv(trRayDirX - tlRayDirX, FixedMaths.FloatToFixed((float)width));
            Int16 rayXStepY = (Int16)FixedMaths.FixedDiv(trRayDirY - tlRayDirY, FixedMaths.FloatToFixed((float)width));
            Int16 rayXStepZ = (Int16)FixedMaths.FixedDiv(trRayDirZ - tlRayDirZ, FixedMaths.FloatToFixed((float)width));

            Int16 rayYStepX = (Int16)FixedMaths.FixedDiv(blRayDirX - tlRayDirX, FixedMaths.FloatToFixed((float)height));
            Int16 rayYStepY = (Int16)FixedMaths.FixedDiv(blRayDirY - tlRayDirY, FixedMaths.FloatToFixed((float)height));
            Int16 rayYStepZ = (Int16)FixedMaths.FixedDiv(blRayDirZ - tlRayDirZ, FixedMaths.FloatToFixed((float)height));

            //Debug.WriteLine("X step base " + FixedMaths.FixedToFloat(trRayDirX - tlRayDirX).ToString("0.000") + ", " + FixedMaths.FixedToFloat(trRayDirY - tlRayDirY).ToString("0.000") + ", " + FixedMaths.FixedToFloat(trRayDirZ - tlRayDirZ).ToString("0.000"));

            //Debug.WriteLine("RayXStep " + FixedMaths.FixedToFloat(rayXStepX).ToString("0.000") + ", " + FixedMaths.FixedToFloat(rayXStepY).ToString("0.000") + ", " + FixedMaths.FixedToFloat(rayXStepZ).ToString("0.000"));
            //Debug.WriteLine("RayYStep " + FixedMaths.FixedToFloat(rayYStepX).ToString("0.000") + ", " + FixedMaths.FixedToFloat(rayYStepY).ToString("0.000") + ", " + FixedMaths.FixedToFloat(rayYStepZ).ToString("0.000"));

            StringBuilder traceDebug = noTrace ? null : new StringBuilder();

            traceDebug?.AppendLine("Compiler output:");
            traceDebug?.AppendLine(LastCompileMessages);
            traceDebug?.AppendLine("");

            int debugClockIndex = -1;

            if ((DebugX >= 0) && (!noTrace))
            {
                debugClockIndex = (DebugY * width) + DebugX;

                traceDebug?.AppendLine("Debugging pixel " + DebugX + ", " + DebugY + " index " + debugClockIndex);
            }

            Int16 rayDirX = (Int16)tlRayDirX;
            Int16 rayDirY = (Int16)tlRayDirY;
            Int16 rayDirZ = (Int16)tlRayDirZ;

            Int16 lineStartRayDirX = rayDirX;
            Int16 lineStartRayDirY = rayDirY;
            Int16 lineStartRayDirZ = rayDirZ;

            bool showBranchPrediction = showBranchPredictionHitRateCheckbox.Checked;

#if USE_THREADING
            Color[] destBuffer = new Color[width * height];
            Int16[] rayDirData = new Int16[width * height * 3];

            // Precalculate ray directions

            {
                int x = 0;
                int y = 0;

                int writeIndex = 0;

                for (int clock = 0; clock < width * height; clock++)
                {
                    rayDirData[writeIndex++] = rayDirX;
                    rayDirData[writeIndex++] = rayDirY;
                    rayDirData[writeIndex++] = rayDirZ;

                    x++;

                    if (x >= width)
                    {
                        lineStartRayDirX += rayYStepX;
                        lineStartRayDirY += rayYStepY;
                        lineStartRayDirZ += rayYStepZ;
                        rayDirX = lineStartRayDirX;
                        rayDirY = lineStartRayDirY;
                        rayDirZ = lineStartRayDirZ;

                        x = 0;
                        y++;
                    }
                    else
                    {
                        rayDirX += rayXStepX;
                        rayDirY += rayXStepY;
                        rayDirZ += rayXStepZ;
                    }
                }
            }
#else
            RayEngine engine = new RayEngine();
            int x = 0;
            int y = 0;            
#endif

#if USE_THREADING
            // Stack of idle ray engines that can be reused
            // This is primarily to get at least some notion of correct branch prediction cache behavior when in threaded mode,
            // and doesn't really affect anything else beyond a small speed boost.
            ConcurrentStack<RayEngine> idleRayEngines = new ConcurrentStack<RayEngine>();

            Parallel.For(0, width * height, (clock) =>
#else
            for (int clock = 0; clock < width * height; clock++)
#endif
            {
#if USE_THREADING
                int x = clock % width;
                int y = clock / width;

                RayEngine engine;

                if (!idleRayEngines.TryPop(out engine))
                {
                    engine = new RayEngine();
                }
#endif
                engine.LightDirX = (Int16)lightDirX;
                engine.LightDirY = (Int16)lightDirY;
                engine.LightDirZ = (Int16)lightDirZ;
                engine.PrimaryRayStartX = CameraX;
                engine.PrimaryRayStartY = CameraY;
                engine.PrimaryRayStartZ = CameraZ;

                engine.DebugShowBranchPredictorHitRate = showBranchPrediction;
                engine.CommandBuffer = CommandBuffer;

#if USE_THREADING
                engine.PrimaryRayDirX = rayDirData[(clock * 3) + 0];
                engine.PrimaryRayDirY = rayDirData[(clock * 3) + 1];
                engine.PrimaryRayDirZ = rayDirData[(clock * 3) + 2];
#else
                engine.PrimaryRayDirX = rayDirX;
                engine.PrimaryRayDirY = rayDirY;
                engine.PrimaryRayDirZ = rayDirZ;
#endif

                FixedMaths.Normalise16Bit(ref engine.PrimaryRayDirX, ref engine.PrimaryRayDirY, ref engine.PrimaryRayDirZ);

                //Debug.WriteLine("Old ray dir " + FixedMaths.FixedToFloat(oldRayDirX).ToString("0.000") + ", " + FixedMaths.FixedToFloat(oldRayDirY).ToString("0.000") + ", " + FixedMaths.FixedToFloat(oldRayDirZ).ToString("0.000"));
                //Debug.WriteLine("New ray dir " + FixedMaths.FixedToFloat(engine.PrimaryRayDirX).ToString("0.000") + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayDirY).ToString("0.000") + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayDirZ).ToString("0.000"));

                engine.TraceDebug = (clock == debugClockIndex) ? traceDebug : null;

                engine.TraceDebug?.AppendLine("Ray start " + FixedMaths.FixedToFloat(engine.PrimaryRayStartX) + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayStartY) + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayStartZ));
                engine.TraceDebug?.AppendLine("Ray dir " + FixedMaths.FixedToFloat(engine.PrimaryRayDirX) + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayDirY) + ", " + FixedMaths.FixedToFloat(engine.PrimaryRayDirZ));

                engine.Run();

#if USE_THREADING
                destBuffer[x + (y * width)] = Color.FromArgb(engine.ResultR, engine.ResultG, engine.ResultB);
#else
                result.SetPixel(x, y, Color.FromArgb(engine.ResultR, engine.ResultG, engine.ResultB));
#endif

                if (DebugX >= 0)
                {
                    if ((x >= DebugX - 1) && (x <= DebugX + 1) && (y >= DebugY - 1) && (y <= DebugY + 1))
                    {
                        if ((x != DebugX) || (y != DebugY))
                        {
#if USE_THREADING
                            destBuffer[x + (y * width)] = Color.FromArgb(0, 0, 0);
#else
                            result.SetPixel(x, y, Color.FromArgb(0, 0, 0));
#endif
                        }
                    }
                }

#if USE_THREADING
                // Return ray engine to pool
                idleRayEngines.Push(engine);
                engine = null;
#else
                x++;

                if (x >= width)
                {
                    lineStartRayDirX += rayYStepX;
                    lineStartRayDirY += rayYStepY;
                    lineStartRayDirZ += rayYStepZ;
                    rayDirX = lineStartRayDirX;
                    rayDirY = lineStartRayDirY;
                    rayDirZ = lineStartRayDirZ;
                    x = 0;
                    y++;
                }
                else
                {
                    rayDirX += rayXStepX;
                    rayDirY += rayXStepY;
                    rayDirZ += rayXStepZ;
                }
#endif
            }
#if USE_THREADING
            );
#endif

#if USE_THREADING
            for (int writeY = 0; writeY < height; writeY++)
            {
                for (int writeX = 0; writeX < width; writeX++)
                {
                    result.SetPixel(writeX, writeY, destBuffer[writeX + (writeY * width)]);
                }
            }
#endif

            if (traceDebug != null)
            {
                pixelTraceBox.Text = traceDebug.ToString();
            }

            return result;
        }

        byte[] ConvertTo15BPP(Bitmap source)
        {
            byte[] outData = new byte[source.Width * source.Height * 2];

            int writeIndex = 0;
            for (int y = 0; y < source.Height; y++)
            {
                for (int x = 0; x < source.Width; x++)
                {
                    Color col = source.GetPixel(x, y);

                    UInt16 val = (UInt16)((col.R >> 3) | ((col.G >> 3) << 5) | ((col.B >> 3) << 10));

                    outData[writeIndex++] = (byte)((val >> 8) & 0xFF);
                    outData[writeIndex++] = (byte)(val & 0xFF);
                }
            }

            return outData;
        }

        void ConvertTo15BPP(Bitmap source, string outFile)
        {
            File.WriteAllBytes(outFile, ConvertTo15BPP(source));
        }

        void ConvertToSNESFormat(Bitmap source, string outFile, PaletteGenerator palette)
        {
            byte[] srcData = ConvertTo15BPP(source);

            int tilesX = source.Width / 8;
            int tilesY = source.Height / 8;

            byte[] outData = new byte[8 * 8 * tilesX * tilesY];
            byte[] srcPixelBuffer = new byte[8];
            byte[] destPixelBuffer = new byte[8];

            // We do this in a somewhat weird way because we're emulating what the FPGA does

            int readIndex = 0; // In 16 bit units
            int writeIndex = 0;

            int currentTileX = 0; // Which tile are we on in the current row?
            int y = 0; // Which Y are we on within the tile? (0-7)
            int rowStartTileIndex = 0; // Row index at the start of this row
            int currentTileIndex = rowStartTileIndex; // Current overall tile index

            for (int index = 0; index < (source.Width * source.Height); index += 8)
            {
                for (int x = 0; x < 8; x++)
                {
                    //Color actualCol = source.GetPixel(readIndex % source.Width, readIndex / source.Width);
                    UInt16 packedCol = (UInt16)((srcData[readIndex << 1] << 8) | srcData[(readIndex << 1) + 1]);
                    readIndex++;

                    if (palette != null)
                    {
                        // Convert to palette colour
                        srcPixelBuffer[x] = palette.MapColour(packedCol);
                    }
                    else
                    {
                        // Convert to RRRGGBBB
                        srcPixelBuffer[x] = (byte)((((int)(packedCol >> 2) & 7) << 5) | ((int)((packedCol >> 8) & 3) << 3) | ((int)((packedCol >> 12) & 7) << 0));
                    }
                }

                // Reformat into bitplanes

                destPixelBuffer[0] = (byte)((((srcPixelBuffer[0] >> 0) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 0) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 0) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 0) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 0) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 0) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 0) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 0) & 1) << 0));

                destPixelBuffer[1] = (byte)((((srcPixelBuffer[0] >> 1) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 1) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 1) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 1) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 1) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 1) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 1) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 1) & 1) << 0));

                destPixelBuffer[2] = (byte)((((srcPixelBuffer[0] >> 2) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 2) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 2) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 2) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 2) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 2) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 2) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 2) & 1) << 0));

                destPixelBuffer[3] = (byte)((((srcPixelBuffer[0] >> 3) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 3) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 3) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 3) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 3) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 3) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 3) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 3) & 1) << 0));

                destPixelBuffer[4] = (byte)((((srcPixelBuffer[0] >> 4) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 4) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 4) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 4) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 4) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 4) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 4) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 4) & 1) << 0));

                destPixelBuffer[5] = (byte)((((srcPixelBuffer[0] >> 5) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 5) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 5) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 5) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 5) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 5) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 5) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 5) & 1) << 0));

                destPixelBuffer[6] = (byte)((((srcPixelBuffer[0] >> 6) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 6) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 6) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 6) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 6) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 6) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 6) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 6) & 1) << 0));

                destPixelBuffer[7] = (byte)((((srcPixelBuffer[0] >> 7) & 1) << 7) |
                                               (((srcPixelBuffer[1] >> 7) & 1) << 6) |
                                               (((srcPixelBuffer[2] >> 7) & 1) << 5) |
                                               (((srcPixelBuffer[3] >> 7) & 1) << 4) |
                                               (((srcPixelBuffer[4] >> 7) & 1) << 3) |
                                               (((srcPixelBuffer[5] >> 7) & 1) << 2) |
                                               (((srcPixelBuffer[6] >> 7) & 1) << 1) |
                                               (((srcPixelBuffer[7] >> 7) & 1) << 0));

                // Write pixels out

                for (int x = 0; x < 8; x++)
                {
                    // For arbitrary-sized buffer, with C as the tile index

                    // X0 => Bit 0
                    // X1 => Bit 4
                    // X2 => Bit 5
                    // C0 => Bit 6
                    // C1 => Bit 7
                    // C2 => Bit 8
                    // C3 => Bit 9
                    // Y0 => Bit 1
                    // Y1 => Bit 2
                    // Y2 => Bit 3
                    // C4 => Bit 10
                    // C5 => Bit 11
                    // C6 => Bit 12
                    // C7 => Bit 13
                    // C8 => Bit 14
                    // C9 => Bit 15

                    // ...or:

                    // Bit 0 = X0
                    // Bit 1 = Y0
                    // Bit 2 = Y1
                    // Bit 3 = Y2
                    // Bit 4 = X1
                    // Bit 5 = X2
                    // Bit 6 = C0
                    // Bit 7 = C1
                    // Bit 8 = C2
                    // Bit 9 = C3
                    // Bit 10 = C4
                    // Bit 11 = C5
                    // Bit 12 = C6
                    // Bit 13 = C7
                    // Bit 14 = C8
                    // Bit 15 = C9

                    // We can get X from the bottom 3 bits of writeIndex

                    int swizzledWriteIndex = //(((currentTileIndex >> 9) & 1) << 15) | // <-- Not needed with only 500 tiles max
                                             (((currentTileIndex >> 8) & 1) << 14) | 
                                             (((currentTileIndex >> 7) & 1) << 13) |
                                             (((currentTileIndex >> 6) & 1) << 12) |
                                             (((currentTileIndex >> 5) & 1) << 11) |
                                             (((currentTileIndex >> 4) & 1) << 10) |
                                             (((currentTileIndex >> 3) & 1) << 9) |
                                             (((currentTileIndex >> 2) & 1) << 8) |
                                             (((currentTileIndex >> 1) & 1) << 7) |
                                             (((currentTileIndex >> 0) & 1) << 6) |
                                             (((writeIndex >> 2) & 1) << 5) |
                                             (((writeIndex >> 1) & 1) << 4) |
                                             (((y >> 2) & 1) << 3) |
                                             (((y >> 1) & 1) << 2) |
                                             (((y >> 0) & 1) << 1) |
                                             (((writeIndex >> 0) & 1) << 0);

                    outData[swizzledWriteIndex] = destPixelBuffer[x];
                    writeIndex++;
                }

                currentTileX++;
                currentTileIndex++;
                if (currentTileX == tilesX)
                {
                    // End of one line
                    currentTileX = 0;
                    if (y == 7)
                    {
                        // End of one complete row of tiles
                        y = 0;
                        rowStartTileIndex = currentTileIndex;
                    }
                    else
                    {
                        // Reset tile index for the next row
                        y++;
                    }
                    currentTileIndex = rowStartTileIndex;
                }
            }

            File.WriteAllBytes(outFile, outData);
        }

        public bool MoveForward = false;
        public bool MoveBackward = false;
        public bool MoveLeft = false;
        public bool MoveRight = false;
        public bool MoveUp = false;
        public bool MoveDown = false;
        public bool TurnLeft = false;
        public bool TurnRight = false;

        void SetKeyState(Keys key, bool down)
        {
            switch (key)
            {
                case Keys.W: MoveForward = down; break;
                case Keys.S: MoveBackward = down; break;
                case Keys.Q: TurnLeft = down; break;
                case Keys.E: TurnRight = down; break;
                case Keys.R: MoveUp = down; break;
                case Keys.F: MoveDown = down; break;
                case Keys.A: MoveLeft = down; break;
                case Keys.D: MoveRight = down; break;
                default: break;
            }
        }

        private void Form1_KeyDown(object sender, KeyEventArgs e)
        {
            SetKeyState(e.KeyCode, true);
        }

        private void Form1_KeyUp(object sender, KeyEventArgs e)
        {
            SetKeyState(e.KeyCode, false);
        }

        private void timer1_Tick(object sender, EventArgs e)
        {
            bool needRedraw = false;

            int forwardX, forwardY, forwardZ;

            forwardX = FixedMaths.FloatToFixed(0.0f);
            forwardY = FixedMaths.FloatToFixed(0.0f);
            forwardZ = FixedMaths.FloatToFixed(0.5f);

            RotateVector(ref forwardX, ref forwardY, ref forwardZ, CameraYaw);

            int rightX, rightY, rightZ;

            rightX = FixedMaths.FloatToFixed(0.5f);
            rightY = FixedMaths.FloatToFixed(0.0f);
            rightZ = FixedMaths.FloatToFixed(0.0f);

            RotateVector(ref rightX, ref rightY, ref rightZ, CameraYaw);

            if (MoveForward)
            {
                CameraX += forwardX;
                CameraY += forwardY;
                CameraZ += forwardZ;
                needRedraw = true;
            }
            if (MoveBackward)
            {
                CameraX -= forwardX;
                CameraY -= forwardY;
                CameraZ -= forwardZ;
                needRedraw = true;
            }
            if (MoveLeft)
            {
                CameraX -= rightX;
                CameraY -= rightY;
                CameraZ -= rightZ;
                needRedraw = true;
            }
            if (MoveRight)
            {
                CameraX += rightX;
                CameraY += rightY;
                CameraZ += rightZ;
                needRedraw = true;
            }
            if (MoveUp)
            {
                CameraY -= FixedMaths.FloatToFixed(0.5f);
                needRedraw = true;
            }
            if (MoveDown)
            {
                CameraY += FixedMaths.FloatToFixed(0.5f);
                needRedraw = true;
            }
            if (TurnLeft)
            {
                CameraYaw -= FixedMaths.FloatToFixed((15.0f / 180.0f) * 3.14f);
                needRedraw = true;
            }
            if (TurnRight)
            {
                CameraYaw += FixedMaths.FloatToFixed((15.0f / 180.0f) * 3.14f);
                needRedraw = true;
            }

            if (animateCheckBox.Checked)
            {
                needRedraw = true;
            }

            if (needRedraw)
            {
                RedrawImage();
            }
        }

        void RedrawImage()
        {
            Bitmap image = Trace();

            if (palettizedDisplayCheckbox.Checked)
            {
                Bitmap palImage = Palette.ConvertBitmap(image, ditherCheckbox.Checked);
                image.Dispose();
                image = palImage;
            }
            else if (rgb555DisplayCheckBox.Checked)
            {
                Bitmap palImage = PaletteGenerator.ConvertBitmapToRGB555(image, ditherCheckbox.Checked);
                image.Dispose();
                image = palImage;
            }

            pictureBox1.Image.Dispose();
            pictureBox1.Image = image;
        }

        private void pictureBox1_MouseClick(object sender, MouseEventArgs e)
        {
            if (pictureBox1.Image == null)
                return;

            float scale = Math.Min((float)pictureBox1.Width / (float)pictureBox1.Image.Width, (float)pictureBox1.Height / (float)pictureBox1.Image.Height);

            float actualImageWidth = pictureBox1.Image.Width * scale;
            float actualImageHeight = pictureBox1.Image.Height * scale;

            float imageOffsetX = (pictureBox1.Width - actualImageWidth) * 0.5f;
            float imageOffsetY = (pictureBox1.Height - actualImageHeight) * 0.5f;

            float x = (e.X - imageOffsetX) / scale;
            float y = (e.Y - imageOffsetY) / scale;

            DebugX = (int)x;
            DebugY = (int)y;
            RedrawImage();
        }

        void GeneratePalette()
        {
            bool dither = ditherCheckbox.Checked;

            Task.Run(() =>
            {
                PaletteGenerator palette = new PaletteGenerator();
                palette.AddFixedColour(0, Color.Black);
                palette.AddFixedColour(1, Color.White);

                int oldCamX = CameraX;
                int oldCamY = CameraY;
                int oldCamZ = CameraZ;
                int oldCamYaw = CameraYaw;

                for (float x = -10.0f; x <= 10.0f; x += 4.0f)
                {
                    for (float z = -10.0f; z <= 10.0f; z += 4.0f)
                    {
                        for (float yaw = 0.0f; yaw < 360.0f; yaw += 90.0f)
                        {
                            CameraX = FixedMaths.FloatToFixed(x);
                            CameraY = FixedMaths.FloatToFixed(0.0f);
                            CameraZ = FixedMaths.FloatToFixed(z);
                            CameraYaw = FixedMaths.FloatToFixed((yaw * (float)Math.PI) / 180.0f);

                            Bitmap image = Trace(noTrace: true);
                            palette.AddImage(image, dither);

                            Invoke((Action)(() => {
                                pictureBox1.Image?.Dispose();
                                pictureBox1.Image = image;
                            }));
                        }
                    }
                }

                palette.GeneratePalette();
                Palette = palette;

                CameraX = oldCamX;
                CameraY = oldCamY;
                CameraZ = oldCamZ;
                CameraYaw = oldCamYaw;

                Invoke((Action)(() =>
                {
                    pictureBox2.Image.Dispose();
                    pictureBox2.Image = Palette.GeneratePaletteBitmap();

                    RedrawImage();
                }));
            });
        }

        private void regeneratePaletteButton_Click(object sender, EventArgs e)
        {
            GeneratePalette();
        }

        private void palettizedDisplayCheckbox_CheckedChanged(object sender, EventArgs e)
        {
            RedrawImage();
        }

        private void rgb555DisplayCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            RedrawImage();
        }

        private void ditherCheckbox_CheckedChanged(object sender, EventArgs e)
        {
            RedrawImage();
        }

        private void showBranchPredictionHitRateCheckbox_CheckedChanged(object sender, EventArgs e)
        {
            RedrawImage();
        }

        private void Form1_Activated(object sender, EventArgs e)
        {
            CheckForSourceChanges();
        }

        private void timer2_Tick(object sender, EventArgs e)
        {
            CheckForSourceChanges();
        }

        void CheckForSourceChanges()
        {
            DateTime fileTime = File.GetLastWriteTimeUtc(SourceFilename);
            if (fileTime != LastSourceTimestamp)
            {
                RedrawImage();
            }
        }

        private void writeData_Click(object sender, EventArgs e)
        {
            BuildTables();

            Bitmap image = Trace();

            // Code to save a reference image (in full-colour and palletised form, as well as SNES-ready format)
            /*
            Bitmap palImage = Palette.ConvertBitmap(image, ditherCheckbox.Checked);

            image.Save(@"../../../SRT-SNES/Data/RefImage.png");
            palImage.Save(@"../../../SRT-SNES/Data/RefImage-8bpp.png");
            ConvertToSNESFormat(image, @"../../../SRT-SNES/Data/TestImage.bin", Palette);
            */

            // Save the real command buffer for the SNES to read
            SaveCommandBuffer(OriginalCommandBuffer, @"../../../SRT-SNES/Data/CommandBuffer.bin");

            // Save edit point information
            using (StreamWriter writer = new StreamWriter(@"../../../SRT-SNES/Data/CommandEditPoints.s"))
            {
                writer.WriteLine("; Auto-generated edit point information");

                if (EditPoints != null)
                {
                    for (int i = 0; i < EditPoints.Length; i++)
                    {
                        writer.WriteLine("COMMAND_EDIT_POINT_" + i + " = " + EditPoints[i]);
                    }
                }
            }

            // Create a blank command buffer to use as the FPGA default command RAM contents
            SaveCommandBuffer(CreateBlankCommandBuffer(), @"../../../SRT/CommandBuffer.bin");

            using (Bitmap b = (Bitmap)Bitmap.FromFile(@"../../../SRT-SNES/Data/Placeholder.png"))
            {
                ConvertToSNESFormat(b, @"../../../SRT-SNES/Data/Placeholder.bin", Palette);
            }

            using (Bitmap b = (Bitmap)Bitmap.FromFile(@"../../../SRT-SNES/Data/Placeholder2.png"))
            {
                ConvertToSNESFormat(b, @"../../../SRT-SNES/Data/Placeholder2.bin", Palette);
            }

            File.WriteAllBytes(@"../../../SRT-SNES/Data/MainPal.bin", Palette.GetSNESPaletteData());
            File.WriteAllBytes(@"../../../SRT-SNES/Data/PaletteMap.bin", Palette.GetPaletteMap());
        }

        private void animateCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            if (animateCheckBox.Checked)
            {
                StartAnimation();
            }

            CommandBuffer = null;
            RedrawImage();
        }

        private void visualiseCullingCheckBox_CheckedChanged(object sender, EventArgs e)
        {
            CommandBuffer = null;
            RedrawImage();
        }
    }
}

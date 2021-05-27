//#define USE_64BIT_MUL
// Disable maths exceptions because pipelined operation tends to push garbage in sometimes
#define NO_MATHS_EXCEPTIONS

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;
using System.IO;
using System.Diagnostics;
using System.Threading;

namespace SRTTestbed
{
    static class FixedMaths
    {
        public const int FixedShift = 14;
        public const float FixedScale = 1 << FixedShift;

        // Convert a regular fixed-point value to one with the specified number of fractional bits
        public static UInt32 ConvertTo(int src, int numIntegerBits, int numFractionalBits)
        {
            int totalBits = numIntegerBits + numFractionalBits;
            UInt32 val = unchecked((UInt32)(src >> (FixedShift - numFractionalBits)));
            UInt32 mask = (UInt32)((1UL << totalBits) - 1);

            // All bits outside the mask should be sign-extension
            if ((val & (mask ^ 0xFFFFFFFF)) != ((((val >> (totalBits - 1)) & 1) != 0) ? (mask ^ 0xFFFFFFFF) : 0x0))
            {
                throw new OverflowException();
            }
            return val & mask;
        }

        // Convert a fixed-point number with a (assumed to be smaller than FixedShift) number of fraction bits into a regular one
        public static int ConvertFrom(UInt32 src, int numIntegerBits, int numFractionalBits)
        {
            int totalBits = numIntegerBits + numFractionalBits;
            UInt32 mask = (UInt32)((1UL << (numIntegerBits + numFractionalBits)) - 1);

            // Sanity check
            if ((src & (mask ^ 0xFFFFFFFF)) != 0)
            {
                throw new Exception("Source value contains out-of-range bits");
            }

            UInt32 val = src << (FixedShift - numFractionalBits);

            if (((src >> (totalBits - 1)) & 1) != 0)
            {
                // Sign-extend
                UInt32 usedOutputBits = (UInt32)((1UL << (numIntegerBits + FixedShift)) - 1);
                val = val | (usedOutputBits ^ 0xFFFFFFFF);
            }

            return unchecked((int)val);
        }

        public static int ConvertFrom8Dot7(UInt32 src)
        {
            return ConvertFrom(src, 8, 7);
        }

        public static int ConvertFrom4Dot7(UInt16 src)
        {
            return ConvertFrom(src, 4, 7);
        }

        public static Int16 ConvertFrom2Dot10(UInt16 src)
        {
            return (Int16)ConvertFrom(src, 2, 10);
        }

        public static int ConvertFrom8Dot12(UInt32 src)
        {
            return ConvertFrom(src, 8, 12);
        }

        public static int ConvertFrom8Dot1(UInt16 src)
        {
            return ConvertFrom(src, 8, 1);
        }

        public static UInt32 ConvertTo8Dot7(int src)
        {
            return ConvertTo(src, 8, 7);
        }

        public static UInt16 ConvertTo4Dot7(int src)
        {
            return unchecked((UInt16)ConvertTo(src, 4, 7));
        }

        public static UInt16 ConvertTo2Dot10(int src)
        {
            return unchecked((UInt16)ConvertTo(src, 2, 10));
        }

        public static UInt32 ConvertTo8Dot12(int src)
        {
            return ConvertTo(src, 8, 12);
        }

        public static UInt16 ConvertTo8Dot1(int src)
        {
            return unchecked((UInt16)ConvertTo(src, 8, 1));
        }

        public static void Normalise(ref float x, ref float y, ref float z)
        {
            float len = (x * x) + (y * y) + (z * z);

            if (len > 0.0001f)
            {
                len = (float)Math.Sqrt(len);
                x /= len;
                y /= len;
                z /= len;
            }
        }

        public static void Normalise(ref int x, ref int y, ref int z)
        {
            int lenSq = FixedMul(x, x) + FixedMul(y, y) + FixedMul(z, z);

            if (lenSq > 0)
            {
                int rcpLen = FixedRcpSqrt(lenSq);

                x = FixedMul(x, rcpLen);
                y = FixedMul(y, rcpLen);
                z = FixedMul(z, rcpLen);
            }
        }

        // A version of Normalise() that only works if the input values fit in 16 bits (i.e. <2-ish)
        public static void Normalise16Bit(ref Int16 x, ref Int16 y, ref Int16 z)
        {
            Int16 lenSq = (Int16)((Int16)FixedMul16x16(x, x) + (Int16)FixedMul16x16(y, y) + (Int16)FixedMul16x16(z, z));

            if (lenSq > 0)
            {
                Int16 rcpLen = (Int16)FixedRcpSqrt(lenSq);

                x = (Int16)FixedMul16x16(x, rcpLen);
                y = (Int16)FixedMul16x16(y, rcpLen);
                z = (Int16)FixedMul16x16(z, rcpLen);
            }
        }

        public static int FloatToFixed(float val)
        {
            return (int)(val * FixedScale);
        }

        public static float FixedToFloat(int val)
        {
            return (float)val / FixedScale;
        }

        public static Int64 TruncateTo40Bit(Int64 val)
        {
            if (val >= 0)
                return val & 0x7FFFFFFFFF;
            else
                return -((-val) & 0x7FFFFFFFFF);
        }

        public static Int64 TruncateTo48Bit(Int64 val)
        {
            if (val >= 0)
                return val & 0x7FFFFFFFFFF;
            else
                return -((-val) & 0x7FFFFFFFFFF);
        }

        public static int FixedMul48(int x, int y)
        {
#if USE_64BIT_MUL
            return (int)(((Int64)x * (Int64)y) >> FixedShift);
#else
            // Simulate 48-bit maths
            return (int)(TruncateTo48Bit((Int64)x * (Int64)y) >> FixedShift);

            // 32-bit maths (buggy)
            //return ((x >> 3) * (y >> 3)) >> (FixedShift - 6);
#endif
        }

        public static int FixedMul(int x, int y)
        {
#if USE_64BIT_MUL
            return (int)(((Int64)x * (Int64)y) >> FixedShift);
#else
            // Simulate 40-bit maths
            return (int)(TruncateTo40Bit((Int64)x * (Int64)y) >> FixedShift);

            // 32-bit maths (buggy)
            //return ((x >> 3) * (y >> 3)) >> (FixedShift - 6);
#endif
        }

        // Fixed-point multiply where both values are known to fit into 16 bits
        // (i.e. values <=2 or thereabouts, such as normalised vectors)
        public static int FixedMul16x16(int x, int y)
        {
            if ((Math.Abs(x) > 0x7FFF) || (Math.Abs(y) > 0x7FFF))
            {
#if NO_MATHS_EXCEPTIONS
                return 0;
#else
                throw new OverflowException();
#endif
            }

            return ((int)x * (int)y) >> FixedShift;
        }

        public static int FixedDiv(int x, int y)
        {
            return (x << FixedShift) / y;
        }

        public static int FixedSqrtReal(int val)
        {
            return (int)(Math.Sqrt((float)val / FixedScale) * FixedScale);
        }

        public static int FixedRcp(int val)
        {
            if (val == 0)
                return 0x7FFFFFFF;

            if (val > 0)
            {
                int rcpSqrt = FixedRcpSqrt(val);
                return FixedMul(rcpSqrt, rcpSqrt);
            }
            else
            {
                int rcpSqrt = FixedRcpSqrt(-val);
                return -FixedMul(rcpSqrt, rcpSqrt);
            }
        }

        public static int FixedRcpReal(int val)
        {
            return (int)((1.0f / ((float)val / FixedScale)) * FixedScale);
        }

        // Table of initial 1/sqrt(x) guesses for values of x with <n> leading zeros
        public static int[] SqrtTable = new int[31];

        public static void BuildSqrtTable()
        {
            for (int i = 0; i < 31; i++)
            {
                int val = (1 << i);
                if (i > 0)
                {
                    val |= (1 << (i - 1)); // Take the half-way point
                }
                float actualVal = FixedToFloat(val);
                SqrtTable[30 - i] = FloatToFixed(1.0f / (float)Math.Sqrt(actualVal));
                Debug.WriteLine("Table[" + (30 - i) + "] actualVal = 0x" + val.ToString("x8") + ", val = " + actualVal + " Sqrt = " + Math.Sqrt(actualVal));
            }
        }

        public static int GetSqrtTableEntry(int val)
        {
            for (int i = 0; i < 31; i++)
            {
                if (((val >> (30 - i)) & 1) == 1) return SqrtTable[i];
            }

            throw new NotImplementedException();
        }
      
        public static int FixedSqrt(int val)
        {
            if (val <= 0)
            {
#if NO_MATHS_EXCEPTIONS
                return 0;
#else
                throw new Exception("Attempting square root of negative number");
#endif
            }

#if false
            // Float version
            float initialVal = FixedToFloat(val);
            float outVal = FixedToFloat(GetSqrtTableEntry(val)); // Initial guess from table

            //Debug.WriteLine("FixedSqrt(" + initialVal + ")");
            //Debug.WriteLine("OutVal = " + outVal);

            for (int i = 0; i < 2; i++)
            {
                // Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))
                float factor = 1.5f - (0.5f * initialVal * outVal * outVal);
                outVal *=  factor;
                //Debug.WriteLine("Factor = " + factor + " OutVal = " + outVal);
            }

            outVal *= initialVal; // Convert 1/sqrt(val) into sqrt(val)

            //Debug.WriteLine("Result = " + outVal);

            return FloatToFixed(outVal);
#else
            // Fixed-point version
            int initialVal = val;
            int halfInitialVal = val >> 1;
            int outVal = GetSqrtTableEntry(val); // Initial guess from table
            int onePointFive = FloatToFixed(1.5f);

            //Debug.WriteLine("FixedSqrt(" + initialVal + ")");
            //Debug.WriteLine("OutVal = " + outVal);

            for (int i = 0; i < 2; i++)
            {
                // Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))
                int factor = onePointFive - FixedMul(halfInitialVal, FixedMul(outVal, outVal));
                outVal = FixedMul(outVal, factor);
                //Debug.WriteLine("Factor = " + factor + " OutVal = " + outVal);
            }

            outVal = FixedMul(outVal, initialVal); // Convert 1/sqrt(val) into sqrt(val)

            //Debug.WriteLine("Result = " + outVal);

            return outVal;
#endif
        }

        public static int FixedRcpSqrt(int val)
        {
            if (val <= 0)
            {
#if NO_MATHS_EXCEPTIONS
                return 0;
#else
                throw new Exception("Attempting square root of negative number");
#endif
            }

            int initialVal = val;
            int halfInitialVal = val >> 1;
            int outVal = GetSqrtTableEntry(val); // Initial guess from table
            int onePointFive = FloatToFixed(1.5f);

            for (int i = 0; i < 2; i++)
            {
                // Newton's method - x(n+1) =(x(n) * (1.5 - (val * 0.5f * x(n)^2))
                int factor = onePointFive - FixedMul(halfInitialVal, FixedMul(outVal, outVal));
                outVal = FixedMul(outVal, factor);
            }

            return outVal;
        }

        public static int FixedRcpSqrtReal(int val)
        {
            return (int)((1.0f / Math.Sqrt((float)val / FixedScale)) * FixedScale);
        }

        // Table of sin(x) values, where X is 0-255
        public static Int16[] SinTable = new Int16[256];

        public static void BuildSinTable()
        {
            for (int i = 0; i < 256; i++)
            {
                float angle = (float)(((float)i / 256) * Math.PI * 2.0f);
                float sin = (float)Math.Sin(angle);

                int fixedVal = FloatToFixed(sin);

                // We expect all the values to fit into 16 bits
                if (((fixedVal & 0xFFFF0000) != 0) && ((fixedVal & 0xFFFF8000) != 0xFFFF8000)) // 0xFFFF8000 to allow sign extensions
                    throw new Exception("Sin value overflow");

                SinTable[i] = (Int16)FloatToFixed(sin);
            }
        }
    }
}

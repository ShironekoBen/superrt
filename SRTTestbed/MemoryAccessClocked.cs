using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    // This emulates memory access latency (2 cycle latency, 1 cycle throughput)
    class MemoryAccessClocked<MemType>
    {
        public MemType[] inMemoryBuffer;
        public int inAddress;
        public MemType outData;
        public int outDataAddressForDebugging;

        public MemoryAccessClocked<MemType> Tick()
        {
            MemoryAccessClocked<MemType> destData = (MemoryAccessClocked<MemType>)this.MemberwiseClone();

            Cycle1(destData);
            Cycle2(destData);

            return destData;
        }

        void Cycle1(MemoryAccessClocked<MemType> destData)
        {
            destData.c2_address = inAddress;
        }

        int c2_address;

        void Cycle2(MemoryAccessClocked<MemType> destData)
        {
            destData.outDataAddressForDebugging = c2_address;

            if ((inMemoryBuffer != null) && (c2_address < inMemoryBuffer.Length))
            {
                destData.outData = inMemoryBuffer[c2_address];
            }
            else
            {
                destData.outData = default(MemType);
            }
        }
    }
}

using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

namespace SRTTestbed
{
    class PipelineTracer
    {
        const int MaxCycles = 20;

        List<StringBuilder> TraceData = new List<StringBuilder>();

        public void AppendLine(int cycle, string message)
        {
            while (TraceData.Count <= cycle)
            {
                TraceData.Add(new StringBuilder());
            }

            TraceData[cycle].AppendLine(message);
        }

        public string Emit(int cycle)
        {
            string result = null;

            if (TraceData.Count > cycle)
            {
                result = TraceData[cycle].ToString();
                TraceData[cycle].Clear();
            }

            return result;
        }

        public void Update()
        {
            TraceData.Insert(0, new StringBuilder());

            while (TraceData.Count > MaxCycles)
            {
                TraceData.RemoveAt(TraceData.Count - 1);
            }
        }
    }
}

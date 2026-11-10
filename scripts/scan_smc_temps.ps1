$ErrorActionPreference = "Stop"

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Runtime.InteropServices;

public static class SmcTempScan {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
    [DllImport("kernel32.dll")]
    public static extern bool DeviceIoControl(IntPtr h, uint c, byte[] i, uint isz, byte[] o, uint osz, out uint r, IntPtr ov);
    [DllImport("kernel32.dll")]
    public static extern bool CloseHandle(IntPtr h);

    public static string Scan() {
        IntPtr h = CreateFileW("\\\\.\\APPLESMC", 0xC0000000, 3, IntPtr.Zero, 3, 0, IntPtr.Zero);
        if (h == (IntPtr)(-1)) return "OPEN_ERROR " + Marshal.GetLastWin32Error();
        try {
            byte[] key = new byte[] { (byte)'#', (byte)'K', (byte)'E', (byte)'Y' };
            byte[] info = new byte[8];
            uint ret;
            if (!DeviceIoControl(h, 0x0022000C, key, 4, info, 6, out ret, IntPtr.Zero)) return "KEYINFO_ERROR";
            int size = info[0];
            byte[] readIn = new byte[5];
            Array.Copy(key, readIn, 4);
            readIn[4] = (byte)size;
            byte[] readOut = new byte[32];
            if (!DeviceIoControl(h, 0x00220000, readIn, 5, readOut, 32, out ret, IntPtr.Zero)) return "READ_ERROR";
            uint count = (uint)((readOut[0] << 24) | (readOut[1] << 16) | (readOut[2] << 8) | readOut[3]);

            StringBuilder sb = new StringBuilder();
            sb.AppendLine("key\ttype\tsize\tvalue\tplausible\thex");
            for (uint i = 0; i < count; i++) {
                byte[] idx = BitConverter.GetBytes(i);
                byte[] kout = new byte[4];
                if (!DeviceIoControl(h, 0x00220008, idx, 4, kout, 4, out ret, IntPtr.Zero)) continue;
                string k = Encoding.ASCII.GetString(kout);
                if (k.Length != 4 || k[0] != 'T') continue;

                byte[] kinfo = new byte[8];
                if (!DeviceIoControl(h, 0x0022000C, kout, 4, kinfo, 6, out ret, IntPtr.Zero)) continue;
                int ksize = kinfo[0];
                string type = "";
                for (int j = 1; j < 5; j++) {
                    char c = (char)kinfo[j];
                    type += (c >= 32 && c < 127) ? c : '.';
                }

                byte[] rin = new byte[5];
                Array.Copy(kout, rin, 4);
                rin[4] = (byte)ksize;
                byte[] rout = new byte[32];
                if (!DeviceIoControl(h, 0x00220000, rin, 5, rout, 32, out ret, IntPtr.Zero)) continue;

                double val = double.NaN;
                if (type == "sp78" && ret >= 2) val = (double)(short)((rout[0] << 8) | rout[1]) / 256.0;
                else if (type == "sp87" && ret >= 2) val = (double)(short)((rout[0] << 8) | rout[1]) / 128.0;
                else if (type == "fpe2" && ret >= 2) val = (double)((rout[0] << 8) | rout[1]) / 4.0;
                else if (type == "flt " && ret >= 4) val = BitConverter.ToSingle(new byte[] { rout[3], rout[2], rout[1], rout[0] }, 0);
                else if (type == "ui16" && ret >= 2) val = (double)((rout[0] << 8) | rout[1]);
                else if (type == "ui8 " && ret >= 1) val = rout[0];

                bool plausible = !double.IsNaN(val) && val >= 0.0 && val <= 110.0;
                string hex = BitConverter.ToString(rout, 0, (int)Math.Min(ret, 8));
                sb.AppendLine(k + "\t" + type + "\t" + ksize + "\t" + (double.IsNaN(val) ? "-" : val.ToString("F2")) + "\t" + (plausible ? "yes" : "no") + "\t" + hex);
            }
            return sb.ToString();
        } finally {
            CloseHandle(h);
        }
    }
}
'@

$out = [SmcTempScan]::Scan()
$dest = Join-Path $env:APPDATA "MacndowsFan\sensor_scan.txt"
[IO.File]::WriteAllText($dest, $out, (New-Object Text.UTF8Encoding($false)))
$out

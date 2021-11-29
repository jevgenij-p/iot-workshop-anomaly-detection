using System;
using System.Security.Cryptography;
using System.Text;

namespace telemetry
{
    public class Parameters
    {
        public string DeviceId { get; set; } = Environment.GetEnvironmentVariable("DPS_DEVICE_ID");
        public string DpsEndpoint { get; set; } = Environment.GetEnvironmentVariable("DPS_ENDPOINT");
        public string DpsIdScope { get; set; } = Environment.GetEnvironmentVariable("DPS_ID_SCOPE");
        public string DpsPrimaryKey { get; set; } = Environment.GetEnvironmentVariable("DPS_PRIMARY_KEY");
        public string DeviceSymmetricKey { get; set; }

        public void GenerateDeviceKey()
        {
            byte[] key = Convert.FromBase64String(this.DpsPrimaryKey);
            using (var hmac = new HMACSHA256(key))
            {
                var ascii = new ASCIIEncoding();
                byte[] bytes = ascii.GetBytes(this.DeviceId);
                byte[] signature = hmac.ComputeHash(bytes);
                this.DpsPrimaryKey = Convert.ToBase64String(signature);
            }
        }
    }
}
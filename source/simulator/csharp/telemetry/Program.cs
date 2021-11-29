using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Azure.Devices.Provisioning.Client;
using Microsoft.Azure.Devices.Provisioning.Client.Transport;
using Microsoft.Azure.Devices.Shared;

// https://github.com/Azure-Samples/azure-iot-samples-csharp/blob/main/iot-hub/Samples/device/PnpDeviceSamples/Thermostat/Program.cs

namespace telemetry
{
    class Program
    {
        static void Main(string[] args)
        {
            var parameters = new Parameters();
            parameters.GenerateDeviceKey();

            Console.WriteLine("IoT Device Simulator");
            Console.WriteLine("Press Control+C to quit");
        }

        private static async Task<DeviceRegistrationResult> ProvisionDeviceAsync(Parameters parameters, CancellationToken cancellationToken)
        {
            SecurityProvider symmetricKeyProvider = new SecurityProviderSymmetricKey(parameters.DeviceId, parameters.DeviceSymmetricKey, null);
            ProvisioningTransportHandler mqttTransportHandler = new ProvisioningTransportHandlerMqtt();
            ProvisioningDeviceClient pdc = ProvisioningDeviceClient.Create(parameters.DpsEndpoint, parameters.DpsIdScope,
                symmetricKeyProvider, mqttTransportHandler);

            return await pdc.RegisterAsync(cancellationToken);
        }
    }
}

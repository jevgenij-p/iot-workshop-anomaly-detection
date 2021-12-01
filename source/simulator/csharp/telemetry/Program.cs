using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Azure.Devices.Client;
using Microsoft.Azure.Devices.Provisioning.Client;
using Microsoft.Azure.Devices.Provisioning.Client.Transport;
using Microsoft.Azure.Devices.Shared;

namespace telemetry
{
    class Program
    {
        public static async Task Main(string[] args)
        {
            Console.WriteLine("IoT Device Simulator");
            Console.WriteLine("Press Control+C to quit\n");

            var parameters = new Parameters();
            parameters.GenerateDeviceKey();

            var runningTime = Timeout.InfiniteTimeSpan;
            using var cts = new CancellationTokenSource(runningTime);
            Console.CancelKeyPress += (sender, eventArgs) =>
            {
                eventArgs.Cancel = true;
                cts.Cancel();
                Console.WriteLine("\nQuitting...");
            };

            using DeviceClient deviceClient = await SetupDeviceClientAsync(parameters, cts.Token);

            Console.WriteLine("\nPress the following key and <Enter>:");
            Console.WriteLine("   +  to increase temperature");
            Console.WriteLine("   -  to decrease temperature");
            Console.WriteLine("\nSending telemetry...");

            var simulator = new Simulator(deviceClient);
            await simulator.RunAsync(cts.Token);
            await deviceClient.CloseAsync();
        }

        private static async Task<DeviceClient> SetupDeviceClientAsync(Parameters parameters, CancellationToken cancellationToken)
        {
            DeviceRegistrationResult dpsRegistrationResult = await ProvisionDeviceAsync(parameters, cancellationToken);
            if (dpsRegistrationResult.Status == ProvisioningRegistrationStatusType.Assigned)
            {
                Console.WriteLine("IoT Device was assigned");
                Console.WriteLine($"Assigned Hub: {dpsRegistrationResult.AssignedHub}");
                Console.WriteLine($"Device id: {dpsRegistrationResult.DeviceId}");
            }
            else
            {
                Console.WriteLine($"Could not provision device. Provisioning status: {dpsRegistrationResult.Status}");
                Environment.Exit(0);
            }

            var authMethod = new DeviceAuthenticationWithRegistrySymmetricKey(dpsRegistrationResult.DeviceId, parameters.DeviceSymmetricKey);
            DeviceClient deviceClient = InitializeDeviceClient(dpsRegistrationResult.AssignedHub, authMethod);

            return deviceClient;
        }

        private static async Task<DeviceRegistrationResult> ProvisionDeviceAsync(Parameters parameters, CancellationToken cancellationToken)
        {
            SecurityProvider symmetricKeyProvider = new SecurityProviderSymmetricKey(parameters.DeviceId, parameters.DeviceSymmetricKey, null);
            ProvisioningTransportHandler mqttTransportHandler = new ProvisioningTransportHandlerMqtt();
            ProvisioningDeviceClient pdc = ProvisioningDeviceClient.Create(parameters.DpsEndpoint, parameters.DpsIdScope,
                symmetricKeyProvider, mqttTransportHandler);

            return await pdc.RegisterAsync(cancellationToken);
        }

        private static DeviceClient InitializeDeviceClient(string hostname, IAuthenticationMethod authenticationMethod)
        {
            DeviceClient deviceClient = DeviceClient.Create(hostname, authenticationMethod, TransportType.Mqtt, null);
            deviceClient.SetConnectionStatusChangesHandler((status, reason) =>
            {
                Console.WriteLine($"Connection status change registered - status={status}, reason={reason}.");
                if (status == ConnectionStatus.Disabled)
                {
                    Environment.Exit(0);
                }
            });

            return deviceClient;
        }
    }
}

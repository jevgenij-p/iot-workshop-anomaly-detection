using System;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Azure.Devices.Client;

namespace telemetry
{
    public class Simulator
    {
        private const double BASE_TEMPERATURE = 20.0;
        private const double BASE_HUMIDITY = 60.0;
        private const double TEMPERATURE_INCREMENT = 2.0;
        private const int DELAY = 2;

        private readonly DeviceClient deviceClient;
        private readonly Random random = new Random();
        private double base_temperature = BASE_TEMPERATURE;
        private double base_humidity = BASE_HUMIDITY;

        public Simulator(DeviceClient deviceClient)
        {
            this.deviceClient = deviceClient ?? throw new ArgumentNullException($"{nameof(deviceClient)} cannot be null.");
        }

        public async Task RunAsync(CancellationToken cancellationToken)
        {
            while (!cancellationToken.IsCancellationRequested)
            {
                await SendMessageAsync();
                await Task.Delay(DELAY * 1000);
                ReadKeypress();
            }
        }

        private async Task SendMessageAsync()
        {
            string telemetryPayload = GetTelemetryPayload();
            using var message = new Message(Encoding.UTF8.GetBytes(telemetryPayload))
            {
                ContentEncoding = "utf-8",
                ContentType = "application/json",
            };

            await deviceClient.SendEventAsync(message);
        }

        private string GetTelemetryPayload()
        {
            double temperature_noise = random.NextDouble() * 2 - 1;
            double temperature = Math.Round(base_temperature + temperature_noise, 2);

            double humidity_noise = random.NextDouble() * 3 - 1;
            double humidity = Math.Round(base_humidity + humidity_noise, 2);

            string telemetryPayload = $"{{ \"temperature\": {temperature}, \"humidity\": {humidity} }}";
            Console.WriteLine($"Message: temperature: {temperature}  humidity: {humidity}");

            return telemetryPayload;
        }

        public void ReadKeypress()
        {
            Task.Run(async () =>
            {
                while (true)
                {
                    var text = await Console.In.ReadLineAsync();
                    text = text.ToLower();
                    if (text == "+")
                    {
                        base_temperature += TEMPERATURE_INCREMENT;
                        Console.WriteLine("Temperature increased");
                    }
                    if (text == "-")
                    {
                        base_temperature -= TEMPERATURE_INCREMENT;
                        Console.WriteLine("Temperature decreased");
                    }
                }
            });
        }
    }
}
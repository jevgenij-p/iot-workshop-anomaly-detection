using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Mail;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.EventHubs;
using Microsoft.Azure.WebJobs;
using Microsoft.Extensions.Logging;

namespace IoTLab.Workshop
{
    public static class SendEmailOnEventTrigger
    {
        [FunctionName("SendEmailOnEventTrigger")]
        public static async Task Run([EventHubTrigger("eventhub2", Connection = "EVENTHUB_Connection")] EventData[] events, ILogger log)
        {
            var exceptions = new List<Exception>();

            foreach (EventData eventData in events)
            {
                try
                {
                    string messageBody = Encoding.UTF8.GetString(eventData.Body.Array, eventData.Body.Offset, eventData.Body.Count);
                    await SendEmail(messageBody);

                    log.LogInformation($"C# Event Hub trigger function processed a message: {messageBody}");
                    await Task.Yield();
                }
                catch (Exception e)
                {
                    log.LogError($"Error occured during message sending: {e.Message}");
                    exceptions.Add(e);
                }
            }

            // Once processing of the batch is complete, if any messages in the batch failed processing throw an exception so that there is a record of the failure.

            if (exceptions.Count > 1)
                throw new AggregateException(exceptions);

            if (exceptions.Count == 1)
                throw exceptions.Single();
        }

        private static async Task SendEmail(string message)
        {
            string username = GetEnvironmentVariable("EMAIL_USER_NAME");
            string password = GetEnvironmentVariable("EMAIL_PASSWORD");
            var msg = new MailMessage();
            msg.To.Add(new MailAddress(username));
            msg.From = new MailAddress(username);
            msg.Subject = "Temperature anomaly detected";
            msg.Body = message;
            msg.IsBodyHtml = true;

            using (var client = new SmtpClient())
            {
                client.UseDefaultCredentials = false;
                client.Credentials = new System.Net.NetworkCredential(username, password);
                client.Port = 587;
                client.Host = "smtp.gmail.com";
                client.DeliveryMethod = SmtpDeliveryMethod.Network;
                client.EnableSsl = true;
                await client.SendMailAsync(msg);
            }
        }

        private static string GetEnvironmentVariable(string name)
        {
            return System.Environment.GetEnvironmentVariable(name, EnvironmentVariableTarget.Process);
        }
    }
}

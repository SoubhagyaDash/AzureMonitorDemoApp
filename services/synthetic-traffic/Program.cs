using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using System;
using System.Net.Http;
using System.Threading.Tasks;

namespace SyntheticTraffic
{
    class Program
    {
        static async Task Main(string[] args)
        {
            Console.WriteLine("=== OpenTelemetry Demo - Synthetic Traffic Generator ===");
            Console.WriteLine("Starting always-on traffic generation...");

            var host = CreateHostBuilder(args).Build();
            
            try
            {
                await host.RunAsync();
            }
            catch (Exception ex)
            {
                Console.WriteLine($"Application terminated unexpectedly: {ex.Message}");
                Environment.Exit(1);
            }
        }

        static IHostBuilder CreateHostBuilder(string[] args) =>
            Host.CreateDefaultBuilder(args)
                .ConfigureAppConfiguration((hostingContext, config) =>
                {
                    config.AddJsonFile("appsettings.json", optional: false, reloadOnChange: true);
                    config.AddJsonFile($"appsettings.{hostingContext.HostingEnvironment.EnvironmentName}.json", 
                        optional: true, reloadOnChange: true);
                    config.AddEnvironmentVariables();
                    config.AddCommandLine(args);
                })
                .ConfigureServices((hostContext, services) =>
                {
                    // Configure HttpClient with timeouts and retry policies
                    services.AddHttpClient<TrafficGenerator>(client =>
                    {
                        client.Timeout = TimeSpan.FromSeconds(30);
                        client.DefaultRequestHeaders.Add("User-Agent", "SyntheticTraffic/1.0");
                        client.DefaultRequestHeaders.Add("X-Traffic-Source", "Synthetic");
                    });

                    // Add the traffic generator as a hosted service
                    services.AddHostedService<TrafficGenerator>();

                    // Add configuration
                    services.AddSingleton<IConfiguration>(hostContext.Configuration);
                })
                .ConfigureLogging((hostingContext, logging) =>
                {
                    logging.ClearProviders();
                    logging.AddConsole();
                    logging.AddDebug();
                    
                    // Set log levels based on environment
                    if (hostingContext.HostingEnvironment.IsDevelopment())
                    {
                        logging.SetMinimumLevel(LogLevel.Debug);
                    }
                    else
                    {
                        logging.SetMinimumLevel(LogLevel.Information);
                    }
                });
    }
}
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;

var host = new HostBuilder()
    .ConfigureFunctionsWorkerDefaults()
    .ConfigureAppConfiguration((context, config) =>
    {
        config.AddJsonFile("local.settings.json", optional: true, reloadOnChange: true);
        config.AddEnvironmentVariables();
    })
    .ConfigureServices((context, services) =>
    {
        services.AddApplicationInsightsTelemetryWorkerService();
        services.ConfigureFunctionsApplicationInsights();
        
        // Add HttpClient for making requests to the API Gateway
        services.AddHttpClient<SyntheticTraffic.Function.TrafficGeneratorFunction>(client =>
        {
            client.Timeout = TimeSpan.FromSeconds(30);
            client.DefaultRequestHeaders.Add("User-Agent", "SyntheticTraffic-Function/1.0");
            client.DefaultRequestHeaders.Add("X-Traffic-Source", "Azure-Function");
        });

        // Add configuration
        services.AddSingleton<IConfiguration>(context.Configuration);
    })
    .ConfigureLogging((context, logging) =>
    {
        // Application Insights will capture all logs automatically in Azure
        logging.SetMinimumLevel(LogLevel.Information);
        
        // For local development
        if (context.HostingEnvironment.IsDevelopment())
        {
            logging.AddConsole();
            logging.SetMinimumLevel(LogLevel.Debug);
        }
    })
    .Build();

host.Run();
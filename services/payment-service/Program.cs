using Microsoft.EntityFrameworkCore;
using PaymentService.Data;
using PaymentService.Services;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;
using OpenTelemetry.Exporter;

var builder = WebApplication.CreateBuilder(args);

// OpenTelemetry Configuration
var serviceName = "payment-service";
var serviceVersion = "1.0.0";
var applicationId = Environment.GetEnvironmentVariable("APPLICATION_INSIGHTS_APPLICATION_ID") ?? "unknown";

// Read OTLP endpoints from environment (injected by Azure Monitor)
var otlpTracesEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_TRACES_ENDPOINT");
var otlpMetricsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_METRICS_ENDPOINT");
var otlpLogsEndpoint = Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_LOGS_ENDPOINT");

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment"] = builder.Environment.EnvironmentName,
            ["deployment.platform"] = "kubernetes",
            ["deployment.cloud"] = "azure",
            ["microsoft.applicationId"] = applicationId
        }))
    .WithTracing(tracing =>
    {
        tracing
            .AddAspNetCoreInstrumentation(options =>
            {
                options.RecordException = true;
                options.EnrichWithHttpRequest = (activity, httpRequest) =>
                {
                    activity.SetTag("http.request.body_size", httpRequest.ContentLength);
                };
                options.EnrichWithHttpResponse = (activity, httpResponse) =>
                {
                    activity.SetTag("http.response.status_code", httpResponse.StatusCode);
                };
            })
            .AddHttpClientInstrumentation(options =>
            {
                options.RecordException = true;
                options.EnrichWithHttpRequestMessage = (activity, httpRequest) =>
                {
                    activity.SetTag("http.request.method", httpRequest.Method.Method);
                };
            })
            .AddEntityFrameworkCoreInstrumentation(options =>
            {
                options.SetDbStatementForText = true;
                options.EnrichWithIDbCommand = (activity, command) =>
                {
                    activity.SetTag("db.command_text", command.CommandText);
                };
            })
            .AddSource(serviceName)
            .AddSource("Azure.Messaging.EventHubs.*");

        // Use OTLP exporter if traces endpoint is configured
        if (!string.IsNullOrEmpty(otlpTracesEndpoint))
        {
            tracing.AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(otlpTracesEndpoint);
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
            });
        }
    })
    .WithMetrics(metrics =>
    {
        metrics
            .AddAspNetCoreInstrumentation()
            .AddHttpClientInstrumentation()
            .AddMeter(serviceName);

        // Use OTLP exporter if metrics endpoint is configured
        if (!string.IsNullOrEmpty(otlpMetricsEndpoint))
        {
            metrics.AddOtlpExporter(options =>
            {
                options.Endpoint = new Uri(otlpMetricsEndpoint);
                options.Protocol = OtlpExportProtocol.HttpProtobuf;
            });
        }
    });

// Configure logging with OTLP export
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    
    if (!string.IsNullOrEmpty(otlpLogsEndpoint))
    {
        logging.AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(otlpLogsEndpoint);
            options.Protocol = OtlpExportProtocol.HttpProtobuf;
        });
    }
});

// Add services to the container.
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Entity Framework - In-Memory Database
builder.Services.AddDbContext<PaymentDbContext>(options =>
    options.UseInMemoryDatabase("PaymentDb"));

// Redis Cache
builder.Services.AddStackExchangeRedisCache(options =>
{
    options.Configuration = builder.Configuration.GetConnectionString("Redis") ?? "localhost:6379";
});

// HTTP Client with Polly
builder.Services.AddHttpClient();

// Business Services
builder.Services.AddScoped<IPaymentProcessorService, PaymentProcessorService>();
builder.Services.AddScoped<IEventHubService, EventHubService>();
builder.Services.AddScoped<IFailureInjectionService, FailureInjectionService>();

// Health checks
builder.Services.AddHealthChecks()
    .AddDbContextCheck<PaymentDbContext>();

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();
app.MapHealthChecks("/health");

// Ensure database is created
using (var scope = app.Services.CreateScope())
{
    var context = scope.ServiceProvider.GetRequiredService<PaymentDbContext>();
    context.Database.EnsureCreated();
}

app.Run();
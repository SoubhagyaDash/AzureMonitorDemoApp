using Microsoft.EntityFrameworkCore;
using PaymentService.Data;
using PaymentService.Services;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using Azure.Monitor.OpenTelemetry.Exporter;

var builder = WebApplication.CreateBuilder(args);

// OpenTelemetry Configuration
var serviceName = "payment-service";
var serviceVersion = "1.0.0";
var instrumentationKey = builder.Configuration["APPLICATIONINSIGHTS_INSTRUMENTATION_KEY"] 
    ?? builder.Configuration["ApplicationInsights:InstrumentationKey"]
    ?? Environment.GetEnvironmentVariable("APPLICATIONINSIGHTS_INSTRUMENTATION_KEY");

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: serviceName, serviceVersion: serviceVersion))
    .WithTracing(tracing => tracing
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
        .AddAzureMonitorTraceExporter(options =>
        {
            if (!string.IsNullOrEmpty(instrumentationKey))
            {
                options.ConnectionString = $"InstrumentationKey={instrumentationKey}";
            }
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddMeter(serviceName)
        .AddAzureMonitorMetricExporter(options =>
        {
            if (!string.IsNullOrEmpty(instrumentationKey))
            {
                options.ConnectionString = $"InstrumentationKey={instrumentationKey}";
            }
        }));

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
using ApiGateway.Services;
using System.Diagnostics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;
using OpenTelemetry.Metrics;
using OpenTelemetry.Logs;

var builder = WebApplication.CreateBuilder(args);

// Add services to the container.
builder.Services.AddControllers()
    .AddJsonOptions(options =>
    {
        options.JsonSerializerOptions.Converters.Add(new System.Text.Json.Serialization.JsonStringEnumConverter());
    });
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen();

// Register custom services
builder.Services.AddScoped<IOrderService, OrderService>();
builder.Services.AddScoped<IEventHubService, EventHubService>();
builder.Services.AddScoped<ICacheService, RedisCacheService>();
builder.Services.AddScoped<IFailureInjectionService, FailureInjectionService>();
builder.Services.AddScoped<IPaymentService, PaymentService>();

// Configure HttpClient for downstream services
builder.Services.AddHttpClient("OrderService", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:OrderService:BaseUrl"] ?? "http://localhost:8080");
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("InventoryService", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:InventoryService:BaseUrl"] ?? "http://localhost:3000");
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("PaymentService", client =>
{
    client.BaseAddress = new Uri(builder.Configuration["Services:PaymentService:BaseUrl"] ?? "http://localhost:5002");
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("EventProcessor", client =>
{
    var baseUrl = builder.Configuration["Services:EventProcessor:BaseUrl"] ?? "http://localhost:8000";
    client.BaseAddress = new Uri(baseUrl);
    client.Timeout = TimeSpan.FromSeconds(30);
});

builder.Services.AddHttpClient("NotificationService", client =>
{
    var baseUrl = builder.Configuration["Services:NotificationService:BaseUrl"];
    if (!string.IsNullOrEmpty(baseUrl))
    {
        client.BaseAddress = new Uri(baseUrl);
    }
    client.Timeout = TimeSpan.FromSeconds(30);
});

// Configure OpenTelemetry
var serviceName = "api-gateway";
var serviceVersion = "1.0.0";

builder.Services.AddOpenTelemetry()
    .ConfigureResource(resource => resource
        .AddService(serviceName: serviceName, serviceVersion: serviceVersion)
        .AddAttributes(new Dictionary<string, object>
        {
            ["deployment.environment"] = builder.Environment.EnvironmentName,
            ["service.instance.id"] = Environment.MachineName
        }))
    .WithTracing(tracing => tracing
        .AddAspNetCoreInstrumentation(options =>
        {
            options.RecordException = true;
            options.Filter = (httpContext) => !httpContext.Request.Path.StartsWithSegments("/health");
        })
        .AddHttpClientInstrumentation(options =>
        {
            options.RecordException = true;
            options.FilterHttpRequestMessage = (httpRequestMessage) =>
            {
                return !httpRequestMessage.RequestUri?.AbsolutePath.Contains("/health") ?? true;
            };
        })
        .AddRedisInstrumentation()
        .AddSource(serviceName)
        .AddConsoleExporter()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"] ?? "http://localhost:4317");
        })
        .AddAzureMonitorTraceExporter(options =>
        {
            options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
        }))
    .WithMetrics(metrics => metrics
        .AddAspNetCoreInstrumentation()
        .AddHttpClientInstrumentation()
        .AddRuntimeInstrumentation()
        .AddMeter(serviceName)
        .AddConsoleExporter()
        .AddOtlpExporter(options =>
        {
            options.Endpoint = new Uri(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"] ?? "http://localhost:4317");
        })
        .AddAzureMonitorMetricExporter(options =>
        {
            options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
        }));

// Configure OpenTelemetry Logging
builder.Logging.AddOpenTelemetry(logging =>
{
    logging.IncludeFormattedMessage = true;
    logging.IncludeScopes = true;
    logging.AddConsoleExporter();
    logging.AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri(builder.Configuration["OTEL_EXPORTER_OTLP_ENDPOINT"] ?? "http://localhost:4317");
    });
    logging.AddAzureMonitorLogExporter(options =>
    {
        options.ConnectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
    });
});

// Add CORS
builder.Services.AddCors(options =>
{
    options.AddPolicy("AllowAll", policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

var app = builder.Build();

// Configure the HTTP request pipeline.
if (app.Environment.IsDevelopment())
{
    app.UseSwagger();
    app.UseSwaggerUI();
}

app.UseCors("AllowAll");
app.UseHttpsRedirection();
app.UseAuthorization();
app.MapControllers();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { Status = "Healthy", Timestamp = DateTime.UtcNow }));

app.Run();
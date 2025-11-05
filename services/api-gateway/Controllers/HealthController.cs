using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;

namespace ApiGateway.Controllers
{
    [ApiController]
    [Route("api/[controller]")]
    public class HealthController : ControllerBase
    {
        private readonly IHttpClientFactory _httpClientFactory;
        private readonly IConfiguration _configuration;
        private readonly ILogger<HealthController> _logger;

        public HealthController(
            IHttpClientFactory httpClientFactory,
            IConfiguration configuration,
            ILogger<HealthController> logger)
        {
            _httpClientFactory = httpClientFactory;
            _configuration = configuration;
            _logger = logger;
        }

        /// <summary>
        /// Get health status of all services in the system
        /// </summary>
        [HttpGet("all")]
        public async Task<IActionResult> GetAllServicesHealth()
        {
            var stopwatch = Stopwatch.StartNew();
            
            var services = new List<ServiceHealth>();

            // Check all downstream services in parallel
            var tasks = new List<Task>
            {
                CheckServiceHealth(services, "API Gateway", () => Task.FromResult((true, 0))),
                CheckServiceHealth(services, "Order Service", () => CheckHttpServiceHealth("OrderService", "/actuator/health")),
                CheckServiceHealth(services, "Payment Service", () => CheckHttpServiceHealth("PaymentService", "/health")),
                CheckServiceHealth(services, "Inventory Service", () => CheckHttpServiceHealth("InventoryService", "/health")),
                CheckServiceHealth(services, "Event Processor", () => CheckEventProcessorHealth()),
                CheckServiceHealth(services, "Notification Service", () => CheckNotificationServiceHealth())
            };

            await Task.WhenAll(tasks);

            stopwatch.Stop();

            var response = new
            {
                OverallStatus = services.All(s => s.IsHealthy) ? "Healthy" : "Degraded",
                TotalServices = services.Count,
                HealthyServices = services.Count(s => s.IsHealthy),
                UnhealthyServices = services.Count(s => !s.IsHealthy),
                Services = services.OrderBy(s => s.Name).ToList(),
                CheckedAt = DateTime.UtcNow,
                ResponseTimeMs = stopwatch.ElapsedMilliseconds
            };

            return Ok(response);
        }

        /// <summary>
        /// Get health status of a specific service
        /// </summary>
        [HttpGet("{serviceName}")]
        public async Task<IActionResult> GetServiceHealth(string serviceName)
        {
            var services = new List<ServiceHealth>();
            
            switch (serviceName.ToLowerInvariant())
            {
                case "api-gateway":
                case "apigateway":
                    await CheckServiceHealth(services, "API Gateway", () => Task.FromResult((true, 0)));
                    break;
                    
                case "order-service":
                case "orderservice":
                case "order":
                    await CheckServiceHealth(services, "Order Service", () => CheckHttpServiceHealth("OrderService", "/actuator/health"));
                    break;
                    
                case "payment-service":
                case "paymentservice":
                case "payment":
                    await CheckServiceHealth(services, "Payment Service", () => CheckHttpServiceHealth("PaymentService", "/health"));
                    break;
                    
                case "inventory-service":
                case "inventoryservice":
                case "inventory":
                    await CheckServiceHealth(services, "Inventory Service", () => CheckHttpServiceHealth("InventoryService", "/health"));
                    break;
                    
                case "event-processor":
                case "eventprocessor":
                    await CheckServiceHealth(services, "Event Processor", () => CheckEventProcessorHealth());
                    break;
                    
                case "notification-service":
                case "notificationservice":
                case "notification":
                    await CheckServiceHealth(services, "Notification Service", () => CheckNotificationServiceHealth());
                    break;
                    
                default:
                    return NotFound(new { Error = $"Service '{serviceName}' not found" });
            }

            if (!services.Any())
            {
                return NotFound(new { Error = $"Service '{serviceName}' not found" });
            }

            var service = services.First();
            return service.IsHealthy ? Ok(service) : StatusCode(503, service);
        }

        private async Task CheckServiceHealth(
            List<ServiceHealth> services, 
            string serviceName, 
            Func<Task<(bool isHealthy, long responseTimeMs)>> healthCheck)
        {
            var stopwatch = Stopwatch.StartNew();
            var serviceHealth = new ServiceHealth
            {
                Name = serviceName,
                IsHealthy = false,
                Status = "Unknown",
                ResponseTimeMs = 0,
                LastChecked = DateTime.UtcNow
            };

            try
            {
                var (isHealthy, responseTime) = await healthCheck();
                stopwatch.Stop();
                
                serviceHealth.IsHealthy = isHealthy;
                serviceHealth.Status = isHealthy ? "Healthy" : "Unhealthy";
                serviceHealth.ResponseTimeMs = responseTime > 0 ? responseTime : stopwatch.ElapsedMilliseconds;
            }
            catch (Exception ex)
            {
                stopwatch.Stop();
                _logger.LogWarning(ex, "Health check failed for {ServiceName}", serviceName);
                serviceHealth.Status = "Unavailable";
                serviceHealth.Error = ex.Message;
                serviceHealth.ResponseTimeMs = stopwatch.ElapsedMilliseconds;
            }

            lock (services)
            {
                services.Add(serviceHealth);
            }
        }

        private async Task<(bool isHealthy, long responseTimeMs)> CheckHttpServiceHealth(string clientName, string healthEndpoint)
        {
            var stopwatch = Stopwatch.StartNew();
            
            try
            {
                var client = _httpClientFactory.CreateClient(clientName);
                var response = await client.GetAsync(healthEndpoint);
                stopwatch.Stop();
                
                return (response.IsSuccessStatusCode, stopwatch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                stopwatch.Stop();
                _logger.LogWarning(ex, "HTTP health check failed for {ClientName}", clientName);
                return (false, stopwatch.ElapsedMilliseconds);
            }
        }

        private async Task<(bool isHealthy, long responseTimeMs)> CheckEventProcessorHealth()
        {
            var stopwatch = Stopwatch.StartNew();
            
            try
            {
                var eventProcessorUrl = _configuration["Services:EventProcessor:BaseUrl"];
                if (string.IsNullOrEmpty(eventProcessorUrl))
                {
                    return (false, 0);
                }

                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                var response = await client.GetAsync($"{eventProcessorUrl}/health");
                stopwatch.Stop();
                
                return (response.IsSuccessStatusCode, stopwatch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                stopwatch.Stop();
                _logger.LogWarning(ex, "Event Processor health check failed");
                return (false, stopwatch.ElapsedMilliseconds);
            }
        }

        private async Task<(bool isHealthy, long responseTimeMs)> CheckNotificationServiceHealth()
        {
            var stopwatch = Stopwatch.StartNew();
            
            try
            {
                var notificationServiceUrl = _configuration["Services:NotificationService:BaseUrl"];
                if (string.IsNullOrEmpty(notificationServiceUrl))
                {
                    // Notification service is optional, return healthy if not configured
                    return (true, 0);
                }

                using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
                var response = await client.GetAsync($"{notificationServiceUrl}/health");
                stopwatch.Stop();
                
                return (response.IsSuccessStatusCode, stopwatch.ElapsedMilliseconds);
            }
            catch (Exception ex)
            {
                stopwatch.Stop();
                _logger.LogWarning(ex, "Notification Service health check failed");
                // Notification service is optional, return true but log the error
                return (true, stopwatch.ElapsedMilliseconds);
            }
        }

        public class ServiceHealth
        {
            public string Name { get; set; } = string.Empty;
            public bool IsHealthy { get; set; }
            public string Status { get; set; } = string.Empty;
            public long ResponseTimeMs { get; set; }
            public DateTime LastChecked { get; set; }
            public string? Error { get; set; }
        }
    }
}

using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;

namespace SyntheticTraffic
{
    public class TrafficGenerator : BackgroundService
    {
        private readonly ILogger<TrafficGenerator> _logger;
        private readonly IConfiguration _configuration;
        private readonly HttpClient _httpClient;
        private readonly Random _random;
        private readonly TrafficPattern _currentPattern;
        
        private readonly List<TrafficScenario> _scenarios;
        private readonly string _apiGatewayUrl;

        public TrafficGenerator(ILogger<TrafficGenerator> logger, IConfiguration configuration, HttpClient httpClient)
        {
            _logger = logger;
            _configuration = configuration;
            _httpClient = httpClient;
            _random = new Random();
            _currentPattern = new TrafficPattern();
            
            _apiGatewayUrl = configuration.GetValue<string>("ApiGateway:BaseUrl") ?? "http://localhost:5000";
            
            _scenarios = InitializeScenarios();
            
            _logger.LogInformation("Synthetic Traffic Generator initialized with API Gateway: {ApiGateway}", _apiGatewayUrl);
        }

        protected override async Task ExecuteAsync(CancellationToken stoppingToken)
        {
            _logger.LogInformation("Starting synthetic traffic generation...");
            
            while (!stoppingToken.IsCancellationRequested)
            {
                try
                {
                    // Update traffic pattern based on time of day
                    UpdateTrafficPattern();
                    
                    // Generate traffic burst
                    await GenerateTrafficBurst(stoppingToken);
                    
                    // Wait before next burst (varies by pattern)
                    var delay = CalculateDelay();
                    await Task.Delay(delay, stoppingToken);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    _logger.LogError(ex, "Error in traffic generation cycle");
                    await Task.Delay(TimeSpan.FromSeconds(30), stoppingToken);
                }
            }
            
            _logger.LogInformation("Synthetic traffic generation stopped");
        }

        private void UpdateTrafficPattern()
        {
            var currentHour = DateTime.Now.Hour;
            
            // Business hours pattern (9 AM - 5 PM)
            if (currentHour >= 9 && currentHour <= 17)
            {
                _currentPattern.RequestsPerMinute = 15 + _random.Next(10); // 15-25 requests/min
                _currentPattern.ErrorRate = 0.02; // 2% error rate
                _currentPattern.LatencyMultiplier = 1.0;
                _currentPattern.PatternName = "Business Hours";
            }
            // Peak hours (12 PM - 2 PM)
            else if (currentHour >= 12 && currentHour <= 14)
            {
                _currentPattern.RequestsPerMinute = 25 + _random.Next(15); // 25-40 requests/min
                _currentPattern.ErrorRate = 0.03; // 3% error rate
                _currentPattern.LatencyMultiplier = 1.2;
                _currentPattern.PatternName = "Peak Hours";
            }
            // Evening hours (6 PM - 10 PM)
            else if (currentHour >= 18 && currentHour <= 22)
            {
                _currentPattern.RequestsPerMinute = 10 + _random.Next(8); // 10-18 requests/min
                _currentPattern.ErrorRate = 0.01; // 1% error rate
                _currentPattern.LatencyMultiplier = 0.8;
                _currentPattern.PatternName = "Evening Hours";
            }
            // Night/Early morning (low activity)
            else
            {
                _currentPattern.RequestsPerMinute = 3 + _random.Next(5); // 3-8 requests/min
                _currentPattern.ErrorRate = 0.005; // 0.5% error rate
                _currentPattern.LatencyMultiplier = 0.6;
                _currentPattern.PatternName = "Night/Early Morning";
            }
        }

        private async Task GenerateTrafficBurst(CancellationToken cancellationToken)
        {
            var requestsThisBurst = _currentPattern.RequestsPerMinute / 4; // Quarter-minute bursts
            var tasks = new List<Task>();
            
            _logger.LogDebug("Generating {RequestCount} requests for pattern: {Pattern}", 
                requestsThisBurst, _currentPattern.PatternName);

            for (int i = 0; i < requestsThisBurst && !cancellationToken.IsCancellationRequested; i++)
            {
                var scenario = SelectScenario();
                var delay = TimeSpan.FromMilliseconds(_random.Next(0, 15000)); // Spread over 15 seconds
                
                var task = Task.Delay(delay, cancellationToken)
                    .ContinueWith(async _ => await ExecuteScenario(scenario, cancellationToken), 
                        cancellationToken)
                    .Unwrap();
                
                tasks.Add(task);
            }

            await Task.WhenAll(tasks);
        }

        private TrafficScenario SelectScenario()
        {
            var totalWeight = 0;
            foreach (var scenario in _scenarios)
            {
                totalWeight += scenario.Weight;
            }

            var randomValue = _random.Next(totalWeight);
            var currentWeight = 0;

            foreach (var scenario in _scenarios)
            {
                currentWeight += scenario.Weight;
                if (randomValue < currentWeight)
                {
                    return scenario;
                }
            }

            return _scenarios[0]; // Fallback
        }

        private async Task ExecuteScenario(TrafficScenario scenario, CancellationToken cancellationToken)
        {
            try
            {
                foreach (var step in scenario.Steps)
                {
                    if (cancellationToken.IsCancellationRequested) break;
                    
                    await ExecuteStep(step);
                    
                    if (step.DelayAfter > TimeSpan.Zero)
                    {
                        await Task.Delay(step.DelayAfter, cancellationToken);
                    }
                }
                
                _logger.LogDebug("Completed scenario: {ScenarioName}", scenario.Name);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Error executing scenario: {ScenarioName}", scenario.Name);
            }
        }

        private async Task ExecuteStep(TrafficStep step)
        {
            var url = $"{_apiGatewayUrl}{step.Endpoint}";
            HttpResponseMessage response = null;
            
            try
            {
                switch (step.Method.ToUpper())
                {
                    case "GET":
                        response = await _httpClient.GetAsync(url);
                        break;
                    case "POST":
                        var content = new StringContent(step.Body ?? "{}", Encoding.UTF8, "application/json");
                        response = await _httpClient.PostAsync(url, content);
                        break;
                    case "PUT":
                        var putContent = new StringContent(step.Body ?? "{}", Encoding.UTF8, "application/json");
                        response = await _httpClient.PutAsync(url, putContent);
                        break;
                    case "DELETE":
                        response = await _httpClient.DeleteAsync(url);
                        break;
                }

                if (response != null)
                {
                    var responseBody = await response.Content.ReadAsStringAsync();
                    
                    _logger.LogDebug("Request: {Method} {Url} -> {StatusCode}", 
                        step.Method, url, response.StatusCode);
                    
                    // Log errors for monitoring
                    if (!response.IsSuccessStatusCode)
                    {
                        _logger.LogWarning("Request failed: {Method} {Url} -> {StatusCode} {ResponseBody}", 
                            step.Method, url, response.StatusCode, responseBody);
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Request exception: {Method} {Url}", step.Method, url);
            }
            finally
            {
                response?.Dispose();
            }
        }

        private TimeSpan CalculateDelay()
        {
            // Base delay of 15 seconds, with some randomization
            var baseDelay = TimeSpan.FromSeconds(15);
            var jitter = TimeSpan.FromMilliseconds(_random.Next(-5000, 5000));
            
            // Adjust based on traffic pattern
            var patternMultiplier = _currentPattern.PatternName switch
            {
                "Peak Hours" => 0.7, // Faster during peak
                "Business Hours" => 1.0, // Normal timing
                "Evening Hours" => 1.3, // Slower in evening
                "Night/Early Morning" => 2.0, // Much slower at night
                _ => 1.0
            };

            return TimeSpan.FromMilliseconds(baseDelay.TotalMilliseconds * patternMultiplier + jitter.TotalMilliseconds);
        }

        private List<TrafficScenario> InitializeScenarios()
        {
            return new List<TrafficScenario>
            {
                // User Registration/Login (10% of traffic)
                new TrafficScenario
                {
                    Name = "User Registration",
                    Weight = 10,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep
                        {
                            Method = "POST",
                            Endpoint = "/api/users/register",
                            Body = JsonSerializer.Serialize(new
                            {
                                email = $"user{Guid.NewGuid():N}@example.com",
                                name = "Demo User",
                                password = "SecurePass123!"
                            })
                        }
                    }
                },

                // Product Browsing (30% of traffic)
                new TrafficScenario
                {
                    Name = "Product Browsing",
                    Weight = 30,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep { Method = "GET", Endpoint = "/api/products" },
                        new TrafficStep 
                        { 
                            Method = "GET", 
                            Endpoint = $"/api/products/{_random.Next(1, 100)}",
                            DelayAfter = TimeSpan.FromMilliseconds(1000)
                        },
                        new TrafficStep { Method = "GET", Endpoint = "/api/inventory/availability" }
                    }
                },

                // Shopping Cart Operations (25% of traffic)
                new TrafficScenario
                {
                    Name = "Shopping Cart",
                    Weight = 25,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep { Method = "GET", Endpoint = "/api/products" },
                        new TrafficStep
                        {
                            Method = "POST",
                            Endpoint = "/api/cart/add",
                            Body = JsonSerializer.Serialize(new
                            {
                                productId = _random.Next(1, 100),
                                quantity = _random.Next(1, 5),
                                userId = $"user{_random.Next(1, 1000)}"
                            }),
                            DelayAfter = TimeSpan.FromMilliseconds(500)
                        },
                        new TrafficStep { Method = "GET", Endpoint = "/api/cart" },
                        new TrafficStep
                        {
                            Method = "PUT",
                            Endpoint = "/api/cart/update",
                            Body = JsonSerializer.Serialize(new
                            {
                                productId = _random.Next(1, 100),
                                quantity = _random.Next(1, 3)
                            })
                        }
                    }
                },

                // Order Processing (20% of traffic)
                new TrafficScenario
                {
                    Name = "Order Processing",
                    Weight = 20,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep
                        {
                            Method = "POST",
                            Endpoint = "/api/orders",
                            Body = JsonSerializer.Serialize(new
                            {
                                userId = $"user{_random.Next(1, 1000)}",
                                items = new[]
                                {
                                    new { productId = _random.Next(1, 100), quantity = _random.Next(1, 3) }
                                },
                                totalAmount = _random.Next(50, 500)
                            }),
                            DelayAfter = TimeSpan.FromMilliseconds(1000)
                        },
                        new TrafficStep
                        {
                            Method = "POST",
                            Endpoint = "/api/payments/process",
                            Body = JsonSerializer.Serialize(new
                            {
                                amount = _random.Next(50, 500),
                                currency = "USD",
                                paymentMethod = "credit_card"
                            }),
                            DelayAfter = TimeSpan.FromMilliseconds(2000)
                        },
                        new TrafficStep { Method = "GET", Endpoint = "/api/orders/status" }
                    }
                },

                // Inventory Checks (10% of traffic)
                new TrafficScenario
                {
                    Name = "Inventory Management",
                    Weight = 10,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep { Method = "GET", Endpoint = "/api/inventory/status" },
                        new TrafficStep { Method = "GET", Endpoint = "/api/inventory/low-stock" },
                        new TrafficStep
                        {
                            Method = "POST",
                            Endpoint = "/api/inventory/restock",
                            Body = JsonSerializer.Serialize(new
                            {
                                productId = _random.Next(1, 100),
                                quantity = _random.Next(10, 100)
                            })
                        }
                    }
                },

                // Health Checks and Monitoring (5% of traffic)
                new TrafficScenario
                {
                    Name = "Health Monitoring",
                    Weight = 5,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep { Method = "GET", Endpoint = "/health" },
                        new TrafficStep { Method = "GET", Endpoint = "/api/status" },
                        new TrafficStep { Method = "GET", Endpoint = "/metrics" }
                    }
                }
            };
        }
    }

    public class TrafficPattern
    {
        public int RequestsPerMinute { get; set; }
        public double ErrorRate { get; set; }
        public double LatencyMultiplier { get; set; }
        public string PatternName { get; set; } = "";
    }

    public class TrafficScenario
    {
        public string Name { get; set; } = "";
        public int Weight { get; set; }
        public List<TrafficStep> Steps { get; set; } = new();
    }

    public class TrafficStep
    {
        public string Method { get; set; } = "GET";
        public string Endpoint { get; set; } = "";
        public string? Body { get; set; }
        public TimeSpan DelayAfter { get; set; }
    }
}
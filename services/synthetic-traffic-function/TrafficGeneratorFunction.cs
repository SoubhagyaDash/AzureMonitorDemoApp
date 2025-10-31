using System;
using System.Collections.Generic;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace SyntheticTraffic.Function
{
    public class TrafficGeneratorFunction
    {
        private readonly ILogger<TrafficGeneratorFunction> _logger;
        private readonly IConfiguration _configuration;
        private readonly HttpClient _httpClient;
        private readonly Random _random;

        public TrafficGeneratorFunction(ILogger<TrafficGeneratorFunction> logger, 
            IConfiguration configuration, HttpClient httpClient)
        {
            _logger = logger;
            _configuration = configuration;
            _httpClient = httpClient;
            _random = new Random();
        }

        [Function("GenerateTrafficTimer")]
        public async Task GenerateTrafficTimer([TimerTrigger("0 */2 * * * *")] TimerInfo timer)
        {
            _logger.LogInformation("Timer trigger executed at: {Time}", DateTime.Now);
            
            var pattern = GetCurrentTrafficPattern();
            var requestCount = CalculateRequestCount(pattern);
            
            _logger.LogInformation("Generating {RequestCount} requests for pattern: {Pattern}", 
                requestCount, pattern.PatternName);

            var tasks = new List<Task>();
            for (int i = 0; i < requestCount; i++)
            {
                var scenario = SelectScenario();
                var delay = TimeSpan.FromMilliseconds(_random.Next(0, 120000)); // Spread over 2 minutes
                
                var task = Task.Delay(delay)
                    .ContinueWith(async _ => await ExecuteScenario(scenario))
                    .Unwrap();
                
                tasks.Add(task);
            }

            await Task.WhenAll(tasks);
            _logger.LogInformation("Completed traffic generation burst");
        }

        [Function("GenerateTrafficHttp")]
        public async Task<HttpResponseData> GenerateTrafficHttp(
            [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
        {
            _logger.LogInformation("HTTP trigger executed");

            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var request = string.IsNullOrEmpty(requestBody) 
                ? new TrafficRequest() 
                : JsonSerializer.Deserialize<TrafficRequest>(requestBody);

            var pattern = request.Pattern ?? GetCurrentTrafficPattern();
            var requestCount = request.RequestCount ?? CalculateRequestCount(pattern);
            var scenario = request.ScenarioName != null 
                ? GetScenarioByName(request.ScenarioName) 
                : SelectScenario();

            _logger.LogInformation("HTTP request: generating {RequestCount} requests using scenario {Scenario}", 
                requestCount, scenario.Name);

            if (request.RequestCount.HasValue && request.RequestCount == 1)
            {
                // Single request execution
                await ExecuteScenario(scenario);
            }
            else
            {
                // Burst execution
                var tasks = new List<Task>();
                for (int i = 0; i < requestCount; i++)
                {
                    var selectedScenario = request.ScenarioName != null ? scenario : SelectScenario();
                    var delay = TimeSpan.FromMilliseconds(_random.Next(0, 30000)); // Spread over 30 seconds
                    
                    var task = Task.Delay(delay)
                        .ContinueWith(async _ => await ExecuteScenario(selectedScenario))
                        .Unwrap();
                    
                    tasks.Add(task);
                }
                await Task.WhenAll(tasks);
            }

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                message = "Traffic generation completed",
                requestCount = requestCount,
                pattern = pattern.PatternName,
                scenario = scenario.Name,
                timestamp = DateTime.UtcNow
            });

            return response;
        }

        [Function("GetTrafficStatus")]
        public async Task<HttpResponseData> GetTrafficStatus(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get")] HttpRequestData req)
        {
            var pattern = GetCurrentTrafficPattern();
            var nextExecution = GetNextTimerExecution();

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                status = "running",
                currentPattern = new
                {
                    name = pattern.PatternName,
                    requestsPerBurst = CalculateRequestCount(pattern),
                    errorRate = pattern.ErrorRate,
                    latencyMultiplier = pattern.LatencyMultiplier
                },
                nextScheduledExecution = nextExecution,
                apiGatewayUrl = GetApiGatewayUrl(),
                availableScenarios = GetScenarios().Select(s => new { s.Name, s.Weight }).ToArray(),
                timestamp = DateTime.UtcNow
            });

            return response;
        }

        [Function("ConfigureTrafficPattern")]
        public async Task<HttpResponseData> ConfigureTrafficPattern(
            [HttpTrigger(AuthorizationLevel.Function, "post")] HttpRequestData req)
        {
            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var config = JsonSerializer.Deserialize<TrafficConfiguration>(requestBody);

            // Store configuration (in production, use Azure Table Storage or Cosmos DB)
            Environment.SetEnvironmentVariable("TRAFFIC_MIN_REQUESTS", config.MinRequestsPerBurst?.ToString());
            Environment.SetEnvironmentVariable("TRAFFIC_MAX_REQUESTS", config.MaxRequestsPerBurst?.ToString());
            Environment.SetEnvironmentVariable("TRAFFIC_ERROR_RATE", config.ErrorRate?.ToString());
            Environment.SetEnvironmentVariable("TRAFFIC_ENABLED_SCENARIOS", 
                string.Join(",", config.EnabledScenarios ?? Array.Empty<string>()));

            _logger.LogInformation("Traffic configuration updated: MinRequests={Min}, MaxRequests={Max}, ErrorRate={Error}",
                config.MinRequestsPerBurst, config.MaxRequestsPerBurst, config.ErrorRate);

            var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
            await response.WriteAsJsonAsync(new
            {
                message = "Configuration updated successfully",
                configuration = config,
                timestamp = DateTime.UtcNow
            });

            return response;
        }

        private TrafficPattern GetCurrentTrafficPattern()
        {
            var currentHour = DateTime.Now.Hour;
            var pattern = new TrafficPattern();

            // Business hours pattern (9 AM - 5 PM)
            if (currentHour >= 9 && currentHour <= 17)
            {
                pattern.RequestsPerMinute = 15 + _random.Next(10); // 15-25 requests/min
                pattern.ErrorRate = 0.02; // 2% error rate
                pattern.LatencyMultiplier = 1.0;
                pattern.PatternName = "Business Hours";
            }
            // Peak hours (12 PM - 2 PM)
            else if (currentHour >= 12 && currentHour <= 14)
            {
                pattern.RequestsPerMinute = 25 + _random.Next(15); // 25-40 requests/min
                pattern.ErrorRate = 0.03; // 3% error rate
                pattern.LatencyMultiplier = 1.2;
                pattern.PatternName = "Peak Hours";
            }
            // Evening hours (6 PM - 10 PM)
            else if (currentHour >= 18 && currentHour <= 22)
            {
                pattern.RequestsPerMinute = 10 + _random.Next(8); // 10-18 requests/min
                pattern.ErrorRate = 0.01; // 1% error rate
                pattern.LatencyMultiplier = 0.8;
                pattern.PatternName = "Evening Hours";
            }
            // Night/Early morning (low activity)
            else
            {
                pattern.RequestsPerMinute = 3 + _random.Next(5); // 3-8 requests/min
                pattern.ErrorRate = 0.005; // 0.5% error rate
                pattern.LatencyMultiplier = 0.6;
                pattern.PatternName = "Night/Early Morning";
            }

            return pattern;
        }

        private int CalculateRequestCount(TrafficPattern pattern)
        {
            // Convert per-minute rate to per-2-minute burst (timer interval)
            var baseCount = pattern.RequestsPerMinute * 2;
            
            // Apply configuration overrides
            var minRequests = int.TryParse(Environment.GetEnvironmentVariable("TRAFFIC_MIN_REQUESTS"), out var min) ? min : baseCount / 2;
            var maxRequests = int.TryParse(Environment.GetEnvironmentVariable("TRAFFIC_MAX_REQUESTS"), out var max) ? max : baseCount * 2;
            
            return Math.Max(minRequests, Math.Min(maxRequests, baseCount + _random.Next(-5, 6)));
        }

        private TrafficScenario SelectScenario()
        {
            var scenarios = GetScenarios();
            var enabledScenarios = GetEnabledScenarios(scenarios);
            
            var totalWeight = enabledScenarios.Sum(s => s.Weight);
            var randomValue = _random.Next(totalWeight);
            var currentWeight = 0;

            foreach (var scenario in enabledScenarios)
            {
                currentWeight += scenario.Weight;
                if (randomValue < currentWeight)
                {
                    return scenario;
                }
            }

            return enabledScenarios.First();
        }

        private TrafficScenario GetScenarioByName(string name)
        {
            return GetScenarios().FirstOrDefault(s => s.Name.Equals(name, StringComparison.OrdinalIgnoreCase))
                ?? GetScenarios().First();
        }

        private List<TrafficScenario> GetEnabledScenarios(List<TrafficScenario> allScenarios)
        {
            var enabledScenariosStr = Environment.GetEnvironmentVariable("TRAFFIC_ENABLED_SCENARIOS");
            if (string.IsNullOrEmpty(enabledScenariosStr))
            {
                return allScenarios;
            }

            var enabledNames = enabledScenariosStr.Split(',', StringSplitOptions.RemoveEmptyEntries);
            var enabledScenarios = allScenarios.Where(s => 
                enabledNames.Any(name => s.Name.Contains(name, StringComparison.OrdinalIgnoreCase)))
                .ToList();

            return enabledScenarios.Any() ? enabledScenarios : allScenarios;
        }

        private async Task ExecuteScenario(TrafficScenario scenario)
        {
            try
            {
                foreach (var step in scenario.Steps)
                {
                    await ExecuteStep(step);
                    
                    if (step.DelayAfter > TimeSpan.Zero)
                    {
                        await Task.Delay(step.DelayAfter);
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
            var apiGatewayUrl = GetApiGatewayUrl();
            var url = $"{apiGatewayUrl}{step.Endpoint}";
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
                    _logger.LogDebug("Request: {Method} {Url} -> {StatusCode}", 
                        step.Method, url, response.StatusCode);
                    
                    if (!response.IsSuccessStatusCode)
                    {
                        var responseBody = await response.Content.ReadAsStringAsync();
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

        private string GetApiGatewayUrl()
        {
            return _configuration.GetValue<string>("ApiGateway:BaseUrl") 
                ?? Environment.GetEnvironmentVariable("API_GATEWAY_URL") 
                ?? "http://localhost:5000";
        }

        private DateTime GetNextTimerExecution()
        {
            var now = DateTime.Now;
            var nextMinute = now.AddMinutes(1);
            var nextEvenMinute = new DateTime(nextMinute.Year, nextMinute.Month, nextMinute.Day, 
                nextMinute.Hour, nextMinute.Minute - (nextMinute.Minute % 2), 0);
            
            if (nextEvenMinute <= now)
            {
                nextEvenMinute = nextEvenMinute.AddMinutes(2);
            }
            
            return nextEvenMinute;
        }

        private List<TrafficScenario> GetScenarios()
        {
            return new List<TrafficScenario>
            {
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
                        new TrafficStep { Method = "GET", Endpoint = "/api/cart" }
                    }
                },
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
                new TrafficScenario
                {
                    Name = "Health Monitoring",
                    Weight = 5,
                    Steps = new List<TrafficStep>
                    {
                        new TrafficStep { Method = "GET", Endpoint = "/health" },
                        new TrafficStep { Method = "GET", Endpoint = "/api/status" }
                    }
                }
            };
        }
    }

    public class TrafficRequest
    {
        public TrafficPattern? Pattern { get; set; }
        public int? RequestCount { get; set; }
        public string? ScenarioName { get; set; }
    }

    public class TrafficConfiguration
    {
        public int? MinRequestsPerBurst { get; set; }
        public int? MaxRequestsPerBurst { get; set; }
        public double? ErrorRate { get; set; }
        public string[]? EnabledScenarios { get; set; }
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
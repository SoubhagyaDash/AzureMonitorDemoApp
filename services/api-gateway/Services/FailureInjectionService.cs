using System.Diagnostics;
using OTelDemo.ApiGateway.Controllers;

namespace ApiGateway.Services;

public interface IFailureInjectionService
{
    Task MaybeInjectFailureAsync(string operation);
    Task ApplyFailuresAsync(string operation);
    Task<object> GetCurrentConfigurationAsync();
    Task UpdateConfigurationAsync(FailureInjectionConfigDto config);
    Task ResetToDefaultsAsync();
    Task<object> GetStatusAsync();
}

public class FailureInjectionService : IFailureInjectionService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<FailureInjectionService> _logger;
    private readonly Random _random = new();
    
    // Runtime configuration cache
    private static FailureInjectionConfigDto? _runtimeConfig;
    private static DateTime _lastConfigUpdate = DateTime.UtcNow;
    private static int _totalInjections = 0;
    private static int _latencyInjections = 0;
    private static int _errorInjections = 0;

    public FailureInjectionService(IConfiguration configuration, ILogger<FailureInjectionService> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task<object> GetCurrentConfigurationAsync()
    {
        if (_runtimeConfig != null)
        {
            return _runtimeConfig;
        }

        var config = _configuration.GetSection("FailureInjection");
        return new
        {
            Enabled = config.GetValue<bool>("Enabled"),
            Latency = new
            {
                Probability = config.GetSection("Latency").GetValue<double>("Probability"),
                MinDelayMs = config.GetSection("Latency").GetValue<int>("MinDelayMs"),
                MaxDelayMs = config.GetSection("Latency").GetValue<int>("MaxDelayMs")
            },
            Errors = new
            {
                Probability = config.GetSection("Errors").GetValue<double>("Probability"),
                Types = config.GetSection("Errors").GetValue<string[]>("Types")
            }
        };
    }

    public async Task UpdateConfigurationAsync(FailureInjectionConfigDto config)
    {
        _runtimeConfig = config;
        _lastConfigUpdate = DateTime.UtcNow;
        
        _logger.LogInformation("Runtime failure injection configuration updated: {@Config}", config);
        await Task.CompletedTask;
    }

    public async Task ResetToDefaultsAsync()
    {
        _runtimeConfig = null;
        _lastConfigUpdate = DateTime.UtcNow;
        
        _logger.LogInformation("Failure injection configuration reset to defaults");
        await Task.CompletedTask;
    }

    public async Task<object> GetStatusAsync()
    {
        return new
        {
            Service = "API Gateway",
            Enabled = await IsEnabledAsync(),
            LastConfigUpdate = _lastConfigUpdate,
            Statistics = new
            {
                TotalInjections = _totalInjections,
                LatencyInjections = _latencyInjections,
                ErrorInjections = _errorInjections
            },
            RuntimeConfigActive = _runtimeConfig != null
        };
    }

    private async Task<bool> IsEnabledAsync()
    {
        if (_runtimeConfig != null)
        {
            return _runtimeConfig.Enabled;
        }

        var config = _configuration.GetSection("FailureInjection");
        return config.GetValue<bool>("Enabled");
    }

    public async Task MaybeInjectFailureAsync(string operation)
    {
        if (!await IsEnabledAsync())
        {
            return;
        }

        _totalInjections++;

        // Inject latency
        await MaybeInjectLatencyAsync(operation);
        
        // Inject errors
        MaybeInjectError(operation);
    }

    public Task ApplyFailuresAsync(string operation)
    {
        return MaybeInjectFailureAsync(operation);
    }

    private async Task MaybeInjectLatencyAsync(string operation)
    {
        double probability;
        int minDelayMs;
        int maxDelayMs;

        if (_runtimeConfig?.Latency != null)
        {
            probability = _runtimeConfig.Latency.Probability;
            minDelayMs = _runtimeConfig.Latency.MinDelayMs;
            maxDelayMs = _runtimeConfig.Latency.MaxDelayMs;
        }
        else
        {
            var latencyConfig = _configuration.GetSection("FailureInjection:Latency");
            probability = latencyConfig.GetValue<double>("Probability");
            minDelayMs = latencyConfig.GetValue<int>("MinDelayMs");
            maxDelayMs = latencyConfig.GetValue<int>("MaxDelayMs");
        }

        if (_random.NextDouble() < probability)
        {
            var delay = _random.Next(minDelayMs, maxDelayMs);
            _latencyInjections++;
            
            using var activity = Activity.Current;
            activity?.SetTag("failure_injection.latency", delay);
            
            _logger.LogWarning("Injecting latency: {Delay}ms in operation {Operation}", delay, operation);
            await Task.Delay(delay);
        }
    }

    private void MaybeInjectError(string operation)
    {
        double probability;
        string[] errorTypes;

        if (_runtimeConfig?.Errors != null)
        {
            probability = _runtimeConfig.Errors.Probability;
            errorTypes = _runtimeConfig.Errors.Types ?? new[] { "timeout", "database", "network" };
        }
        else
        {
            var errorConfig = _configuration.GetSection("FailureInjection:Errors");
            probability = errorConfig.GetValue<double>("Probability");
            errorTypes = errorConfig.GetValue<string[]>("Types") ?? new[] { "timeout", "database", "network" };
        }

        if (_random.NextDouble() < probability)
        {
            var errorType = errorTypes[_random.Next(errorTypes.Length)];
            _errorInjections++;
            
            using var activity = Activity.Current;
            activity?.SetTag("failure_injection.error", errorType);
            
            _logger.LogError("Injecting {ErrorType} error in operation {Operation}", errorType, operation);
            
            var exception = errorType switch
            {
                "timeout" => new TimeoutException($"Simulated timeout in {operation}"),
                "database" => new InvalidOperationException($"Simulated database error in {operation}"),
                "network" => new HttpRequestException($"Simulated network error in {operation}"),
                _ => new Exception($"Simulated {errorType} error in {operation}")
            };
            
            throw exception;
        }
    }
}
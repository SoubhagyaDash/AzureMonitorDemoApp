namespace PaymentService.Services;

public interface IFailureInjectionService
{
    Task ApplyFailuresAsync(string operationType);
}

public class FailureInjectionService : IFailureInjectionService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<FailureInjectionService> _logger;

    public FailureInjectionService(IConfiguration configuration, ILogger<FailureInjectionService> logger)
    {
        _configuration = configuration;
        _logger = logger;
    }

    public async Task ApplyFailuresAsync(string operationType)
    {
        var failureConfig = _configuration.GetSection("FailureInjection");
        
        if (!failureConfig.GetValue<bool>("Enabled", false))
            return;

        var latencyMs = failureConfig.GetValue<int>("LatencyMs", 0);
        var errorRate = failureConfig.GetValue<double>("ErrorRate", 0.0);
        var timeoutRate = failureConfig.GetValue<double>("TimeoutRate", 0.0);

        // Apply latency
        if (latencyMs > 0)
        {
            var delay = Random.Shared.Next(0, latencyMs);
            if (delay > 0)
            {
                _logger.LogWarning("Injecting {Delay}ms latency for {OperationType}", delay, operationType);
                await Task.Delay(delay);
            }
        }

        // Apply random errors
        if (errorRate > 0 && Random.Shared.NextDouble() < errorRate)
        {
            _logger.LogError("Injecting error for {OperationType}", operationType);
            throw new InvalidOperationException($"Injected failure for {operationType}");
        }

        // Apply timeouts
        if (timeoutRate > 0 && Random.Shared.NextDouble() < timeoutRate)
        {
            _logger.LogError("Injecting timeout for {OperationType}", operationType);
            await Task.Delay(30000); // Simulate timeout
            throw new TimeoutException($"Injected timeout for {operationType}");
        }
    }
}
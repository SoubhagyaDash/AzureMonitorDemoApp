using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using System.Text.Json;

namespace PaymentService.Services;

public interface IEventHubService
{
    Task PublishPaymentEventAsync(object eventData);
}

public class EventHubService : IEventHubService
{
    private readonly EventHubProducerClient _producerClient;
    private readonly ILogger<EventHubService> _logger;

    public EventHubService(IConfiguration configuration, ILogger<EventHubService> logger)
    {
        var connectionString = configuration.GetConnectionString("EventHub");
        var eventHubName = configuration["EventHub:PaymentEvents"] ?? "payment-events";
        
        _producerClient = new EventHubProducerClient(connectionString, eventHubName);
        _logger = logger;
    }

    public async Task PublishPaymentEventAsync(object eventData)
    {
        try
        {
            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataBatch = await _producerClient.CreateBatchAsync();
            
            var eventHubEvent = new EventData(eventBody)
            {
                ContentType = "application/json"
            };
            
            // Add metadata
            eventHubEvent.Properties.Add("source", "payment-service");
            eventHubEvent.Properties.Add("timestamp", DateTime.UtcNow.ToString("O"));
            
            if (!eventDataBatch.TryAdd(eventHubEvent))
            {
                _logger.LogError("Failed to add event to batch - event too large");
                return;
            }

            await _producerClient.SendAsync(eventDataBatch);
            _logger.LogDebug("Published payment event to EventHub");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish payment event to EventHub");
            // Don't throw - we don't want payment processing to fail due to event publishing issues
        }
    }

    public void Dispose()
    {
        _producerClient?.DisposeAsync().GetAwaiter().GetResult();
    }
}
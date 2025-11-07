using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using System.Diagnostics;
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
    private readonly ActivitySource _activitySource;

    public EventHubService(IConfiguration configuration, ILogger<EventHubService> logger)
    {
        var connectionString = configuration.GetConnectionString("EventHub");
        var eventHubName = configuration["EventHub:PaymentEvents"] ?? "payment-events";
        
        _producerClient = new EventHubProducerClient(connectionString, eventHubName);
        _logger = logger;
        _activitySource = new ActivitySource("payment-service");
    }

    public async Task PublishPaymentEventAsync(object eventData)
    {
        using var activity = _activitySource.StartActivity("eventhub.send", ActivityKind.Producer);
        
        try
        {
            var eventHubName = _producerClient.EventHubName;
            
            // Set messaging semantic conventions
            activity?.SetTag("messaging.system", "eventhub");
            activity?.SetTag("messaging.destination", eventHubName);
            activity?.SetTag("messaging.operation", "send");
            
            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataBatch = await _producerClient.CreateBatchAsync();
            
            var eventHubEvent = new EventData(eventBody)
            {
                ContentType = "application/json"
            };
            
            // Add metadata
            eventHubEvent.Properties.Add("source", "payment-service");
            eventHubEvent.Properties.Add("timestamp", DateTime.UtcNow.ToString("O"));
            
            // Inject distributed tracing context into EventHub message properties
            // Use Diagnostic-Id for compatibility with Azure SDKs
            if (activity != null)
            {
                eventHubEvent.Properties.Add("Diagnostic-Id", activity.Id);
                eventHubEvent.Properties.Add("traceparent", activity.Id);
                if (!string.IsNullOrEmpty(activity.TraceStateString))
                {
                    eventHubEvent.Properties.Add("tracestate", activity.TraceStateString);
                }
            }
            
            if (!eventDataBatch.TryAdd(eventHubEvent))
            {
                _logger.LogError("Failed to add event to batch - event too large");
                activity?.SetStatus(ActivityStatusCode.Error, "Event too large");
                return;
            }

            await _producerClient.SendAsync(eventDataBatch);
            _logger.LogDebug("Published payment event to EventHub");
            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish payment event to EventHub");
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            // Don't throw - we don't want payment processing to fail due to event publishing issues
        }
    }

    public void Dispose()
    {
        _producerClient?.DisposeAsync().GetAwaiter().GetResult();
    }
}
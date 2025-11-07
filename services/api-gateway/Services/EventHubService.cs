using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using ApiGateway.Models;
using System.Diagnostics;
using System.Text.Json;

namespace ApiGateway.Services;

public interface IEventHubService
{
    Task SendOrderCreatedEventAsync(Order order);
    Task SendOrderStatusUpdatedEventAsync(int orderId, string status);
    Task PublishEventAsync(object eventData);
}

public class EventHubService : IEventHubService
{
    private readonly EventHubProducerClient _producerClient;
    private readonly ILogger<EventHubService> _logger;
    private readonly ActivitySource _activitySource;
    private readonly string _eventHubName;

    public EventHubService(IConfiguration configuration, ILogger<EventHubService> logger)
    {
        var connectionString = configuration["EventHub:ConnectionString"];
        _eventHubName = configuration["EventHub:Name"] ?? "orders";
        
        _producerClient = new EventHubProducerClient(connectionString, _eventHubName);
        _logger = logger;
        _activitySource = new ActivitySource("api-gateway");
    }

    public async Task SendOrderCreatedEventAsync(Order order)
    {
        using var activity = _activitySource.StartActivity("eventhub.send", ActivityKind.Producer);
        
        try
        {
            // Set messaging semantic conventions
            activity?.SetTag("messaging.system", "eventhub");
            activity?.SetTag("messaging.destination", _eventHubName);
            activity?.SetTag("messaging.operation", "send");
            
            var eventData = new
            {
                EventType = "OrderCreated",
                OrderId = order.Id,
                CustomerId = order.CustomerId,
                ProductId = order.ProductId,
                Quantity = order.Quantity,
                TotalAmount = order.TotalAmount,
                Timestamp = order.CreatedAt
            };

            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataInstance = new EventData(eventBody);
            
            // Add metadata
            eventDataInstance.Properties["EventType"] = "OrderCreated";
            eventDataInstance.Properties["Source"] = "ApiGateway";

            // Inject distributed tracing context into EventHub message properties
            if (activity != null)
            {
                eventDataInstance.Properties["Diagnostic-Id"] = activity.Id;
                eventDataInstance.Properties["traceparent"] = activity.Id;
                if (!string.IsNullOrEmpty(activity.TraceStateString))
                {
                    eventDataInstance.Properties["tracestate"] = activity.TraceStateString;
                }
            }

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Sent OrderCreated event for order {OrderId}", order.Id);
            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send OrderCreated event for order {OrderId}", order.Id);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }

    public async Task SendOrderStatusUpdatedEventAsync(int orderId, string status)
    {
        using var activity = _activitySource.StartActivity("eventhub.send", ActivityKind.Producer);
        
        try
        {
            // Set messaging semantic conventions
            activity?.SetTag("messaging.system", "eventhub");
            activity?.SetTag("messaging.destination", _eventHubName);
            activity?.SetTag("messaging.operation", "send");
            
            var eventData = new
            {
                EventType = "OrderStatusUpdated",
                OrderId = orderId,
                Status = status,
                Timestamp = DateTime.UtcNow
            };

            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataInstance = new EventData(eventBody);
            
            eventDataInstance.Properties["EventType"] = "OrderStatusUpdated";
            eventDataInstance.Properties["Source"] = "ApiGateway";

            // Inject distributed tracing context into EventHub message properties
            if (activity != null)
            {
                eventDataInstance.Properties["Diagnostic-Id"] = activity.Id;
                eventDataInstance.Properties["traceparent"] = activity.Id;
                if (!string.IsNullOrEmpty(activity.TraceStateString))
                {
                    eventDataInstance.Properties["tracestate"] = activity.TraceStateString;
                }
            }

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Sent OrderStatusUpdated event for order {OrderId} with status {Status}", orderId, status);
            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send OrderStatusUpdated event for order {OrderId}", orderId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }

    public async Task PublishEventAsync(object eventData)
    {
        using var activity = _activitySource.StartActivity("eventhub.send", ActivityKind.Producer);
        
        try
        {
            // Set messaging semantic conventions
            activity?.SetTag("messaging.system", "eventhub");
            activity?.SetTag("messaging.destination", _eventHubName);
            activity?.SetTag("messaging.operation", "send");
            
            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataInstance = new EventData(eventBody);
            
            // Try to extract event type from the object
            var eventType = eventData.GetType().GetProperty("EventType")?.GetValue(eventData)?.ToString() ?? "GenericEvent";
            eventDataInstance.Properties["EventType"] = eventType;
            eventDataInstance.Properties["Source"] = "ApiGateway";

            // Inject distributed tracing context into EventHub message properties
            if (activity != null)
            {
                eventDataInstance.Properties["Diagnostic-Id"] = activity.Id;
                eventDataInstance.Properties["traceparent"] = activity.Id;
                if (!string.IsNullOrEmpty(activity.TraceStateString))
                {
                    eventDataInstance.Properties["tracestate"] = activity.TraceStateString;
                }
            }

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Published event {EventType}", eventType);
            activity?.SetStatus(ActivityStatusCode.Ok);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event");
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
        }
    }
}
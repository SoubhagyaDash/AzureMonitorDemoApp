using Azure.Messaging.EventHubs;
using Azure.Messaging.EventHubs.Producer;
using ApiGateway.Models;
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

    public EventHubService(IConfiguration configuration, ILogger<EventHubService> logger)
    {
        var connectionString = configuration["EventHub:ConnectionString"];
        var eventHubName = configuration["EventHub:Name"];
        
        _producerClient = new EventHubProducerClient(connectionString, eventHubName);
        _logger = logger;
    }

    public async Task SendOrderCreatedEventAsync(Order order)
    {
        try
        {
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

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Sent OrderCreated event for order {OrderId}", order.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send OrderCreated event for order {OrderId}", order.Id);
            throw;
        }
    }

    public async Task SendOrderStatusUpdatedEventAsync(int orderId, string status)
    {
        try
        {
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

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Sent OrderStatusUpdated event for order {OrderId} with status {Status}", orderId, status);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to send OrderStatusUpdated event for order {OrderId}", orderId);
            throw;
        }
    }

    public async Task PublishEventAsync(object eventData)
    {
        try
        {
            var eventBody = JsonSerializer.Serialize(eventData);
            var eventDataInstance = new EventData(eventBody);
            
            // Try to extract event type from the object
            var eventType = eventData.GetType().GetProperty("EventType")?.GetValue(eventData)?.ToString() ?? "GenericEvent";
            eventDataInstance.Properties["EventType"] = eventType;
            eventDataInstance.Properties["Source"] = "ApiGateway";

            using var eventBatch = await _producerClient.CreateBatchAsync();
            eventBatch.TryAdd(eventDataInstance);

            await _producerClient.SendAsync(eventBatch);
            
            _logger.LogInformation("Published event {EventType}", eventType);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to publish event");
            throw;
        }
    }
}
using Microsoft.AspNetCore.Mvc;
using ApiGateway.Models;
using ApiGateway.Services;
using System.Diagnostics;

namespace ApiGateway.Controllers;

[ApiController]
[Route("api/[controller]")]
public class OrdersController : ControllerBase
{
    private readonly IOrderService _orderService;
    private readonly IEventHubService _eventHubService;
    private readonly ICacheService _cacheService;
    private readonly IFailureInjectionService _failureInjection;
    private readonly IPaymentService _paymentService;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<OrdersController> _logger;

    private static readonly ActivitySource ActivitySource = new("ApiGateway.Orders");

    public OrdersController(
        IOrderService orderService,
        IEventHubService eventHubService,
        ICacheService cacheService,
        IFailureInjectionService failureInjection,
        IPaymentService paymentService,
        IHttpClientFactory httpClientFactory,
        ILogger<OrdersController> logger)
    {
        _orderService = orderService;
        _eventHubService = eventHubService;
        _cacheService = cacheService;
        _failureInjection = failureInjection;
        _paymentService = paymentService;
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    [HttpGet]
    public async Task<ActionResult<IEnumerable<Order>>> GetOrders()
    {
        using var activity = ActivitySource.StartActivity("GetOrders");
        
        try
        {
            // Check for injected failures
            await _failureInjection.MaybeInjectFailureAsync("GetOrders");
            
            // Try cache first
            var cacheKey = "orders:all";
            var cachedOrders = await _cacheService.GetAsync<List<Order>>(cacheKey);
            
            if (cachedOrders != null)
            {
                activity?.SetTag("cache.hit", true);
                _logger.LogInformation("Retrieved {Count} orders from cache", cachedOrders.Count);
                return Ok(cachedOrders);
            }

            activity?.SetTag("cache.hit", false);
            var orders = await _orderService.GetOrdersAsync();
            
            // Cache the results
            await _cacheService.SetAsync(cacheKey, orders, TimeSpan.FromMinutes(5));
            
            _logger.LogInformation("Retrieved {Count} orders from database", orders.Count());
            return Ok(orders);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving orders");
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpGet("{id}")]
    public async Task<ActionResult<Order>> GetOrder(int id)
    {
        using var activity = ActivitySource.StartActivity("GetOrder");
        activity?.SetTag("order.id", id);

        try
        {
            await _failureInjection.MaybeInjectFailureAsync("GetOrder");
            
            var order = await _orderService.GetOrderByIdAsync(id);
            if (order == null)
            {
                return NotFound();
            }

            return Ok(order);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving order {OrderId}", id);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpPost]
    public async Task<ActionResult<Order>> CreateOrder(CreateOrderRequest request)
    {
        using var activity = ActivitySource.StartActivity("CreateOrder");
        activity?.SetTag("order.customer_id", request.CustomerId);
        activity?.SetTag("order.total_amount", request.TotalAmount);

        try
        {
            await _failureInjection.MaybeInjectFailureAsync("CreateOrder");

            // Check inventory via downstream service
            var inventoryClient = _httpClientFactory.CreateClient("InventoryService");
            var inventoryResponse = await inventoryClient.GetAsync($"/api/inventory/check/{request.ProductId}");
            
            if (!inventoryResponse.IsSuccessStatusCode)
            {
                return BadRequest("Product not available");
            }

            // Create order
            var order = await _orderService.CreateOrderAsync(request);
            
            // Process payment
            var paymentRequest = new Services.PaymentRequest
            {
                OrderId = order.Id.ToString(),
                CustomerId = order.CustomerId,
                Amount = order.TotalAmount,
                Currency = "USD",
                PaymentMethod = new Services.PaymentMethodDetails
                {
                    Type = "credit_card",
                    CardNumber = "4111111111111111",
                    ExpiryMonth = "12",
                    ExpiryYear = "2025",
                    CVV = "123",
                    CardHolderName = "Test User"
                }
            };

            var paymentResponse = await _paymentService.ProcessPaymentAsync(paymentRequest);
            
            if (paymentResponse != null && paymentResponse.Status != Services.PaymentStatus.Failed)
            {
                order.PaymentId = paymentResponse.PaymentId.ToString();
                order.PaymentStatus = paymentResponse.Status.ToString();
                
                // Update order with payment info
                await _orderService.UpdateOrderPaymentAsync(order.Id, paymentResponse.PaymentId.ToString(), paymentResponse.Status.ToString());
                
                activity?.SetTag("payment.id", paymentResponse.PaymentId);
                activity?.SetTag("payment.status", paymentResponse.Status.ToString());
            }
            else
            {
                _logger.LogWarning("Payment processing failed for order {OrderId}", order.Id);
                order.PaymentStatus = "Failed";
            }
            
            // Send event to Event Hub
            await _eventHubService.SendOrderCreatedEventAsync(order);
            
            // Invalidate cache
            await _cacheService.RemoveAsync("orders:all");
            
            _logger.LogInformation("Created order {OrderId} for customer {CustomerId} with payment {PaymentId}", 
                order.Id, order.CustomerId, order.PaymentId ?? "none");
            
            return CreatedAtAction(nameof(GetOrder), new { id = order.Id }, order);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order");
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpPut("{id}/status")]
    public async Task<ActionResult> UpdateOrderStatus(int id, UpdateOrderStatusRequest request)
    {
        using var activity = ActivitySource.StartActivity("UpdateOrderStatus");
        activity?.SetTag("order.id", id);
        activity?.SetTag("order.status", request.Status);

        try
        {
            await _failureInjection.MaybeInjectFailureAsync("UpdateOrderStatus");
            
            var success = await _orderService.UpdateOrderStatusAsync(id, request.Status);
            if (!success)
            {
                return NotFound();
            }

            // Send status update event
            await _eventHubService.SendOrderStatusUpdatedEventAsync(id, request.Status);
            
            // Invalidate cache
            await _cacheService.RemoveAsync("orders:all");
            
            return NoContent();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating order status for order {OrderId}", id);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }
}
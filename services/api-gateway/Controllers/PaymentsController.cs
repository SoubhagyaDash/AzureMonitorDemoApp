using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using ApiGateway.Models;
using ApiGateway.Services;
using System.Text.Json;

namespace ApiGateway.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PaymentsController : ControllerBase
{
    private readonly HttpClient _paymentHttpClient;
    private readonly IEventHubService _eventHubService;
    private readonly IFailureInjectionService _failureInjection;
    private readonly ILogger<PaymentsController> _logger;

    private static readonly ActivitySource ActivitySource = new("ApiGateway.Payments");

    public PaymentsController(
        IHttpClientFactory httpClientFactory,
        IEventHubService eventHubService,
        IFailureInjectionService failureInjection,
        ILogger<PaymentsController> logger)
    {
        _paymentHttpClient = httpClientFactory.CreateClient("PaymentService");
        _eventHubService = eventHubService;
        _failureInjection = failureInjection;
        _logger = logger;
    }

    [HttpPost]
    public async Task<IActionResult> ProcessPayment([FromBody] PaymentRequest request)
    {
        using var activity = ActivitySource.StartActivity("ProcessPayment");
        activity?.SetTag("order.id", request.OrderId);
        activity?.SetTag("payment.amount", request.Amount);
        activity?.SetTag("payment.currency", request.Currency);

        try
        {
            _logger.LogInformation("Processing payment for order {OrderId}, amount {Amount} {Currency}", 
                request.OrderId, request.Amount, request.Currency);

            // Apply failure injection
            await _failureInjection.ApplyFailuresAsync("payment-gateway");

            // Forward to payment service
            var response = await _paymentHttpClient.PostAsJsonAsync("api/payments", request);
            
            if (response.IsSuccessStatusCode)
            {
                var paymentResponse = await response.Content.ReadFromJsonAsync<PaymentResponse>();
                
                activity?.SetTag("payment.id", paymentResponse?.PaymentId.ToString());
                activity?.SetTag("payment.status", paymentResponse?.Status.ToString());

                // Publish gateway event
                await _eventHubService.PublishEventAsync(new
                {
                    EventType = "PaymentRequested",
                    Source = "api-gateway",
                    OrderId = request.OrderId,
                    PaymentId = paymentResponse?.PaymentId,
                    Amount = request.Amount,
                    Currency = request.Currency,
                    Timestamp = DateTime.UtcNow
                });

                _logger.LogInformation("Payment processed successfully for order {OrderId}", request.OrderId);
                return Ok(paymentResponse);
            }
            else
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("Payment processing failed for order {OrderId}: {StatusCode} - {Error}", 
                    request.OrderId, response.StatusCode, errorContent);
                
                activity?.SetStatus(ActivityStatusCode.Error, $"Payment service returned {response.StatusCode}");
                return StatusCode((int)response.StatusCode, errorContent);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing payment for order {OrderId}", request.OrderId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpGet("{paymentId}")]
    public async Task<IActionResult> GetPayment(Guid paymentId)
    {
        using var activity = ActivitySource.StartActivity("GetPayment");
        activity?.SetTag("payment.id", paymentId.ToString());

        try
        {
            _logger.LogInformation("Retrieving payment {PaymentId}", paymentId);

            await _failureInjection.ApplyFailuresAsync("payment-lookup");

            var response = await _paymentHttpClient.GetAsync($"api/payments/{paymentId}");
            
            if (response.IsSuccessStatusCode)
            {
                var payment = await response.Content.ReadFromJsonAsync<object>();
                return Ok(payment);
            }
            else if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return NotFound();
            }
            else
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("Payment lookup failed for {PaymentId}: {StatusCode} - {Error}", 
                    paymentId, response.StatusCode, errorContent);
                
                return StatusCode((int)response.StatusCode, errorContent);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving payment {PaymentId}", paymentId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpPost("{paymentId}/refund")]
    public async Task<IActionResult> RefundPayment(Guid paymentId, [FromBody] RefundRequest request)
    {
        using var activity = ActivitySource.StartActivity("RefundPayment");
        activity?.SetTag("payment.id", paymentId.ToString());
        activity?.SetTag("refund.amount", request.Amount?.ToString());

        try
        {
            _logger.LogInformation("Processing refund for payment {PaymentId}, amount: {Amount}", 
                paymentId, request.Amount);

            await _failureInjection.ApplyFailuresAsync("payment-refund");

            var response = await _paymentHttpClient.PostAsJsonAsync($"api/payments/{paymentId}/refund", request);
            
            if (response.IsSuccessStatusCode)
            {
                var refundResponse = await response.Content.ReadFromJsonAsync<PaymentResponse>();
                
                activity?.SetTag("refund.status", refundResponse?.Status.ToString());

                // Publish gateway event
                await _eventHubService.PublishEventAsync(new
                {
                    EventType = "RefundRequested",
                    Source = "api-gateway",
                    PaymentId = paymentId,
                    RefundAmount = request.Amount,
                    Reason = request.Reason,
                    Timestamp = DateTime.UtcNow
                });

                _logger.LogInformation("Refund processed for payment {PaymentId}", paymentId);
                return Ok(refundResponse);
            }
            else
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("Refund processing failed for payment {PaymentId}: {StatusCode} - {Error}", 
                    paymentId, response.StatusCode, errorContent);
                
                return StatusCode((int)response.StatusCode, errorContent);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing refund for payment {PaymentId}", paymentId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpGet("order/{orderId}")]
    public async Task<IActionResult> GetPaymentsByOrder(string orderId)
    {
        using var activity = ActivitySource.StartActivity("GetPaymentsByOrder");
        activity?.SetTag("order.id", orderId);

        try
        {
            _logger.LogInformation("Retrieving payments for order {OrderId}", orderId);

            await _failureInjection.ApplyFailuresAsync("payment-order-lookup");

            var response = await _paymentHttpClient.GetAsync($"api/payments/order/{orderId}");
            
            if (response.IsSuccessStatusCode)
            {
                var payments = await response.Content.ReadFromJsonAsync<object>();
                return Ok(payments);
            }
            else
            {
                var errorContent = await response.Content.ReadAsStringAsync();
                _logger.LogWarning("Payment lookup failed for order {OrderId}: {StatusCode} - {Error}", 
                    orderId, response.StatusCode, errorContent);
                
                return StatusCode((int)response.StatusCode, errorContent);
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving payments for order {OrderId}", orderId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            return StatusCode(500, "Internal server error");
        }
    }
}

public class PaymentRequest
{
    public string OrderId { get; set; } = string.Empty;
    public string CustomerId { get; set; } = string.Empty;
    public decimal Amount { get; set; }
    public string Currency { get; set; } = "USD";
    public PaymentMethodDetails PaymentMethod { get; set; } = new();
}

public class PaymentMethodDetails
{
    public string Type { get; set; } = string.Empty;
    public string? CardNumber { get; set; }
    public string? ExpiryMonth { get; set; }
    public string? ExpiryYear { get; set; }
    public string? CVV { get; set; }
    public string? CardHolderName { get; set; }
    public string? PayPalEmail { get; set; }
    public string? BankAccount { get; set; }
    public string? RoutingNumber { get; set; }
}

public class PaymentResponse
{
    public Guid PaymentId { get; set; }
    public string Status { get; set; } = string.Empty;
    public string? TransactionId { get; set; }
    public string? Message { get; set; }
    public DateTime ProcessedAt { get; set; }
}

public class RefundRequest
{
    public decimal? Amount { get; set; }
    public string? Reason { get; set; }
}
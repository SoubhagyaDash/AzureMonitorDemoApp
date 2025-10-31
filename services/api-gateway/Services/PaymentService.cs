using System.Diagnostics;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace ApiGateway.Services;

public interface IPaymentService
{
    Task<PaymentResponse?> ProcessPaymentAsync(PaymentRequest request);
}

public class PaymentService : IPaymentService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<PaymentService> _logger;
    private static readonly ActivitySource ActivitySource = new("ApiGateway.PaymentService");

    public PaymentService(
        IHttpClientFactory httpClientFactory,
        ILogger<PaymentService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    public async Task<PaymentResponse?> ProcessPaymentAsync(PaymentRequest request)
    {
        using var activity = ActivitySource.StartActivity("ProcessPayment");
        activity?.SetTag("payment.amount", request.Amount);
        activity?.SetTag("payment.method", request.PaymentMethod);
        activity?.SetTag("payment.order_id", request.OrderId);

        try
        {
            var client = _httpClientFactory.CreateClient("PaymentService");
            var json = JsonSerializer.Serialize(request);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            _logger.LogInformation("Processing payment for order {OrderId}, amount {Amount}", 
                request.OrderId, request.Amount);

            var response = await client.PostAsync("/api/payments", content);
            
            if (response.IsSuccessStatusCode)
            {
                var responseJson = await response.Content.ReadAsStringAsync();
                var payment = JsonSerializer.Deserialize<PaymentResponse>(responseJson, 
                    new JsonSerializerOptions 
                    { 
                        PropertyNameCaseInsensitive = true,
                        Converters = { new JsonStringEnumConverter() }
                    });

                activity?.SetTag("payment.id", payment?.PaymentId);
                activity?.SetTag("payment.status", payment?.Status);

                _logger.LogInformation("Payment {PaymentId} processed with status {Status}", 
                    payment?.PaymentId, payment?.Status);

                return payment;
            }
            else
            {
                var error = await response.Content.ReadAsStringAsync();
                _logger.LogError("Payment processing failed: {Error}", error);
                activity?.SetStatus(ActivityStatusCode.Error, $"Payment failed: {response.StatusCode}");
                return null;
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing payment for order {OrderId}", request.OrderId);
            activity?.SetStatus(ActivityStatusCode.Error, ex.Message);
            throw;
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
    public string Type { get; set; } = "credit_card";
    public string? CardNumber { get; set; }
    public string? ExpiryMonth { get; set; }
    public string? ExpiryYear { get; set; }
    public string? CVV { get; set; }
    public string? CardHolderName { get; set; }
}

public class PaymentResponse
{
    public Guid PaymentId { get; set; }
    public PaymentStatus Status { get; set; }
    public string? TransactionId { get; set; }
    public string? Message { get; set; }
    public DateTime ProcessedAt { get; set; }
}

public enum PaymentStatus
{
    Pending = 0,
    Processing = 1,
    Completed = 2,
    Failed = 3,
    Refunded = 4,
    Cancelled = 5
}

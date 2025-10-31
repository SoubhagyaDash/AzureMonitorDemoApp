using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Distributed;
using PaymentService.Data;
using PaymentService.Models;
using System.Text.Json;

namespace PaymentService.Services;

public interface IPaymentProcessorService
{
    Task<PaymentResponse> ProcessPaymentAsync(PaymentRequest request);
    Task<Payment?> GetPaymentAsync(Guid paymentId);
    Task<IEnumerable<Payment>> GetPaymentsByOrderAsync(string orderId);
    Task<IEnumerable<Payment>> GetPaymentsByCustomerAsync(string customerId);
    Task<PaymentResponse> RefundPaymentAsync(RefundRequest request);
    Task<PaymentResponse> CancelPaymentAsync(Guid paymentId);
}

public class PaymentProcessorService : IPaymentProcessorService
{
    private readonly PaymentDbContext _context;
    private readonly IDistributedCache _cache;
    private readonly IEventHubService _eventHub;
    private readonly ILogger<PaymentProcessorService> _logger;

    public PaymentProcessorService(
        PaymentDbContext context,
        IDistributedCache cache,
        IEventHubService eventHub,
        ILogger<PaymentProcessorService> logger)
    {
        _context = context;
        _cache = cache;
        _eventHub = eventHub;
        _logger = logger;
    }

    public async Task<PaymentResponse> ProcessPaymentAsync(PaymentRequest request)
    {
        var payment = new Payment
        {
            OrderId = request.OrderId,
            CustomerId = request.CustomerId,
            Amount = request.Amount,
            Currency = request.Currency,
            PaymentMethod = request.PaymentMethod.Type,
            Status = PaymentStatus.Processing,
            Metadata = new Dictionary<string, object>
            {
                ["payment_method_details"] = JsonSerializer.Serialize(request.PaymentMethod),
                ["user_agent"] = "PaymentService/1.0",
                ["ip_address"] = "127.0.0.1" // In real app, get from request
            }
        };

        _context.Payments.Add(payment);
        await _context.SaveChangesAsync();

        _logger.LogInformation("Payment {PaymentId} created for order {OrderId}", payment.Id, request.OrderId);

        // Simulate payment processing
        var success = await SimulatePaymentGatewayAsync(payment);

        payment.Status = success ? PaymentStatus.Completed : PaymentStatus.Failed;
        payment.ProcessedAt = DateTime.UtcNow;
        payment.TransactionId = success ? $"txn_{Guid.NewGuid():N}" : null;
        payment.FailureReason = success ? null : GetRandomFailureReason();

        await _context.SaveChangesAsync();

        // Cache the result
        var cacheKey = $"payment:{payment.Id}";
        var cacheValue = JsonSerializer.Serialize(payment);
        await _cache.SetStringAsync(cacheKey, cacheValue, new DistributedCacheEntryOptions
        {
            AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30)
        });

        // Publish event
        await _eventHub.PublishPaymentEventAsync(new
        {
            EventType = "PaymentProcessed",
            PaymentId = payment.Id,
            OrderId = payment.OrderId,
            CustomerId = payment.CustomerId,
            Amount = payment.Amount,
            Currency = payment.Currency,
            Status = payment.Status.ToString(),
            TransactionId = payment.TransactionId,
            ProcessedAt = payment.ProcessedAt
        });

        return new PaymentResponse
        {
            PaymentId = payment.Id,
            Status = payment.Status,
            TransactionId = payment.TransactionId,
            Message = success ? "Payment processed successfully" : payment.FailureReason,
            ProcessedAt = payment.ProcessedAt.Value
        };
    }

    public async Task<Payment?> GetPaymentAsync(Guid paymentId)
    {
        // Try cache first
        var cacheKey = $"payment:{paymentId}";
        var cachedPayment = await _cache.GetStringAsync(cacheKey);
        
        if (cachedPayment != null)
        {
            _logger.LogDebug("Payment {PaymentId} retrieved from cache", paymentId);
            return JsonSerializer.Deserialize<Payment>(cachedPayment);
        }

        // Fallback to database
        var payment = await _context.Payments
            .FirstOrDefaultAsync(p => p.Id == paymentId);

        if (payment != null)
        {
            // Update cache
            var cacheValue = JsonSerializer.Serialize(payment);
            await _cache.SetStringAsync(cacheKey, cacheValue, new DistributedCacheEntryOptions
            {
                AbsoluteExpirationRelativeToNow = TimeSpan.FromMinutes(30)
            });
        }

        return payment;
    }

    public async Task<IEnumerable<Payment>> GetPaymentsByOrderAsync(string orderId)
    {
        return await _context.Payments
            .Where(p => p.OrderId == orderId)
            .OrderByDescending(p => p.CreatedAt)
            .ToListAsync();
    }

    public async Task<IEnumerable<Payment>> GetPaymentsByCustomerAsync(string customerId)
    {
        return await _context.Payments
            .Where(p => p.CustomerId == customerId)
            .OrderByDescending(p => p.CreatedAt)
            .Take(50) // Limit to recent payments
            .ToListAsync();
    }

    public async Task<PaymentResponse> RefundPaymentAsync(RefundRequest request)
    {
        var payment = await GetPaymentAsync(request.PaymentId);
        
        if (payment == null)
            throw new ArgumentException("Payment not found");

        if (payment.Status != PaymentStatus.Completed)
            throw new ArgumentException("Payment cannot be refunded");

        var refundAmount = request.Amount ?? payment.Amount;
        
        if (refundAmount > payment.Amount)
            throw new ArgumentException("Refund amount cannot exceed payment amount");

        // Create refund payment record
        var refund = new Payment
        {
            OrderId = payment.OrderId,
            CustomerId = payment.CustomerId,
            Amount = -refundAmount, // Negative amount for refund
            Currency = payment.Currency,
            PaymentMethod = payment.PaymentMethod,
            Status = PaymentStatus.Processing,
            Metadata = new Dictionary<string, object>
            {
                ["refund_reason"] = request.Reason ?? "Customer requested refund",
                ["original_payment_id"] = payment.Id.ToString(),
                ["refund_type"] = request.Amount.HasValue ? "partial" : "full"
            }
        };

        _context.Payments.Add(refund);
        await _context.SaveChangesAsync();

        // Simulate refund processing
        var success = await SimulateRefundGatewayAsync(refund);

        refund.Status = success ? PaymentStatus.Refunded : PaymentStatus.Failed;
        refund.ProcessedAt = DateTime.UtcNow;
        refund.TransactionId = success ? $"rfnd_{Guid.NewGuid():N}" : null;
        refund.FailureReason = success ? null : "Refund gateway error";

        await _context.SaveChangesAsync();

        // Publish refund event
        await _eventHub.PublishPaymentEventAsync(new
        {
            EventType = "PaymentRefunded",
            PaymentId = refund.Id,
            OriginalPaymentId = payment.Id,
            OrderId = refund.OrderId,
            CustomerId = refund.CustomerId,
            Amount = Math.Abs(refund.Amount),
            Currency = refund.Currency,
            Status = refund.Status.ToString(),
            ProcessedAt = refund.ProcessedAt
        });

        return new PaymentResponse
        {
            PaymentId = refund.Id,
            Status = refund.Status,
            TransactionId = refund.TransactionId,
            Message = success ? "Refund processed successfully" : refund.FailureReason,
            ProcessedAt = refund.ProcessedAt.Value
        };
    }

    public async Task<PaymentResponse> CancelPaymentAsync(Guid paymentId)
    {
        var payment = await GetPaymentAsync(paymentId);
        
        if (payment == null)
            throw new ArgumentException("Payment not found");

        if (payment.Status != PaymentStatus.Pending && payment.Status != PaymentStatus.Processing)
            throw new ArgumentException("Payment cannot be cancelled");

        payment.Status = PaymentStatus.Cancelled;
        payment.ProcessedAt = DateTime.UtcNow;
        payment.FailureReason = "Cancelled by request";

        await _context.SaveChangesAsync();

        // Invalidate cache
        var cacheKey = $"payment:{paymentId}";
        await _cache.RemoveAsync(cacheKey);

        // Publish cancellation event
        await _eventHub.PublishPaymentEventAsync(new
        {
            EventType = "PaymentCancelled",
            PaymentId = payment.Id,
            OrderId = payment.OrderId,
            CustomerId = payment.CustomerId,
            Amount = payment.Amount,
            Currency = payment.Currency,
            ProcessedAt = payment.ProcessedAt
        });

        return new PaymentResponse
        {
            PaymentId = payment.Id,
            Status = payment.Status,
            Message = "Payment cancelled successfully",
            ProcessedAt = payment.ProcessedAt.Value
        };
    }

    private async Task<bool> SimulatePaymentGatewayAsync(Payment payment)
    {
        // Simulate gateway processing time
        await Task.Delay(Random.Shared.Next(100, 500));

        // Simulate different failure scenarios based on payment method
        return payment.PaymentMethod switch
        {
            "credit_card" => Random.Shared.NextDouble() > 0.05, // 5% failure rate
            "paypal" => Random.Shared.NextDouble() > 0.02, // 2% failure rate
            "bank_transfer" => Random.Shared.NextDouble() > 0.01, // 1% failure rate
            _ => Random.Shared.NextDouble() > 0.1 // 10% failure rate for unknown methods
        };
    }

    private async Task<bool> SimulateRefundGatewayAsync(Payment refund)
    {
        // Simulate refund processing time
        await Task.Delay(Random.Shared.Next(200, 800));

        // Refunds are generally more reliable than payments
        return Random.Shared.NextDouble() > 0.02; // 2% failure rate
    }

    private static string GetRandomFailureReason()
    {
        var reasons = new[]
        {
            "Insufficient funds",
            "Card declined",
            "Invalid card details",
            "Card expired",
            "Gateway timeout",
            "Fraud detection triggered",
            "Daily limit exceeded",
            "Invalid CVV"
        };

        return reasons[Random.Shared.Next(reasons.Length)];
    }
}
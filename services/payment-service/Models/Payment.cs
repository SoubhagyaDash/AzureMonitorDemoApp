using System.ComponentModel.DataAnnotations;

namespace PaymentService.Models;

public class Payment
{
    public Guid Id { get; set; } = Guid.NewGuid();
    
    [Required]
    public string OrderId { get; set; } = string.Empty;
    
    [Required]
    public string CustomerId { get; set; } = string.Empty;
    
    [Required]
    [Range(0.01, double.MaxValue, ErrorMessage = "Amount must be greater than 0")]
    public decimal Amount { get; set; }
    
    [Required]
    public string Currency { get; set; } = "USD";
    
    [Required]
    public string PaymentMethod { get; set; } = string.Empty;
    
    public PaymentStatus Status { get; set; } = PaymentStatus.Pending;
    
    public string? TransactionId { get; set; }
    
    public string? FailureReason { get; set; }
    
    public DateTime CreatedAt { get; set; } = DateTime.UtcNow;
    
    public DateTime? ProcessedAt { get; set; }
    
    public Dictionary<string, object> Metadata { get; set; } = new();
}

public enum PaymentStatus
{
    Pending,
    Processing,
    Completed,
    Failed,
    Refunded,
    Cancelled
}

public class PaymentRequest
{
    [Required]
    public string OrderId { get; set; } = string.Empty;
    
    [Required]
    public string CustomerId { get; set; } = string.Empty;
    
    [Required]
    [Range(0.01, double.MaxValue)]
    public decimal Amount { get; set; }
    
    public string Currency { get; set; } = "USD";
    
    [Required]
    public PaymentMethodDetails PaymentMethod { get; set; } = new();
}

public class PaymentMethodDetails
{
    [Required]
    public string Type { get; set; } = string.Empty; // "credit_card", "paypal", "bank_transfer"
    
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
    
    public PaymentStatus Status { get; set; }
    
    public string? TransactionId { get; set; }
    
    public string? Message { get; set; }
    
    public DateTime ProcessedAt { get; set; }
}

public class RefundRequest
{
    [Required]
    public Guid PaymentId { get; set; }
    
    [Range(0.01, double.MaxValue)]
    public decimal? Amount { get; set; } // Null for full refund
    
    public string? Reason { get; set; }
}
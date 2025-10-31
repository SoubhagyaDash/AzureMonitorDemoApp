using Microsoft.AspNetCore.Mvc;
using PaymentService.Models;
using PaymentService.Services;

namespace PaymentService.Controllers;

[ApiController]
[Route("api/[controller]")]
public class PaymentsController : ControllerBase
{
    private readonly IPaymentProcessorService _paymentProcessor;
    private readonly IFailureInjectionService _failureInjection;
    private readonly ILogger<PaymentsController> _logger;

    public PaymentsController(
        IPaymentProcessorService paymentProcessor,
        IFailureInjectionService failureInjection,
        ILogger<PaymentsController> logger)
    {
        _paymentProcessor = paymentProcessor;
        _failureInjection = failureInjection;
        _logger = logger;
    }

    [HttpPost]
    public async Task<ActionResult<PaymentResponse>> ProcessPayment([FromBody] PaymentRequest request)
    {
        try
        {
            _logger.LogInformation("Processing payment for order {OrderId}, amount {Amount} {Currency}", 
                request.OrderId, request.Amount, request.Currency);

            // Apply failure injection
            await _failureInjection.ApplyFailuresAsync("payment-processing");

            var response = await _paymentProcessor.ProcessPaymentAsync(request);
            
            _logger.LogInformation("Payment processed for order {OrderId}, status: {Status}", 
                request.OrderId, response.Status);
            
            return response.Status switch
            {
                PaymentStatus.Completed => Ok(response),
                PaymentStatus.Failed => BadRequest(response),
                _ => Accepted(response)
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing payment for order {OrderId}", request.OrderId);
            return StatusCode(500, new PaymentResponse 
            { 
                Status = PaymentStatus.Failed, 
                Message = "Internal server error" 
            });
        }
    }

    [HttpGet("{paymentId}")]
    public async Task<ActionResult<Payment>> GetPayment(Guid paymentId)
    {
        try
        {
            _logger.LogInformation("Retrieving payment {PaymentId}", paymentId);

            await _failureInjection.ApplyFailuresAsync("payment-lookup");

            var payment = await _paymentProcessor.GetPaymentAsync(paymentId);
            if (payment == null)
            {
                _logger.LogWarning("Payment {PaymentId} not found", paymentId);
                return NotFound();
            }

            return Ok(payment);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving payment {PaymentId}", paymentId);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpGet("order/{orderId}")]
    public async Task<ActionResult<IEnumerable<Payment>>> GetPaymentsByOrder(string orderId)
    {
        try
        {
            _logger.LogInformation("Retrieving payments for order {OrderId}", orderId);

            await _failureInjection.ApplyFailuresAsync("payment-order-lookup");

            var payments = await _paymentProcessor.GetPaymentsByOrderAsync(orderId);
            return Ok(payments);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving payments for order {OrderId}", orderId);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpPost("{paymentId}/refund")]
    public async Task<ActionResult<PaymentResponse>> RefundPayment(Guid paymentId, [FromBody] RefundRequest request)
    {
        try
        {
            _logger.LogInformation("Processing refund for payment {PaymentId}, amount: {Amount}", 
                paymentId, request.Amount);

            await _failureInjection.ApplyFailuresAsync("payment-refund");

            request.PaymentId = paymentId;
            var response = await _paymentProcessor.RefundPaymentAsync(request);
            
            _logger.LogInformation("Refund processed for payment {PaymentId}, status: {Status}", 
                paymentId, response.Status);
            
            return Ok(response);
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning(ex, "Invalid refund request for payment {PaymentId}", paymentId);
            return BadRequest(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing refund for payment {PaymentId}", paymentId);
            return StatusCode(500, new PaymentResponse 
            { 
                Status = PaymentStatus.Failed, 
                Message = "Internal server error" 
            });
        }
    }

    [HttpGet("customer/{customerId}")]
    public async Task<ActionResult<IEnumerable<Payment>>> GetPaymentsByCustomer(string customerId)
    {
        try
        {
            _logger.LogInformation("Retrieving payments for customer {CustomerId}", customerId);

            await _failureInjection.ApplyFailuresAsync("payment-customer-lookup");

            var payments = await _paymentProcessor.GetPaymentsByCustomerAsync(customerId);
            return Ok(payments);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error retrieving payments for customer {CustomerId}", customerId);
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpPost("{paymentId}/cancel")]
    public async Task<ActionResult<PaymentResponse>> CancelPayment(Guid paymentId)
    {
        try
        {
            _logger.LogInformation("Cancelling payment {PaymentId}", paymentId);

            await _failureInjection.ApplyFailuresAsync("payment-cancellation");

            var response = await _paymentProcessor.CancelPaymentAsync(paymentId);
            
            _logger.LogInformation("Payment cancellation processed for {PaymentId}, status: {Status}", 
                paymentId, response.Status);
            
            return Ok(response);
        }
        catch (ArgumentException ex)
        {
            _logger.LogWarning(ex, "Invalid cancellation request for payment {PaymentId}", paymentId);
            return BadRequest(ex.Message);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error cancelling payment {PaymentId}", paymentId);
            return StatusCode(500, new PaymentResponse 
            { 
                Status = PaymentStatus.Failed, 
                Message = "Internal server error" 
            });
        }
    }
}
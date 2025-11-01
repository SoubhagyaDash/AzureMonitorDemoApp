using ApiGateway.Models;
using System.Text.Json;
using System.Text;

namespace ApiGateway.Services;

public interface IOrderService
{
    Task<IEnumerable<Order>> GetOrdersAsync();
    Task<Order?> GetOrderByIdAsync(int id);
    Task<Order> CreateOrderAsync(CreateOrderRequest request);
    Task<bool> UpdateOrderStatusAsync(int id, string status);
    Task<bool> UpdateOrderPaymentAsync(int id, string paymentId, string paymentStatus);
}

public class OrderService : IOrderService
{
    private readonly HttpClient _httpClient;
    private readonly ILogger<OrderService> _logger;
    private readonly JsonSerializerOptions _jsonOptions;

    public OrderService(IHttpClientFactory httpClientFactory, ILogger<OrderService> logger)
    {
        _httpClient = httpClientFactory.CreateClient("OrderService");
        _logger = logger;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            WriteIndented = false
        };
    }

    public async Task<IEnumerable<Order>> GetOrdersAsync()
    {
        try
        {
            var response = await _httpClient.GetAsync("/api/orders");
            response.EnsureSuccessStatusCode();
            
            var content = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<List<Order>>(content, _jsonOptions) ?? new List<Order>();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching orders from Order Service");
            return new List<Order>();
        }
    }

    public async Task<Order?> GetOrderByIdAsync(int id)
    {
        try
        {
            var response = await _httpClient.GetAsync($"/api/orders/{id}");
            
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return null;
            }
            
            response.EnsureSuccessStatusCode();
            var content = await response.Content.ReadAsStringAsync();
            return JsonSerializer.Deserialize<Order>(content, _jsonOptions);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error fetching order {OrderId} from Order Service", id);
            return null;
        }
    }

    public async Task<Order> CreateOrderAsync(CreateOrderRequest request)
    {
        try
        {
            var json = JsonSerializer.Serialize(request, _jsonOptions);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            _logger.LogInformation("Calling Order Service to create order for customer {CustomerId}", request.CustomerId);
            
            var response = await _httpClient.PostAsync("/api/orders", content);
            response.EnsureSuccessStatusCode();
            
            var responseContent = await response.Content.ReadAsStringAsync();
            var order = JsonSerializer.Deserialize<Order>(responseContent, _jsonOptions);
            
            if (order == null)
            {
                throw new Exception("Order Service returned null order");
            }
            
            _logger.LogInformation("Order {OrderId} created successfully via Order Service", order.Id);
            return order;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error creating order via Order Service");
            throw;
        }
    }

    public async Task<bool> UpdateOrderStatusAsync(int id, string status)
    {
        try
        {
            var updateRequest = new { status };
            var json = JsonSerializer.Serialize(updateRequest, _jsonOptions);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PutAsync($"/api/orders/{id}/status", content);
            
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return false;
            }
            
            response.EnsureSuccessStatusCode();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating order {OrderId} status", id);
            return false;
        }
    }

    public async Task<bool> UpdateOrderPaymentAsync(int id, string paymentId, string paymentStatus)
    {
        try
        {
            var updateRequest = new { paymentId, paymentStatus };
            var json = JsonSerializer.Serialize(updateRequest, _jsonOptions);
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            
            var response = await _httpClient.PutAsync($"/api/orders/{id}/payment", content);
            
            if (response.StatusCode == System.Net.HttpStatusCode.NotFound)
            {
                return false;
            }
            
            response.EnsureSuccessStatusCode();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating order {OrderId} payment info", id);
            return false;
        }
    }
}
using Microsoft.AspNetCore.Mvc;
using System.Diagnostics;
using System.Text.Json;

namespace ApiGateway.Controllers;

[ApiController]
[Route("api/[controller]")]
public class InventoryController : ControllerBase
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly ILogger<InventoryController> _logger;
    private static readonly ActivitySource ActivitySource = new("ApiGateway.Inventory");

    public InventoryController(
        IHttpClientFactory httpClientFactory,
        ILogger<InventoryController> logger)
    {
        _httpClientFactory = httpClientFactory;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> GetInventory()
    {
        using var activity = ActivitySource.StartActivity("GetInventory");
        
        try
        {
            var client = _httpClientFactory.CreateClient("InventoryService");
            var response = await client.GetAsync("/api/inventory");
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Failed to get inventory. Status: {StatusCode}", response.StatusCode);
                return StatusCode((int)response.StatusCode, new { error = "Failed to retrieve inventory" });
            }

            var content = await response.Content.ReadAsStringAsync();
            activity?.SetTag("inventory.item_count", JsonDocument.Parse(content).RootElement.GetArrayLength());
            
            return Content(content, "application/json");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting inventory");
            activity?.SetTag("error", true);
            activity?.SetTag("error.message", ex.Message);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    [HttpGet("{id}")]
    public async Task<IActionResult> GetInventoryItem(int id)
    {
        using var activity = ActivitySource.StartActivity("GetInventoryItem");
        activity?.SetTag("inventory.item_id", id);
        
        try
        {
            var client = _httpClientFactory.CreateClient("InventoryService");
            var response = await client.GetAsync($"/api/inventory/{id}");
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Failed to get inventory item {Id}. Status: {StatusCode}", id, response.StatusCode);
                return StatusCode((int)response.StatusCode, new { error = $"Failed to retrieve inventory item {id}" });
            }

            var content = await response.Content.ReadAsStringAsync();
            return Content(content, "application/json");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting inventory item {Id}", id);
            activity?.SetTag("error", true);
            activity?.SetTag("error.message", ex.Message);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    [HttpPost("{id}/check")]
    public async Task<IActionResult> CheckInventory(int id, [FromBody] CheckInventoryRequest request)
    {
        using var activity = ActivitySource.StartActivity("CheckInventory");
        activity?.SetTag("inventory.item_id", id);
        activity?.SetTag("inventory.quantity", request.Quantity);
        
        try
        {
            var client = _httpClientFactory.CreateClient("InventoryService");
            var response = await client.PostAsJsonAsync($"/api/inventory/{id}/check", request);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Failed to check inventory for item {Id}. Status: {StatusCode}", id, response.StatusCode);
                return StatusCode((int)response.StatusCode, new { error = $"Failed to check inventory for item {id}" });
            }

            var content = await response.Content.ReadAsStringAsync();
            return Content(content, "application/json");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error checking inventory for item {Id}", id);
            activity?.SetTag("error", true);
            activity?.SetTag("error.message", ex.Message);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }

    [HttpPost("{id}/reserve")]
    public async Task<IActionResult> ReserveInventory(int id, [FromBody] ReserveInventoryRequest request)
    {
        using var activity = ActivitySource.StartActivity("ReserveInventory");
        activity?.SetTag("inventory.item_id", id);
        activity?.SetTag("inventory.quantity", request.Quantity);
        
        try
        {
            var client = _httpClientFactory.CreateClient("InventoryService");
            var response = await client.PostAsJsonAsync($"/api/inventory/{id}/reserve", request);
            
            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Failed to reserve inventory for item {Id}. Status: {StatusCode}", id, response.StatusCode);
                return StatusCode((int)response.StatusCode, new { error = $"Failed to reserve inventory for item {id}" });
            }

            var content = await response.Content.ReadAsStringAsync();
            return Content(content, "application/json");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error reserving inventory for item {Id}", id);
            activity?.SetTag("error", true);
            activity?.SetTag("error.message", ex.Message);
            return StatusCode(500, new { error = "Internal server error" });
        }
    }
}

public record CheckInventoryRequest(int Quantity);
public record ReserveInventoryRequest(int Quantity, string OrderId);

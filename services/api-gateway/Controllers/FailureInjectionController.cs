using Microsoft.AspNetCore.Mvc;
using System.ComponentModel.DataAnnotations;
using ApiGateway.Services;

namespace OTelDemo.ApiGateway.Controllers;

[ApiController]
[Route("api/[controller]")]
public class FailureInjectionController : ControllerBase
{
    private readonly IFailureInjectionService _failureInjectionService;
    private readonly ILogger<FailureInjectionController> _logger;

    public FailureInjectionController(
        IFailureInjectionService failureInjectionService,
        ILogger<FailureInjectionController> logger)
    {
        _failureInjectionService = failureInjectionService;
        _logger = logger;
    }

    [HttpGet]
    public async Task<IActionResult> GetConfiguration()
    {
        try
        {
            var config = await _failureInjectionService.GetCurrentConfigurationAsync();
            return Ok(config);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting failure injection configuration");
            return StatusCode(500, new { error = "Failed to get configuration" });
        }
    }

    [HttpPost]
    public async Task<IActionResult> UpdateConfiguration([FromBody] FailureInjectionConfigDto config)
    {
        try
        {
            if (!ModelState.IsValid)
            {
                return BadRequest(ModelState);
            }

            await _failureInjectionService.UpdateConfigurationAsync(config);
            
            _logger.LogInformation("Failure injection configuration updated: {@Config}", config);
            
            return Ok(new 
            { 
                message = "Configuration updated successfully",
                config = config,
                timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error updating failure injection configuration");
            return StatusCode(500, new { error = "Failed to update configuration" });
        }
    }

    [HttpPost("reset")]
    public async Task<IActionResult> ResetConfiguration()
    {
        try
        {
            await _failureInjectionService.ResetToDefaultsAsync();
            _logger.LogInformation("Failure injection configuration reset to defaults");
            
            return Ok(new 
            { 
                message = "Configuration reset to defaults",
                timestamp = DateTime.UtcNow
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error resetting failure injection configuration");
            return StatusCode(500, new { error = "Failed to reset configuration" });
        }
    }

    [HttpGet("status")]
    public async Task<IActionResult> GetStatus()
    {
        try
        {
            var status = await _failureInjectionService.GetStatusAsync();
            return Ok(status);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting failure injection status");
            return StatusCode(500, new { error = "Failed to get status" });
        }
    }
}

public class FailureInjectionConfigDto
{
    [Required]
    public bool Enabled { get; set; }

    public LatencyConfigDto? Latency { get; set; }
    public ErrorConfigDto? Errors { get; set; }
}

public class LatencyConfigDto
{
    [Range(0.0, 1.0)]
    public double Probability { get; set; }

    [Range(0, 60000)]
    public int MinDelayMs { get; set; }

    [Range(0, 60000)]
    public int MaxDelayMs { get; set; }
}

public class ErrorConfigDto
{
    [Range(0.0, 1.0)]
    public double Probability { get; set; }

    public string[]? Types { get; set; }
}
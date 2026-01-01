using Microsoft.AspNetCore.Mvc;
using VpnService.Application.DTOs;
using VpnService.Application.UseCases;
using VpnService.Infrastructure.Repositories;

namespace VpnService.Api.Controllers;

[ApiController]
[Route("api/v1/[controller]")]
public class PeersController : ControllerBase
{
    private readonly IPeerRepository _peerRepository;
    private readonly ILogger<PeersController> _logger;

    public PeersController(IPeerRepository peerRepository, ILogger<PeersController> logger)
    {
        _peerRepository = peerRepository;
        _logger = logger;
    }

    [HttpPost]
    [ProducesResponseType(typeof(PeerResponse), StatusCodes.Status201Created)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<ActionResult<PeerResponse>> CreatePeer([FromBody] CreatePeerRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.PublicKey) || string.IsNullOrWhiteSpace(request.AssignedIp))
            return BadRequest("PublicKey and AssignedIp are required");

        try
        {
            var handler = new RegisterPeerHandler(_peerRepository);
            var command = new RegisterPeerCommand
            {
                PublicKey = request.PublicKey,
                AssignedIp = request.AssignedIp,
                VpnServerId = request.VpnServerId
            };

            var result = await handler.HandleAsync(command);
            _logger.LogInformation($"Peer created: {result.Id}");
            return CreatedAtAction(nameof(GetPeer), new { id = result.Id }, result);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning($"Failed to create peer: {ex.Message}");
            return BadRequest(ex.Message);
        }
    }

    [HttpGet]
    [ProducesResponseType(typeof(ListPeersResponse), StatusCodes.Status200OK)]
    public async Task<ActionResult<ListPeersResponse>> ListPeers()
    {
        try
        {
            var handler = new ListPeersHandler(_peerRepository);
            var result = await handler.HandleAsync();
            _logger.LogInformation($"Listed {result.Peers.Count()} peers");
            return Ok(result);
        }
        catch (Exception ex)
        {
            _logger.LogError($"Error listing peers: {ex.Message}");
            return StatusCode(500, "Internal server error");
        }
    }

    [HttpGet("{id}")]
    [ProducesResponseType(typeof(PeerResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PeerResponse>> GetPeer(Guid id)
    {
        try
        {
            var handler = new GetPeerConfigHandler(_peerRepository);
            var command = new GetPeerConfigCommand { PeerId = id };
            var result = await handler.HandleAsync(command);
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning($"Peer not found: {id}");
            return NotFound(ex.Message);
        }
    }

    [HttpDelete("{id}")]
    [ProducesResponseType(typeof(PeerResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<ActionResult<PeerResponse>> RevokePeer(Guid id)
    {
        try
        {
            var handler = new RevokePeerHandler(_peerRepository);
            var command = new RevokePeerCommand { PeerId = id };
            var result = await handler.HandleAsync(command);
            _logger.LogInformation($"Peer revoked: {id}");
            return Ok(result);
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogWarning($"Failed to revoke peer: {ex.Message}");
            return NotFound(ex.Message);
        }
    }
}

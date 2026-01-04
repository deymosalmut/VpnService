using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.Linq;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using VpnService.Infrastructure.Abstractions.WireGuard;

namespace VpnService.Infrastructure.WireGuard;

public sealed class LinuxWireGuardStateReader : IWireGuardStateReader
{
    private readonly ILogger<LinuxWireGuardStateReader> _logger;

    public LinuxWireGuardStateReader(ILogger<LinuxWireGuardStateReader> logger)
    {
        _logger = logger;
    }

    public async Task<string> ReadStateJsonAsync(string iface, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(iface))
            throw new ArgumentException("iface is required", nameof(iface));

        foreach (var ch in iface)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '-'))
                throw new ArgumentException("iface contains invalid characters", nameof(iface));
        }

        var psi = new ProcessStartInfo
        {
            FileName = "wg",
            ArgumentList = { "show", iface, "dump" },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = new Process { StartInfo = psi };

        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "wg executable not found or failed to start.");
            throw new InvalidOperationException("wg not found");
        }

        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

        await proc.WaitForExitAsync(ct);

        var stdout = (await stdoutTask).Trim();
        var stderr = (await stderrTask).Trim();

        if (proc.ExitCode != 0)
        {
            if (IsInterfaceNotFound(stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg show dump failed. iface={Iface} exit={Exit} err={Err}", iface, proc.ExitCode, stderr);
            throw new InvalidOperationException($"wg show dump failed (exit={proc.ExitCode}): {stderr}");
        }

        if (string.IsNullOrWhiteSpace(stdout))
            throw new WireGuardInterfaceNotFoundException(iface);

        var lines = stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);
        if (lines.Length == 0)
            throw new WireGuardInterfaceNotFoundException(iface);

        var ifaceInfo = ParseInterfaceLine(lines[0], iface);
        var peers = new List<WireGuardPeerDto>();

        for (var i = 1; i < lines.Length; i++)
        {
            peers.Add(ParsePeerLine(lines[i], iface));
        }

        var dto = new WireGuardStateDto
        {
            Iface = iface,
            GeneratedAtUtc = DateTime.UtcNow,
            Interface = ifaceInfo,
            Peers = peers
        };

        return JsonSerializer.Serialize(dto);
    }

    private static bool IsInterfaceNotFound(string stderr)
    {
        if (string.IsNullOrWhiteSpace(stderr))
            return false;

        var message = stderr.ToLowerInvariant();
        return message.Contains("no such device") ||
               message.Contains("not found") ||
               message.Contains("does not exist");
    }

    private static WireGuardInterfaceDto ParseInterfaceLine(string line, string iface)
    {
        var parts = line.Split('\t');
        if (parts.Length < 3)
            throw new InvalidOperationException($"wg dump invalid interface line for {iface}");

        if (!int.TryParse(parts[2], NumberStyles.Integer, CultureInfo.InvariantCulture, out var listenPort))
            throw new InvalidOperationException($"wg dump invalid listen port for {iface}");

        return new WireGuardInterfaceDto
        {
            PublicKey = parts[1],
            ListenPort = listenPort
        };
    }

    private static WireGuardPeerDto ParsePeerLine(string line, string iface)
    {
        var parts = line.Split('\t');
        if (parts.Length < 8)
            throw new InvalidOperationException($"wg dump invalid peer line for {iface}");

        var presharedKeyRaw = parts[1];
        var endpointRaw = parts[2];
        var allowedIpsRaw = parts[3];
        var latestHandshakeRaw = parts[4];
        var rxRaw = parts[5];
        var txRaw = parts[6];
        var keepaliveRaw = parts[7];

        if (!long.TryParse(latestHandshakeRaw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var latestHandshake))
            throw new InvalidOperationException($"wg dump invalid latest handshake for {iface}");

        if (!long.TryParse(rxRaw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var rxBytes))
            throw new InvalidOperationException($"wg dump invalid rx bytes for {iface}");

        if (!long.TryParse(txRaw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var txBytes))
            throw new InvalidOperationException($"wg dump invalid tx bytes for {iface}");

        int? persistentKeepalive = null;
        if (!string.IsNullOrWhiteSpace(keepaliveRaw) && !string.Equals(keepaliveRaw, "off", StringComparison.OrdinalIgnoreCase))
        {
            if (!int.TryParse(keepaliveRaw, NumberStyles.Integer, CultureInfo.InvariantCulture, out var keepalive))
                throw new InvalidOperationException($"wg dump invalid keepalive for {iface}");
            persistentKeepalive = keepalive;
        }

        var allowedIps = string.IsNullOrWhiteSpace(allowedIpsRaw)
            ? Array.Empty<string>()
            : allowedIpsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries).Select(ip => ip.Trim()).ToArray();

        var presharedKey = !string.IsNullOrWhiteSpace(presharedKeyRaw) && presharedKeyRaw != "(none)";
        var endpoint = string.IsNullOrWhiteSpace(endpointRaw) || endpointRaw == "(none)" ? null : endpointRaw;

        return new WireGuardPeerDto
        {
            PublicKey = parts[0],
            PresharedKey = presharedKey,
            Endpoint = endpoint,
            AllowedIps = allowedIps,
            LatestHandshakeEpoch = latestHandshake,
            RxBytes = rxBytes,
            TxBytes = txBytes,
            PersistentKeepalive = persistentKeepalive
        };
    }

    private sealed class WireGuardStateDto
    {
        [JsonPropertyName("iface")]
        public string Iface { get; set; } = string.Empty;

        [JsonPropertyName("generatedAtUtc")]
        public DateTime GeneratedAtUtc { get; set; }

        [JsonPropertyName("interface")]
        public WireGuardInterfaceDto Interface { get; set; } = new();

        [JsonPropertyName("peers")]
        public List<WireGuardPeerDto> Peers { get; set; } = new();
    }

    private sealed class WireGuardInterfaceDto
    {
        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("listenPort")]
        public int ListenPort { get; set; }
    }

    private sealed class WireGuardPeerDto
    {
        [JsonPropertyName("publicKey")]
        public string PublicKey { get; set; } = string.Empty;

        [JsonPropertyName("presharedKey")]
        public bool PresharedKey { get; set; }

        [JsonPropertyName("endpoint")]
        public string? Endpoint { get; set; }

        [JsonPropertyName("allowedIps")]
        public string[] AllowedIps { get; set; } = Array.Empty<string>();

        [JsonPropertyName("latestHandshakeEpoch")]
        public long LatestHandshakeEpoch { get; set; }

        [JsonPropertyName("rxBytes")]
        public long RxBytes { get; set; }

        [JsonPropertyName("txBytes")]
        public long TxBytes { get; set; }

        [JsonPropertyName("persistentKeepalive")]
        public int? PersistentKeepalive { get; set; }
    }
}

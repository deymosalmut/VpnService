using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;
using VpnService.Api.DTOs.WireGuard;
using VpnService.Infrastructure.Abstractions.WireGuard;

namespace VpnService.Api.Services;

public sealed class WireGuardPeerCreator
{
    private const int DefaultEndpointPort = 51820;
    private const string DefaultPoolCidr = "10.8.0.0/24";
    private const string DefaultClientAllowedIps = "0.0.0.0/0";
    private const int DefaultLockTimeoutSeconds = 15;
    private const string DefaultPeerAllocLockFileName = "vpnservice_wg_peer_alloc.lock";

    private readonly ILogger<WireGuardPeerCreator> _logger;
    private readonly string _defaultEndpointHost;
    private readonly int _defaultEndpointPort;
    private readonly string _addressPoolCidr;
    private readonly string _clientAllowedIps;
    private readonly bool _persistPeers;
    private readonly string? _configPathOverride;
    private readonly string _peerAllocLockPath;
    private readonly TimeSpan _peerAllocLockTimeout;

    public WireGuardPeerCreator(ILogger<WireGuardPeerCreator> logger, IConfiguration config)
    {
        _logger = logger;
        _defaultEndpointHost = (config["WireGuard:EndpointHost"] ?? string.Empty).Trim();
        _defaultEndpointPort = ParseEndpointPort(config["WireGuard:EndpointPort"], DefaultEndpointPort);
        _addressPoolCidr = (config["WireGuard:AddressPoolCidr"] ?? DefaultPoolCidr).Trim();
        var clientAllowed = (config["WireGuard:ClientAllowedIps"] ?? DefaultClientAllowedIps).Trim();
        _clientAllowedIps = string.IsNullOrWhiteSpace(clientAllowed) ? DefaultClientAllowedIps : clientAllowed;
        _persistPeers = bool.TryParse(config["WireGuard:PersistPeers"], out var persist) && persist;
        _configPathOverride = NormalizeOptional(config["WireGuard:ConfigPath"]);
        _peerAllocLockPath = Path.Combine(Path.GetTempPath(), DefaultPeerAllocLockFileName);
        _peerAllocLockTimeout = TimeSpan.FromSeconds(DefaultLockTimeoutSeconds);
    }

    public async Task<AdminCreatePeerResponse> CreatePeerAsync(string iface, AdminCreatePeerRequest request, CancellationToken ct)
    {
        if (request == null)
            throw new ArgumentNullException(nameof(request));

        var name = (request.Name ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(name))
            throw new ArgumentException("name is required", nameof(request.Name));

        ValidateIface(iface);

        var endpointHost = ResolveEndpointHost(request.EndpointHost);
        var endpointPort = ResolveEndpointPort(request.EndpointPort);

        var serverPublicKey = await GetServerPublicKeyAsync(iface, ct);
        var (privateKey, publicKey) = await GenerateKeyPairAsync(ct);
        string address;

        using (var _ = await AcquirePeerAllocationLockAsync(ct))
        {
            var usedIps = await GetUsedAddressesAsync(iface, ct);
            address = ResolveAddress(request.AllowedIps, usedIps);

            if (_persistPeers)
            {
                var configPath = ResolveConfigPath(iface);
                await EnsurePeerNotInConfigAsync(configPath, publicKey, address, ct);
            }

            await AddPeerAsync(iface, publicKey, address, ct);

            if (_persistPeers)
                await PersistPeerAsync(iface, publicKey, address, ct);
        }

        var config = BuildClientConfig(privateKey, address, request.Dns, serverPublicKey, endpointHost, endpointPort, _clientAllowedIps);
        var qrBytes = await GenerateQrPngAsync(config, ct);
        var qrBase64 = Convert.ToBase64String(qrBytes);

        _logger.LogInformation("WG peer created iface={Iface} name={Name} allowed={Allowed} publicKey={PublicKey}",
            iface, name, address, publicKey);

        return new AdminCreatePeerResponse
        {
            Iface = iface,
            Name = name,
            Address = address,
            PublicKey = publicKey,
            Config = config,
            QrPngBase64 = qrBase64,
            QrDataUrl = $"data:image/png;base64,{qrBase64}"
        };
    }

    private string ResolveEndpointHost(string? requestHost)
    {
        var host = (requestHost ?? string.Empty).Trim();
        if (string.IsNullOrWhiteSpace(host))
            host = _defaultEndpointHost;

        if (string.IsNullOrWhiteSpace(host))
            throw new ArgumentException("endpointHost is required (request or WireGuard:EndpointHost)");

        return host;
    }

    private int ResolveEndpointPort(int? requestPort)
    {
        if (requestPort.HasValue)
        {
            if (requestPort.Value < 1 || requestPort.Value > 65535)
                throw new ArgumentException("endpointPort must be between 1 and 65535");
            return requestPort.Value;
        }

        return _defaultEndpointPort;
    }

    private string ResolveAddress(string[]? allowedIps, HashSet<string> usedIps)
    {
        if (allowedIps != null && allowedIps.Length > 0)
        {
            if (allowedIps.Length != 1)
                throw new ArgumentException("allowedIps must contain a single /32 entry");

            var cidr = (allowedIps[0] ?? string.Empty).Trim();
            if (!TryParseIpv4Cidr(cidr, out var ip, out var prefix) || prefix != 32)
                throw new ArgumentException("allowedIps must be a valid IPv4 /32 CIDR");

            var ipText = ip.ToString();
            if (usedIps.Contains(ipText))
                throw new PeerConflictException("allowedIps is already in use");

            return $"{ipText}/32";
        }

        return AllocateNextAvailableAddress(_addressPoolCidr, usedIps);
    }

    private async Task<FileStream> AcquirePeerAllocationLockAsync(CancellationToken ct)
    {
        var lockDirectory = Path.GetDirectoryName(_peerAllocLockPath);
        if (!string.IsNullOrWhiteSpace(lockDirectory))
            Directory.CreateDirectory(lockDirectory);

        var deadline = DateTime.UtcNow + _peerAllocLockTimeout;

        while (true)
        {
            ct.ThrowIfCancellationRequested();
            try
            {
                return new FileStream(_peerAllocLockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            }
            catch (IOException)
            {
                if (DateTime.UtcNow >= deadline)
                    throw new PeerAllocationLockTimeoutException(
                        $"Peer allocation busy; failed to acquire lock within {(int)_peerAllocLockTimeout.TotalSeconds} seconds.");
                await Task.Delay(200, ct);
            }
        }
    }

    private string ResolveConfigPath(string iface)
    {
        if (!string.IsNullOrWhiteSpace(_configPathOverride))
            return _configPathOverride!;

        return Path.Combine("/etc/wireguard", $"{iface}.conf");
    }

    private async Task EnsurePeerNotInConfigAsync(string configPath, string publicKey, string allowedIpCidr, CancellationToken ct)
    {
        if (!File.Exists(configPath))
            return;

        var config = await File.ReadAllTextAsync(configPath, ct);
        if (ConfigContainsPeer(config, publicKey, allowedIpCidr))
            throw new PeerConflictException($"Peer already exists in config {configPath}");
    }

    private async Task PersistPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct)
    {
        var configPath = ResolveConfigPath(iface);
        var configExists = File.Exists(configPath);
        string? existingConfig = null;

        if (configExists)
            existingConfig = await File.ReadAllTextAsync(configPath, ct);

        if (existingConfig != null && ConfigContainsPeer(existingConfig, publicKey, allowedIpCidr))
            throw new PeerConflictException($"Peer already exists in config {configPath}");

        var runtimeConfig = await GetRuntimeConfigAsync(iface, ct);
        var tempPath = Path.Combine(Path.GetTempPath(), $"vpnservice_{iface}_{Guid.NewGuid():N}.conf");
        await File.WriteAllTextAsync(tempPath, runtimeConfig, ct);

        try
        {
            await SyncRuntimeConfigAsync(iface, tempPath, ct);
        }
        finally
        {
            TryDeleteFile(tempPath);
        }

        if (configExists)
        {
            var updated = AppendPeerBlock(existingConfig ?? string.Empty, publicKey, allowedIpCidr);
            await WriteConfigFileAsync(configPath, updated, backupExisting: true, ct);
        }
        else
        {
            await WriteConfigFileAsync(configPath, runtimeConfig, backupExisting: false, ct);
        }
    }

    private async Task<string> GetRuntimeConfigAsync(string iface, CancellationToken ct)
    {
        var result = await RunCommandAsync("wg", new[] { "showconf", iface }, null, ct);
        if (result.ExitCode != 0)
        {
            if (IsInterfaceNotFound(result.Stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg showconf failed. iface={Iface} exit={Exit}", iface, result.ExitCode);
            throw new InvalidOperationException($"wg showconf failed (exit={result.ExitCode})");
        }

        var config = result.Stdout;
        if (string.IsNullOrWhiteSpace(config))
            throw new InvalidOperationException("wg showconf returned empty output");

        return config;
    }

    private async Task SyncRuntimeConfigAsync(string iface, string configPath, CancellationToken ct)
    {
        var result = await RunCommandAsync("wg", new[] { "syncconf", iface, configPath }, null, ct);
        if (result.ExitCode != 0)
        {
            if (IsInterfaceNotFound(result.Stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg syncconf failed. iface={Iface} exit={Exit}", iface, result.ExitCode);
            throw new InvalidOperationException($"wg syncconf failed (exit={result.ExitCode})");
        }
    }

    private static bool ConfigContainsPeer(string config, string publicKey, string allowedIpCidr)
    {
        if (string.IsNullOrWhiteSpace(config))
            return false;

        var inPeerSection = false;
        var lines = config.Split(new[] { '\r', '\n' }, StringSplitOptions.None);

        foreach (var rawLine in lines)
        {
            var line = rawLine.Trim();
            if (string.IsNullOrWhiteSpace(line) || line.StartsWith("#", StringComparison.Ordinal) || line.StartsWith(";", StringComparison.Ordinal))
                continue;

            if (line.StartsWith("[", StringComparison.Ordinal))
            {
                inPeerSection = line.Equals("[Peer]", StringComparison.OrdinalIgnoreCase);
                continue;
            }

            if (!inPeerSection)
                continue;

            if (TryParseConfigValue(line, "PublicKey", out var value) &&
                string.Equals(value, publicKey, StringComparison.Ordinal))
                return true;

            if (TryParseConfigValue(line, "AllowedIPs", out var allowedIpsRaw))
            {
                var entries = allowedIpsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries);
                foreach (var entry in entries)
                {
                    if (string.Equals(entry.Trim(), allowedIpCidr, StringComparison.Ordinal))
                        return true;
                }
            }
        }

        return false;
    }

    private static bool TryParseConfigValue(string line, string key, out string value)
    {
        value = string.Empty;
        var idx = line.IndexOf('=', StringComparison.Ordinal);
        if (idx < 0)
            return false;

        var left = line[..idx].Trim();
        if (!left.Equals(key, StringComparison.OrdinalIgnoreCase))
            return false;

        var rawValue = line[(idx + 1)..].Trim();
        var commentIndex = rawValue.IndexOfAny(new[] { '#', ';' });
        if (commentIndex >= 0)
            rawValue = rawValue[..commentIndex].Trim();

        value = rawValue;
        return true;
    }

    private static string AppendPeerBlock(string config, string publicKey, string allowedIpCidr)
    {
        var trimmed = (config ?? string.Empty).TrimEnd();
        var sb = new StringBuilder(trimmed);
        if (sb.Length > 0)
            sb.AppendLine().AppendLine();

        sb.AppendLine("[Peer]");
        sb.AppendLine($"PublicKey = {publicKey}");
        sb.AppendLine($"AllowedIPs = {allowedIpCidr}");
        sb.AppendLine();
        return sb.ToString();
    }

    private static async Task WriteConfigFileAsync(string configPath, string content, bool backupExisting, CancellationToken ct)
    {
        var directory = Path.GetDirectoryName(configPath);
        if (!string.IsNullOrWhiteSpace(directory))
            Directory.CreateDirectory(directory);

        if (backupExisting && File.Exists(configPath))
        {
            var backupPath = configPath + ".bak." + DateTime.UtcNow.ToString("yyyyMMddHHmmss", CultureInfo.InvariantCulture);
            File.Copy(configPath, backupPath, overwrite: false);
        }

        var tempPath = Path.Combine(directory ?? ".", Path.GetFileName(configPath) + ".tmp." + Guid.NewGuid().ToString("N"));
        await File.WriteAllTextAsync(tempPath, content, ct);
        File.Move(tempPath, configPath, overwrite: true);
    }

    private static void TryDeleteFile(string path)
    {
        try
        {
            if (File.Exists(path))
                File.Delete(path);
        }
        catch
        {
            // Best-effort cleanup.
        }
    }

    private static string BuildClientConfig(
        string privateKey,
        string address,
        string? dns,
        string serverPublicKey,
        string endpointHost,
        int endpointPort,
        string clientAllowedIps)
    {
        var sb = new StringBuilder();
        sb.AppendLine("[Interface]");
        sb.AppendLine($"PrivateKey = {privateKey}");
        sb.AppendLine($"Address = {address}");
        if (!string.IsNullOrWhiteSpace(dns))
            sb.AppendLine($"DNS = {dns.Trim()}");

        sb.AppendLine();
        sb.AppendLine("[Peer]");
        sb.AppendLine($"PublicKey = {serverPublicKey}");
        sb.AppendLine($"Endpoint = {endpointHost}:{endpointPort}");
        sb.AppendLine($"AllowedIPs = {clientAllowedIps}");
        sb.AppendLine();

        return sb.ToString();
    }

    private async Task<string> GetServerPublicKeyAsync(string iface, CancellationToken ct)
    {
        var result = await RunCommandAsync("wg", new[] { "show", iface, "public-key" }, null, ct);
        if (result.ExitCode != 0)
        {
            if (IsInterfaceNotFound(result.Stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg show public-key failed. iface={Iface} exit={Exit}", iface, result.ExitCode);
            throw new InvalidOperationException($"wg show public-key failed (exit={result.ExitCode})");
        }

        var key = result.Stdout.Trim();
        if (string.IsNullOrWhiteSpace(key))
            throw new InvalidOperationException("wg show public-key returned empty output");

        return key;
    }

    private async Task<HashSet<string>> GetUsedAddressesAsync(string iface, CancellationToken ct)
    {
        var result = await RunCommandAsync("wg", new[] { "show", iface, "allowed-ips" }, null, ct);
        if (result.ExitCode != 0)
        {
            if (IsInterfaceNotFound(result.Stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg show allowed-ips failed. iface={Iface} exit={Exit}", iface, result.ExitCode);
            throw new InvalidOperationException($"wg show allowed-ips failed (exit={result.ExitCode})");
        }

        var used = new HashSet<string>(StringComparer.Ordinal);
        var lines = result.Stdout.Split(new[] { '\r', '\n' }, StringSplitOptions.RemoveEmptyEntries);

        foreach (var line in lines)
        {
            var parts = line.Split(new[] { '\t', ' ' }, StringSplitOptions.RemoveEmptyEntries);
            if (parts.Length < 2)
                continue;

            var allowedIpsRaw = parts[1];
            var entries = allowedIpsRaw.Split(',', StringSplitOptions.RemoveEmptyEntries);
            foreach (var entry in entries)
            {
                var trimmed = entry.Trim();
                if (TryParseIpv4Cidr(trimmed, out var ip, out var prefix) && prefix == 32)
                    used.Add(ip.ToString());
            }
        }

        return used;
    }

    private async Task AddPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct)
    {
        var result = await RunCommandAsync("wg", new[] { "set", iface, "peer", publicKey, "allowed-ips", allowedIpCidr }, null, ct);
        if (result.ExitCode != 0)
        {
            if (IsInterfaceNotFound(result.Stderr))
                throw new WireGuardInterfaceNotFoundException(iface);

            _logger.LogError("wg set failed. iface={Iface} exit={Exit}", iface, result.ExitCode);
            throw new InvalidOperationException($"wg set failed (exit={result.ExitCode})");
        }
    }

    private async Task<(string PrivateKey, string PublicKey)> GenerateKeyPairAsync(CancellationToken ct)
    {
        var genResult = await RunCommandAsync("wg", new[] { "genkey" }, null, ct);
        if (genResult.ExitCode != 0)
        {
            _logger.LogError("wg genkey failed. exit={Exit}", genResult.ExitCode);
            throw new InvalidOperationException($"wg genkey failed (exit={genResult.ExitCode})");
        }

        var privateKey = genResult.Stdout.Trim();
        if (string.IsNullOrWhiteSpace(privateKey))
            throw new InvalidOperationException("wg genkey returned empty output");

        var pubResult = await RunCommandAsync("wg", new[] { "pubkey" }, privateKey + "\n", ct);
        if (pubResult.ExitCode != 0)
        {
            _logger.LogError("wg pubkey failed. exit={Exit}", pubResult.ExitCode);
            throw new InvalidOperationException($"wg pubkey failed (exit={pubResult.ExitCode})");
        }

        var publicKey = pubResult.Stdout.Trim();
        if (string.IsNullOrWhiteSpace(publicKey))
            throw new InvalidOperationException("wg pubkey returned empty output");

        return (privateKey, publicKey);
    }

    private async Task<byte[]> GenerateQrPngAsync(string config, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = "qrencode",
            RedirectStandardInput = true,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };
        psi.ArgumentList.Add("-t");
        psi.ArgumentList.Add("png");
        psi.ArgumentList.Add("-o");
        psi.ArgumentList.Add("-");

        using var proc = new Process { StartInfo = psi };

        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "qrencode executable not found or failed to start.");
            throw new InvalidOperationException("qrencode not found");
        }

        await proc.StandardInput.WriteAsync(config);
        await proc.StandardInput.FlushAsync();
        proc.StandardInput.Close();

        await using var ms = new MemoryStream();
        var stdoutTask = proc.StandardOutput.BaseStream.CopyToAsync(ms, ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

        await proc.WaitForExitAsync(ct);
        await stdoutTask;

        var stderr = (await stderrTask).Trim();
        if (proc.ExitCode != 0)
        {
            _logger.LogError("qrencode failed. exit={Exit}", proc.ExitCode);
            throw new InvalidOperationException($"qrencode failed (exit={proc.ExitCode})");
        }

        return ms.ToArray();
    }

    private static string AllocateNextAvailableAddress(string poolCidr, HashSet<string> usedIps)
    {
        if (!TryParseIpv4Cidr(poolCidr, out var baseIp, out var prefix) || prefix != 24)
        {
            poolCidr = DefaultPoolCidr;
            if (!TryParseIpv4Cidr(poolCidr, out baseIp, out prefix) || prefix != 24)
                throw new InvalidOperationException("Address pool CIDR must be IPv4 /24");
        }

        var baseBytes = baseIp.GetAddressBytes();
        for (var last = 2; last <= 254; last++)
        {
            var candidate = new IPAddress(new[] { baseBytes[0], baseBytes[1], baseBytes[2], (byte)last }).ToString();
            if (!usedIps.Contains(candidate))
                return $"{candidate}/32";
        }

        throw new PeerConflictException($"No free IPs in pool {poolCidr}");
    }

    private static bool TryParseIpv4Cidr(string cidr, out IPAddress address, out int prefix)
    {
        address = IPAddress.None;
        prefix = 0;

        if (string.IsNullOrWhiteSpace(cidr))
            return false;

        var parts = cidr.Trim().Split('/', StringSplitOptions.RemoveEmptyEntries);
        if (parts.Length != 2)
            return false;

        if (!IPAddress.TryParse(parts[0], out var parsed) || parsed == null)
            return false;

        address = parsed;

        if (address.AddressFamily != AddressFamily.InterNetwork)
            return false;

        if (!int.TryParse(parts[1], NumberStyles.Integer, CultureInfo.InvariantCulture, out prefix))
            return false;

        return prefix >= 0 && prefix <= 32;
    }

    private static int ParseEndpointPort(string? raw, int fallback)
    {
        if (string.IsNullOrWhiteSpace(raw))
            return fallback;

        if (int.TryParse(raw.Trim(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var port) && port >= 1 && port <= 65535)
            return port;

        return fallback;
    }

    private static string? NormalizeOptional(string? value)
    {
        var trimmed = (value ?? string.Empty).Trim();
        return string.IsNullOrWhiteSpace(trimmed) ? null : trimmed;
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

    private static void ValidateIface(string iface)
    {
        if (string.IsNullOrWhiteSpace(iface) || iface.Length > 32)
            throw new ArgumentException("Invalid interface name");

        foreach (var ch in iface)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '-'))
                throw new ArgumentException("Invalid interface name");
        }
    }

    private async Task<CommandResult> RunCommandAsync(string fileName, IEnumerable<string> args, string? stdin, CancellationToken ct)
    {
        var psi = new ProcessStartInfo
        {
            FileName = fileName,
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        foreach (var arg in args)
            psi.ArgumentList.Add(arg);

        if (stdin != null)
            psi.RedirectStandardInput = true;

        using var proc = new Process { StartInfo = psi };

        try
        {
            proc.Start();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "{File} executable not found or failed to start.", fileName);
            throw new InvalidOperationException($"{fileName} not found");
        }

        if (stdin != null)
        {
            await proc.StandardInput.WriteAsync(stdin);
            await proc.StandardInput.FlushAsync();
            proc.StandardInput.Close();
        }

        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

        await proc.WaitForExitAsync(ct);

        var stdout = await stdoutTask;
        var stderr = await stderrTask;

        return new CommandResult(proc.ExitCode, stdout, stderr);
    }

    private sealed record CommandResult(int ExitCode, string Stdout, string Stderr);
}

public sealed class PeerAllocationLockTimeoutException : Exception
{
    public PeerAllocationLockTimeoutException(string message) : base(message) { }
}

public sealed class PeerConflictException : Exception
{
    public PeerConflictException(string message) : base(message) { }
}

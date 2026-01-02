using System.Diagnostics;
using System.Text;
using Microsoft.Extensions.Logging;
using VpnService.Application.Interfaces;

namespace VpnService.Infrastructure.WireGuard;

public sealed class LinuxWireGuardCommandWriter : IWireGuardCommandWriter
{
    private readonly ILogger<LinuxWireGuardCommandWriter> _logger;
    private readonly string _writeScriptPath;

    public LinuxWireGuardCommandWriter(ILogger<LinuxWireGuardCommandWriter> logger)
    {
        _logger = logger;
        _writeScriptPath = Environment.GetEnvironmentVariable("WG_WRITE_SCRIPT")
            ?? "/opt/vpn-adapter/wg_write.sh";
    }

    public async Task AddPeerAsync(string iface, string publicKey, string allowedIpCidr, CancellationToken ct)
    {
        ValidateIface(iface);
        ValidateWgPublicKey(publicKey);
        ValidateAllowedIpCidr(allowedIpCidr);

        var args = $"add {EscapeArg(iface)} {EscapeArg(publicKey)} {EscapeArg(allowedIpCidr)}";
        await RunScriptAsync(args, ct);
        _logger.LogInformation("WG peer added iface={Iface} allowed={Allowed}", iface, allowedIpCidr);
    }

    public async Task RemovePeerAsync(string iface, string publicKey, CancellationToken ct)
    {
        ValidateIface(iface);
        ValidateWgPublicKey(publicKey);

        var args = $"remove {EscapeArg(iface)} {EscapeArg(publicKey)}";
        await RunScriptAsync(args, ct);
        _logger.LogInformation("WG peer removed iface={Iface}", iface);
    }

    private async Task RunScriptAsync(string args, CancellationToken ct)
    {
        if (!File.Exists(_writeScriptPath))
            throw new InvalidOperationException($"WG write script not found: {_writeScriptPath}");

        using var p = new Process
        {
            StartInfo = new ProcessStartInfo
            {
                FileName = "/usr/bin/env",
                Arguments = $"bash {_writeScriptPath} {args}",
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                UseShellExecute = false,
                CreateNoWindow = true
            }
        };

        p.Start();

        var stdout = await p.StandardOutput.ReadToEndAsync(ct);
        var stderr = await p.StandardError.ReadToEndAsync(ct);
        await p.WaitForExitAsync(ct);

        if (p.ExitCode != 0)
        {
            var msg = $"WG write failed (exit {p.ExitCode}). stderr={stderr}";
            _logger.LogError("{Msg}", msg);
            throw new InvalidOperationException(msg);
        }
    }

    private static void ValidateIface(string iface)
    {
        // минимально безопасно: буквы/цифры/подчёрк/дефис
        if (string.IsNullOrWhiteSpace(iface) || iface.Length > 32 || iface.Any(ch => !(char.IsLetterOrDigit(ch) || ch is '_' or '-')))
            throw new ArgumentException("Invalid interface name");
    }

    private static void ValidateWgPublicKey(string key)
    {
        // WG pubkey = base64, обычно 44 символа с '=' на конце.
        if (string.IsNullOrWhiteSpace(key) || key.Length < 40 || key.Length > 60)
            throw new ArgumentException("Invalid WireGuard public key length");
        // можно усилить regex, но MVP достаточно
    }

    private static void ValidateAllowedIpCidr(string cidr)
    {
        // MVP: строго ожидаем /32
        if (string.IsNullOrWhiteSpace(cidr) || !cidr.EndsWith("/32"))
            throw new ArgumentException("AllowedIpCidr must be /32 in MVP");
    }

    private static string EscapeArg(string s)
    {
        // bash-аргумент через одинарные кавычки
        return "'" + s.Replace("'", "'\"'\"'") + "'";
    }
}

using System.Diagnostics;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Extensions.Logging;
using VpnService.Infrastructure.Abstractions;

namespace VpnService.Infrastructure.WireGuard
{
    public sealed class LinuxWireGuardStateReader : IWireGuardStateReader
{
    private readonly ILogger<LinuxWireGuardStateReader> _logger;
    private readonly string _scriptPath;

    public LinuxWireGuardStateReader(
        ILogger<LinuxWireGuardStateReader> logger,
        string scriptPath = "/opt/vpn-adapter/wg_dump.sh")
    {
        _logger = logger;
        _scriptPath = scriptPath;
    }

    public async Task<string> GetDumpJsonAsync(string iface, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(iface))
            throw new ArgumentException("iface is required", nameof(iface));

        // Защита от инъекций: разрешаем только [a-zA-Z0-9_-]
        foreach (var ch in iface)
        {
            if (!(char.IsLetterOrDigit(ch) || ch is '_' or '-'))
                throw new ArgumentException("iface содержит недопустимые символы", nameof(iface));
        }

        if (!File.Exists(_scriptPath))
            throw new FileNotFoundException($"wg adapter script not found: {_scriptPath}");

        var psi = new ProcessStartInfo
        {
            FileName = "/bin/bash",
            // Важно: без -c, чтобы не открывать shell-инъекции.
            ArgumentList = { _scriptPath, iface },
            RedirectStandardOutput = true,
            RedirectStandardError = true,
            UseShellExecute = false,
            CreateNoWindow = true
        };

        using var proc = new Process { StartInfo = psi };

        proc.Start();

        var stdoutTask = proc.StandardOutput.ReadToEndAsync(ct);
        var stderrTask = proc.StandardError.ReadToEndAsync(ct);

        await proc.WaitForExitAsync(ct);

        var stdout = (await stdoutTask).Trim();
        var stderr = (await stderrTask).Trim();

        if (proc.ExitCode != 0)
        {
            _logger.LogError("wg_dump failed. iface={Iface} exit={Exit} err={Err}", iface, proc.ExitCode, stderr);
            throw new InvalidOperationException($"wg_dump failed (exit={proc.ExitCode}): {stderr}");
        }

        // stdout должен быть JSON
        if (string.IsNullOrWhiteSpace(stdout) || !stdout.StartsWith("{"))
        {
            _logger.LogWarning("wg_dump returned non-json. iface={Iface} out={Out}", iface, stdout);
            throw new InvalidOperationException("wg_dump returned invalid json");
        }

        return stdout;
    }
    }
}

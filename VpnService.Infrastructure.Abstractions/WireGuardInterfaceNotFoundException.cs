using System;

namespace VpnService.Infrastructure.Abstractions.WireGuard;

public sealed class WireGuardInterfaceNotFoundException : Exception
{
    public WireGuardInterfaceNotFoundException(string iface)
        : base($"WireGuard interface not found: {iface}")
    {
    }
}

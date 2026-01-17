using System.Collections.Concurrent;

namespace VpnService.Api.Security;

internal static class LoginRateLimiter
{
    private const int MaxAttemptsPerIp = 10;
    private const int MaxAttemptsPerUser = 5;
    private static readonly long WindowTicks = TimeSpan.FromSeconds(60).Ticks;

    private static readonly ConcurrentDictionary<string, RateLimitWindow> IpWindows = new(StringComparer.Ordinal);
    private static readonly ConcurrentDictionary<string, RateLimitWindow> UserWindows = new(StringComparer.Ordinal);

    public static bool IsLimited(string? ip, string? username)
    {
        // Normalize IP: use "unknown" if null/whitespace
        var normalizedIp = string.IsNullOrWhiteSpace(ip) ? "unknown" : ip.Trim();
        
        // Normalize username: convert to lowercase for case-insensitive rate limiting
        var normalizedUser = string.IsNullOrWhiteSpace(username) ? null : username.Trim().ToLowerInvariant();
        
        var nowTicks = DateTime.UtcNow.Ticks;

        var ipAllowed = Consume(IpWindows, normalizedIp, MaxAttemptsPerIp, nowTicks);
        var userAllowed = normalizedUser == null || Consume(UserWindows, normalizedUser, MaxAttemptsPerUser, nowTicks);

        return !ipAllowed || !userAllowed;
    }

    private static bool Consume(
        ConcurrentDictionary<string, RateLimitWindow> windows,
        string key,
        int maxAttempts,
        long nowTicks)
    {
        var window = windows.GetOrAdd(key, _ => new RateLimitWindow());
        return window.TryConsume(nowTicks, WindowTicks, maxAttempts);
    }

    private sealed class RateLimitWindow
    {
        private readonly Queue<long> _attempts = new();
        private readonly object _lock = new();

        public bool TryConsume(long nowTicks, long windowTicks, int maxAttempts)
        {
            lock (_lock)
            {
                // Remove expired attempts outside the current window
                while (_attempts.Count > 0 && nowTicks - _attempts.Peek() > windowTicks)
                {
                    _attempts.Dequeue();
                }

                // Reject if at max attempts
                if (_attempts.Count >= maxAttempts)
                {
                    return false;
                }

                // Consume one attempt
                _attempts.Enqueue(nowTicks);
                return true;
            }
        }
    }
}

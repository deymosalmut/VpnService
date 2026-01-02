namespace VpnService.Infrastructure.Abstractions;

/// <summary>
/// Контракт управления VPN-пирами на уровне ОС.
/// Реализация будет зависеть от конкретной ОС (Linux/Windows).
/// </summary>
public interface IVpnPeerProvisioner
{
    /// <summary>
    /// Создает/активирует VPN пир с заданными параметрами.
    /// </summary>
    /// <param name="peerId">Уникальный идентификатор пира</param>
    /// <param name="publicKey">Публичный ключ WireGuard</param>
    /// <param name="assignedIp">Назначенный IP адрес пира</param>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Task для асинхронного выполнения</returns>
    Task ProvisionAsync(
        Guid peerId,
        string publicKey,
        string assignedIp,
        CancellationToken ct = default);

    /// <summary>
    /// Отзывает/деактивирует VPN пир.
    /// </summary>
    /// <param name="peerId">Уникальный идентификатор пира</param>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Task для асинхронного выполнения</returns>
    Task RevokeAsync(
        Guid peerId,
        CancellationToken ct = default);

    /// <summary>
    /// Проверяет, активен ли пир на уровне ОС.
    /// </summary>
    /// <param name="peerId">Уникальный идентификатор пира</param>
    /// <param name="ct">Токен отмены</param>
    /// <returns>True если пир активен, иначе false</returns>
    Task<bool> IsPeerActiveAsync(
        Guid peerId,
        CancellationToken ct = default);
}

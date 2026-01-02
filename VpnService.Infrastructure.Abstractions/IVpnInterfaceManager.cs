namespace VpnService.Infrastructure.Abstractions;

/// <summary>
/// Контракт управления VPN-интерфейсом на уровне ОС.
/// Отвечает за инициализацию и конфигурацию виртуального интерфейса.
/// </summary>
public interface IVpnInterfaceManager
{
    /// <summary>
    /// Гарантирует, что VPN-интерфейс существует и инициализирован.
    /// </summary>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Task для асинхронного выполнения</returns>
    Task EnsureInterfaceExistsAsync(CancellationToken ct = default);

    /// <summary>
    /// Перезагружает конфигурацию VPN-интерфейса.
    /// </summary>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Task для асинхронного выполнения</returns>
    Task ReloadConfigurationAsync(CancellationToken ct = default);

    /// <summary>
    /// Получает статус VPN-интерфейса.
    /// </summary>
    /// <param name="ct">Токен отмены</param>
    /// <returns>True если интерфейс активен, иначе false</returns>
    Task<bool> IsInterfaceActiveAsync(CancellationToken ct = default);

    /// <summary>
    /// Получает конфигурацию VPN-интерфейса.
    /// </summary>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Текущая конфигурация интерфейса</returns>
    Task<VpnInterfaceConfiguration> GetConfigurationAsync(CancellationToken ct = default);
}

/// <summary>
/// Конфигурация VPN-интерфейса.
/// </summary>
public class VpnInterfaceConfiguration
{
    /// <summary>
    /// Имя интерфейса (например, wg0)
    /// </summary>
    public string InterfaceName { get; set; } = null!;

    /// <summary>
    /// IP адрес сервера
    /// </summary>
    public string ServerIp { get; set; } = null!;

    /// <summary>
    /// CIDR маска сети
    /// </summary>
    public string Subnet { get; set; } = null!;

    /// <summary>
    /// Приватный ключ сервера
    /// </summary>
    public string ServerPrivateKey { get; set; } = null!;

    /// <summary>
    /// Публичный ключ сервера
    /// </summary>
    public string ServerPublicKey { get; set; } = null!;

    /// <summary>
    /// Прослушивающий порт
    /// </summary>
    public int ListeningPort { get; set; }
}

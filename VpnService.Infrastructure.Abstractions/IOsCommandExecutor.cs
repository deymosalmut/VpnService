namespace VpnService.Infrastructure.Abstractions;

/// <summary>
/// Контракт для выполнения системных команд ОС.
/// Абстрагирует вызовы shell команд (wg, ip, iptables и т.д.)
/// </summary>
public interface IOsCommandExecutor
{
    /// <summary>
    /// Выполняет системную команду и возвращает результат.
    /// </summary>
    /// <param name="command">Команда для выполнения (например, "wg show")</param>
    /// <param name="arguments">Аргументы команды</param>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Результат выполнения команды</returns>
    Task<OsCommandResult> ExecuteAsync(
        string command,
        string? arguments = null,
        CancellationToken ct = default);

    /// <summary>
    /// Выполняет команду с привилегиями (требует sudo на Linux).
    /// </summary>
    /// <param name="command">Команда для выполнения</param>
    /// <param name="arguments">Аргументы команды</param>
    /// <param name="ct">Токен отмены</param>
    /// <returns>Результат выполнения команды</returns>
    Task<OsCommandResult> ExecuteAsRootAsync(
        string command,
        string? arguments = null,
        CancellationToken ct = default);
}

/// <summary>
/// Результат выполнения системной команды.
/// </summary>
public class OsCommandResult
{
    /// <summary>
    /// Код выхода (0 = успех)
    /// </summary>
    public int ExitCode { get; set; }

    /// <summary>
    /// Стандартный вывод команды
    /// </summary>
    public string Output { get; set; } = null!;

    /// <summary>
    /// Стандартная ошибка
    /// </summary>
    public string Error { get; set; } = null!;

    /// <summary>
    /// Успешно ли выполнена команда
    /// </summary>
    public bool IsSuccess => ExitCode == 0;
}

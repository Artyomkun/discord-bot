defmodule MusicCore.Reports do
  @moduledoc """
  Модуль для обработки репортов от пользователей.

  Поддерживает:
  - Сохранение в БД
  - Логирование в файл
  - Уведомления в лог
  - Статистику жалоб
  - Автоматическое резолвинг
  """

  import Ecto.Query
  require Logger

  alias MusicCore.Repo
  alias MusicCore.Schema.Report
  alias MusicCore.Metrics

  @log_file "reports.log"

  @doc """
  Отправляет репорт.
  """
  @spec send(String.t(), String.t() | nil, String.t(), String.t()) :: :ok | {:error, term()}
  def send(user_id, guild_id, reason, details) do
    case create_report(user_id, guild_id, reason, details, %{}) do
      {:ok, report} ->
        log_to_file(report)
        Metrics.increment("reports.total")
        Metrics.increment("reports.reason.#{reason}")

        Logger.warning("""
        📝 New report from #{user_id} in #{guild_id || "DM"}:
        Reason: #{reason}
        Details: #{details}
        """)

        :ok

      {:error, reason} ->
        Logger.error("Failed to save report: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Отправляет репорт с дополнительной информацией.
  """
  @spec send_with_meta(String.t(), String.t() | nil, String.t(), String.t(), map()) :: :ok | {:error, term()}
  def send_with_meta(user_id, guild_id, reason, details, meta) do
    case create_report(user_id, guild_id, reason, details, meta) do
      {:ok, report} ->
        log_to_file(report)
        Metrics.increment("reports.total")
        Metrics.increment("reports.reason.#{reason}")

        Logger.warning("""
        📝 New report with meta from #{user_id}:
        Reason: #{reason}
        Details: #{details}
        Meta: #{inspect(meta)}
        """)

        :ok

      {:error, reason} ->
        Logger.error("Failed to save report: #{reason}")
        {:error, reason}
    end
  end

  @doc """
  Получает статистику репортов.
  """
  @spec get_stats(DateTime.t()) :: list()
  def get_stats(since \\ days_ago(7)) do
    query = from r in Report,
            where: r.inserted_at >= ^since,
            group_by: r.reason,
            select: {r.reason, count(r.id)}

    Repo.all(query)
  end

  @doc """
  Получает репорты по статусу.
  """
  @spec get_by_status(String.t()) :: list()
  def get_by_status(status) do
    query = from r in Report,
            where: r.status == ^status,
            order_by: [desc: :inserted_at],
            limit: 100

    Repo.all(query)
  end

  @doc """
  Получает все новые репорты.
  """
  @spec get_new() :: list()
  def get_new do
    get_by_status("new")
  end

  @doc """
  Разрешает репорт.
  """
  @spec resolve(integer(), String.t(), String.t() | nil) :: {:ok, Report.t()} | {:error, term()}
  def resolve(report_id, admin_id, resolution_note \\ nil) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        changeset = Report.resolve_changeset(report, admin_id, resolution_note)
        Repo.update(changeset)
    end
  end

  @doc """
  Отклоняет репорт.
  """
  @spec reject(integer(), String.t(), String.t()) :: {:ok, Report.t()} | {:error, term()}
  def reject(report_id, admin_id, reason) do
    case Repo.get(Report, report_id) do
      nil ->
        {:error, :not_found}

      report ->
        changeset = Report.reject_changeset(report, admin_id, reason)
        Repo.update(changeset)
    end
  end

  # ========== ПРИВАТНЫЕ ФУНКЦИИ ==========

  defp create_report(user_id, guild_id, reason, details, meta) do
    attrs = %{
      user_id: user_id,
      guild_id: guild_id,
      reason: reason,
      details: details,
      meta: meta,
      status: "new"
    }

    %Report{}
    |> Report.changeset(attrs)
    |> Repo.insert()
  end

  defp log_to_file(report) do
    line = Jason.encode!(%{
      id: report.id,
      user_id: report.user_id,
      guild_id: report.guild_id,
      reason: report.reason,
      details: report.details,
      meta: report.meta,
      status: report.status,
      inserted_at: report.inserted_at
    })

    File.write(@log_file, line <> "\n", [:append])
  rescue
    e -> Logger.error("Failed to write to report log: #{inspect(e)}")
  end

  defp days_ago(n) do
    DateTime.utc_now()
    |> DateTime.add(-n * 86_400, :second)
  end
end

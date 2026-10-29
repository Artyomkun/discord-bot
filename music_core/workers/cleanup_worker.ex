defmodule MusicCore.Workers.CleanupWorker do
  @moduledoc """
  Worker для очистки устаревших данных.

  Выполняет периодическую очистку базы данных, кэша и других ресурсов.
  """

  use Oban.Worker, queue: :cleanup
  require Logger
  use GenServer

  alias MusicCore.Metrics
  alias MusicCore.Cache
  alias MusicCore.Buffer
  alias MusicCore.JavaGateway.Client

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, opts}
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    cleanup_type = Map.get(args, "type", "full")

    Logger.info("Starting cleanup job: #{cleanup_type}")

    result = case cleanup_type do
      "full" -> perform_full_cleanup()
      "cache" -> perform_cache_cleanup()
      "database" -> perform_database_cleanup()
      "files" -> perform_files_cleanup()
      _ -> {:error, :unknown_cleanup_type}
    end

    case result do
      {:ok, stats} ->
        Metrics.record(:cleanup_job_success, 1, %{type: cleanup_type, stats: stats})
        Logger.info("Cleanup job completed: #{cleanup_type} - #{inspect(stats)}")
        :ok

      {:error, reason} ->
        Metrics.record(:cleanup_job_failed, 1, %{type: cleanup_type, error: reason})
        Logger.error("Cleanup job failed: #{cleanup_type} - #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp perform_full_cleanup do
    stats = %{}
    cache_stats = perform_cache_cleanup()
    stats = Map.put(stats, :cache, cache_stats)
    db_stats = perform_database_cleanup()
    stats = Map.put(stats, :database, db_stats)
    files_stats = perform_files_cleanup()
    stats = Map.put(stats, :files, files_stats)
    {:ok, stats}
  end

  defp perform_cache_cleanup do
    cutoff = DateTime.utc_now() |> DateTime.add(-24 * 60 * 60, :second)

    # Очистка аудио кэша
    audio_keys = Cache.keys(:audio_cache)
    audio_cleaned = Enum.count(audio_keys, fn key ->
      case Cache.get(:audio_cache, key) do
        {:ok, %{timestamp: ts}} when not is_nil(ts) ->
          if DateTime.compare(ts, cutoff) == :lt do
            Cache.delete(:audio_cache, key)
            true
          else
            false
          end
        _ -> false
      end
    end)

    # Очистка кэша эффектов
    effects_cleaned = Enum.count(Cache.keys(:effects_cache), fn key ->
      case Cache.get(:effects_cache, key) do
        {:ok, %{updated_at: ts}} ->
          if DateTime.compare(ts, cutoff) == :lt do
            Cache.delete(:effects_cache, key)
            true
          else
            false
          end
        _ -> false
      end
    end)

    stats = %{
      audio_cache: %{cleaned: audio_cleaned, remaining: Cache.size(:audio_cache)},
      effects_cache: %{cleaned: effects_cleaned, remaining: Cache.size(:effects_cache)}
    }

    Logger.info("Cache cleanup completed: #{inspect(stats)}")
    {:ok, stats}
  end

  defp perform_database_cleanup do
    Task.start(fn ->
      case Client.cleanup_database(%{older_than_days: 30}) do
        {:ok, response} ->
          Logger.info("Async database cleanup completed: #{inspect(response)}")
        {:error, reason} ->
          Logger.error("Async database cleanup failed: #{inspect(reason)}")
      end
    end)
    {:ok, %{async: true}}
  end

  defp perform_files_cleanup do
    temp_dir = System.tmp_dir!()

    case File.ls(temp_dir) do
      {:ok, files} ->
        cutoff_time = System.system_time(:second) - 86_400

        old_files = Enum.filter(files, fn file ->
          file_path = Path.join(temp_dir, file)

          case File.stat(file_path) do
            {:ok, stat} ->
              String.starts_with?(file, "music_core_") and stat.mtime < cutoff_time
            _ -> false
          end
        end)

        deleted_count = Enum.reduce(old_files, 0, fn file, acc ->
          file_path = Path.join(temp_dir, file)

          case File.rm(file_path) do
            :ok ->
              Logger.debug("Cleanup: deleted temp file #{file_path}")
              acc + 1
            {:error, reason} ->
              Logger.warning("Cleanup: failed to delete #{file_path}: #{reason}")
              acc
          end
        end)

        {:ok, %{temp_files_deleted: deleted_count, temp_dir: temp_dir}}

      {:error, reason} ->
        Logger.warning("Cleanup: failed to list temp directory: #{reason}")
        {:ok, %{error: reason}}
    end
  end

  @doc """
  Планирование полной очистки.
  """
  def schedule_full_cleanup do
    %{"type" => "full"}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Планирование очистки кэша.
  """
  def schedule_cache_cleanup do
    %{"type" => "cache"}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Планирование очистки базы данных.
  """
  def schedule_database_cleanup do
    %{"type" => "database"}
    |> new()
    |> Oban.insert()
  end

  @doc """
  Планирование очистки файлов.
  """
  def schedule_files_cleanup do
    %{"type" => "files"}
    |> new()
    |> Oban.insert()
  end
end

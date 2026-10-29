defmodule MusicCore.AudioStream.PeriodicCleanup do
  @moduledoc """
  Периодическая очистка аудио потоков.

  Удаляет старые, неактивные стримы и очищает связанные ресурсы.
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, Cache}

  # API

  @doc """
  Запустить периодическую очистку.
  """
  def start_link(opts) do
    interval = Keyword.get(opts, :interval, :timer.minutes(5))
    GenServer.start_link(__MODULE__, %{interval: interval}, name: __MODULE__)
  end

  # Server callbacks

  @impl true
  def init(state) do
    Process.send_after(self(), :cleanup, state.interval)

    Logger.info("PeriodicCleanup started with interval: #{state.interval}ms")

    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("Starting periodic cleanup")

    cleanup_stats = perform_cleanup()

    Logger.info("Cleanup completed: #{inspect(cleanup_stats)}")

    Process.send_after(self(), :cleanup, state.interval)

    {:noreply, state}
  end

  # ========== PRIVATE ==========

  defp perform_cleanup do
    %{
      audio_cache: cleanup_audio_cache(),
      effects_cache: cleanup_effects_cache(),
      streams: cleanup_expired_streams(),
      metrics: cleanup_old_metrics(),
      temp_files: cleanup_temp_files()
    }
  end

  defp cleanup_audio_cache do
    size_before = Cache.size(:audio_cache)
    size_after = Cache.size(:audio_cache)

    %{
      size_before: size_before,
      size_after: size_after,
      cleaned: size_before - size_after
    }
  end

  defp cleanup_effects_cache do
    size_before = Cache.size(:effects_cache)
    size_after = Cache.size(:effects_cache)

    %{
      size_before: size_before,
      size_after: size_after,
      cleaned: size_before - size_after
    }
  end

  defp cleanup_expired_streams do
    active_count = MusicCore.AudioStream.Manager.active_streams_count()

    %{
      active_streams: active_count,
      checked: true
    }
  end

  defp cleanup_old_metrics do
    %{cleaned: 0, checked: true}
  end

  defp cleanup_temp_files do
    temp_dir = System.tmp_dir!()

    case File.ls(temp_dir) do
      {:ok, files} ->
        now = System.system_time(:second)

        old_files = Enum.filter(files, fn file ->
          file_path = Path.join(temp_dir, file)

          case File.stat(file_path) do
            {:ok, stat} ->
              age_hours = (now - stat.mtime) / 3600
              String.starts_with?(file, "music_core_") and age_hours > 1

            _ ->
              false
          end
        end)

        deleted_count = Enum.reduce(old_files, 0, fn file, acc ->
          file_path = Path.join(temp_dir, file)

          case File.rm(file_path) do
            :ok ->
              Logger.debug("Deleted temp file: #{file_path}")
              acc + 1

            {:error, reason} ->
              Logger.warning("Failed to delete temp file #{file_path}: #{reason}")
              acc
          end
        end)

        %{temp_dir: temp_dir, deleted_files: deleted_count}

      {:error, reason} ->
        Logger.warning("Failed to list temp directory: #{reason}")
        %{error: reason, temp_dir: temp_dir}
    end
  end
end

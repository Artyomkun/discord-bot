defmodule MusicCore.AudioEffects.Metrics.Collector do
  @moduledoc """
  Сборщик метрик производительности для подсистемы аудио эффектов.
  Периодически собирает и отправляет метрики через Telemetry.
  """
  use GenServer
  require Logger

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    interval = Keyword.get(opts, :interval, 10_000)
    supervisor = Keyword.fetch!(opts, :supervisor)

    # Откладываем первый сбор, чтобы супервизор успел инициализироваться
    Process.send_after(self(), :collect, 5_000)
    schedule_collect(interval)

    {:ok, %{
      interval: interval,
      supervisor: supervisor,
      last_collection: System.monotonic_time()
    }}
  end

  def handle_info(:collect, state) do
    try do
      # Проверяем, что супервизор запущен и имеет функцию status
      status = if function_exported?(state.supervisor, :status, 0) do
        state.supervisor.status()
      else
        Logger.warning("Supervisor #{inspect(state.supervisor)} does not export status/0")
        []
      end

      # Безопасный подсчёт метрик
      {memory, queue_len, dsp_loaded} = calculate_metrics(status)

      # Отправляем метрики в Telemetry
      :telemetry.execute([:music_core, :audio_effects, :metrics], %{
        memory_bytes: memory,
        memory_mb: div(memory, 1_048_576),
        queue_len: queue_len,
        dsp_loaded: dsp_loaded,
        processes_count: length(status)
      }, %{
        collection_time: System.monotonic_time() - state.last_collection,
        timestamp: System.system_time(:millisecond)
      })

      # Обновляем состояние
      new_state = %{state | last_collection: System.monotonic_time()}
      schedule_collect(state.interval)
      {:noreply, new_state}

    rescue
      e ->
        Logger.error("Failed to collect metrics: #{inspect(e)}")
        schedule_collect(state.interval)
        {:noreply, state}
    end
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp calculate_metrics(status) when is_list(status) do
    memory = Enum.reduce(status, 0, fn child, acc ->
      acc + Map.get(child, :memory, 0)
    end)

    queue_len = Enum.reduce(status, 0, fn child, acc ->
      acc + Map.get(child, :message_queue_len, 0)
    end)

    dsp_loaded = Enum.any?(status, fn child ->
      case Map.get(child, :dsp_info) do
        %{nif_loaded: true} -> true
        %{dsp_loaded: true} -> true
        _ -> false
      end
    end)

    {memory, queue_len, dsp_loaded}
  end

  defp calculate_metrics(_), do: {0, 0, false}

  defp schedule_collect(interval) when interval > 0 do
    Process.send_after(self(), :collect, interval)
  end
  defp schedule_collect(_) do
    Process.send_after(self(), :collect, 10_000)
  end
end

defmodule MusicCore.HealthCheck.HealthCheck do
  @moduledoc """
  Модуль проверки здоровья MusicCore.

  Проверяет состояние всех компонентов системы.
  """

  use GenServer
  require Logger

  alias MusicCore.{
    AudioStreaming.DiscordClient,
    AudioStreaming.Processor,
    AudioStream.Manager,
    ExternalAPIs,
    GoProcessor,
    JavaGateway,
    Metrics,
    Cache,
  }

  # API

  @doc """
  Запускает health check процесс.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Выполняет полную проверку здоровья.
  """
  @spec check() :: map()
  def check do
    GenServer.call(__MODULE__, :check_health)
  end

  @doc """
  Проверяет здоровье конкретного компонента.
  """
  @spec check_component(atom()) :: :healthy | :unhealthy | :unknown
  def check_component(component) do
    GenServer.call(__MODULE__, {:check_component, component})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    Process.send_after(self(), :periodic_check, :timer.minutes(1))
    {:ok, %{last_check: nil, status: :unknown}}
  end

  @impl true
  def handle_call(:check_health, _from, state) do
    health_status = perform_health_check()
    new_state = %{state | last_check: DateTime.utc_now(), status: overall_status(health_status)}
    {:reply, health_status, new_state}
  end

  @impl true
  def handle_call({:check_component, component}, _from, state) do
    status = check_single_component(component)
    {:reply, status, state}
  end

  @impl true
  def handle_info(:periodic_check, state) do
    health_status = perform_health_check()
    log_health_issues(health_status)
    Process.send_after(self(), :periodic_check, :timer.minutes(1))
    {:noreply, %{state | last_check: DateTime.utc_now(), status: overall_status(health_status)}}
  end

  # ========== PRIVATE ==========

  defp perform_health_check do
    %{
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
      overall_status: :unknown,
      components: %{
        database: check_database(),
        cache: check_cache(),
        audio_processor: check_audio_processor(),
        stream_manager: check_stream_manager(),
        discord_client: check_discord_client(),
        external_apis: check_external_apis(),
        go_processor: check_go_processor(),
        java_gateway: check_java_gateway()
      }
    }
  end

  defp check_single_component(:database), do: check_database()
  defp check_single_component(:cache), do: check_cache()
  defp check_single_component(:audio_processor), do: check_audio_processor()
  defp check_single_component(:stream_manager), do: check_stream_manager()
  defp check_single_component(:discord_client), do: check_discord_client()
  defp check_single_component(:external_apis), do: check_external_apis()
  defp check_single_component(:go_processor), do: check_go_processor()
  defp check_single_component(:java_gateway), do: check_java_gateway()
  defp check_single_component(_), do: :unknown

  defp check_database do
    if Code.ensure_loaded?(MusicCore.Repo) do
      try do
        case MusicCore.Repo.query("SELECT 1", []) do
          {:ok, _} -> :healthy
          _ -> :unhealthy
        end
      rescue
        _ -> :unhealthy
      end
    else
      :healthy
    end
  end

  defp check_cache do
    try do
      _ = Cache.size(:audio_cache)
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  defp check_audio_processor do
    try do
      stats = Processor.stats()
      active_count = if is_map(stats), do: Map.get(stats, :active_count, 0), else: 0
      if active_count >= 0 do
        :healthy
      else
        :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_stream_manager do
    try do
      count = Manager.active_streams_count()
      if is_integer(count) do
        :healthy
      else
        :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_discord_client do
    try do
      if Code.ensure_loaded?(DiscordClient) and function_exported?(DiscordClient, :connected?, 0) do
        if DiscordClient.connected?() do
          :healthy
        else
          :unhealthy
        end
      else
        :unknown
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_external_apis do
    try do
      if Code.ensure_loaded?(ExternalAPIs.Manager) and function_exported?(ExternalAPIs.Manager, :api_available?, 1) do
        youtube_ok = ExternalAPIs.Manager.api_available?(:youtube)
        if youtube_ok do
          :healthy
        else
          :degraded
        end
      else
        :unknown
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_go_processor do
    try do
      case GoProcessor.Client.health_check() do
        true -> :healthy
        false -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_java_gateway do
    try do
      if JavaGateway.Client.health_check() do
        :healthy
      else
        :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp overall_status(health_status) do
    components = health_status.components

    cond do
      Enum.any?(components, fn {_k, v} -> v == :unhealthy end) -> :unhealthy
      Enum.any?(components, fn {_k, v} -> v == :degraded end) -> :degraded
      Enum.all?(components, fn {_k, v} -> v == :healthy end) -> :healthy
      true -> :unknown
    end
  end

  defp log_health_issues(health_status) do
    components = health_status.components

    unhealthy = Enum.filter(components, fn {_k, v} -> v == :unhealthy end)
    degraded = Enum.filter(components, fn {_k, v} -> v == :degraded end)

    if length(unhealthy) > 0 do
      Logger.warning("Unhealthy components: #{inspect(unhealthy)}")
    end

    if length(degraded) > 0 do
      Logger.info("Degraded components: #{inspect(degraded)}")
    end
  end
end

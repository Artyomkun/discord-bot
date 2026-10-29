defmodule MusicCore.HealthCheck do
  @moduledoc """
  Модуль проверки здоровья MusicCore.

  Проверяет состояние всех компонентов системы.
  """

  use GenServer
  require Logger

  alias MusicCore.{Metrics, Cache}

  # API

  @doc """
  Запускает health check процесс.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Выполняет полную проверку здоровья.

  ## Возвращает
  map со статусом здоровья
  """
  @spec check() :: map()
  def check do
    GenServer.call(__MODULE__, :check_health)
  end

  @doc """
  Проверяет здоровье конкретного компонента.

  ## Параметры
  - component: имя компонента

  ## Возвращает
  :healthy | :unhealthy | :unknown
  """
  @spec check_component(atom()) :: :healthy | :unhealthy | :unknown
  def check_component(component) do
    GenServer.call(__MODULE__, {:check_component, component})
  end

  # Server callbacks

  @impl true
  def init(_opts) do
    # Запускаем периодические проверки
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

    # Логируем проблемы
    log_health_issues(health_status)

    # Запускаем следующую проверку
    Process.send_after(self(), :periodic_check, :timer.minutes(1))

    {:noreply, %{state | last_check: DateTime.utc_now(), status: overall_status(health_status)}}
  end

  # Приватные функции

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
    try do
      # Проверяем подключение к БД
      case MusicCore.Buffer.query("SELECT 1") do
        {:ok, _} -> :healthy
        _ -> :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_cache do
    try do
      # Проверяем кэш
      Cache.size(:audio_cache)
      :healthy
    rescue
      _ -> :unhealthy
    end
  end

  defp check_audio_processor do
    try do
      # Проверяем аудио процессор
      stats = MusicCore.AudioStreaming.Processor.stats()
      if is_map(stats) and stats.active_count >= 0 do
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
      # Проверяем менеджер стримов
      count = MusicCore.AudioStream.Manager.active_streams_count()
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
      # Проверяем Discord клиент
      if MusicCore.AudioStreaming.DiscordClient.connected?() do
        :healthy
      else
        :unhealthy
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_external_apis do
    try do
      # Проверяем внешние API
      youtube_ok = MusicCore.ExternalAPIs.Manager.api_available?(:youtube)
      if youtube_ok do
        :healthy
      else
        :degraded  # Некоторые API могут быть недоступны
      end
    rescue
      _ -> :unhealthy
    end
  end

  defp check_go_processor do
    # Заглушка - в реальной реализации проверка HTTP запросом
    :unknown
  end

  defp check_java_gateway do
    # Заглушка - в реальной реализации проверка HTTP запросом
    :unknown
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
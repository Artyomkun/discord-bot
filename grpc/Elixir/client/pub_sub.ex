defmodule ElixirClient.Client.PubSub do
  @moduledoc """
  Центральный PubSub для обмена сообщениями между gRPC компонентами.

  Использует Phoenix.PubSub под капотом для распределённых сообщений.

  Поддерживает:
  - События сервисов (регистрация, дерегистрация)
  - Метрики и мониторинг
  - Health check уведомления
  - Системные события
  - Ошибки и предупреждения
  - Graceful shutdown
  """

  use Phoenix.PubSub, otp_app: :music_core, name: __MODULE__
  require Logger

  # Топики для сообщений
  @topics %{
    # gRPC сервисы
    service_up: "grpc.service.up",
    service_down: "grpc.service.down",
    service_discovery: "grpc.service.discovery",

    # Пул соединений
    pool_created: "grpc.pool.created",
    pool_destroyed: "grpc.pool.destroyed",
    pool_health: "grpc.pool.health",

    # Вызовы
    call_started: "grpc.call.started",
    call_completed: "grpc.call.completed",
    call_failed: "grpc.call.failed",

    # Балансировка
    balance_changed: "grpc.balance.changed",

    # Метрики
    metrics: "grpc.metrics",

    # Системные
    system: "grpc.system",
    errors: "grpc.errors",
    warnings: "grpc.warnings",

    # Health checks
    health_check: "grpc.health",
    health_check_result: "grpc.health.result",

    # Service discovery
    discovery_updated: "grpc.discovery.updated",
    instances_changed: "grpc.instances.changed"
  }

  @doc """
  Получить список всех доступных топиков
  """
  def topics, do: @topics

  @doc """
  Подписаться на топик
  """
  def subscribe(topic) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.subscribe(__MODULE__, topic_name)
  end
  def subscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribe(__MODULE__, topic)
  end

  @doc """
  Отписаться от топика
  """
  def unsubscribe(topic) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.unsubscribe(__MODULE__, topic_name)
  end
  def unsubscribe(topic) when is_binary(topic) do
    Phoenix.PubSub.unsubscribe(__MODULE__, topic)
  end

  @doc """
  Опубликовать сообщение в топик
  """
  def broadcast(topic, message, dispatcher \\ :none) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.broadcast(__MODULE__, topic_name, {__MODULE__, topic_name, message, dispatcher})
  end
  def broadcast(topic, message, dispatcher \\ :none) when is_binary(topic) do
    Phoenix.PubSub.broadcast(__MODULE__, topic, {__MODULE__, topic, message, dispatcher})
  end

  @doc """
  Опубликовать сообщение в топик (без получения своих сообщений)
  """
  def broadcast_from(pid, topic, message) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.broadcast_from(__MODULE__, pid, topic_name, {__MODULE__, topic_name, message, pid})
  end
  def broadcast_from(pid, topic, message) when is_binary(topic) do
    Phoenix.PubSub.broadcast_from(__MODULE__, pid, topic, {__MODULE__, topic, message, pid})
  end

  # Специализированные функции для gRPC

  @doc """
  Опубликовать событие о запуске сервиса
  """
  def broadcast_service_up(service_name, metadata \\ %{}) do
    broadcast(:service_up, %{
      service: service_name,
      metadata: metadata,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать событие об остановке сервиса
  """
  def broadcast_service_down(service_name, reason \\ :normal) do
    broadcast(:service_down, %{
      service: service_name,
      reason: reason,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать событие об обновлении discovery
  """
  def broadcast_discovery_updated(service_name, instances, changes \\ %{}) do
    broadcast(:discovery_updated, %{
      service: service_name,
      instances: instances,
      changes: changes,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать событие об изменении инстансов
  """
  def broadcast_instances_changed(service_name, added, removed) do
    broadcast(:instances_changed, %{
      service: service_name,
      added: added,
      removed: removed,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать событие о создании пула
  """
  def broadcast_pool_created(service_name, size, config) do
    broadcast(:pool_created, %{
      service: service_name,
      size: size,
      config: config,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать событие об удалении пула
  """
  def broadcast_pool_destroyed(service_name, stats) do
    broadcast(:pool_destroyed, %{
      service: service_name,
      stats: stats,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать результат health check
  """
  def broadcast_health_result(service_name, status, checks) do
    broadcast(:health_check_result, %{
      service: service_name,
      status: status,
      checks: checks,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать метрику вызова
  """
  def broadcast_call_metrics(service_name, method, duration, success) do
    broadcast(:metrics, %{
      type: :call,
      service: service_name,
      method: method,
      duration: duration,
      success: success,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать ошибку
  """
  def broadcast_error(source, error, metadata \\ %{}) do
    broadcast(:errors, %{
      source: source,
      error: error,
      metadata: metadata,
      timestamp: System.system_time(:millisecond),
      error_id: generate_error_id()
    })
  end

  @doc """
  Опубликовать предупреждение
  """
  def broadcast_warning(source, warning, metadata \\ %{}) do
    broadcast(:warnings, %{
      source: source,
      warning: warning,
      metadata: metadata,
      timestamp: System.system_time(:millisecond)
    })
  end

  @doc """
  Опубликовать системное событие
  """
  def broadcast_system_event(event, details \\ %{}) do
    broadcast(:system, %{
      event: event,
      details: details,
      timestamp: System.system_time(:millisecond)
    })
  end

  # Утилиты

  @doc """
  Получить количество подписчиков на топик
  """
  def subscribers_count(topic) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.subscribers(__MODULE__, topic_name) |> length()
  end
  def subscribers_count(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribers(__MODULE__, topic) |> length()
  end

  @doc """
  Получить список подписчиков на топик
  """
  def list_subscribers(topic) when is_atom(topic) do
    topic_name = Map.get(@topics, topic, to_string(topic))
    Phoenix.PubSub.subscribers(__MODULE__, topic_name)
  end
  def list_subscribers(topic) when is_binary(topic) do
    Phoenix.PubSub.subscribers(__MODULE__, topic)
  end

  @doc """
  Подписаться на все gRPC события
  """
  def subscribe_all do
    @topics
    |> Map.values()
    |> Enum.each(&Phoenix.PubSub.subscribe(__MODULE__, &1))
  end

  @doc """
  Отписаться от всех gRPC событий
  """
  def unsubscribe_all do
    @topics
    |> Map.values()
    |> Enum.each(&Phoenix.PubSub.unsubscribe(__MODULE__, &1))
  end

  # Приватные функции

  defp generate_error_id do
    "err_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
  end
end

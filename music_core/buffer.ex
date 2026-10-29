defmodule MusicCore.Buffer do
  @moduledoc """
  Буфер для временного хранения данных в памяти.

  Использует ETS для быстрого доступа.
  Подходит для:
  - Кэширования аудио
  - Временных данных сессий
  - Очередей
  - Состояния потоков
  """

  @tables %{
    audio: :audio_buffer,
    sessions: :session_buffer,
    queues: :queue_buffer,
    streams: :stream_buffer,
    stats: :stats_buffer,
    temp: :temp_buffer
  }

  @default_ttl 300_000  # 5 минут

  @doc """
  Инициализирует буфер при старте.
  """
  def init do
    Enum.each(@tables, fn {_name, table} ->
      :ets.new(table, [:named_table, :public, :set, :write_concurrency, :read_concurrency])
    end)

    # Запускаем cleaner для TTL
    start_cleaner()

    :ok
  end

  # ========== ОСНОВНЫЕ ОПЕРАЦИИ ==========

  @doc """
  Получить значение из буфера.
  """
  @spec get(atom(), term()) :: {:ok, term()} | {:error, :not_found}
  def get(buffer, key) do
    table = Map.get(@tables, buffer)
    now = System.system_time(:second)
    case :ets.lookup(table, key) do
      [{^key, value, expires}] when expires > now ->
        {:ok, value}

      [{^key, value}] ->
        {:ok, value}

      _ ->
        {:error, :not_found}
    end
  end

  @doc """
  Получить значение или вернуть default.
  """
  @spec get(atom(), term(), term()) :: term()
  def get(buffer, key, default) do
    case get(buffer, key) do
      {:ok, value} -> value
      {:error, :not_found} -> default
    end
  end

  @doc """
  Сохранить значение в буфер.
  """
  @spec put(atom(), term(), term()) :: :ok
  def put(buffer, key, value) do
    table = Map.get(@tables, buffer)
    :ets.insert(table, {key, value})
    :ok
  end

  @doc """
  Сохранить значение с TTL.
  """
  @spec put(atom(), term(), term(), integer()) :: :ok
  def put(buffer, key, value, ttl) do
    table = Map.get(@tables, buffer)
    expires = current_time() + ttl
    :ets.insert(table, {key, value, expires})
    :ok
  end

  @doc """
  Обновить значение (если есть).
  """
  @spec update(atom(), term(), term(), (term() -> term())) :: {:ok, term()}
  def update(buffer, key, default, fun) do
    table = Map.get(@tables, buffer)

    case :ets.lookup(table, key) do
      [{^key, old}] ->
        new = fun.(old)
        :ets.insert(table, {key, new})
        {:ok, new}

      [{^key, old, expires}] ->
        new = fun.(old)
        :ets.insert(table, {key, new, expires})
        {:ok, new}

      [] ->
        :ets.insert(table, {key, default})
        {:ok, default}
    end
  end

  @doc """
  Удалить значение.
  """
  @spec delete(atom(), term()) :: :ok
  def delete(buffer, key) do
    table = Map.get(@tables, buffer)
    :ets.delete(table, key)
    :ok
  end

  @doc """
  Проверить наличие ключа.
  """
  @spec has_key?(atom(), term()) :: boolean()
  def has_key?(buffer, key) do
    table = Map.get(@tables, buffer)
    now = System.system_time(:second)
    case :ets.lookup(table, key) do
      [] -> false
      [{^key, _, expires}] when expires < now  -> false
      _ -> true
    end
  end

  # ========== МАССОВЫЕ ОПЕРАЦИИ ==========

  @doc """
  Получить все значения.
  """
  @spec all(atom()) :: list()
  def all(buffer) do
    table = Map.get(@tables, buffer)
    :ets.tab2list(table)
    |> Enum.filter(&not_expired?/1)
    |> Enum.map(fn
      {_key, value} -> value
      {_key, value, _expires} -> value
    end)
  end

  @doc """
  Получить все пары ключ-значение.
  """
  @spec entries(atom()) :: list({term(), term()})
  def entries(buffer) do
    table = Map.get(@tables, buffer)
    :ets.tab2list(table)
    |> Enum.filter(&not_expired?/1)
    |> Enum.map(fn
      {key, value} -> {key, value}
      {key, value, _expires} -> {key, value}
    end)
  end

  @doc """
  Очистить буфер.
  """
  @spec clear(atom()) :: :ok
  def clear(buffer) do
    table = Map.get(@tables, buffer)
    :ets.delete_all_objects(table)
    :ok
  end

  @doc """
  Очистить все буферы.
  """
  @spec clear_all() :: :ok
  def clear_all do
    Enum.each(@tables, fn {_name, table} ->
      :ets.delete_all_objects(table)
    end)
    :ok
  end

  # ========== СЧЁТЧИКИ ==========

  @doc """
  Инкрементировать счётчик.
  """
  @spec increment(atom(), term()) :: integer()
  def increment(buffer, key) do
    increment(buffer, key, 1)
  end

  @spec increment(atom(), term(), integer()) :: integer()
  def increment(buffer, key, by) do
    table = Map.get(@tables, buffer)
    :ets.update_counter(table, key, {2, by}, {key, 0})
  end

  @doc """
  Получить значение счётчика.
  """
  @spec counter(atom(), term()) :: integer()
  def counter(buffer, key) do
    table = Map.get(@tables, buffer)
    case :ets.lookup(table, key) do
      [{^key, value}] -> value
      _ -> 0
    end
  end

  # ========== ОЧЕРЕДИ ==========

  @doc """
  Добавить в очередь.
  """
  @spec enqueue(atom(), term(), term()) :: :ok
  def enqueue(buffer, queue_name, item) do
    key = {:queue, queue_name}
    update(buffer, key, :queue.new(), fn q ->
      :queue.in(item, q)
    end)
    :ok
  end

  @doc """
  Взять из очереди.
  """
  @spec dequeue(atom(), term()) :: {:ok, term()} | {:error, :empty}
  def dequeue(buffer, queue_name) do
    key = {:queue, queue_name}
    table = Map.get(@tables, buffer)

    case :ets.lookup(table, key) do
      [{^key, q}] ->
        case :queue.out(q) do
          {{:value, item}, new_q} ->
            :ets.insert(table, {key, new_q})
            {:ok, item}
          {:empty, _} ->
            {:error, :empty}
        end

      _ ->
        {:error, :empty}
    end
  end

  # ========== СТАТИСТИКА ==========

  @doc """
  Размер буфера.
  """
  @spec size(atom()) :: integer()
  def size(buffer) do
    table = Map.get(@tables, buffer)
    :ets.info(table, :size)
  end

  @doc """
  Статистика по буферу.
  """
  @spec stats(atom()) :: map()
  def stats(buffer) do
    table = Map.get(@tables, buffer)
    %{
      size: :ets.info(table, :size),
      memory: :ets.info(table, :memory),
      hits: get(:stats, {:hits, buffer}, 0),
      misses: get(:stats, {:misses, buffer}, 0)
    }
  end

  # ========== ПРИВАТНОЕ ==========

  defp current_time, do: System.system_time(:millisecond)

  defp not_expired?({_key, _value}), do: true
  defp not_expired?({_key, _value, expires}), do: expires > current_time()

  defp start_cleaner do
    spawn(fn -> cleaner_loop() end)
  end

  defp cleaner_loop do
    Process.sleep(60_000)  # каждую минуту
    clean_expired()
    cleaner_loop()
  end

  defp clean_expired do
    now = current_time()
    Enum.each(@tables, fn {_name, table} ->
      :ets.foldl(fn
        {key, _value, expires} = obj when expires < now ->
          :ets.delete_object(table, obj)
        _ ->
          :ok
      end, :ok, table)
    end)
  end
end

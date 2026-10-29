defmodule MusicCore.Cache do
  @moduledoc """
  Модуль кэширования для MusicCore.
  """
  require Logger
  use GenServer

  @type cache_key :: term()
  @type cache_value :: term()
  @type ttl :: non_neg_integer() | :infinity

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, opts}
  end

  @doc """
  Получить значение из кэша по ключу.
  """
  @spec get(atom(), cache_key()) :: {:ok, cache_value()} | {:error, :not_found}
  def get(cache_name, key) do
    case ConCache.get(cache_name, key) do
      nil -> {:error, :not_found}
      value -> {:ok, value}
    end
  end

  @doc """
  Получить значение из кэша с дефолтным значением.
  """
  @spec get(atom(), cache_key(), cache_value()) :: cache_value()
  def get(cache_name, key, default) do
    case get(cache_name, key) do
      {:ok, value} -> value
      {:error, :not_found} -> default
    end
  end

  @doc """
  Сохранить значение в кэше с TTL.
  """
  @spec put(atom(), cache_key(), cache_value(), ttl()) :: :ok
  def put(cache_name, key, value, ttl \\ :infinity) do
    case ttl do
      :infinity ->
        ConCache.put(cache_name, key, value)
      ttl when is_integer(ttl) ->
        ConCache.put(cache_name, key, value, ttl: ttl)
    end
    :ok
  end

  @doc """
  Удалить значение из кэша.
  """
  @spec delete(atom(), cache_key()) :: :ok
  def delete(cache_name, key) do
    ConCache.delete(cache_name, key)
    :ok
  end

  @doc """
  Проверить существование ключа в кэше.
  """
  @spec exists?(atom(), cache_key()) :: boolean()
  def exists?(cache_name, key) do
    case ConCache.get(cache_name, key) do
      nil -> false
      _ -> true
    end
  end

  @doc """
  Очистить весь кэш.
  """
  @spec clear(atom()) :: :ok
  def clear(cache_name) do
    ConCache.clear(cache_name)
    :ok
  end

  @doc """
  Получить размер кэша.
  """
  @spec size(atom()) :: non_neg_integer()
  def size(cache_name) do
    case :ets.info(cache_name) do
      :undefined -> 0
      info -> :erlang.map_get(:size, info)
    end
  end

  @doc """
  Получить статистику кэша.
  """
  @spec stats(atom()) :: map()
  def stats(cache_name) do
    %{
      size: size(cache_name),
      cache_name: cache_name
    }
  end

  @doc """
  Атомарная операция: получить и обновить.
  """
  @spec get_and_update(atom(), cache_key(), (cache_value() -> cache_value())) ::
          {:ok, cache_value()} | {:error, :not_found}
  def get_and_update(cache_name, key, update_fun) do
    ConCache.update(cache_name, key, fn
      nil -> {:ignore, {:error, :not_found}}
      current_value ->
        new_value = update_fun.(current_value)
        {:ok, new_value, new_value}
    end)
    |> case do
      {:ok, value} -> {:ok, value}
      {:ignore, error} -> error
    end
  end

  @doc """
  Увеличивает счётчик в кэше (атомарно).
  """
  @spec increment_counter(atom(), String.t(), integer()) :: integer()
  def increment_counter(cache_name, key, inc \\ 1) do
    ConCache.update(cache_name, key, 0, fn current ->
      new_value = current + inc
      {:ok, new_value, new_value}
    end)
  end

  @doc """
  Сохраняет информацию об обработанном файле.
  """
  @spec store_processed_file(String.t(), String.t(), map()) :: :ok
  def store_processed_file(guild_id, hash, metadata) do
    key = "processed:#{guild_id}:#{hash}"
    metadata_with_ts = Map.put_new(metadata, :timestamp, DateTime.utc_now())
    put(:audio_cache, key, metadata_with_ts, :timer.hours(24 * 7))

    increment_counter(:audio_cache, "stats:processed:#{guild_id}")
    increment_counter(:audio_cache, "stats:processed:#{guild_id}:today")

    :ok
  end

  @doc """
  Получает информацию об обработанном файле.
  """
  @spec get_processed_file(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_processed_file(guild_id, hash) do
    key = "processed:#{guild_id}:#{hash}"
    get(:audio_cache, key)
  end

  @doc """
  Получает количество обработанных файлов.
  """
  @spec get_processed_count(String.t(), :today | :total) :: integer()
  def get_processed_count(guild_id, :today) do
    key = "stats:processed:#{guild_id}:today"
    get(:audio_cache, key, 0)
  end

  def get_processed_count(guild_id, :total) do
    key = "stats:processed:#{guild_id}"
    get(:audio_cache, key, 0)
  end

  @doc """
  Очистка кэша (логгирует только, ConCache сам очищает по TTL).
  """
  @spec cleanup() :: :ok
  def cleanup do
    Logger.info("""
    Cache stats:
    Audio cache size: #{size(:audio_cache)}
    Effects cache size: #{size(:effects_cache)}
    """)

    :ok
  end
end

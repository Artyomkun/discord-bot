defmodule MusicCore.AudioEffects.Effects.CacheManager do
  @moduledoc """
  Кэширование аудио с использованием ETS.
  """
  @behaviour MusicCore.AudioEffects.Effect
  use GenServer

  @table_name __MODULE__
  @cleanup_interval 60_000  # 1 минута

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    cleanup_expired()
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_expired do
    now = System.system_time(:second)
    keys = :ets.select(@table_name, [{{:_, :_, :"$1"}, [], [:"$1"]}])

    expired_keys = Enum.filter(keys, fn key ->
      case :ets.lookup(@table_name, key) do
        [{^key, _value, expires}] -> expires <= now
        [] -> false
      end
    end)

    Enum.each(expired_keys, fn key ->
      :ets.delete(@table_name, key)
    end)
  end

  @doc """
  Получить значение из кэша.
  """
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value, expires}] ->
        if expires > System.system_time(:second) do
          {:ok, value}
        else
          :ets.delete(@table_name, key)
          {:error, :expired}
        end
      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  Получить значение или nil.
  """
  def get!(key) do
    case get(key) do
      {:ok, value} -> value
      _ -> nil
    end
  end

  @doc """
  Сохранить значение в кэш.
  """
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, 3600)
    expires = System.system_time(:second) + ttl
    :ets.insert(@table_name, {key, value, expires})
    :ok
  end

  @doc """
  Проверить существование ключа.
  """
  def exists?(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, _value, expires}] ->
        expires > System.system_time(:second)
      [] -> false
    end
  end

  @doc """
  Удалить ключ из кэша.
  """
  def delete(key) do
    :ets.delete(@table_name, key)
    :ok
  end

  @doc """
  Очистить весь кэш.
  """
  def clear do
    :ets.delete_all_objects(@table_name)
    :ok
  end

  @doc """
  Получить размер кэша.
  """
  def size do
    :ets.info(@table_name, :size)
  end

  @doc """
  Получить статистику кэша.
  """
  def stats do
    %{
      size: size(),
      memory: :ets.info(@table_name, :memory),
      max_table_size: :ets.info(@table_name, :max_fixed_table_size) || 0
    }
  end

  @doc """
  Получить или вычислить значение.
  """
  def get_or_compute(key, ttl \\ 3600, compute_fn) do
    case get(key) do
      {:ok, value} ->
        value
      _ ->
        value = compute_fn.()
        put(key, value, ttl: ttl)
        value
    end
  end
end

defmodule MusicCore.AudioCache do
  @moduledoc """
  Специализированный кэш для аудио-данных.

  Использует общий модуль Cache, но с предопределённым именем :audio_cache.
  """

  alias MusicCore.Cache

  @cache_name :audio_cache

  @doc """
  Сохраняет значение в аудио-кэш.
  """
  @spec put(String.t(), term(), keyword()) :: :ok
  def put(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl, :infinity)
    Cache.put(@cache_name, key, value, ttl)
  end

  @doc """
  Получает значение из аудио-кэш.
  """
  @spec get(String.t()) :: {:ok, term()} | {:error, :not_found}
  def get(key) do
    Cache.get(@cache_name, key)
  end

  @doc """
  Получает значение с дефолтом.
  """
  @spec get(String.t(), term()) :: term()
  def get(key, default) do
    Cache.get(@cache_name, key, default)
  end

  @doc """
  Удаляет значение из аудио-кэш.
  """
  @spec delete(String.t()) :: :ok
  def delete(key) do
    Cache.delete(@cache_name, key)
  end

  @doc """
  Проверяет существование ключа.
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(key) do
    Cache.exists?(@cache_name, key)
  end

  @doc """
  Увеличивает счётчик.
  """
  @spec increment_counter(String.t(), integer()) :: integer()
  def increment_counter(key, inc \\ 1) do
    Cache.increment_counter(@cache_name, key, inc)
  end

  @doc """
  Сохраняет информацию об обработанном файле.
  """
  @spec store_processed_file(String.t(), String.t(), map()) :: :ok
  def store_processed_file(guild_id, hash, metadata) do
    Cache.store_processed_file(guild_id, hash, metadata)
  end

  @doc """
  Получает информацию об обработанном файле.
  """
  @spec get_processed_file(String.t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get_processed_file(guild_id, hash) do
    Cache.get_processed_file(guild_id, hash)
  end

  @doc """
  Получает количество обработанных файлов.
  """
  @spec get_processed_count(String.t(), :today | :total) :: integer()
  def get_processed_count(guild_id, period) do
    Cache.get_processed_count(guild_id, period)
  end

  @doc """
  Очищает аудио-кэш.
  """
  @spec clear() :: :ok
  def clear do
    Cache.clear(@cache_name)
  end

  @doc """
  Возвращает размер аудио-кэша.
  """
  @spec size() :: non_neg_integer()
  def size do
    Cache.size(@cache_name)
  end
end

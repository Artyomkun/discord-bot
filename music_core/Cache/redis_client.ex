defmodule MusicCore.Cache.RedisClient do
  @moduledoc """
  Клиент для работы с Redis.

  Предоставляет базовые операции для кэширования и хранения сессионных данных.
  """

  require Logger
  alias Redix
  
  @default_timeout 5000

  @doc """
  Получить значение по ключу.
  """
  @spec get(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get(key) when is_binary(key) do
    case redix_command(["GET", key]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Установить значение по ключу с опциональным TTL.
  """
  @spec set(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def set(key, value, opts \\ []) do
    ttl = Keyword.get(opts, :ttl)
    commands = if ttl do
      ["SET", key, value, "EX", to_string(ttl)]
    else
      ["SET", key, value]
    end

    case redix_command(commands) do
      {:ok, "OK"} -> :ok
      error -> error
    end
  end

  @doc """
  Удалить ключ.
  """
  @spec del(String.t()) :: :ok | {:error, term()}
  def del(key) do
    case redix_command(["DEL", key]) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  @doc """
  Проверить существование ключа.
  """
  @spec exists?(String.t()) :: boolean() | {:error, term()}
  def exists?(key) do
    case redix_command(["EXISTS", key]) do
      {:ok, 1} -> true
      {:ok, 0} -> false
      error -> error
    end
  end

  @doc """
  Увеличить счётчик.
  """
  @spec incr(String.t(), integer()) :: {:ok, integer()} | {:error, term()}
  def incr(key, increment \\ 1) do
    case redix_command(["INCRBY", key, to_string(increment)]) do
      {:ok, value} -> {:ok, value}
      error -> error
    end
  end

  @doc """
  Получить TTL ключа в секундах.
  """
  @spec ttl(String.t()) :: {:ok, integer()} | {:error, term()}
  def ttl(key) do
    case redix_command(["TTL", key]) do
      {:ok, -1} -> {:ok, :infinity}
      {:ok, -2} -> {:error, :not_found}
      {:ok, seconds} -> {:ok, seconds}
      error -> error
    end
  end

  @doc """
  Выполнить команду Redis напрямую.
  """
  @spec command([String.t()]) :: {:ok, term()} | {:error, term()}
  def command(args) do
    redix_command(args)
  end

  # ========== PRIVATE ==========

  defp redix_command(args) do
    case Redix.command(:redix, args, timeout: @default_timeout) do
      {:ok, result} -> {:ok, result}
      {:error, %Redix.Error{} = err} -> {:error, err.message}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e ->
      Logger.error("Redis command failed: #{inspect(e)}")
      {:error, :redis_connection_failed}
  end
end

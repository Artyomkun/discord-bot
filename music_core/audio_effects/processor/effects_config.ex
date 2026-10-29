defmodule MusicCore.AudioEffects.Processor.EffectsConfig do
  @moduledoc """
  Управление конфигурацией эффектов для процессора аудио.

  Предоставляет функции для получения настроек эффектов из разных источников:
  - Redis (сессионные настройки)
  - База данных (пользовательские)
  - База данных (настройки гильдии)
  - Дефолтные настройки
  """

  alias MusicCore.{Cache, Database, RedisClient}

  require Logger

  @default_effects %{
    equalizer: %{
      bass: 0.0,
      mid: 0.0,
      treble: 0.0,
      gain: 1.0
    },
    compressor: %{
      enabled: false,
      threshold: -20.0,
      ratio: 2.0,
      attack: 20,
      release: 250
    },
    reverb: %{
      enabled: false,
      level: 0.0,
      room_size: 0.5
    },
    normalize: true,
    volume: 100
  }

  @doc """
  Получает конфигурацию эффектов для пользователя и гильдии.
  """
  @spec get(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def get(user_id, guild_id) do
    case get_from_redis(user_id, guild_id) do
      {:ok, config} -> {:ok, config}
      {:error, _} ->
        case get_from_database(user_id, guild_id) do
          {:ok, config} -> {:ok, config}
          {:error, _} ->
            {:ok, @default_effects}
        end
    end
  end

  @doc """
  Сохраняет конфигурацию эффектов в Redis.
  """
  @spec save_to_redis(String.t(), String.t(), map()) :: :ok | {:error, term()}
  def save_to_redis(user_id, guild_id, config) do
    key = "audio:effects:#{guild_id}:#{user_id}"

    with {:ok, json} <- Jason.encode(config),
         :ok <- RedisClient.set(key, json, ttl: 86_400) do  # 24 часа
      :ok
    else
      error ->
        Logger.error("Failed to save effects config to Redis: #{inspect(error)}")
        error
    end
  end

  @doc """
  Сохраняет конфигурацию эффектов в базу данных.
  """
  @spec save_to_database(String.t(), String.t(), map()) :: {:ok, term()} | {:error, term()}
  def save_to_database(user_id, guild_id, config) do
    # Сначала пробуем сохранить как пользовательские настройки
    case Database.save_user_audio_prefs(user_id, config) do
      {:ok, prefs} -> {:ok, prefs}
      {:error, _} ->
        # Если не вышло, сохраняем как настройки гильдии
        Database.save_guild_audio_prefs(guild_id, config)
    end
  end

  @doc """
  Обновляет конкретный эффект в конфигурации.
  """
  @spec update_effect(String.t(), String.t(), atom(), map()) :: {:ok, map()} | {:error, term()}
  def update_effect(user_id, guild_id, effect_type, params) do
    with {:ok, current_config} <- get(user_id, guild_id),
         new_config = Map.put(current_config, effect_type, params),
         :ok <- save_to_redis(user_id, guild_id, new_config) do
      {:ok, new_config}
    else
      error -> error
    end
  end

  @doc """
  Сбрасывает конфигурацию к дефолтной.
  """
  @spec reset_to_default(String.t(), String.t()) :: {:ok, map()} | {:error, term()}
  def reset_to_default(user_id, guild_id) do
    save_to_redis(user_id, guild_id, @default_effects)
    {:ok, @default_effects}
  end

  defp get_from_redis(user_id, guild_id) do
    key = "audio:effects:#{guild_id}:#{user_id}"

    case RedisClient.get(key) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, json} ->
        case Jason.decode(json, keys: :atoms) do
          {:ok, config} -> {:ok, config}
          error -> error
        end
      error -> error
    end
  end

  defp get_from_database(user_id, guild_id) do
    case Database.get_user_audio_prefs(user_id) do
      {:ok, config} -> {:ok, config}
      {:error, _} ->
        case Database.get_guild_audio_prefs(guild_id) do
          {:ok, config} -> {:ok, config}
          error -> error
        end
    end
  end
end

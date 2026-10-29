defmodule MusicCore.Cache.Database do
  @moduledoc """
  Модуль для работы с базой данных (PostgreSQL через Ecto).

  Предоставляет функции для получения пользовательских и гильдийных
  настроек аудио эффектов.
  """

  require Logger
  import MusicCore.Repo
  alias MusicCore.Schema.GuildPrefs
  alias MusicCore.Schema.UserPrefs

  @doc """
  Получить аудио настройки пользователя.
  """
  @spec get_user_audio_prefs(String.t()) :: {:ok, map()} | {:error, term()}
  def get_user_audio_prefs(user_id) when is_binary(user_id) do
    if Code.ensure_loaded?(Repo) do
      try do
        case Repo.get_by(UserPrefs, user_id: user_id) do
          %{prefs: prefs} when is_map(prefs) ->
            {:ok, prefs}
          nil ->
            {:ok, %{}}
          other ->
            {:error, {:invalid_response, other}}
        end
      rescue
        e -> {:error, {:database_error, e}}
      end
    else
      # Fallback: возвращаем пустые настройки если Ecto не доступен
      Logger.warning("Ecto not available, using empty user prefs")
      {:ok, %{}}
    end
  end

  @doc """
  Получить аудио настройки гильдии (сервера).
  """
  @spec get_guild_audio_prefs(String.t()) :: {:ok, map()} | {:error, term()}
  def get_guild_audio_prefs(guild_id) when is_binary(guild_id) do
    if Code.ensure_loaded?(Repo) do
      try do
        case Repo.get_by(GuildPrefs, guild_id: guild_id) do
          %{prefs: prefs} when is_map(prefs) ->
            {:ok, prefs}
          nil ->
            {:ok, %{}}
          other ->
            {:error, {:invalid_response, other}}
        end
      rescue
        e -> {:error, {:database_error, e}}
      end
    else
      # Fallback: возвращаем пустые настройки если Ecto не доступен
      Logger.warning("Ecto not available, using empty guild prefs")
      {:ok, %{}}
    end
  end

  @doc """
  Сохранить аудио настройки пользователя.
  """
  @spec set_user_audio_prefs(String.t(), map()) :: :ok | {:error, term()}
  def set_user_audio_prefs(user_id, prefs) when is_binary(user_id) and is_map(prefs) do
    if Code.ensure_loaded?(Repo) do
      try do
        case Repo.get_by(UserPrefs, user_id: user_id) do
          nil ->
            %UserPrefs{user_id: user_id, prefs: prefs}
            |> Repo.insert()
            |> case do
              {:ok, _} -> :ok
              error -> error
            end
          existing ->
            existing
            |> Ecto.Changeset.change(%{prefs: prefs})
            |> Repo.update()
            |> case do
              {:ok, _} -> :ok
              error -> error
            end
        end
      rescue
        e -> {:error, {:database_error, e}}
      end
    else
      Logger.warning("Ecto not available, user prefs not saved")
      :ok
    end
  end

  @doc """
  Сохранить аудио настройки гильдии.
  """
  @spec set_guild_audio_prefs(String.t(), map()) :: :ok | {:error, term()}
  def set_guild_audio_prefs(guild_id, prefs) when is_binary(guild_id) and is_map(prefs) do
    if Code.ensure_loaded?(Repo) do
      try do
        case Repo.get_by(GuildPrefs, guild_id: guild_id) do
          nil ->
            %GuildPrefs{guild_id: guild_id, prefs: prefs}
            |> Repo.insert()
            |> case do
              {:ok, _} -> :ok
              error -> error
            end
          existing ->
            existing
            |> Ecto.Changeset.change(%{prefs: prefs})
            |> Repo.update()
            |> case do
              {:ok, _} -> :ok
              error -> error
            end
        end
      rescue
        e -> {:error, {:database_error, e}}
      end
    else
      Logger.warning("Ecto not available, guild prefs not saved")
      :ok
    end
  end

  @doc """
  Сохранить аудио настройки пользователя.
  """
  @spec save_user_audio_prefs(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_user_audio_prefs(user_id, prefs) do
    set_user_audio_prefs(user_id, prefs)
    {:ok, prefs}
  end

  @doc """
  Сохранить аудио настройки гильдии.
  """
  @spec save_guild_audio_prefs(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def save_guild_audio_prefs(guild_id, prefs) do
    set_guild_audio_prefs(guild_id, prefs)
    {:ok, prefs}
  end
end

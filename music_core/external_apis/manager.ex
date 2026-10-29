defmodule MusicCore.ExternalAPIs.Manager do
  @moduledoc """
  Менеджер для работы с внешними API.
  Вся логика обработки вынесена в Go сервис.
  """

  alias MusicCore.GoProcessor.Client

  @doc """
  Проверяет доступность API через Go сервис.
  """
  @spec api_available?(atom()) :: boolean()
  def api_available?(api_name) do
    case Client.get_api_status() do
      {:ok, %{"apis" => apis}} ->
        case Map.get(apis, to_string(api_name)) do
          %{"available" => available} -> available
          _ -> false
        end
      _ -> false
    end
  end

  @doc """
  Получает статус всех API через Go сервис.
  """
  @spec get_status() :: map()
  def get_status do
    case Client.get_api_status() do
      {:ok, %{"apis" => apis}} -> apis
      _ -> %{}
    end
  end

  @doc """
  Делает запрос к API через Go сервис.
  """
  @spec request(atom(), String.t(), map(), keyword()) :: {:ok, map()} | {:error, term()}
  def request(api_name, endpoint, params \\ %{}, _opts \\ []) do
    Client.api_request(api_name, endpoint, params)
  end
end

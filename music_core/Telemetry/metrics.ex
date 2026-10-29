defmodule MusicCore.Telemetry.Metrics do
  @moduledoc """
  Модуль для сбора и обновления метрик приложения.
  """

  @doc """
  Обновляет метрики состояния на основе новых данных.
  """
  def update(state, metrics) do
    current_metrics = Map.get(state, :metrics, %{})
    updated_metrics = Map.merge(current_metrics, metrics)

    %{state | metrics: updated_metrics}
  end

  @doc """
  Возвращает текущие метрики из состояния.
  """
  def get(state) do
    Map.get(state, :metrics, %{})
  end

  @doc """
  Сбрасывает метрики в исходное состояние.
  """
  def reset(state) do
    %{state | metrics: %{}}
  end

  @doc """
  Увеличивает счётчик метрики на заданное значение.
  """
  def increment(state, key, value \\ 1) do
    current = get_in(state, [:metrics, key]) || 0
    put_in(state, [:metrics, key], current + value)
  end

  @doc """
  Устанавливает значение метрики.
  """
  def set(state, key, value) do
    put_in(state, [:metrics, key], value)
  end

  @doc """
  Обновляет среднее значение метрики (скользящее среднее).
  """
  def update_average(state, key, new_value, total_count) do
    old_avg = get_in(state, [:metrics, key]) || 0.0
    new_avg = old_avg + (new_value - old_avg) / total_count
    put_in(state, [:metrics, key], new_avg)
  end

  def distribution(name, measurement, unit) do
    %{
      type: :distribution,
      name: name,
      measurement: measurement,
      unit: unit
    }
  end
end

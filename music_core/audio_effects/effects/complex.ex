defmodule MusicCore.AudioEffects.Effects.Complex do
  @moduledoc """
  Работа с комплексными числами для DSP.
  """
  @behaviour MusicCore.AudioEffects.Effect

  import Kernel

  @type t :: {float(), float()}

  @doc """
  Создание комплексного числа из полярных координат.
  """
  def from_polar(r, theta) when is_number(r) and is_number(theta) do
    {r * :math.cos(theta), r * :math.sin(theta)}
  end

  @doc """
  Фаза (аргумент) комплексного числа.
  """
  def arg({re, im}) when is_number(re) and is_number(im) do
    :math.atan2(im, re)
  end

  @doc """
  Сложение.
  """
  def add({re1, im1}, {re2, im2}) do
    {re1 + re2, im1 + im2}
  end

  @doc """
  Вычитание.
  """
  def sub({re1, im1}, {re2, im2}) do
    {re1 - re2, im1 - im2}
  end

  @doc """
  Умножение.
  """
  def mul({re1, im1}, {re2, im2}) do
    {re1 * re2 - im1 * im2, re1 * im2 + im1 * re2}
  end

  @doc """
  Деление.
  """
  def div({re1, im1}, {re2, im2}) do
    denom = re2 * re2 + im2 * im2
    if denom == 0 do
      {0, 0}
    else
      {(re1 * re2 + im1 * im2) / denom, (im1 * re2 - re1 * im2) / denom}
    end
  end

  @doc """
  Сопряжённое число.
  """
  def conj({re, im}) do
    {re, -im}
  end

  @doc """
  Экспонента комплексного числа.
  """
  def exp({re, im}) do
    factor = :math.exp(re)
    {factor * :math.cos(im), factor * :math.sin(im)}
  end

  @doc """
  Возведение в степень.
  """
  def pow({re, im}, exponent) when is_number(exponent) do
    r = abs({re, im})
    theta = arg({re, im})
    from_polar(:math.pow(r, exponent), theta * exponent)
  end

  @doc """
  Квадрат модуля.
  """
  def abs_sq({re, im}) do
    re * re + im * im
  end

  @doc """
  Нормализация.
  """
  def normalize({re, im}) do
    mag = abs({re, im})
    if mag == 0 do
      {0, 0}
    else
      {re / mag, im / mag}
    end
  end
end

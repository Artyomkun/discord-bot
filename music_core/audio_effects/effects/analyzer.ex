defmodule MusicCore.AudioEffects.Effects.Analyzer do
  @moduledoc """
  Модуль для комплексного анализа аудиоданных.
  Содержит все функции для извлечения характеристик из аудио.
  """
  @behaviour MusicCore.AudioEffects.Effect
  alias MusicCore.AudioEffects.Effects.Analysis

  @doc """
  Основная точка входа для анализа аудио.
  """
  def analyze(audio_data, opts \\ []) do
    analysis = %{
      metadata: Analysis.extract_metadata(audio_data),
      waveform: Analysis.analyze_waveform(audio_data),
      spectrum: Analysis.analyze_spectrum(audio_data, opts),
      dynamics: Analysis.analyze_dynamics(audio_data),
      spatial: Analysis.analyze_spatial(audio_data),
      quality: Analysis.analyze_quality(audio_data)
    }

    if Keyword.get(opts, :summary, false) do
      Map.put(analysis, :summary, Analysis.generate_summary(analysis))
    else
      analysis
    end
  end

  @doc """
  Сравнивает два аудиофайла и возвращает метрики схожести.
  """
  def compare(audio1, audio2) do
    analysis1 = analyze(audio1)
    analysis2 = analyze(audio2)

    spectral_sim = calculate_spectral_similarity(
      Map.get(analysis1, :spectrum, %{}),
      Map.get(analysis2, :spectrum, %{})
    )

    dynamics_sim = calculate_dynamics_similarity(
      Map.get(analysis1, :dynamics, %{}),
      Map.get(analysis2, :dynamics, %{})
    )

    spatial_sim = calculate_spatial_similarity(
      Map.get(analysis1, :spatial, %{}),
      Map.get(analysis2, :spatial, %{})
    )

    %{
      spectral_similarity: spectral_sim,
      dynamic_similarity: dynamics_sim,
      spatial_similarity: spatial_sim,
      overall_similarity: (spectral_sim * 0.5 + dynamics_sim * 0.3 + spatial_sim * 0.2)
    }
  end

  defp calculate_spectral_similarity(spectrum1, spectrum2) do
    c1 = Map.get(spectrum1, :centroid, 0)
    c2 = Map.get(spectrum2, :centroid, 0)
    diff = abs(c1 - c2)
    1.0 - min(1.0, diff / 5000.0)
  end

  defp calculate_spectral_similarity(_, _) do
    0.0
  end

  defp calculate_dynamics_similarity(%{dynamic_range: dr1}, %{dynamic_range: dr2}) do
    diff = abs(dr1 - dr2)
    1.0 - min(1.0, diff / 40.0)
  end

  defp calculate_dynamics_similarity(_, _) do
    0.0
  end

  defp calculate_spatial_similarity(%{type: :mono}, %{type: :mono}) do
    1.0
  end

  defp calculate_spatial_similarity(%{type: :stereo, phase_coherence: pc1}, %{type: :stereo, phase_coherence: pc2}) do
    diff = abs(pc1 - pc2)
    1.0 - min(1.0, diff / 1.0)
  end

  defp calculate_spatial_similarity(_, _) do
    0.5
  end
end

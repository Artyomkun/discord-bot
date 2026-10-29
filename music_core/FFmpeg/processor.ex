defmodule MusicCore.FFmpeg.Processor do
  @moduledoc """
  FFmpeg аудио процессор.

  Отвечает за обработку аудио через FFmpeg: конвертация, применение эффектов,
  изменение формата и т.д.
  """

  alias MusicCore.Config
  require Logger

  @default_ffmpeg_path "/usr/bin/ffmpeg"

  @doc """
  Процессинг аудио через FFmpeg.
  """
  def process(raw_stream, effects_config, audio_source \\ :youtube) do
    output_path = generate_temp_path("audio_opus")

    case start_ffmpeg(raw_stream, effects_config, output_path) do
      {:ok, ^output_path} ->
        Logger.debug("FFmpeg processing completed: #{output_path}")
        {:ok, output_path}

      {:error, reason} ->
        Logger.error("FFmpeg processing failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Запуск FFmpeg процесса.
  """
  def run(input_data, args, output_path) do
    config = Config.load()
    ffmpeg_path = config.ffmpeg_path || @default_ffmpeg_path

    port = :erlang.open_port({:spawn, ffmpeg_path}, [
      :binary,
      :exit_status,
      {:args, args}
    ])

    # Отправляем данные в stdin FFmpeg
    send(port, {self(), {:command, input_data}})
    send(port, {self(), :eof})

    receive_ffmpeg_output(port, output_path)
  end

  # ========== PRIVATE ==========

  defp start_ffmpeg(raw_stream, effects_config, output_path) do
    args = build_ffmpeg_args(effects_config, output_path)

    case run(raw_stream, args, output_path) do
      {:ok, ^output_path} -> {:ok, output_path}
      error -> error
    end
  end

  defp build_ffmpeg_args(effects_config, output_path) do
    base_args = [
      "-i", "pipe:0",
      "-c:a", "libopus",
      "-b:a", "128k",
      "-ar", "48000",
      "-ac", "2",
      "-f", "opus",
      "-y",
      output_path
    ]

    filters = build_audio_filters(effects_config)

    if filters == [] do
      base_args
    else
      base_args ++ ["-af", Enum.join(filters, ",")]
    end
  end

  defp build_audio_filters(effects) do
    []
    |> maybe_add_volume(effects[:volume])
    |> maybe_add_equalizer(effects[:equalizer])
    |> maybe_add_compressor(effects[:compressor])
    |> maybe_add_reverb(effects[:reverb])
    |> maybe_add_normalization(effects[:normalize])
  end

  defp maybe_add_volume(filters, volume) when is_number(volume) and volume != 100 do
    vol = volume / 100.0
    filters ++ ["volume=#{vol}"]
  end
  defp maybe_add_volume(filters, _), do: filters

  defp maybe_add_equalizer(filters, nil), do: filters
  defp maybe_add_equalizer(filters, eq) when map_size(eq) == 0, do: filters
  defp maybe_add_equalizer(filters, eq) do
    bass = Map.get(eq, :bass, 0.0)
    mid = Map.get(eq, :mid, 0.0)
    treble = Map.get(eq, :treble, 0.0)

    if bass != 0.0 or mid != 0.0 or treble != 0.0 do
      filters ++ ["superequalizer=1b=#{bass}:2b=#{mid}:3b=#{treble}"]
    else
      filters
    end
  end

  defp maybe_add_compressor(filters, nil), do: filters
  defp maybe_add_compressor(filters, %{enabled: false}), do: filters
  defp maybe_add_compressor(filters, %{enabled: true, threshold: th, ratio: r, attack: a, release: rel}) do
    points = "-#{th}/-#{th * r}|-6/-10"
    filters ++ ["compand=attacks=#{a}:decays=#{rel}:points=#{points}"]
  end
  defp maybe_add_compressor(filters, _), do: filters

  defp maybe_add_reverb(filters, nil), do: filters
  defp maybe_add_reverb(filters, %{enabled: false}), do: filters
  defp maybe_add_reverb(filters, %{enabled: true, level: level, room_size: size}) do
    filters ++ ["aecho=#{level * 0.5}:#{level * 0.5}:#{size * 1000}:0.5"]
  end
  defp maybe_add_reverb(filters, _), do: filters

  defp maybe_add_normalization(filters, true) do
    filters ++ ["dynaudnorm"]
  end
  defp maybe_add_normalization(filters, false), do: filters
  defp maybe_add_normalization(filters, _), do: filters

  defp receive_ffmpeg_output(port, output_path) do
    receive do
      {^port, {:data, data}} ->
        Logger.debug("FFmpeg output: #{data}")
        receive_ffmpeg_output(port, output_path)

      {^port, {:exit_status, 0}} ->
        {:ok, output_path}

      {^port, {:exit_status, status}} ->
        {:error, "FFmpeg exited with status #{status}"}

      {:PORT, {:closed, ^port}} ->
        {:error, "FFmpeg port closed"}

      after
        30_000 ->
          Port.close(port)
          {:error, :timeout}
    end
  end

  defp generate_temp_path(prefix) do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(100_000)
    Path.join(System.tmp_dir!(), "#{prefix}_#{timestamp}_#{random}.opus")
  end
end

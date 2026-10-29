defmodule MusicCore.AudioEffects.FFmpegWrapper do
  @moduledoc """
  Обёртка для работы с FFmpeg.
  Предоставляет функции для конвертации, обработки и анализа аудио.
  """
  require Logger
  use GenServer
  alias MusicCore.Config

  @default_ffmpeg_path "/usr/bin/ffmpeg"
  @default_ffprobe_path "/usr/bin/ffprobe"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    {:ok, opts}
  end

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc """
  Обрабатывает аудио поток через FFmpeg с указанными фильтрами.
  """
  def process(audio_stream, filters, output_format, bitrate, extra_args \\ []) do
    temp_input = generate_temp_path("input")
    temp_output = generate_temp_path("output.#{output_format}")

    try do
      File.write!(temp_input, audio_stream)

      args = [
        "-i", temp_input,
        "-c:a", codec_for_format(output_format),
        "-b:a", bitrate
      ] ++ build_filter_args(filters) ++ extra_args ++ [temp_output]

      case run_ffmpeg(args, temp_output) do
        {:ok, _path} -> {:ok, File.read!(temp_output)}
        error -> error
      end
    after
      File.rm(temp_input)
      File.rm(temp_output)
    end
  end

  @doc """
  Конвертирует аудио файл в нужный формат.
  """
  @spec convert(String.t(), String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def convert(input_path, output_path, options \\ []) do
    config = Config.load()

    codec = Keyword.get(options, :codec, config.ffmpeg_codec)
    bitrate = Keyword.get(options, :bitrate, config.ffmpeg_bitrate)
    sample_rate = Keyword.get(options, :sample_rate, config.ffmpeg_sample_rate)
    channels = Keyword.get(options, :channels, config.ffmpeg_channels)

    args = [
      "-i", input_path,
      "-c:a", codec,
      "-b:a", "#{bitrate}k",
      "-ar", "#{sample_rate}",
      "-ac", "#{channels}",
      "-y",
      output_path
    ]

    run_ffmpeg(args, output_path)
  end

  @doc """
  Применяет фильтры к аудио.
  """
  @spec apply_filters(String.t(), String.t(), list(String.t())) :: {:ok, String.t()} | {:error, term()}
  def apply_filters(input_path, output_path, filters) do
    args = [
      "-i", input_path,
      "-af", Enum.join(filters, ","),
      "-y",
      output_path
    ]

    run_ffmpeg(args, output_path)
  end

  @doc """
  Получает информацию об аудио файле.
  """
  @spec get_info(String.t()) :: {:ok, map()} | {:error, term()}
  def get_info(file_path) do
    args = [
      "-i", file_path,
      "-f", "null",
      "-"
    ]

    case run_ffmpeg(args, nil, stderr: true) do
      {:ok, output} ->
        parse_ffprobe_info(output)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Нормализует громкость аудио.
  """
  @spec normalize(String.t(), String.t(), float()) :: {:ok, String.t()} | {:error, term()}
  def normalize(input_path, output_path, target_lufs \\ -16.0) do
    filter = "loudnorm=I=#{target_lufs}:TP=-1.5:LRA=11:print_format=json"

    args = [
      "-i", input_path,
      "-af", filter,
      "-y",
      output_path
    ]

    run_ffmpeg(args, output_path)
  end

  @doc """
  Обрезает аудио.
  """
  @spec trim(String.t(), String.t(), float(), float()) :: {:ok, String.t()} | {:error, term()}
  def trim(input_path, output_path, start_time, duration) do
    args = [
      "-i", input_path,
      "-ss", "#{start_time}",
      "-t", "#{duration}",
      "-c", "copy",
      "-y",
      output_path
    ]

    run_ffmpeg(args, output_path)
  end

  @doc """
  Смешивает несколько аудио файлов.
  """
  @spec mix(list(String.t()), String.t()) :: {:ok, String.t()} | {:error, term()}
  def mix(input_paths, output_path) do
    inputs = Enum.flat_map(input_paths, fn path -> ["-i", path] end)
    count = length(input_paths)

    filter = Enum.map_join(1..count, "", fn i -> "[#{i-1}:a]" end) <> "amix=inputs=#{count}:duration=longest"

    args = inputs ++
           ["-filter_complex", filter] ++
           ["-y", output_path]

    run_ffmpeg(args, output_path)
  end

  # ============================================================================
  # PRIVATE FUNCTIONS
  # ============================================================================

  defp run_ffmpeg(args, output_path, opts \\ []) do
    config = Config.load()
    ffmpeg_path = config.ffmpeg_path || @default_ffmpeg_path

    cmd_args = [ffmpeg_path | args]

    case System.cmd(hd(cmd_args), tl(cmd_args), stderr_to_stdout: true) do
      {output, 0} ->
        case Keyword.get(opts, :stderr, false) do
          true -> {:ok, output}
          false when is_binary(output_path) -> {:ok, output_path}
          false -> {:ok, output}
        end

      {output, code} ->
        Logger.error("FFmpeg error (code #{code}): #{output}")
        {:error, {:ffmpeg_error, code, output}}
    end
  rescue
    e ->
      Logger.error("FFmpeg execution failed: #{inspect(e)}")
      {:error, {:execution_error, e}}
  end

  defp build_filter_args(filters) when is_list(filters) do
    if Enum.empty?(filters) do
      []
    else
      ["-af", Enum.join(filters, ",")]
    end
  end
  defp build_filter_args(_), do: []

  defp codec_for_format("mp3"), do: "libmp3lame"
  defp codec_for_format("aac"), do: "aac"
  defp codec_for_format("ogg"), do: "libvorbis"
  defp codec_for_format("opus"), do: "libopus"
  defp codec_for_format("flac"), do: "flac"
  defp codec_for_format("wav"), do: "pcm_s16le"
  defp codec_for_format(_), do: "aac"

  defp generate_temp_path(prefix) do
    timestamp = System.system_time(:millisecond)
    random = :rand.uniform(100_000)
    Path.join(System.tmp_dir!(), "#{prefix}_#{timestamp}_#{random}")
  end

  # ============================================================================
  # INFO PARSING
  # ============================================================================

  defp parse_ffprobe_info(output) do
    case Jason.decode(output) do
      {:ok, data} ->
        format = data["format"] || %{}
        streams = data["streams"] || []
        audio_stream = Enum.find(streams, fn s -> s["codec_type"] == "audio" end) || %{}

        duration = case format["duration"] do
          dur when is_binary(dur) -> String.to_float(dur)
          dur when is_number(dur) -> dur
          _ -> 0.0
        end

        bitrate = case format["bit_rate"] do
          br when is_binary(br) -> String.to_integer(br)
          br when is_number(br) -> br
          _ -> 0
        end

        sample_rate = case audio_stream["sample_rate"] do
          sr when is_binary(sr) -> String.to_integer(sr)
          sr when is_number(sr) -> sr
          _ -> 0
        end

        channels = case audio_stream["channels"] do
          ch when is_binary(ch) -> String.to_integer(ch)
          ch when is_number(ch) -> ch
          _ -> 0
        end

        codec = audio_stream["codec_name"] || "unknown"
        sample_format = audio_stream["sample_fmt"] || "unknown"
        bit_depth = case audio_stream["bits_per_sample"] do
          bps when is_binary(bps) -> String.to_integer(bps)
          bps when is_number(bps) -> bps
          _ -> 16
        end

        tags = format["tags"] || %{}

        {:ok, %{
          duration: duration,
          bitrate: bitrate,
          format: format["format_name"] || "unknown",
          codec: codec,
          sample_rate: sample_rate,
          channels: channels,
          sample_format: sample_format,
          bit_depth: bit_depth,
          tags: tags,
          title: tags["title"],
          artist: tags["artist"],
          album: tags["album"],
          year: tags["date"],
          track: tags["track"]
        }}

      {:error, _} ->
        parse_info_from_text(output)
    end
  end

  defp parse_info_from_text(output) do
    {:ok, %{
      duration: parse_duration_regex(output),
      bitrate: parse_bitrate_regex(output),
      format: parse_format_regex(output),
      codec: parse_codec_regex(output),
      sample_rate: parse_sample_rate_regex(output),
      channels: parse_channels_regex(output),
      sample_format: "unknown",
      bit_depth: 16,
      tags: %{}
    }}
  end

  defp parse_duration_regex(output) do
    case Regex.run(~r/Duration: (\d{2}):(\d{2}):(\d{2}\.\d+)/, output) do
      [_, h, m, s] ->
        String.to_integer(h) * 3600 + String.to_integer(m) * 60 + String.to_float(s)
      nil -> 0.0
    end
  end

  defp parse_bitrate_regex(output) do
    case Regex.run(~r/bitrate: (\d+) kb\/s/, output) do
      [_, br] -> String.to_integer(br)
      nil -> 0
    end
  end

  defp parse_format_regex(output) do
    case Regex.run(~r/Input #0, (\w+),/, output) do
      [_, format] -> format
      nil -> "unknown"
    end
  end

  defp parse_codec_regex(output) do
    case Regex.run(~r/Audio: (\w+)/, output) do
      [_, codec] -> codec
      nil -> "unknown"
    end
  end

  defp parse_sample_rate_regex(output) do
    case Regex.run(~r/(\d+) Hz/, output) do
      [_, rate] -> String.to_integer(rate)
      nil -> 0
    end
  end

  defp parse_channels_regex(output) do
    case Regex.run(~r/(\d+) channels?/, output) do
      [_, ch] -> String.to_integer(ch)
      nil -> 0
    end
  end
end

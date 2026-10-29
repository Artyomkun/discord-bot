defmodule MusicCore.AudioStreaming.FFmpeg do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    # Здесь логика для FFmpeg
    path = Keyword.get(opts, :path, "ffmpeg")
    buffer = Keyword.get(opts, :buffer_size, 8192)

    # Проверяем, что ffmpeg доступен
    case System.find_executable(path) do
      nil ->
        Logger.error("FFmpeg not found at #{path}")
        {:ok, %{available: false}}
      exec_path ->
        Logger.info("FFmpeg found at #{exec_path}")
        {:ok, %{available: true, path: exec_path, buffer: buffer}}
    end
  end

  def available? do
    GenServer.call(__MODULE__, :available?)
  end

  def handle_call(:available?, state) do
    {:reply, state[:available] == true, state}
  end

  defp ffmpeg_opts(config) do
    ffmpeg = config[:ffmpeg] || %{}
    [
      path: ffmpeg[:path] || "ffmpeg",
      buffer_size: ffmpeg[:buffer_size] || 8192,
      sample_rate: ffmpeg[:sample_rate] || 48000,
      channels: ffmpeg[:channels] || 2,
      bitrate: ffmpeg[:bitrate] || 128,
      codec: ffmpeg[:codec] || "libmp3lame",
      format: ffmpeg[:format] || "mp3",
      reconnect_attempts: ffmpeg[:reconnect_attempts] || 5,
      reconnect_delay: ffmpeg[:reconnect_delay] || 1_000,
      frame_buffer: ffmpeg[:frame_buffer] || 5000,
      opus_quality: ffmpeg[:opus_quality] || 4
    ]
  end
end

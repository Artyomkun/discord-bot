defmodule MusicCore.AudioStreaming.DiscordClient do
  @moduledoc """
  Клиент для подключения к FFmpeg через WebSocket.
  Обёртка над FFmpegClient.
  """

  use GenServer
  require Logger

  alias MusicCore.AudioStreaming.FFmpegClient
  alias MusicCore.Metrics

  # API

  def start_link(opts \\ []) do
    url = Application.get_env(:music_core, :ffmpeg_url, "ws://localhost:8080/ws")
    GenServer.start_link(__MODULE__, %{url: url}, name: __MODULE__)
  end

  def connected? do
    GenServer.call(__MODULE__, :connected?)
  end

  def connect_voice(guild_id, channel_id, session_id, token) do
    endpoint = get_voice_endpoint(channel_id)
    GenServer.cast(__MODULE__, {:connect_voice, guild_id, channel_id, session_id, token, endpoint})
  end

  def disconnect_voice(guild_id) do
    GenServer.cast(__MODULE__, {:disconnect_voice, guild_id})
  end

  def play_track(guild_id, track) do
    GenServer.cast(__MODULE__, {:play_track, guild_id, track})
  end

  def stop_track(guild_id) do
    GenServer.cast(__MODULE__, {:stop_track, guild_id})
  end

  def set_volume(guild_id, volume) when volume >= 0 and volume <= 100 do
    GenServer.cast(__MODULE__, {:set_volume, guild_id, volume})
  end

  # Server callbacks

  def init(state) do
    case FFmpegClient.start_link(url: state.url, name: FFmpegClient) do
      {:ok, pid} ->
        Logger.info("DiscordClient started with FFmpeg")
        {:ok, %{pid: pid, connected: false}}

      {:error, reason} ->
        Logger.error("Failed to start FFmpeg client: #{inspect(reason)}")
        {:ok, %{pid: nil, connected: false}}
    end
  end

  def handle_call(:connected?, state) do
    {:reply, state.connected, state}
  end

  def handle_cast({:connect_voice, guild_id, _channel_id, session_id, token, endpoint}, state) do
    FFmpegClient.connect_voice(FFmpegClient, guild_id, session_id, token, endpoint)
    Metrics.record(:voice_connected, 1, %{guild_id: guild_id})
    {:noreply, state}
  end

  def handle_cast({:disconnect_voice, guild_id}, state) do
    FFmpegClient.disconnect(FFmpegClient, guild_id)
    Metrics.record(:voice_disconnected, 1, %{guild_id: guild_id})
    {:noreply, state}
  end

  def handle_cast({:play_track, guild_id, track}, state) do
    start_time = Map.get(track, "start_time", 0)
    end_time = Map.get(track, "duration", 0)
    volume = Map.get(track, "volume", 100)

    FFmpegClient.play(FFmpegClient, guild_id, track["url"], start_time, end_time, volume)
    Metrics.record(:track_play_requested, 1, %{guild_id: guild_id})
    {:noreply, state}
  end

  def handle_cast({:stop_track, guild_id}, state) do
    FFmpegClient.stop(FFmpegClient, guild_id)
    Metrics.record(:track_stop_requested, 1, %{guild_id: guild_id})
    {:noreply, state}
  end

  def handle_cast({:set_volume, guild_id, volume}, state) do
    FFmpegClient.volume(FFmpegClient, guild_id, volume)
    Metrics.record(:volume_changed, volume, %{guild_id: guild_id})
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.debug("Unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end

  defp get_voice_endpoint(channel_id) do
    region = get_region_from_channel(channel_id)
    "voice.#{region}.discord.gg"
  end

  defp get_region_from_channel(_channel_id) do
    "us"
  end
end

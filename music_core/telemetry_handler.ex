defmodule MusicCore.TelemetryHandler do
  require Logger

  def handle_event([:music_core, :dsp, :nif, :loaded], measurements, metadata, _config) do
    success = Map.get(measurements, :success, false)

    if success do
      Logger.info("✅ DSP NIF loaded successfully")
      :prometheus_counter.inc(:dsp_nif_load_success)

      case Map.get(metadata, :load_time_ms) do
        nil -> :ok
        time -> Logger.debug("NIF load took #{time}ms")
      end
    else
      error_reason = Map.get(metadata, :error, "unknown error")
      error_details = Map.get(metadata, :details, "no details")

      Logger.error("❌ DSP NIF failed to load: #{error_reason} (#{error_details})")
      :prometheus_counter.inc(:dsp_nif_load_error, [error_reason])

      if Map.get(metadata, :critical, false) do
        Logger.critical("CRITICAL: DSP NIF required for operation, system may be unstable")
      end
    end

      :ok
    catch
      error, stacktrace ->
        Logger.error("Telemetry handler crashed: #{inspect(error)} at #{inspect(stacktrace)}")
        :ok
  end

  def rustc_version, do: :erlang.nif_error(:nif_not_loaded)
  def version, do: :erlang.nif_error(:nif_not_loaded)

  def handle_event([:music_core, :dsp, :call], measurements, metadata, _config) do
    duration = Map.get(measurements, :duration, 0)
    effect = Map.get(metadata, :effect, "unknown")
    success = Map.get(measurements, :success, true)

    :prometheus_histogram.observe(:dsp_call_duration, [effect], duration)

    if not success do
      reason = Map.get(metadata, :reason, "unknown")
      :prometheus_counter.inc(:dsp_call_error, [effect, reason])
      Logger.warning("⚠️ DSP call failed for effect #{effect}: #{reason}")
    end
  end

  def handle_event([:music_core, :audio_effects, :metrics], measurements, _metadata, _config) do
    memory = Map.get(measurements, :memory, 0)
    queue_len = Map.get(measurements, :queue_len, 0)
    
    Logger.debug("Audio effects metrics - memory: #{memory} bytes, queue: #{queue_len}")

    if memory > 100_000_000 do
      Logger.warning("⚠️ Audio effects memory high: #{memory} bytes")
    end

    if queue_len > 1000 do
      Logger.warning("⚠️ Audio effects queue backlog: #{queue_len} messages")
    end

    :ok
  end

  def handle_event(_, _, _, _), do: :ok
end

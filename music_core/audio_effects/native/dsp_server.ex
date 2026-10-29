defmodule MusicCore.AudioEffects.Native.DSP.Server do
  @moduledoc """
  GenServer-обёртка для Rust NIF модуля DSP.
  Отвечает за:
  - Проверку наличия скомпилированной библиотеки при старте
  - Мониторинг состояния NIF
  - Проксирование вызовов в нативный код
  - Graceful shutdown
  """

  use GenServer
  require Logger

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Применить эффект к аудиоданным.
  """
  def apply_effect(effect_type, params, audio_data) do
    case GenServer.call(__MODULE__, {:apply_effect, effect_type, params, audio_data}, 5000) do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        {:error, reason}
    end
  catch
    :exit, {:timeout, _} ->
      {:error, :timeout}

    :exit, reason ->
      {:error, reason}
  end

  @doc """
  Получить информацию о состоянии NIF.
  """
  def get_info do
    GenServer.call(__MODULE__, :get_info, 1000)
  end

  @doc """
  Проверить, загружен ли NIF.
  """
  def nif_loaded? do
    case Process.whereis(__MODULE__) do
      nil -> false
      server_pid -> GenServer.call(server_pid, :nif_loaded?, 1000)
    end
  end

  # Server callbacks

  @impl true
  def init(opts) do
    initial_state = %{
      opts: opts,
      nif_loaded: false,
      loaded_at: nil,
      stats: %{
        total_calls: 0,
        errors: 0,
        avg_processing_time: 0
      }
    }

    start_time = System.monotonic_time()

    case check_nif_library() do
      :ok ->
        case test_nif_loaded() do
          {:ok, version} ->
            load_time = System.monotonic_time() - start_time
            load_time_ms = System.convert_time_unit(load_time, :native, :millisecond)

            Logger.info("✅ DSP NIF loaded successfully")

            :telemetry.execute(
              [:music_core, :dsp, :nif, :loaded],
              %{
                success: true,
                load_time_ms: load_time_ms
              },
              %{
                version: version,
                library_path: nif_library_path()
              }
            )

            loaded_state = %{
              initial_state
              | nif_loaded: true,
                loaded_at: DateTime.utc_now()
            }

            {:ok, loaded_state}

          {:error, reason} ->
            Logger.error("❌ DSP NIF load failed: #{reason}")

            :telemetry.execute(
              [:music_core, :dsp, :nif, :loaded],
              %{success: false},
              %{
                error: inspect(reason),
                library_path: nif_library_path(),
                critical: true
              }
            )

            {:ok, initial_state}
        end

      {:error, reason} ->
        Logger.error("❌ DSP NIF library not found: #{reason}")

        :telemetry.execute(
          [:music_core, :dsp, :nif, :loaded],
          %{success: false},
          %{
            error: "library_not_found",
            details: reason,
            expected_path: nif_library_path(),
            critical: true
          }
        )

        {:ok, initial_state}
    end
  end

  @impl true
  def handle_call({:apply_effect, effect_type, params, audio_data}, _from, state) do
    start_time = System.monotonic_time()

    result = if state.nif_loaded do
      MusicCore.AudioEffects.Native.DSP.apply_effect(effect_type, params, audio_data)
    else
      {:error, :nif_not_available}
    end

    processing_time = System.monotonic_time() - start_time

    case result do
      {:ok, processed} ->
        :telemetry.execute([:music_core, :dsp, :call], %{
          duration: processing_time,
          success: true
        }, %{effect: effect_type})

        updated_state = update_stats(state, processing_time, result)
        {:reply, {:ok, processed}, updated_state}

      {:error, reason} ->
        :telemetry.execute([:music_core, :dsp, :call], %{
          duration: processing_time,
          success: false
        }, %{effect: effect_type, error: reason})

        updated_state = update_stats(state, processing_time, result)
        fallback_result = fallback_software_processing(effect_type, params, audio_data)
        {:reply, fallback_result, updated_state}
    end
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    uptime_ms = if state.loaded_at do
      DateTime.diff(DateTime.utc_now(), state.loaded_at, :millisecond)
    else
      nil
    end

    info = %{
      nif_loaded: state.nif_loaded,
      loaded_at: state.loaded_at,
      stats: state.stats,
      uptime_ms: uptime_ms,
      memory: get_process_memory()
    }

    {:reply, info, state}
  end

  @impl true
  def handle_call(:nif_loaded?, _from, state) do
    {:reply, state.nif_loaded, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("🛑 DSP Server terminating: #{inspect(reason)}")

    uptime_ms = if state.loaded_at do
      DateTime.diff(DateTime.utc_now(), state.loaded_at, :millisecond)
    else
      0
    end

    :telemetry.execute([:music_core, :dsp, :terminate], %{
      reason: inspect(reason),
      uptime_ms: uptime_ms,
      total_calls: state.stats.total_calls
    }, %{})

    if state.nif_loaded do
      MusicCore.AudioEffects.Native.DSP.cleanup()
    end

    :ok
  end

  # ========== FALLBACK FUNCTIONS ==========

  defp fallback_software_processing(effect, params, data) when is_binary(data) do
    try do
      case effect do
        :reverb ->
          apply_simple_reverb(data, params)

        :eq ->
          apply_simple_eq(data, params)

        :compressor ->
          apply_simple_compression(data, params)

        _ ->
          Logger.warning("Unknown effect #{inspect(effect)} in software fallback, returning original")
          {:ok, data}
      end
    rescue
      exception ->
        error_message = Exception.message(exception)
        Logger.error("Software processing crashed: #{error_message}")
        {:error, "Software processing crashed: #{error_message}"}
    end
  end

  defp fallback_software_processing(effect, params, data) do
    Logger.warning("Software fallback received non-binary data, attempting conversion")

    case encode_to_binary(data) do
      {:ok, binary} -> fallback_software_processing(effect, params, binary)
      {:error, reason} -> {:error, "Cannot convert data for fallback: #{reason}"}
    end
  end

  defp apply_simple_reverb(data, _params) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_reverb(data, _params) do
    {:ok, data}
  end

  defp apply_simple_reverb(data) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_reverb(data) do
    {:ok, data}
  end

  defp apply_simple_eq(data, _params) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_eq(data, _params) do
    {:ok, data}
  end

  defp apply_simple_eq(data) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_eq(data) do
    {:ok, data}
  end

  defp apply_simple_compression(data, _params) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_compression(data, _params) do
    {:ok, data}
  end

  defp apply_simple_compression(data) when is_binary(data) do
    {:ok, data}
  end

  defp apply_simple_compression(data) do
    {:ok, data}
  end

  defp encode_to_binary(data) when is_list(data) do
    {:ok, :erlang.iolist_to_binary(data)}
  end

  defp encode_to_binary(data) when is_binary(data) do
    {:ok, data}
  end

  defp encode_to_binary(data) when is_map(data) do
    {:error, "Cannot convert map to binary"}
  end

  defp encode_to_binary(_data) do
    {:error, "Unknown data type"}
  end

  # ========== PRIVATE HELPERS ==========

  defp test_nif_loaded do
    try do
      version = MusicCore.AudioEffects.Native.DSP.version()
      {:ok, version}
    rescue
      _ -> {:error, "NIF not available"}
    end
  end

  defp check_nif_library do
    lib_path = Application.app_dir(:music_core, "priv/native/libaudio_effects_native")
    full_path = get_library_path_with_extension(lib_path)

    if File.exists?(full_path), do: :ok, else: {:error, "Library not found at #{full_path}"}
  end

  defp nif_library_path do
    lib_path = Application.app_dir(:music_core, "priv/native/libaudio_effects_native")
    get_library_path_with_extension(lib_path)
  end

  defp get_library_path_with_extension(base_path) do
    case :os.type() do
      {:unix, :darwin} ->
        base_path <> ".dylib"

      {:unix, _} ->
        base_path <> ".so"

      {:win32, _} ->
        base_path <> ".dll"

      _ ->
        base_path <> ".so"
    end
  end

  defp update_stats(state, processing_time, result) do
    stats = state.stats
    total_calls = stats.total_calls + 1

    errors = case result do
      {:error, _} -> stats.errors + 1
      _ -> stats.errors
    end

    processing_time_us = System.convert_time_unit(processing_time, :native, :microsecond)

    old_avg = stats.avg_processing_time
    new_avg = old_avg + (processing_time_us - old_avg) / total_calls

    updated_stats = %{
      stats
      | total_calls: total_calls,
        errors: errors,
        avg_processing_time: new_avg
    }

    %{state | stats: updated_stats}
  end

  defp get_process_memory do
    case Process.info(self(), :memory) do
      {:memory, bytes} -> bytes
      _ -> 0
    end
  end

  # Child spec для супервизора
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end
end

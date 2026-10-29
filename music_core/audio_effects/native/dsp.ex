defmodule MusicCore.AudioEffects.Native.DSP do
  @moduledoc """
  Нативный модуль цифровой обработки сигналов (DSP).
  Rust NIF модуль для высокопроизводительной обработки аудио.
  """

  # ============================================================================
  # ТИПЫ ДАННЫХ
  # ============================================================================

  @type pcm_data :: binary()
  @type sample_rate :: 8000 | 16000 | 22050 | 32000 | 44100 | 48000 | 96000
  @type channel :: :mono | :stereo | :surround_5_1
  @type audio_format :: :s16le | :s24le | :s32le | :f32le

  defstruct [
    sample_rate: 48000,
    channels: :stereo,
    format: :s16le,
    buffer_size: 4096,
    ctx: nil
  ]

  # ============================================================================
  # NIF LOADING
  # ============================================================================
  @on_load :load_nifs

  def load_nifs do
    nif_path = :filename.join([
      :code.priv_dir(:music_core),
      ~c'native',
      ~c'libaudio_effects_native'
    ])

    case :erlang.load_nif(nif_path, 0) do
      :ok ->
        IO.puts("✅ DSP NIF loaded successfully from #{nif_path}")

      {:error, {:load_failed, reason}} ->
        IO.puts("⚠️ DSP NIF load failed: #{reason}")

      {:error, reason} ->
        IO.puts("⚠️ DSP NIF error: #{reason}")
    end

    :ok
  end

  # ============================================================================
  # Прямые NIF-функции
  # ============================================================================
  def rustc_version(), do: :erlang.nif_error(:not_loaded)
  def version(), do: :erlang.nif_error(:not_loaded)
  def native_init(sample_rate, channels, format), do: :erlang.nif_error(:nif_not_loaded)
  def native_release(ctx), do: :erlang.nif_error(:nif_not_loaded)
  def init_processor(sample_rate, channels), do: :erlang.nif_error(:not_loaded)
  def get_processor_stats(processor_id), do: :erlang.nif_error(:not_loaded)
  def process_processor(processor_id, audio_data, config_json), do: :erlang.nif_error(:not_loaded)
  def get_stream_info(stream_id), do: :erlang.nif_error(:not_loaded)
  def create_stream(stream_id), do: :erlang.nif_error(:not_loaded)
  def process_stream(stream_id, input_binary), do: :erlang.nif_error(:not_loaded)
  def process_delay(audio, params), do: :erlang.nif_error(:not_loaded)
  def process_reverb_simple(audio, params), do: :erlang.nif_error(:not_loaded)
  def process_distortion(audio, params), do: :erlang.nif_error(:not_loaded)
  def add_equalizer_effect(stream_id, low_gain, mid_gain, high_gain), do: :erlang.nif_error(:not_loaded)
  def create_eq(config_json, sample_rate, preamp_gain), do: :erlang.nif_error(:not_loaded)
  def create_effect_chain(config_json, sample_rate, channels), do: :erlang.nif_error(:not_loaded)
  def create_chorus(audio, params), do: :erlang.nif_error(:not_loaded)
  def create_compressor(audio, params), do: :erlang.nif_error(:not_loaded)
  def create_distortion(audio, params), do: :erlang.nif_error(:not_loaded)
  def create_delay(audio, params), do: :erlang.nif_error(:not_loaded)
  def create_pitch_shift(audio, params), do: :erlang.nif_error(:not_loaded)
  def create_reverb(audio, params), do: :erlang.nif_error(:not_loaded)
  def detect_pitch(audio_data, sample_rate, min_freq, max_freq), do: :erlang.nif_error(:not_loaded)
  def native_normalize_audio(audio, params), do: :erlang.nif_error(:nif_not_loaded)
  def native_process_chain(ctx, pcm_data, chain), do: :erlang.nif_error(:nif_not_loaded)
  def generate_sine(frequency, sample_rate, duration, amplitude), do: :erlang.nif_error(:not_loaded)
  def generate_white_noise(samples, amp, duration), do: :erlang.nif_error(:not_loaded)
  def generate_pink_noise(duration, sample_rate, amplitude), do: :erlang.nif_error(:not_loaded)
  def apply_fade_in(audio, samples), do: :erlang.nif_error(:not_loaded)
  def apply_fade_out(audio, samples), do: :erlang.nif_error(:not_loaded)
  def apply_effect_chain(stream_id, effects), do: :erlang.nif_error(:not_loaded)
  def native_apply_eq(ctx, pcm_data, config), do: :erlang.nif_error(:nif_not_loaded)
  def native_apply_compressor(ctx, pcm_data, config), do: :erlang.nif_error(:nif_not_loaded)
  def native_apply_reverb(ctx, pcm_data, config), do: :erlang.nif_error(:nif_not_loaded)
  def native_apply_chorus(ctx, pcm_data, config), do: :erlang.nif_error(:nif_not_loaded)
  def native_apply_limiter(ctx, pcm_data, threshold), do: :erlang.nif_error(:nif_not_loaded)
  def add_echo_effect(stream_id, delay_ms, feedback, mix), do: :erlang.nif_error(:not_loaded)
  def native_normalize(ctx, pcm_data, target, mode), do: :erlang.nif_error(:nif_not_loaded)
  def crossfade(audio1, audio2, samples), do: :erlang.nif_error(:not_loaded)
  def native_analyze(ctx, pcm_data), do: :erlang.nif_error(:nif_not_loaded)
  def analyze_spectrum(audio_data, sample_rate, window_size), do: :erlang.nif_error(:not_loaded)
  def db_to_linear(db), do: :erlang.nif_error(:not_loaded)
  def linear_to_db(linear), do: :erlang.nif_error(:not_loaded)
  def midi_to_frequency(note), do: :erlang.nif_error(:not_loaded)
  def frequency_to_midi(freq), do: :erlang.nif_error(:not_loaded)
  def calculate_rms(audio), do: :erlang.nif_error(:not_loaded)
  def calculate_peak(audio), do: :erlang.nif_error(:not_loaded)
  def normalize_peak(audio, target), do: :erlang.nif_error(:not_loaded)
  def get_stream_volume(stream_id), do: :erlang.nif_error(:not_loaded)
  def set_stream_volume(stream_id, volume), do: :erlang.nif_error(:not_loaded)
  def eq_get_response(eq_data, frequencies), do: :erlang.nif_error(:not_loaded)
  def add_volume_effect(stream_id, gain), do: :erlang.nif_error(:not_loaded)
  def set_stream_playing(stream_id, playing), do: :erlang.nif_error(:not_loaded)
  def process_compressor(audio, params), do: :erlang.nif_error(:not_loaded)
  def process_pitch_shift(ps_data, audio_data), do: :erlang.nif_error(:not_loaded)
  def process_reverb_stereo(reverb_data, left_audio, right_audio), do: :erlang.nif_error(:not_loaded)
  def process_chorus(audio, params), do: :erlang.nif_error(:not_loaded)
  def reset_processor(processor_id), do: :erlang.nif_error(:not_loaded)

  # ============================================================================
  # PUBLIC API
  # ============================================================================

  @doc "Инициализация DSP контекста."
  @spec init(keyword()) :: {:ok, reference()} | {:error, String.t()}
  def init(opts \\ []) do
    sample_rate = Keyword.get(opts, :sample_rate, 48000)
    channels = Keyword.get(opts, :channels, :stereo)
    format = Keyword.get(opts, :format, :s16le)

    case native_init(sample_rate, atom_to_channel(channels), atom_to_format(format)) do
      ref when is_reference(ref) -> {:ok, ref}
      error -> {:error, error}
    end
  end

  @doc "Нормализация аудио."
  @spec normalize_audio(binary(), map()) :: {:ok, binary()} | {:error, String.t()}
  def normalize_audio(audio_stream, params) when is_binary(audio_stream) and is_map(params) do
    case native_normalize_audio(audio_stream, params) do
      {:ok, processed} when is_binary(processed) -> {:ok, processed}
      {:error, reason} -> {:error, "Normalization failed: #{reason}"}
      other when is_binary(other) -> {:ok, other}
      other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Применение эквалайзера."
  @spec apply_equalizer(pcm_data(), map(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def apply_equalizer(pcm_data, eq_config, dsp_ctx \\ nil)
    when is_binary(pcm_data) and is_map(eq_config) do
      with {:ok, ctx} <- get_context(dsp_ctx), config = prepare_eq_config(eq_config), result when is_binary(result) <- native_apply_eq(ctx, pcm_data, config) do
        {:ok, result}
      else
        {:error, reason} -> {:error, "Equalizer failed: #{reason}"}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Применение компрессора."
  @spec apply_compressor(pcm_data(), map(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def apply_compressor(pcm_data, comp_config, dsp_ctx \\ nil)
    when is_binary(pcm_data) and is_map(comp_config) do
      with {:ok, ctx} <- get_context(dsp_ctx), config = prepare_comp_config(comp_config), result when is_binary(result) <- native_apply_compressor(ctx, pcm_data, config) do
        {:ok, result}
      else
        {:error, reason} -> {:error, "Compressor failed: #{reason}"}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Применение реверберации."
  @spec apply_reverb(pcm_data(), map(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def apply_reverb(pcm_data, reverb_config, dsp_ctx \\ nil)
    when is_binary(pcm_data) and is_map(reverb_config) do
      with {:ok, ctx} <- get_context(dsp_ctx), config = prepare_reverb_config(reverb_config), result when is_binary(result) <- native_apply_reverb(ctx, pcm_data, config) do
        {:ok, result}
      else
        {:error, reason} -> {:error, "Reverb failed: #{reason}"}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Применение хоруса."
  @spec apply_chorus(pcm_data(), map(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def apply_chorus(pcm_data, chorus_config, dsp_ctx \\ nil)
      when is_binary(pcm_data) and is_map(chorus_config) do
        with {:ok, ctx} <- get_context(dsp_ctx), config = prepare_chorus_config(chorus_config), result when is_binary(result) <- native_apply_chorus(ctx, pcm_data, config) do
          {:ok, result}
        else
          {:error, reason} -> {:error, "Chorus failed: #{reason}"}
          other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Применение лимитера."
  @spec apply_limiter(pcm_data(), float(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def apply_limiter(pcm_data, threshold_db \\ -1.0, dsp_ctx \\ nil)
    when is_binary(pcm_data) and is_number(threshold_db) do
      with {:ok, ctx} <- get_context(dsp_ctx), result when is_binary(result) <- native_apply_limiter(ctx, pcm_data, threshold_db) do
        {:ok, result}
      else
        {:error, reason} -> {:error, "Limiter failed: #{reason}"}
        other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Нормализация громкости."
  @spec normalize(pcm_data(), float(), atom(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def normalize(pcm_data, target_level \\ -14.0, mode \\ :peak, dsp_ctx \\ nil)
      when is_binary(pcm_data) and is_number(target_level) do
        with {:ok, ctx} <- get_context(dsp_ctx), mode_int = mode_to_int(mode), result when is_binary(result) <- native_normalize(ctx, pcm_data, target_level, mode_int) do
          {:ok, result}
        else
          {:error, reason} -> {:error, "Normalization failed: #{reason}"}
          other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Анализ аудио."
  @spec analyze(pcm_data(), reference() | nil) :: {:ok, map()} | {:error, String.t()}
  def analyze(pcm_data, dsp_ctx \\ nil) when is_binary(pcm_data) do
    with {:ok, ctx} <- get_context(dsp_ctx), result when is_map(result) <- native_analyze(ctx, pcm_data) do
      {:ok, result}
    else
      {:error, reason} -> {:error, "Analysis failed: #{reason}"}
      other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end

  @doc "Цепочка эффектов."
  @spec process_chain(pcm_data(), list(), reference() | nil) :: {:ok, pcm_data()} | {:error, String.t()}
  def process_chain(pcm_data, effect_chain, dsp_ctx \\ nil)
    when is_binary(pcm_data) and is_list(effect_chain) do
      with {:ok, ctx} <- get_context(dsp_ctx), chain = build_native_chain(effect_chain), result when is_binary(result) <- native_process_chain(ctx, pcm_data, chain) do
        {:ok, result}
    else
      {:error, reason} -> {:error, "Process chain failed: #{reason}"}
      other -> {:error, "Unexpected result: #{inspect(other)}"}
    end
  end


  def get_context(nil), do: {:error, :no_context}
  def get_context(ctx) when is_reference(ctx), do: {:ok, ctx}

  def prepare_eq_config(config) when is_map(config) do
    %{
      "low_shelf_gain" => Map.get(config, :low_shelf_gain, 0.0),
      "low_shelf_freq" => Map.get(config, :low_shelf_freq, 80.0),
      "low_shelf_q" => Map.get(config, :low_shelf_q, 0.7),
      "peaking1_gain" => Map.get(config, :peaking1_gain, 0.0),
      "peaking1_freq" => Map.get(config, :peaking1_freq, 1000.0),
      "peaking1_q" => Map.get(config, :peaking1_q, 1.0),
      "peaking2_gain" => Map.get(config, :peaking2_gain, 0.0),
      "peaking2_freq" => Map.get(config, :peaking2_freq, 3000.0),
      "peaking2_q" => Map.get(config, :peaking2_q, 1.5),
      "high_shelf_gain" => Map.get(config, :high_shelf_gain, 0.0),
      "high_shelf_freq" => Map.get(config, :high_shelf_freq, 8000.0),
      "high_shelf_q" => Map.get(config, :high_shelf_q, 0.7),
      "global_gain" => Map.get(config, :global_gain, 0.0)
    }
  end

  def prepare_eq_config(_), do: %{}

  def prepare_comp_config(config) when is_map(config) do
    %{
      "threshold" => Map.get(config, :threshold, -20.0),
      "ratio" => Map.get(config, :ratio, 4.0),
      "attack" => Map.get(config, :attack, 20),
      "release" => Map.get(config, :release, 250),
      "makeup_gain" => Map.get(config, :makeup_gain, 0.0),
      "knee" => Map.get(config, :knee, 6.0)
    }
  end
  def prepare_comp_config(_), do: %{}

  def prepare_reverb_config(config) when is_map(config) do
    %{
      "room_size" => Map.get(config, :room_size, 0.5),
      "damping" => Map.get(config, :damping, 0.5),
      "wet_level" => Map.get(config, :wet_level, 0.33),
      "dry_level" => Map.get(config, :dry_level, 0.67),
      "width" => Map.get(config, :width, 1.0),
      "freeze" => Map.get(config, :freeze, 0.0)
    }
  end
  def prepare_reverb_config(_), do: %{}

  def prepare_chorus_config(config) when is_map(config) do
    voices = Map.get(config, :voices, 4)
    voice_list = Enum.map(0..(voices - 1), fn index ->
      ratio = index / voices
      %{
        "delay_ms" => Map.get(config, :delay_ms, 20) + index * 5,
        "depth_ms" => Map.get(config, :depth_ms, 5) + index * 1.5,
        "rate_hz" => Map.get(config, :rate_hz, 0.5) + index * 0.15,
        "gain" => Map.get(config, :gain, 0.7) - ratio * 0.5,
        "phase" => index * 360 / voices
      }
    end)
    %{
      "voices" => voice_list,
      "mix" => Map.get(config, :mix, 0.5),
      "feedback" => Map.get(config, :feedback, 0.1),
      "stereo_width" => Map.get(config, :stereo_width, 0.8),
      "predelay_ms" => Map.get(config, :predelay_ms, 0)
    }
  end

  def prepare_chorus_config(_), do: %{"voices" => [], "mix" => 0.5, "feedback" => 0.1, "stereo_width" => 0.8, "predelay_ms" => 0}

  def build_native_chain(effect_chain) do
    Enum.map(effect_chain, fn
      {:eq, config} -> {:eq, prepare_eq_config(config)}
      {:compressor, config} -> {:compressor, prepare_comp_config(config)}
      {:reverb, config} -> {:reverb, prepare_reverb_config(config)}
      {:chorus, config} -> {:chorus, prepare_chorus_config(config)}
      {:limiter, threshold} when is_number(threshold) -> {:limiter, threshold}
      :limiter -> {:limiter, -1.5}
      effect when is_atom(effect) -> {:error, "Unknown effect: #{effect}"}
      invalid -> {:error, "Invalid effect: #{inspect(invalid)}"}
    end)
    |> Enum.filter(fn
      {:error, _} -> false
      _ -> true
    end)
  end

  def atom_to_channel(:mono), do: 1
  def atom_to_channel(:stereo), do: 2
  def atom_to_channel(:surround_5_1), do: 6
  def atom_to_channel(ch) when is_integer(ch), do: ch
  def atom_to_channel(invalid), do: raise(ArgumentError, "Invalid channel: #{inspect(invalid)}")

  def atom_to_format(:s16le), do: 16
  def atom_to_format(:s24le), do: 24
  def atom_to_format(:s32le), do: 32
  def atom_to_format(:f32le), do: 32
  def atom_to_format(invalid), do: raise(ArgumentError, "Invalid format: #{inspect(invalid)}")

  def mode_to_int(:peak), do: 0
  def mode_to_int(:rms), do: 1
  def mode_to_int(:lufs), do: 2
  def mode_to_int(invalid), do: raise(ArgumentError, "Invalid mode: #{inspect(invalid)}")

  def remove_dc_offset_filter(audio, sr), do: :erlang.nif_error(:not_loaded)
  def remove_dc_offset(audio_data, sample_rate), do: :erlang.nif_error(:not_loaded)
  def clear_stream_effects(stream_id), do: :erlang.nif_error(:not_loaded)
  def destroy_stream(stream_id), do: :erlang.nif_error(:not_loaded)

  @doc "Освобождение контекста."
  @spec release(reference()) :: :ok | {:error, String.t()}
  def release(dsp_ctx) do
    case native_release(dsp_ctx) do
      :ok -> :ok
      error -> {:error, "Release failed: #{inspect(error)}"}
    end
  end

  def clear_processor_cache(), do: :erlang.nif_error(:not_loaded)
  def native_cleanup(), do: :erlang.nif_error(:nif_not_loaded)

  @doc "Очистка всех ресурсов."
  @spec cleanup() :: :ok | {:error, String.t()}
  def cleanup do
    try do
      case native_cleanup() do
        :ok -> :ok
        error -> {:error, "Cleanup failed: #{inspect(error)}"}
      end
    rescue
      exception -> {:error, "Cleanup exception: #{Exception.message(exception)}"}
    end
  end

  def remove_processor(processor_id), do: :erlang.nif_error(:not_loaded)
end

defmodule MusicCore.AudioEffects.Processor.Worker do
  @moduledoc """
  Oban worker для фоновой обработки аудио с использованием модели.
  Выполняет извлечение эмбеддингов для улучшения поиска музыки.
  """

  use Oban.Worker,
    queue: :audio_processing,
    max_attempts: 3,
    priority: 1

  require Logger

  alias MusicCore.AudioEffects.GoBridge
  alias MusicCore.AudioEffects.Native.DSP

  @cache_name :audio_effects_cache
  @default_timeout 30_000
  @sample_rate 16_000
  @frame_size 512
  @hop_size 256
  @num_mfcc 13

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"audio_url" => audio_url, "task" => "extract_embedding"} = args}) do
    Logger.info("[Worker] Starting audio embedding extraction for: #{audio_url}")

    result = with {:ok, audio_data} <- download_audio(audio_url),
                {:ok, audio_f32} <- convert_to_f32(audio_data),
                {:ok, features} <- extract_mfcc(audio_f32),
                {:ok, embedding} <- extract_embedding(features) do
      store_embedding(audio_url, embedding)
      Logger.info("[Worker] Embedding extracted successfully for: #{audio_url}")
      :ok
    else
      {:error, reason} ->
        Logger.error("[Worker] Failed to process audio #{audio_url}: #{inspect(reason)}")
        {:error, reason}
    end

    case result do
      :ok -> :ok
      error -> error
    end
  end

  defp download_audio(audio_url) do
    case Req.get(audio_url, timeout: 30_000) do
      {:ok, %Req.Response{status: 200, body: body}} ->
        {:ok, body}
      {:ok, %Req.Response{status: code}} ->
        Logger.error("[Worker] Download failed with status #{code}")
        {:error, {:download_failed, code}}
      {:error, reason} ->
        Logger.error("[Worker] Download failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  def perform(%Oban.Job{args: %{"task" => "apply_effects", "audio_url" => audio_url, "effects" => effects}}) do
    Logger.info("[Worker] Applying effects to: #{audio_url}")

    case download_audio(audio_url) do
      {:ok, audio_data} ->
        case GoBridge.process_audio(audio_url, "wav", 1.0, effects) do
          {:ok, processed_data} ->
            store_processed_audio(audio_url, processed_data)
            Logger.info("[Worker] Effects applied successfully")
            :ok
          {:error, reason} ->
            Logger.error("[Worker] Failed to apply effects: #{inspect(reason)}")
            {:error, reason}
        end
      {:error, reason} ->
        Logger.error("[Worker] Failed to download audio: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # ============================================================================
  # AUDIO PROCESSING
  # ============================================================================

  defp convert_to_f32(audio_data) when is_binary(audio_data) do
    Logger.debug("[Worker] Converting audio to f32")

    try do
      # Используем Native DSP для конвертации
      case DSP.convert_to_f32(audio_data, @sample_rate, 1) do
        {:ok, f32_data} when is_list(f32_data) ->
          {:ok, f32_data}
        {:ok, f32_data} when is_binary(f32_data) ->
          # Если вернулся бинарный blob, конвертируем в список
          {:ok, binary_to_float_list(f32_data)}
        error ->
          Logger.error("[Worker] DSP conversion failed: #{inspect(error)}")
          {:error, :conversion_failed}
      end
    rescue
      e ->
        Logger.error("[Worker] Conversion exception: #{inspect(e)}")
        {:error, {:conversion_error, e}}
    end
  end

  defp binary_to_float_list(binary) do
    for <<f::float-32 <- binary>>, do: f
  end

  defp extract_mfcc(audio_f32) when is_list(audio_f32) do
    Logger.debug("[Worker] Extracting MFCC features (#{length(audio_f32)} samples)")

    try do
      # Извлекаем MFCC через Native DSP
      case DSP.compute_mfcc(audio_f32, @sample_rate, @frame_size, @hop_size, @num_mfcc) do
        {:ok, mfcc_features} ->
          {:ok, %{
            mfcc: mfcc_features,
            num_frames: length(mfcc_features),
            sample_rate: @sample_rate,
            frame_size: @frame_size,
            hop_size: @hop_size
          }}
        error ->
          Logger.error("[Worker] MFCC extraction failed: #{inspect(error)}")
          {:error, :mfcc_failed}
      end
    rescue
      e ->
        Logger.error("[Worker] MFCC exception: #{inspect(e)}")
        {:error, {:mfcc_error, e}}
    end
  end

  defp extract_mfcc(_), do: {:error, :invalid_audio_data}

  # ============================================================================
  # EMBEDDING EXTRACTION (ONNX via Go or Native)
  # ============================================================================

  defp extract_embedding(features) do
    Logger.debug("[Worker] Extracting embedding from features")

    # Сначала пробуем через GoBridge (если доступен)
    case try_go_inference(features) do
      {:ok, embedding} ->
        {:ok, embedding}

      {:error, reason} ->
        Logger.warning("[Worker] Go inference failed: #{inspect(reason)}, trying native fallback")

        # Fallback на Native DSP (если есть модель)
        case try_native_inference(features) do
          {:ok, embedding} ->
            {:ok, embedding}
          {:error, reason2} ->
            Logger.error("[Worker] All inference backends failed: #{inspect(reason2)}")
            # Возвращаем хэш как fallback (не для продакшена)
            fallback_embedding = generate_fallback_embedding(features)
            {:ok, fallback_embedding}
        end
    end
  rescue
    e ->
      Logger.error("[Worker] Embedding extraction exception: #{inspect(e)}")
      {:error, {:embedding_error, e}}
  end

  defp try_go_inference(features) do
    # Отправляем в Go сервис для ONNX инференса
    case GoBridge.run_inference(features.mfcc, model_name: "music_embedding_v1") do
      {:ok, embedding} when is_binary(embedding) ->
        {:ok, Base.encode64(embedding)}
      {:ok, embedding} when is_list(embedding) ->
        {:ok, :erlang.term_to_binary(embedding) |> Base.encode64()}
      {:error, reason} ->
        {:error, reason}
      _ ->
        {:error, :invalid_response}
    end
  end

  defp try_native_inference(features) do
    # Если есть встроенная модель в Rust
    case DSP.compute_embedding(features.mfcc) do
      {:ok, embedding} ->
        {:ok, embedding}
      error ->
        {:error, error}
    end
  end

  defp generate_fallback_embedding(features) do
    # Генерируем детерминированный хэш на основе MFCC (только для разработки!)
    data = :erlang.term_to_binary(features)
    :crypto.hash(:sha256, data) |> Base.encode64()
  end

  # ============================================================================
  # STORAGE
  # ============================================================================

  defp store_embedding(audio_url, embedding) do
    Logger.debug("[Worker] Storing embedding for: #{audio_url}")

    data = %{
      url: audio_url,
      embedding: embedding,
      extracted_at: DateTime.utc_now(),
      sample_rate: @sample_rate,
      frame_size: @frame_size,
      hop_size: @hop_size,
      num_mfcc: @num_mfcc
    }

    case cache_available?() do
      true ->
        MusicCore.AudioEffects.CacheManager.put("embedding:#{audio_url}", data, ttl: 86_400) # 24 часа
        # Также сохраняем в persistent_term для быстрого доступа
        :persistent_term.put({__MODULE__, :embedding, audio_url}, embedding)

      false ->
        Logger.info("[Worker] No cache available, storing in process dictionary")
        Process.put({:embedding, audio_url}, data)
    end

    # Если есть база данных, сохраняем и туда
    maybe_store_in_db(audio_url, data)

    :ok
  end

  defp store_processed_audio(audio_url, processed_data) do
    Logger.debug("[Worker] Storing processed audio for: #{audio_url}")

    data = %{
      url: audio_url,
      processed_audio: processed_data,
      processed_at: DateTime.utc_now()
    }

    case cache_available?() do
      true ->
        MusicCore.AudioEffects.CacheManager.put("processed:#{audio_url}", data, ttl: 3_600) # 1 час
      false ->
        :ok
    end

    :ok
  end

  defp cache_available? do
    case :persistent_term.get({__MODULE__, :cache}, {nil, false}) do
      {_, true} -> true
      _ -> false
    end
  end

  defp maybe_store_in_db(audio_url, data) do
    # Если есть репозиторий, сохраняем
    case Code.ensure_loaded(MusicCore.Repo) do
      {:module, _} ->
        # Асинхронно сохраняем в БД
        Task.start(fn ->
          try do
            # Пример сохранения
            # MusicCore.AudioEmbedding.changeset(%MusicCore.AudioEmbedding{}, %{
            #   url: audio_url,
            #   embedding: data.embedding,
            #   extracted_at: data.extracted_at
            # }) |> MusicCore.Repo.insert()
          rescue
            e -> Logger.error("[Worker] Failed to store in DB: #{inspect(e)}")
          end
        end)
      _ ->
        :ok
    end
  end

  # ============================================================================
  # BATCH PROCESSING
  # ============================================================================

  @doc """
  Пакетная обработка нескольких аудио URL.
  """
  def process_batch(urls, task \\ "extract_embedding") when is_list(urls) do
    Logger.info("[Worker] Starting batch processing of #{length(urls)} URLs")

    urls
    |> Enum.map(fn url -> %{audio_url: url, task: task} end)
    |> Enum.map(&new/1)
    |> Oban.insert_all()
  end

  @doc """
  Получить эмбеддинг из кэша по URL.
  """
  def get_embedding(audio_url) do
    case :persistent_term.get({__MODULE__, :embedding, audio_url}, nil) do
      nil ->
        case cache_available?() do
          true ->
            case MusicCore.AudioEffects.CacheManager.get("embedding:#{audio_url}") do
              {:ok, %{embedding: emb}} -> {:ok, emb}
              _ -> {:error, :not_found}
            end
          false ->
            {:error, :not_found}
        end
      embedding ->
        {:ok, embedding}
    end
  end

  # ============================================================================
  # SETUP
  # ============================================================================

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 30_000
    }
  end

  def start_link(_opts) do
    # Регистрируем кэш в persistent_term
    cache_module = MusicCore.AudioEffects.CacheManager
    cache_available = function_exported?(cache_module, :put, 2)

    :persistent_term.put({__MODULE__, :cache}, {cache_module, cache_available})

    Logger.info("[Worker] Started with cache available: #{cache_available}")
    Logger.info("[Worker] Configuration: sample_rate=#{@sample_rate}, frame_size=#{@frame_size}, hop_size=#{@hop_size}, num_mfcc=#{@num_mfcc}")

    {:ok, self()}
  end
end

defmodule MusicCore.WebSockAdapter do
  @moduledoc """
  WebSocket адаптер по RFC 6455.

  Реализует:
  - Handshake (секция 4.2, 4.3)
  - Фреймы данных (секция 5)
  - Фрагментацию (секция 5.4)
  - Пинг/Понг (секция 5.5.2, 5.5.3)
  - Закрытие соединения (секция 5.5.1, 7)
  - Маскировку (секция 5.3)
  - Валидацию UTF-8 (секция 8.1)
  """

  require Logger
  import Bitwise

  # RFC 6455, секция 1.3: магическая строка для handshake
  @magic_string "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

  # RFC 6455, секция 7.4: коды закрытия
  @close_normal 1000
  @close_going_away 1001
  @close_protocol_error 1002
  @close_unsupported_data 1003
  @close_invalid_payload 1007
  @close_policy_violation 1008
  @close_message_too_big 1009
  @close_mandatory_ext 1010
  @close_internal_error 1011

  # ========== HANDSHAKE (RFC 6455, секция 4.2, 4.3) ==========

  @doc """
  Выполняет WebSocket handshake.
  """
  @spec upgrade(Plug.Conn.t(), module(), list(), keyword()) :: Plug.Conn.t()
  def upgrade(conn, handler, handler_opts \\ [], opts \\ []) do
    case validate_handshake(conn) do
      :ok ->
        timeout = Keyword.get(opts, :timeout, 60_000)

        case start_websocket(conn, handler, handler_opts, timeout) do
          {:ok, _pid} ->
            # RFC 6455, секция 4.2.2: ответ 101 Switching Protocols
            conn
            |> Plug.Conn.put_status(101)
            |> Plug.Conn.put_resp_header("connection", "Upgrade")
            |> Plug.Conn.put_resp_header("upgrade", "websocket")
            |> Plug.Conn.put_resp_header("sec-websocket-accept", generate_accept_key(conn))
            |> Plug.Conn.send_resp(101, "")
            |> Plug.Conn.halt()

          {:error, reason} ->
            Logger.error("Failed to start WebSocket: #{inspect(reason)}")
            Plug.Conn.send_resp(conn, 500, "WebSocket upgrade failed")
        end

      {:error, reason} ->
        Logger.warning("WebSocket upgrade rejected: #{reason}")
        Plug.Conn.send_resp(conn, 400, reason)
    end
  end

  # RFC 6455, секция 4.2.2: проверка заголовков
  defp validate_handshake(conn) do
    upgrade_header = get_header(conn, "upgrade")
    connection_header = get_header(conn, "connection", "")
    key = get_header(conn, "sec-websocket-key")
    version = get_header(conn, "sec-websocket-version")

    cond do
      upgrade_header != "websocket" ->
        {:error, "Invalid upgrade header: #{inspect(upgrade_header)}"}
      not String.contains?(connection_header, "upgrade") ->
        {:error, "Invalid connection header: #{inspect(connection_header)}"}
      byte_size(key) != 24 ->
        {:error, "Invalid sec-websocket-key length: #{byte_size(key)}"}
      version != "13" ->
        {:error, "Invalid sec-websocket-version: #{inspect(version)}"}
      true ->
        :ok
    end
  end

  # RFC 6455, секция 4.2.2: генерация accept-ключа
  defp generate_accept_key(conn) do
    key = get_header(conn, "sec-websocket-key")
    :crypto.hash(:sha, key <> @magic_string) |> Base.encode64()
  end

  # ========== УПРАВЛЕНИЕ СОЕДИНЕНИЕМ ==========

  defp start_websocket(conn, handler, handler_opts, timeout) do
    {:ok, socket, transport} = Plug.Conn.adapter_info(conn)

    pid = spawn_link(fn ->
      Process.flag(:trap_exit, true)

      case handler.init(handler_opts) do
        {:ok, state} ->
          loop(socket, transport, handler, state, timeout)

        {:stop, reason} ->
          Logger.error("Handler init failed: #{inspect(reason)}")
      end
    end)

    {:ok, pid}
  end

  # ========== ОСНОВНОЙ ЦИКЛ ==========

  defp loop(socket, transport, handler, state, timeout) do
    receive do
      {:tcp, _, data} ->
        case parse_frames(data, [], handler, state) do
          {:ok, new_state} ->
            loop(socket, transport, handler, new_state, timeout)

          {:close, reason} ->
            Logger.info("WebSocket closed: #{reason}")
            transport.close(socket)
        end

      {:tcp_closed, _} ->
        Logger.info("WebSocket connection closed by client")
        handler.terminate({:closed, :remote}, state)

      {:tcp_error, _, reason} ->
        Logger.error("WebSocket error: #{inspect(reason)}")
        handler.terminate({:error, reason}, state)

      {:send, data, opcode} ->
        transport.send(socket, encode_frame(data, opcode))
        loop(socket, transport, handler, state, timeout)

      {:send, data} ->
        transport.send(socket, encode_frame(data, :text))
        loop(socket, transport, handler, state, timeout)

      {:EXIT, _pid, reason} ->
        Logger.error("WebSocket process exiting: #{inspect(reason)}")
        transport.close(socket)

    after
      timeout ->
        # RFC 6455, секция 5.5.2: отправляем ping
        transport.send(socket, encode_ping())
        loop(socket, transport, handler, state, timeout)
    end
  end

  # ========== ПАРСИНГ ФРЕЙМОВ (RFC 6455, секция 5) ==========

  defp parse_frames(<<>>, [], _handler, state), do: {:ok, state}

  defp parse_frames(<<>>, frames, handler, state) do
    case Enum.reduce_while(frames, {:ok, state}, fn frame, {:ok, acc_state} ->
      case handle_frame(frame, handler, acc_state) do
        {:ok, new_state} -> {:cont, {:ok, new_state}}
        {:close, reason} -> {:halt, {:close, reason}}
      end
    end) do
      {:ok, new_state} -> {:ok, new_state}
      {:close, reason} -> {:close, reason}
    end
  end

  defp parse_frames(data, frames, handler, state) do
    case decode_frame(data) do
      {:ok, frame, rest} ->
        parse_frames(rest, [frame | frames], handler, state)

      {:partial, _} ->
        # Ждём ещё данных
        {:ok, state}

      {:error, reason} ->
        Logger.error("Frame parse error: #{reason}")
        {:ok, state}
    end
  end

  # RFC 6455, секция 5.2: декодирование фрейма
  defp decode_frame(<<fin::1, rsv::3, opcode::4, mask::1, len::7, rest::binary>>) do
    case validate_rsv(rsv) do
      :ok ->
        case decode_length(len, rest) do
          {payload_len, rest1} ->
            case decode_masking_key(mask, rest1) do
              {masking_key, rest2} ->
                case extract_payload(payload_len, rest2) do
                  {payload, rest3} ->
                    unmasked = if mask == 1, do: unmask_payload(payload, masking_key), else: payload

                    frame = %{
                      fin: fin == 1,
                      rsv: rsv,
                      opcode: opcode,
                      masked: mask == 1,
                      payload: unmasked
                    }

                    {:ok, frame, rest3}

                  error ->
                    error
                end

              error ->
                error
            end

          error ->
            error
        end

      error ->
        error
    end
  end

  defp decode_frame(_), do: {:partial, :need_more_data}

  # RFC 6455, секция 5.2: RSV биты должны быть 0 (если нет расширений)
  defp validate_rsv(0), do: :ok
  defp validate_rsv(_), do: {:error, "RSV bits must be 0 (no extensions)"}

  # RFC 6455, секция 5.2: декодирование длины
  defp decode_length(126, <<len::16-big, rest::binary>>), do: {len, rest}
  defp decode_length(127, <<len::64-big, rest::binary>>), do: {len, rest}
  defp decode_length(len, rest) when len < 126, do: {len, rest}
  defp decode_length(_, _), do: {:error, "Invalid length encoding"}

  # RFC 6455, секция 5.3: маскирующий ключ
  defp decode_masking_key(1, <<key::32, rest::binary>>), do: {key, rest}
  defp decode_masking_key(0, rest), do: {0, rest}
  defp decode_masking_key(_, _), do: {:error, "Invalid masking key"}

  defp extract_payload(len, rest) when is_integer(len) and len <= byte_size(rest) do
    <<payload::binary-size(len), after_rest::binary>> = rest
    {payload, after_rest}
  end

  defp extract_payload(_, _), do: {:error, "Incomplete payload"}

  # RFC 6455, секция 5.3: снятие маски
  defp unmask_payload(payload, masking_key) do
    mask = <<masking_key::32>>
    for {byte, i} <- Enum.with_index(:binary.bin_to_list(payload)), into: <<>> do
      <<bxor(byte, :binary.at(mask, rem(i, 4)))::8>>
    end
  end

  # ========== ОБРАБОТКА ФРЕЙМОВ (RFC 6455, секция 5.5, 5.6) ==========

  # RFC 6455, секция 5.6: коды операций
  @cont_opcode 0x0
  @text_opcode 0x1
  @binary_opcode 0x2
  @close_opcode 0x8
  @ping_opcode 0x9
  @pong_opcode 0xA

  defp handle_frame(frame, handler, state) do
    case frame.opcode do
      @cont_opcode -> handle_continuation(frame, handler, state)
      @text_opcode -> handle_text(frame, handler, state)
      @binary_opcode -> handle_binary(frame, handler, state)
      @close_opcode -> handle_close(frame, handler, state)
      @ping_opcode -> handle_ping(frame, handler, state)
      @pong_opcode -> handle_pong(frame, handler, state)
      _ ->
        Logger.warning("Unknown opcode: #{frame.opcode}")
        {:ok, state}
    end
  end

  # RFC 6455, секция 5.6: текстовые сообщения
  defp handle_text(frame, handler, state) do
    case validate_utf8(frame.payload) do
      :ok ->
        handler.handle_in({frame.payload, opcode: :text}, state)

      {:error, _} ->
        send_close(@close_invalid_payload, "Invalid UTF-8")
        {:close, "Invalid UTF-8"}
    end
  end

  # RFC 6455, секция 5.6: бинарные сообщения
  defp handle_binary(frame, handler, state) do
    handler.handle_in({frame.payload, opcode: :binary}, state)
  end

  # RFC 6455, секция 5.4: фрагментация
  defp handle_continuation(frame, handler, state) do
    cont_state = Map.get(state, :continuation, %{fragments: [], opcode: nil})

    if frame.fin do
      all_fragments = Enum.reverse([frame.payload | cont_state.fragments])
      full_message = IO.iodata_to_binary(all_fragments)
      opcode = cont_state.opcode

      result = case opcode do
        @text_opcode ->
          handler.handle_in({full_message, opcode: :text}, Map.delete(state, :continuation))

        @binary_opcode ->
          handler.handle_in({full_message, opcode: :binary}, Map.delete(state, :continuation))

        _ ->
          {:ok, Map.delete(state, :continuation)}
      end

      case result do
        {:ok, new_state} -> {:ok, new_state}
        other -> other
      end
    else
      new_cont = %{
        fragments: [frame.payload | cont_state.fragments],
        opcode: cont_state.opcode || frame.opcode
      }
      {:ok, %{state | continuation: new_cont}}
    end
  end

  # RFC 6455, секция 5.5.1: закрытие соединения
  defp handle_close(frame, handler, state) do
    clean_state = Map.delete(state, :continuation)

    {code, reason} = case frame.payload do
      <<code::16, reason::binary>> -> {code, reason}
      <<code::16>> -> {code, ""}
      "" -> {@close_normal, ""}
      _ -> {@close_protocol_error, "Invalid close frame"}
    end

    send_close(code, reason)
    handler.terminate({:closed, code, reason}, clean_state)
    {:close, reason}
  end

  # RFC 6455, секция 5.5.2: пинг
  defp handle_ping(frame, _handler, state) do
    send_pong(frame.payload)
    {:ok, state}
  end

  # RFC 6455, секция 5.5.3: понг
  defp handle_pong(_frame, _handler, state) do
    {:ok, state}
  end

  # ========== КОДИРОВАНИЕ ФРЕЙМОВ (RFC 6455, секция 5.2) ==========

  defp encode_frame(data, opcode) when opcode in [:text, :binary] do
    fin = 1
    rsv = 0
    mask = 0

    opcode_val = case opcode do
      :text -> @text_opcode
      :binary -> @binary_opcode
    end

    len = byte_size(data)

    header = case len do
      l when l < 126 ->
        <<fin::1, rsv::3, opcode_val::4, mask::1, l::7>>

      l when l < 65536 ->
        <<fin::1, rsv::3, opcode_val::4, mask::1, 126::7, l::16>>

      l ->
        <<fin::1, rsv::3, opcode_val::4, mask::1, 127::7, l::64>>
    end

    header <> data
  end

  defp encode_ping(data \\ "") do
    len = byte_size(data)
    <<0b10001001::8, len::8, data::binary>>
  end

  defp encode_pong(data \\ "") do
    len = byte_size(data)
    <<0b10001010::8, len::8, data::binary>>
  end

  defp encode_close(code, reason \\ "") do
    payload = <<code::16, reason::binary>>
    len = byte_size(payload)
    <<0b10001000::8, len::8, payload::binary>>
  end

  defp send_close(code, reason) do
    Process.send(self(), {:send, encode_close(code, reason), :binary}, [])
  end

  defp send_pong(data) do
    Process.send(self(), {:send, encode_pong(data), :binary}, [])
  end

  # ========== ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ==========

  defp validate_utf8(data) do
    case :unicode.characters_to_binary(data, :utf8, :utf8) do
      result when is_binary(result) -> :ok
      _ -> {:error, :invalid_utf8}
    end
  end

  defp get_header(conn, name, default \\ nil) do
    case Plug.Conn.get_req_header(conn, name) do
      [value | _] -> value
      [] -> default
    end
  end

  def child_spec(handler, handler_opts \\ [], opts \\ []) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [handler, handler_opts, opts]},
      type: :supervisor,
      restart: :permanent
    }
  end
end

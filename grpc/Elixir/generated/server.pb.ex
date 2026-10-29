defmodule ElixirServer.V1.CommandRequest.ParamsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.CommandRequest.ParamsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule ElixirServer.V1.CommandRequest do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.CommandRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :command, 1, type: :string
  field :user_id, 2, type: :string, json_name: "userId"
  field :guild_id, 3, type: :string, json_name: "guildId"
  field :channel_id, 4, type: :string, json_name: "channelId"
  field :params, 5, repeated: true, type: ElixirServer.V1.CommandRequest.ParamsEntry, map: true
end

defmodule ElixirServer.V1.CommandResponse.DataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.CommandResponse.DataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule ElixirServer.V1.CommandResponse do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.CommandResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
  field :data, 3, repeated: true, type: ElixirServer.V1.CommandResponse.DataEntry, map: true
  field :target_service, 4, type: :string, json_name: "targetService"
  field :latency_ms, 5, type: :int64, json_name: "latencyMs"
end

defmodule ElixirServer.V1.StatusRequest do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.StatusRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule ElixirServer.V1.AllServicesStatusResponse do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.AllServicesStatusResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :go, 2, type: ElixirServer.V1.ServiceStatus
  field :python, 3, type: ElixirServer.V1.ServiceStatus
  field :audio, 4, type: ElixirServer.V1.ServiceStatus
  field :gateway, 5, type: ElixirServer.V1.ServiceStatus
end

defmodule ElixirServer.V1.ServiceStatus do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.ServiceStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :status, 2, type: :string
  field :message, 3, type: :string
  field :last_heartbeat, 4, type: :int64, json_name: "lastHeartbeat"
  field :latency_ms, 5, type: :int64, json_name: "latencyMs"
end

defmodule ElixirServer.V1.HealthRequest do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.HealthRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :service, 1, type: :string
end

defmodule ElixirServer.V1.HealthResponse.ServicesEntry do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.HealthResponse.ServicesEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: ElixirServer.V1.ServiceStatus
end

defmodule ElixirServer.V1.HealthResponse do
  @moduledoc false

  use Protobuf,
    full_name: "ElixirServer.v1.HealthResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :status, 1, type: :string
  field :message, 2, type: :string
  field :timestamp, 3, type: :int64

  field :services, 4,
    repeated: true,
    type: ElixirServer.V1.HealthResponse.ServicesEntry,
    map: true
end

defmodule Client.V1.ClientType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.ClientType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :CLIENT_TYPE_UNKNOWN, 0
  field :CLIENT_TYPE_GO, 1
  field :CLIENT_TYPE_JAVA, 2
  field :CLIENT_TYPE_PYTHON, 3
  field :CLIENT_TYPE_ELIXIR, 4
  field :CLIENT_TYPE_RUST, 5
  field :CLIENT_TYPE_CUDA, 6
  field :CLIENT_TYPE_WEB, 7
  field :CLIENT_TYPE_MOBILE, 8
end

defmodule Client.V1.MetricsAggregation do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.MetricsAggregation",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :NONE, 0
  field :AVG, 1
  field :SUM, 2
  field :MIN, 3
  field :MAX, 4
  field :PERCENTILE_95, 5
  field :PERCENTILE_99, 6
end

defmodule Client.V1.ClientStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.ClientStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :CLIENT_STATUS_UNKNOWN, 0
  field :CLIENT_STATUS_CONNECTING, 1
  field :CLIENT_STATUS_CONNECTED, 2
  field :CLIENT_STATUS_DISCONNECTED, 3
  field :CLIENT_STATUS_ERROR, 4
  field :CLIENT_STATUS_RECONNECTING, 5
  field :CLIENT_STATUS_DEGRADED, 6
end

defmodule Client.V1.MetricType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.MetricType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :COUNTER, 0
  field :GAUGE, 1
  field :HISTOGRAM, 2
  field :SUMMARY, 3
end

defmodule Client.V1.Error.ErrorCode do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.Error.ErrorCode",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :ERROR_CODE_UNKNOWN, 0
  field :ERROR_CODE_UNAUTHORIZED, 1
  field :ERROR_CODE_FORBIDDEN, 2
  field :ERROR_CODE_NOT_FOUND, 3
  field :ERROR_CODE_TIMEOUT, 4
  field :ERROR_CODE_RATE_LIMITED, 5
  field :ERROR_CODE_INVALID_REQUEST, 6
  field :ERROR_CODE_INTERNAL, 7
  field :ERROR_CODE_UNAVAILABLE, 8
end

defmodule Client.V1.HealthCheckResponse.ServingStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "client.v1.HealthCheckResponse.ServingStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :SERVING_STATUS_UNKNOWN, 0
  field :SERVING_STATUS_SERVING, 1
  field :SERVING_STATUS_NOT_SERVING, 2
  field :SERVING_STATUS_DEGRADED, 3
end

defmodule Client.V1.ClientRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ClientRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :request_type, 0

  field :client_id, 1, type: :string, json_name: "clientId"
  field :request_id, 2, type: :string, json_name: "requestId"
  field :timestamp, 3, type: :int64
  field :auth, 10, type: Client.V1.AuthRequest, oneof: 0
  field :subscribe, 11, type: Client.V1.SubscribeRequest, oneof: 0
  field :unsubscribe, 12, type: Client.V1.UnsubscribeRequest, oneof: 0
  field :ping, 13, type: Client.V1.Ping, oneof: 0
  field :event, 14, type: Client.V1.EventRequest, oneof: 0
  field :status, 15, type: Client.V1.StatusRequest, oneof: 0
  field :metrics, 16, type: Client.V1.MetricsRequest, oneof: 0
  field :config, 17, type: Client.V1.ConfigRequest, oneof: 0
end

defmodule Client.V1.Event do
  @moduledoc false

  use Protobuf, full_name: "client.v1.Event", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :event_id, 1, type: :string, json_name: "eventId"
  field :event_type, 2, type: :string, json_name: "eventType"
  field :payload, 3, type: :bytes
  field :timestamp, 4, type: :int64
  field :from_history, 5, type: :bool, json_name: "fromHistory"
end

defmodule Client.V1.AuthRequest.MetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.AuthRequest.MetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.AuthRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.AuthRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :token, 1, type: :string
  field :client_type, 2, type: Client.V1.ClientType, json_name: "clientType", enum: true
  field :version, 3, type: :string
  field :metadata, 4, repeated: true, type: Client.V1.AuthRequest.MetadataEntry, map: true
end

defmodule Client.V1.SubscribeRequest.FiltersEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.SubscribeRequest.FiltersEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.SubscribeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.SubscribeRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :events, 1, repeated: true, type: :string
  field :ttl_seconds, 2, type: :int64, json_name: "ttlSeconds"
  field :filters, 3, repeated: true, type: Client.V1.SubscribeRequest.FiltersEntry, map: true
  field :replay_history, 4, type: :bool, json_name: "replayHistory"
end

defmodule Client.V1.UnsubscribeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.UnsubscribeRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :events, 1, repeated: true, type: :string
  field :unsubscribe_all, 2, type: :bool, json_name: "unsubscribeAll"
end

defmodule Client.V1.Ping do
  @moduledoc false

  use Protobuf, full_name: "client.v1.Ping", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :timestamp, 1, type: :int64
  field :client_id, 2, type: :string, json_name: "clientId"
end

defmodule Client.V1.EventRequest.MetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.EventRequest.MetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.EventRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.EventRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :event_type, 1, type: :string, json_name: "eventType"
  field :payload, 2, type: :bytes
  field :timestamp, 3, type: :int64
  field :metadata, 4, repeated: true, type: Client.V1.EventRequest.MetadataEntry, map: true
end

defmodule Client.V1.StatusRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.StatusRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :detailed, 1, type: :bool
  field :metrics, 2, repeated: true, type: :string
end

defmodule Client.V1.MetricsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.MetricsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :metric_names, 1, repeated: true, type: :string, json_name: "metricNames"
  field :from_timestamp, 2, type: :int64, json_name: "fromTimestamp"
  field :to_timestamp, 3, type: :int64, json_name: "toTimestamp"
  field :aggregation, 4, type: Client.V1.MetricsAggregation, enum: true
end

defmodule Client.V1.ConfigRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ConfigRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :config_keys, 1, repeated: true, type: :string, json_name: "configKeys"
  field :watch, 2, type: :bool
end

defmodule Client.V1.ClientResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ClientResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :response_type, 0

  field :client_id, 1, type: :string, json_name: "clientId"
  field :request_id, 2, type: :string, json_name: "requestId"
  field :timestamp, 3, type: :int64
  field :auth, 10, type: Client.V1.AuthResponse, oneof: 0
  field :subscribe, 11, type: Client.V1.SubscribeResponse, oneof: 0
  field :unsubscribe, 12, type: Client.V1.UnsubscribeResponse, oneof: 0
  field :pong, 13, type: Client.V1.Pong, oneof: 0
  field :event, 14, type: Client.V1.EventResponse, oneof: 0
  field :status, 15, type: Client.V1.StatusResponse, oneof: 0
  field :metrics, 16, type: Client.V1.MetricsResponse, oneof: 0
  field :config, 17, type: Client.V1.ConfigResponse, oneof: 0
  field :error, 100, type: Client.V1.Error, oneof: 0
end

defmodule Client.V1.AuthResponse.MetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.AuthResponse.MetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.AuthResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.AuthResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :session_id, 1, type: :string, json_name: "sessionId"
  field :name, 2, type: :string
  field :authenticated_at, 3, type: :int64, json_name: "authenticatedAt"
  field :expires_at, 4, type: :int64, json_name: "expiresAt"
  field :permissions, 5, repeated: true, type: :string
  field :metadata, 6, repeated: true, type: Client.V1.AuthResponse.MetadataEntry, map: true
end

defmodule Client.V1.SubscribeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.SubscribeResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :subscribed_events, 1, repeated: true, type: :string, json_name: "subscribedEvents"
  field :ttl_seconds, 2, type: :int64, json_name: "ttlSeconds"
  field :subscription_id, 3, type: :string, json_name: "subscriptionId"
  field :event_count, 4, type: :int64, json_name: "eventCount"
end

defmodule Client.V1.UnsubscribeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.UnsubscribeResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :unsubscribed_events, 1, repeated: true, type: :string, json_name: "unsubscribedEvents"
  field :all_unsubscribed, 2, type: :bool, json_name: "allUnsubscribed"
end

defmodule Client.V1.Pong do
  @moduledoc false

  use Protobuf, full_name: "client.v1.Pong", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :timestamp, 1, type: :int64
  field :server_time, 2, type: :int64, json_name: "serverTime"
  field :latency_ms, 3, type: :int64, json_name: "latencyMs"
  field :server_id, 4, type: :string, json_name: "serverId"
end

defmodule Client.V1.EventResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.EventResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :event_id, 1, type: :string, json_name: "eventId"
  field :event_type, 2, type: :string, json_name: "eventType"
  field :payload, 3, type: :bytes
  field :timestamp, 4, type: :int64
  field :from_history, 5, type: :bool, json_name: "fromHistory"
end

defmodule Client.V1.StatusResponse.EventCountsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.StatusResponse.EventCountsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :int64
end

defmodule Client.V1.StatusResponse.Detailed.DebugInfoEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.StatusResponse.Detailed.DebugInfoEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.StatusResponse.Detailed do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.StatusResponse.Detailed",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :recent_events, 1, repeated: true, type: :string, json_name: "recentEvents"

  field :debug_info, 2,
    repeated: true,
    type: Client.V1.StatusResponse.Detailed.DebugInfoEntry,
    json_name: "debugInfo",
    map: true
end

defmodule Client.V1.StatusResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.StatusResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :client_id, 1, type: :string, json_name: "clientId"
  field :status, 2, type: Client.V1.ClientStatus, enum: true
  field :connected_since, 3, type: :int64, json_name: "connectedSince"
  field :last_activity, 4, type: :int64, json_name: "lastActivity"
  field :connection, 5, type: Client.V1.ConnectionInfo
  field :active_subscriptions, 6, repeated: true, type: :string, json_name: "activeSubscriptions"

  field :event_counts, 7,
    repeated: true,
    type: Client.V1.StatusResponse.EventCountsEntry,
    json_name: "eventCounts",
    map: true

  field :resources, 8, type: Client.V1.ResourceUsage
  field :detailed, 9, type: Client.V1.StatusResponse.Detailed
end

defmodule Client.V1.ConnectionInfo do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ConnectionInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :client_ip, 1, type: :string, json_name: "clientIp"
  field :protocol, 2, type: :string
  field :port, 3, type: :int32
  field :user_agent, 4, type: :string, json_name: "userAgent"
  field :ping_ms, 5, type: :int64, json_name: "pingMs"
  field :bytes_sent, 6, type: :int64, json_name: "bytesSent"
  field :bytes_received, 7, type: :int64, json_name: "bytesReceived"
end

defmodule Client.V1.ResourceUsage do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ResourceUsage",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :cpu_percent, 1, type: :float, json_name: "cpuPercent"
  field :memory_bytes, 2, type: :int64, json_name: "memoryBytes"
  field :uptime_ms, 3, type: :int64, json_name: "uptimeMs"
  field :active_threads, 4, type: :int32, json_name: "activeThreads"
  field :open_files, 5, type: :int32, json_name: "openFiles"
end

defmodule Client.V1.MetricsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.MetricsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :client_id, 1, type: :string, json_name: "clientId"
  field :collected_at, 2, type: :int64, json_name: "collectedAt"
  field :metrics, 3, repeated: true, type: Client.V1.Metric
end

defmodule Client.V1.Metric.LabelsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.Metric.LabelsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Client.V1.Metric do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.Metric",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :value, 0

  field :name, 1, type: :string
  field :type, 2, type: Client.V1.MetricType, enum: true
  field :int_value, 3, type: :int64, json_name: "intValue", oneof: 0
  field :float_value, 4, type: :double, json_name: "floatValue", oneof: 0
  field :string_value, 5, type: :string, json_name: "stringValue", oneof: 0
  field :bool_value, 6, type: :bool, json_name: "boolValue", oneof: 0
  field :histogram, 7, type: Client.V1.Histogram, oneof: 0
  field :labels, 8, repeated: true, type: Client.V1.Metric.LabelsEntry, map: true
  field :timestamp, 9, type: :int64
end

defmodule Client.V1.Histogram do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.Histogram",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :buckets, 1, repeated: true, type: Client.V1.Bucket
  field :sum, 2, type: :double
  field :count, 3, type: :int64
end

defmodule Client.V1.Bucket do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.Bucket",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :upper_bound, 1, type: :double, json_name: "upperBound"
  field :cumulative_count, 2, type: :int64, json_name: "cumulativeCount"
end

defmodule Client.V1.ConfigResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ConfigResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :entries, 1, repeated: true, type: Client.V1.ConfigEntry
  field :version, 2, type: :int64
  field :watching, 3, type: :bool
end

defmodule Client.V1.ConfigEntry do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.ConfigEntry",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  oneof :value, 0

  field :key, 1, type: :string
  field :string_value, 2, type: :string, json_name: "stringValue", oneof: 0
  field :int_value, 3, type: :int64, json_name: "intValue", oneof: 0
  field :float_value, 4, type: :double, json_name: "floatValue", oneof: 0
  field :bool_value, 5, type: :bool, json_name: "boolValue", oneof: 0
  field :bytes_value, 6, type: :bytes, json_name: "bytesValue", oneof: 0
  field :description, 7, type: :string
  field :mutable, 8, type: :bool
end

defmodule Client.V1.Error do
  @moduledoc false

  use Protobuf, full_name: "client.v1.Error", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :code, 1, type: :int32
  field :message, 2, type: :string
  field :details, 3, type: :string
  field :timestamp, 4, type: :int64
  field :request_id, 5, type: :string, json_name: "requestId"
  field :error_code, 6, type: Client.V1.Error.ErrorCode, json_name: "errorCode", enum: true
end

defmodule Client.V1.HealthCheckRequest do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.HealthCheckRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :service, 1, type: :string
  field :detailed, 2, type: :bool
end

defmodule Client.V1.HealthCheckResponse.Check do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.HealthCheckResponse.Check",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :name, 1, type: :string
  field :status, 2, type: Client.V1.HealthCheckResponse.ServingStatus, enum: true
  field :message, 3, type: :string
  field :duration_ms, 4, type: :int64, json_name: "durationMs"
end

defmodule Client.V1.HealthCheckResponse do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.HealthCheckResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :status, 1, type: Client.V1.HealthCheckResponse.ServingStatus, enum: true
  field :message, 2, type: :string
  field :timestamp, 3, type: :int64
  field :checks, 4, repeated: true, type: Client.V1.HealthCheckResponse.Check
  field :version, 5, type: Client.V1.VersionInfo
  field :capacity, 6, type: Client.V1.CapacityInfo
end

defmodule Client.V1.VersionInfo do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.VersionInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :version, 1, type: :string
  field :build, 2, type: :string
  field :commit, 3, type: :string
  field :branch, 4, type: :string
  field :build_time, 5, type: :int64, json_name: "buildTime"
end

defmodule Client.V1.CapacityInfo do
  @moduledoc false

  use Protobuf,
    full_name: "client.v1.CapacityInfo",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :max_connections, 1, type: :int32, json_name: "maxConnections"
  field :current_connections, 2, type: :int32, json_name: "currentConnections"
  field :max_requests_per_second, 3, type: :int32, json_name: "maxRequestsPerSecond"
  field :current_rps, 4, type: :int32, json_name: "currentRps"
  field :cpu_usage, 5, type: :float, json_name: "cpuUsage"
  field :memory_usage, 6, type: :float, json_name: "memoryUsage"
end

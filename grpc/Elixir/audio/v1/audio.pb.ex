defmodule Audio.V1.EffectType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.EffectType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :VOLUME, 0
  field :EQUALIZER, 1
  field :COMPRESSOR, 2
  field :REVERB, 3
  field :DELAY, 4
  field :DISTORTION, 5
  field :CHORUS, 6
  field :PITCH_SHIFT, 7
  field :GATE, 8
  field :LIMITER, 9
end

defmodule Audio.V1.AudioFormat.SampleFormat do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.AudioFormat.SampleFormat",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :U8, 0
  field :S16, 1
  field :S24, 2
  field :S32, 3
  field :F32, 4
  field :F64, 5
end

defmodule Audio.V1.AudioFormat.ChannelLayout do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.AudioFormat.ChannelLayout",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :MONO, 0
  field :STEREO, 1
  field :SURROUND_51, 2
  field :SURROUND_71, 3
end

defmodule Audio.V1.ParametricBand.FilterType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.ParametricBand.FilterType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :PEAKING, 0
  field :LOW_SHELF, 1
  field :HIGH_SHELF, 2
  field :LOW_PASS, 3
  field :HIGH_PASS, 4
  field :BAND_PASS, 5
  field :NOTCH, 6
end

defmodule Audio.V1.ReverbParams.ReverbType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.ReverbParams.ReverbType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :ROOM, 0
  field :HALL, 1
  field :PLATE, 2
  field :SPRING, 3
  field :CATHEDRAL, 4
  field :CUSTOM, 5
end

defmodule Audio.V1.DelayParams.DelayType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.DelayParams.DelayType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :MONO, 0
  field :STEREO, 1
  field :PING_PONG, 2
  field :MULTI_TAP, 3
  field :TAPE, 4
end

defmodule Audio.V1.DistortionParams.DistortionType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.DistortionParams.DistortionType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :SOFT_CLIP, 0
  field :HARD_CLIP, 1
  field :ASYMMETRIC, 2
  field :TUBE, 3
  field :FUZZ, 4
  field :OVERDRIVE, 5
  field :BIT_CRUSHER, 6
  field :WAVE_SHAPER, 7
  field :FOLDBACK, 8
end

defmodule Audio.V1.ChorusParams.ChorusType do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.ChorusParams.ChorusType",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :CHORUS, 0
  field :FLANGER, 1
  field :DIMENSION, 2
  field :ENSEMBLE, 3
  field :VIBRATO, 4
end

defmodule Audio.V1.HealthCheckResponse.ServingStatus do
  @moduledoc false

  use Protobuf,
    enum: true,
    full_name: "audio.v1.HealthCheckResponse.ServingStatus",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :UNKNOWN, 0
  field :SERVING, 1
  field :NOT_SERVING, 2
  field :DEGRADED, 3
end

defmodule Audio.V1.PlayRequest.OptionsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PlayRequest.OptionsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.PlayRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PlayRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
  field :user_id, 2, type: :string, json_name: "userId"
  field :track_url, 3, type: :string, json_name: "trackUrl"
  field :track_title, 4, type: :string, json_name: "trackTitle"
  field :options, 5, repeated: true, type: Audio.V1.PlayRequest.OptionsEntry, map: true
end

defmodule Audio.V1.PlayResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PlayResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :stream_id, 2, type: :string, json_name: "streamId"
  field :message, 3, type: :string
end

defmodule Audio.V1.StopRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.StopRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.StopResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.StopResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Audio.V1.PauseRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PauseRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.PauseResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PauseResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
end

defmodule Audio.V1.ResumeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ResumeRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.ResumeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ResumeResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
end

defmodule Audio.V1.VolumeRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.VolumeRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
  field :volume, 2, type: :int32
end

defmodule Audio.V1.VolumeResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.VolumeResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :message, 2, type: :string
end

defmodule Audio.V1.SkipRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.SkipRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.SkipResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.SkipResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :next_title, 2, type: :string, json_name: "nextTitle"
  field :message, 3, type: :string
end

defmodule Audio.V1.QueueRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.QueueRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.QueueTrack do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.QueueTrack",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :title, 1, type: :string
  field :url, 2, type: :string
end

defmodule Audio.V1.QueueResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.QueueResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :tracks, 2, repeated: true, type: Audio.V1.QueueTrack
  field :message, 3, type: :string
end

defmodule Audio.V1.EffectsRequest.EffectsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.EffectsRequest.EffectsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.EffectsRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.EffectsRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
  field :user_id, 2, type: :string, json_name: "userId"
  field :effects, 3, repeated: true, type: Audio.V1.EffectsRequest.EffectsEntry, map: true
end

defmodule Audio.V1.EffectsResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.EffectsResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :applied, 2, repeated: true, type: :string
  field :message, 3, type: :string
end

defmodule Audio.V1.StatusRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.StatusRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :guild_id, 1, type: :string, json_name: "guildId"
end

defmodule Audio.V1.StatusResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.StatusResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :success, 1, type: :bool
  field :playing, 2, type: :bool
  field :current_track, 3, type: :string, json_name: "currentTrack"
  field :position, 4, type: :int32
  field :volume, 5, type: :int32
  field :message, 6, type: :string
end

defmodule Audio.V1.AudioProcessRequest.MetadataEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioProcessRequest.MetadataEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.AudioProcessRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioProcessRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :stream_id, 1, type: :string, json_name: "streamId"
  field :audio_data, 2, type: :bytes, json_name: "audioData"
  field :format, 3, type: Audio.V1.AudioFormat
  field :effects, 4, type: Audio.V1.EffectChain
  field :options, 5, type: Audio.V1.ProcessingOptions
  field :metadata, 6, repeated: true, type: Audio.V1.AudioProcessRequest.MetadataEntry, map: true
end

defmodule Audio.V1.AudioFormat do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioFormat",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :sample_format, 1,
    type: Audio.V1.AudioFormat.SampleFormat,
    json_name: "sampleFormat",
    enum: true

  field :sample_rate, 2, type: :int32, json_name: "sampleRate"

  field :channel_layout, 3,
    type: Audio.V1.AudioFormat.ChannelLayout,
    json_name: "channelLayout",
    enum: true

  field :bit_depth, 4, type: :int32, json_name: "bitDepth"
  field :little_endian, 5, type: :bool, json_name: "littleEndian"
end

defmodule Audio.V1.EffectChain do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.EffectChain",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :effects, 1, repeated: true, type: Audio.V1.Effect
  field :bypass, 2, type: :bool
  field :mix, 3, type: :float
end

defmodule Audio.V1.Effect do
  @moduledoc false

  use Protobuf, full_name: "audio.v1.Effect", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  oneof :params, 0

  field :id, 1, type: :string
  field :type, 2, type: Audio.V1.EffectType, enum: true
  field :enabled, 3, type: :bool
  field :mix, 4, type: :float
  field :volume, 10, type: Audio.V1.VolumeParams, oneof: 0
  field :equalizer, 11, type: Audio.V1.EqualizerParams, oneof: 0
  field :compressor, 12, type: Audio.V1.CompressorParams, oneof: 0
  field :reverb, 13, type: Audio.V1.ReverbParams, oneof: 0
  field :delay, 14, type: Audio.V1.DelayParams, oneof: 0
  field :distortion, 15, type: Audio.V1.DistortionParams, oneof: 0
  field :chorus, 16, type: Audio.V1.ChorusParams, oneof: 0
  field :pitch_shift, 17, type: Audio.V1.PitchShiftParams, json_name: "pitchShift", oneof: 0
  field :gate, 18, type: Audio.V1.GateParams, oneof: 0
  field :limiter, 19, type: Audio.V1.LimiterParams, oneof: 0
end

defmodule Audio.V1.VolumeParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.VolumeParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :gain, 1, type: :float
  field :mute, 2, type: :bool
  field :solo, 3, type: :bool
end

defmodule Audio.V1.EqualizerParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.EqualizerParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :gains, 1, repeated: true, type: :float
  field :preamp, 2, type: :float
  field :linear_phase, 3, type: :bool, json_name: "linearPhase"

  field :parametric_bands, 10,
    repeated: true,
    type: Audio.V1.ParametricBand,
    json_name: "parametricBands"
end

defmodule Audio.V1.ParametricBand do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ParametricBand",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :frequency, 1, type: :float
  field :gain, 2, type: :float
  field :q, 3, type: :float

  field :filter_type, 4,
    type: Audio.V1.ParametricBand.FilterType,
    json_name: "filterType",
    enum: true

  field :enabled, 5, type: :bool
end

defmodule Audio.V1.CompressorParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.CompressorParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :threshold, 2, type: :float
  field :ratio, 3, type: :float
  field :attack, 4, type: :int32
  field :release, 5, type: :int32
  field :knee, 6, type: :float
  field :makeup_gain, 7, type: :float, json_name: "makeupGain"
  field :lookahead, 8, type: :int32
  field :auto_release, 9, type: :bool, json_name: "autoRelease"

  field :multiband_bands, 10,
    repeated: true,
    type: Audio.V1.MultibandBand,
    json_name: "multibandBands"

  field :sidechain_source, 11, type: :string, json_name: "sidechainSource"
end

defmodule Audio.V1.MultibandBand do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.MultibandBand",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :frequency_low, 1, type: :float, json_name: "frequencyLow"
  field :frequency_high, 2, type: :float, json_name: "frequencyHigh"
  field :threshold, 3, type: :float
  field :ratio, 4, type: :float
  field :attack, 5, type: :int32
  field :release, 6, type: :int32
  field :solo, 7, type: :bool
  field :mute, 8, type: :bool
end

defmodule Audio.V1.ReverbParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ReverbParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :level, 2, type: :float
  field :room_size, 3, type: :float, json_name: "roomSize"
  field :damping, 4, type: :float
  field :width, 5, type: :float
  field :pre_delay, 6, type: :float, json_name: "preDelay"
  field :decay_time, 7, type: :float, json_name: "decayTime"
  field :diffusion, 8, type: :float
  field :modulation, 9, type: :float

  field :reverb_type, 10,
    type: Audio.V1.ReverbParams.ReverbType,
    json_name: "reverbType",
    enum: true
end

defmodule Audio.V1.DelayParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.DelayParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :time, 2, type: :float
  field :feedback, 3, type: :float
  field :mix, 4, type: :float
  field :delay_type, 5, type: Audio.V1.DelayParams.DelayType, json_name: "delayType", enum: true
  field :taps, 10, repeated: true, type: Audio.V1.Tap
end

defmodule Audio.V1.Tap do
  @moduledoc false

  use Protobuf, full_name: "audio.v1.Tap", protoc_gen_elixir_version: "0.16.0", syntax: :proto3

  field :time, 1, type: :float
  field :gain, 2, type: :float
  field :pan, 3, type: :float
  field :enabled, 4, type: :bool
end

defmodule Audio.V1.DistortionParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.DistortionParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :drive, 2, type: :float
  field :tone, 3, type: :float
  field :volume, 4, type: :float

  field :distortion_type, 5,
    type: Audio.V1.DistortionParams.DistortionType,
    json_name: "distortionType",
    enum: true

  field :bit_depth, 6, type: :int32, json_name: "bitDepth"
  field :sample_rate_reduction, 7, type: :float, json_name: "sampleRateReduction"
end

defmodule Audio.V1.ChorusParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ChorusParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :rate, 2, type: :float
  field :depth, 3, type: :float
  field :mix, 4, type: :float

  field :chorus_type, 5,
    type: Audio.V1.ChorusParams.ChorusType,
    json_name: "chorusType",
    enum: true
end

defmodule Audio.V1.PitchShiftParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.PitchShiftParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :pitch_shift, 2, type: :float, json_name: "pitchShift"
  field :fine_tune, 3, type: :float, json_name: "fineTune"
  field :formant_shift, 4, type: :float, json_name: "formantShift"
  field :preserve_formants, 5, type: :bool, json_name: "preserveFormants"
end

defmodule Audio.V1.GateParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.GateParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :threshold, 2, type: :float
  field :attack, 3, type: :int32
  field :hold, 4, type: :int32
  field :release, 5, type: :int32
  field :range, 6, type: :float
end

defmodule Audio.V1.LimiterParams do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.LimiterParams",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :enabled, 1, type: :bool
  field :threshold, 2, type: :float
  field :release, 3, type: :int32
  field :lookahead, 4, type: :int32
end

defmodule Audio.V1.ProcessingOptions do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ProcessingOptions",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :priority, 1, type: :int32
  field :quality_profile, 2, type: :string, json_name: "qualityProfile"
  field :max_retries, 3, type: :int32, json_name: "maxRetries"
  field :realtime, 4, type: :bool
  field :save_debug_info, 5, type: :bool, json_name: "saveDebugInfo"
end

defmodule Audio.V1.AudioBatchRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioBatchRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :batch_id, 1, type: :string, json_name: "batchId"
  field :requests, 2, repeated: true, type: Audio.V1.AudioProcessRequest
  field :parallel, 3, type: :bool
  field :max_concurrent, 4, type: :int32, json_name: "maxConcurrent"
end

defmodule Audio.V1.AudioBatchResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioBatchResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :batch_id, 1, type: :string, json_name: "batchId"
  field :responses, 2, repeated: true, type: Audio.V1.AudioProcessResponse
  field :stats, 3, type: Audio.V1.BatchStats
end

defmodule Audio.V1.BatchStats do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.BatchStats",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :total, 1, type: :int32
  field :successful, 2, type: :int32
  field :failed, 3, type: :int32
  field :total_time_ms, 4, type: :int64, json_name: "totalTimeMs"
  field :average_time_ms, 5, type: :float, json_name: "averageTimeMs"
end

defmodule Audio.V1.AudioProcessResponse.DebugInfoEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioProcessResponse.DebugInfoEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.AudioProcessResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.AudioProcessResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :stream_id, 1, type: :string, json_name: "streamId"
  field :processed_audio, 2, type: :bytes, json_name: "processedAudio"
  field :processing_time_ms, 3, type: :int64, json_name: "processingTimeMs"
  field :stats, 4, type: Audio.V1.ProcessingStats
  field :applied_effects, 5, repeated: true, type: :string, json_name: "appliedEffects"
  field :cached, 6, type: :bool

  field :debug_info, 7,
    repeated: true,
    type: Audio.V1.AudioProcessResponse.DebugInfoEntry,
    json_name: "debugInfo",
    map: true
end

defmodule Audio.V1.ProcessingStats.BandLevelsEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ProcessingStats.BandLevelsEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :float
end

defmodule Audio.V1.ProcessingStats do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.ProcessingStats",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :input_size, 1, type: :int64, json_name: "inputSize"
  field :output_size, 2, type: :int64, json_name: "outputSize"
  field :compression_ratio, 3, type: :float, json_name: "compressionRatio"
  field :peak_level, 4, type: :float, json_name: "peakLevel"
  field :rms_level, 5, type: :float, json_name: "rmsLevel"
  field :crest_factor, 6, type: :float, json_name: "crestFactor"
  field :dynamic_range, 7, type: :float, json_name: "dynamicRange"

  field :band_levels, 8,
    repeated: true,
    type: Audio.V1.ProcessingStats.BandLevelsEntry,
    json_name: "bandLevels",
    map: true
end

defmodule Audio.V1.InfoRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.InfoRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :service_id, 1, type: :string, json_name: "serviceId"
end

defmodule Audio.V1.InfoResponse.ConfigEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.InfoResponse.ConfigEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.InfoResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.InfoResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :version, 1, type: :string
  field :build_info, 2, type: :string, json_name: "buildInfo"
  field :uptime_ms, 3, type: :int64, json_name: "uptimeMs"
  field :capacity, 4, type: Audio.V1.Capacity
  field :available_effects, 5, repeated: true, type: :string, json_name: "availableEffects"
  field :config, 6, repeated: true, type: Audio.V1.InfoResponse.ConfigEntry, map: true
end

defmodule Audio.V1.Capacity do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.Capacity",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :max_concurrent, 1, type: :int32, json_name: "maxConcurrent"
  field :current_concurrent, 2, type: :int32, json_name: "currentConcurrent"
  field :queue_size, 3, type: :int32, json_name: "queueSize"
  field :max_queue_size, 4, type: :int32, json_name: "maxQueueSize"
  field :cpu_usage, 5, type: :float, json_name: "cpuUsage"
  field :memory_usage, 6, type: :float, json_name: "memoryUsage"
  field :gpu_available, 7, type: :bool, json_name: "gpuAvailable"
end

defmodule Audio.V1.HealthCheckRequest do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.HealthCheckRequest",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :service, 1, type: :string
end

defmodule Audio.V1.HealthCheckResponse.ChecksEntry do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.HealthCheckResponse.ChecksEntry",
    map: true,
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :key, 1, type: :string
  field :value, 2, type: :string
end

defmodule Audio.V1.HealthCheckResponse do
  @moduledoc false

  use Protobuf,
    full_name: "audio.v1.HealthCheckResponse",
    protoc_gen_elixir_version: "0.16.0",
    syntax: :proto3

  field :status, 1, type: Audio.V1.HealthCheckResponse.ServingStatus, enum: true
  field :message, 2, type: :string
  field :timestamp, 3, type: :int64
  field :checks, 4, repeated: true, type: Audio.V1.HealthCheckResponse.ChecksEntry, map: true
end

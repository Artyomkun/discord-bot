pub use std::fmt;
pub use crate::audio::sample_format::SampleFormat;
pub use crate::audio::format::AudioFormat;
pub use crate::audio::metadata::AudioMetadata;

/// Audio file/stream information
#[derive(Debug, Clone)]
pub struct AudioInfo {
    pub format: AudioFormat,
    pub sample_format: SampleFormat,
    pub duration: f32,
    pub bitrate: u32,
    pub metadata: AudioMetadata,
}
//! Audio data handling module
//! Formats, buffers, conversions and audio operations

pub mod buffer;
pub mod converter;
pub mod format;
pub mod stream;
pub mod utils;
pub mod effects;
pub mod error;
pub mod sample_format;
pub mod resampler;
pub mod processor;
pub mod metadata;
pub mod info;

// Re-export основных типов
pub use crate::audio::buffer::*;
pub use crate::audio::converter::*;
pub use crate::audio::format::*;
pub use crate::audio::effects::*;
pub use crate::audio::utils::*;
pub use crate::audio::error::*;
pub use crate::audio::sample_format::*;
pub use crate::audio::resampler::*;
pub use crate::audio::processor::*;
pub use crate::audio::metadata::*;
pub use crate::audio::info::*;
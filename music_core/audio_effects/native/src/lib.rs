//! # Native DSP Library
//!
//! This library provides native implementations of digital signal processing
//! functions for audio effects, optimized for performance.

pub mod audio;
pub mod dsp;
pub mod effects;
pub mod nif;

// Re-export only the necessary types from audio
pub use crate::audio::*;

// Re-export from effects
pub use crate::effects::*;

// Re-export from DSP
pub use crate::dsp::*;

// Re-export from NIF
pub use crate::nif::*;

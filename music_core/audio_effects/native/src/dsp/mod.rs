//! Digital signal processing (DSP) module
//! Contains all DSP algorithms and utilities for audio processing

pub mod compressor;
pub mod detectors;
pub mod eq;
pub mod fft;
pub mod filter;
pub mod reverb;
pub mod utils;
pub mod analysis;
pub mod effect;
pub mod processor;

// Re-export most important types and functions
pub use crate::dsp::compressor::*;
pub use crate::dsp::detectors::*;
pub use crate::dsp::eq::*;
pub use crate::dsp::fft::*;
pub use crate::dsp::filter::*;
pub use crate::dsp::reverb::*;
pub use crate::dsp::utils::*;
pub use crate::dsp::analysis::*;
pub use crate::dsp::effect::*;
pub use crate::dsp::processor::*;
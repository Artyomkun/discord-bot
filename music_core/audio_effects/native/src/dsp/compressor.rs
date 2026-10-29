//! Dynamic processors: compressor, limiter, gate, expander
//! Professional dynamic processing algorithms

use crate::dsp::detectors::{DetectorConfig, DetectorMode, PeakDetector, RmsDetector};
use crate::dsp::detectors::LevelDetector;
use crate::dsp::filter::{Filter, FilterType};
use serde::{Deserialize, Serialize};
use std::f32::consts::LN_2;

/// Dynamics processor type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum DynamicsType {
    Compressor,
    Limiter,
    Gate,
    Expander,
    DeEsser,
}

/// Level detector type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum DetectorType {
    Peak,
    RMS,
    PeakHold,
}

/// Compressor configuration
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct CompressorConfig {
    pub dynamics_type: DynamicsType,
    pub detector_type: DetectorType,
    pub threshold_db: f32,   // dB, -60.0 to 0.0
    pub ratio: f32,          // 1.0 to 100.0 (1:1 to 100:1)
    pub attack_ms: f32,      // ms, 0.1 to 100.0
    pub release_ms: f32,     // ms, 10.0 to 5000.0
    pub knee_db: f32,        // dB, 0.0 to 30.0
    pub makeup_gain_db: f32, // dB, -24.0 to 24.0
    pub lookahead_ms: f32,   // ms, 0.0 to 10.0
    pub auto_makeup: bool,
    pub sidechain_filter: bool,
    pub sidechain_freq_hz: f32,
    pub stereo_link: bool,
    pub sample_rate: f32,
}

impl Default for CompressorConfig {
    fn default() -> Self {
        Self {
            dynamics_type: DynamicsType::Compressor,
            detector_type: DetectorType::RMS,
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 2.0,
            auto_makeup: true,
            sidechain_filter: false,
            sidechain_freq_hz: 100.0,
            stereo_link: true,
            sample_rate: 44100.0,
        }
    }
}

/// Professional dynamic processor
pub struct Compressor {
    config: CompressorConfig,
    sample_rate: f32,

    // Envelope and gain reduction
    envelope: f32,
    gain_reduction_linear: f32,

    // Lookahead buffer
    lookahead_buffer: Vec<f32>,
    lookahead_pos: usize,
    lookahead_size: usize,

    // Sidechain filter
    sidechain_filter: Filter,

    // Metering
    peak_level: f32,
    rms_level: f32,
    gain_reduction_db: f32,

    // Internal coefficients
    attack_coeff: f32,
    release_coeff: f32,
    linked_envelope: f32,

    // Detectors
    rms_detector: Option<RmsDetector>,
    peak_detector: Option<PeakDetector>,
}

impl Compressor {
    /// Creates a new compressor
    pub fn new(config: CompressorConfig, sample_rate: f32) -> Self {
        let attack_coeff = (-LN_2 / (config.attack_ms * 0.001 * sample_rate)).exp();
        let release_coeff = (-LN_2 / (config.release_ms * 0.001 * sample_rate)).exp();

        let lookahead_size = ((config.lookahead_ms * 0.001) * sample_rate) as usize;
        let lookahead_buffer = vec![0.0; lookahead_size];

        let mut sidechain_filter = Filter::new(FilterType::HighPass, sample_rate);
        sidechain_filter.set_frequency(config.sidechain_freq_hz);
        sidechain_filter.set_q(0.707);

        let detector_config = DetectorConfig {
            mode: DetectorMode::RMS,
            window_ms: 10.0,
            attack_ms: 0.01,
            release_ms: 0.1,
            hold_ms: 0.0,
            oversampling: 1,
            calibration_db: 0.0,
        };

        Self {
            config,
            sample_rate,
            envelope: 0.0,
            gain_reduction_linear: 1.0,
            lookahead_buffer,
            lookahead_pos: 0,
            lookahead_size,
            sidechain_filter,
            peak_level: 0.0,
            rms_level: 0.0,
            gain_reduction_db: 0.0,
            attack_coeff,
            release_coeff,
            linked_envelope: 0.0,
            rms_detector: Some(RmsDetector::new(detector_config, sample_rate)),
            peak_detector: Some(PeakDetector::new(detector_config, sample_rate)),
        }
    }

    /// Updates the configuration
    pub fn update_config(&mut self, config: CompressorConfig) {
        self.config = config;

        self.attack_coeff = (-LN_2 / (self.config.attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-LN_2 / (self.config.release_ms * 0.001 * self.sample_rate)).exp();

        let new_lookahead_size = ((self.config.lookahead_ms * 0.001) * self.sample_rate) as usize;
        if new_lookahead_size != self.lookahead_size {
            self.lookahead_buffer = vec![0.0; new_lookahead_size];
            self.lookahead_size = new_lookahead_size;
            self.lookahead_pos = 0;
        }

        self.sidechain_filter.set_frequency(self.config.sidechain_freq_hz);
    }

    /// Detects signal level
    fn detect_level(&mut self, sample: f32) -> f32 {
        match self.config.detector_type {
            DetectorType::Peak => {
                if let Some(peak) = &mut self.peak_detector {
                    peak.process(sample)
                } else {
                    sample.abs()
                }
            }
            DetectorType::RMS => {
                if let Some(rms) = &mut self.rms_detector {
                    rms.process(sample)
                } else {
                    sample * sample
                }
            }
            DetectorType::PeakHold => {
                let peak_val = sample.abs();
                if peak_val > self.envelope {
                    peak_val
                } else {
                    self.envelope * 0.99
                }
            }
        }
    }

    /// Updates envelope with attack/release
    fn update_envelope(&mut self, level: f32) {
        let coeff = if level > self.envelope {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope = coeff * self.envelope + (1.0 - coeff) * level;
    }

    /// Calculates gain reduction in dB
    fn calculate_gain_reduction_db(&self, level_db: f32) -> f32 {
        let threshold = self.config.threshold_db;
        let ratio = self.config.ratio;
        let knee = self.config.knee_db;

        match self.config.dynamics_type {
            DynamicsType::Compressor | DynamicsType::Limiter | DynamicsType::DeEsser => {
                if knee > 0.0 && level_db > threshold - knee * 0.5 && level_db < threshold + knee * 0.5 {
                    // Soft knee
                    let overshoot = level_db - (threshold - knee * 0.5);
                    let gain_reduction = (overshoot * overshoot) / (2.0 * knee);
                    -gain_reduction * (1.0 - 1.0 / ratio)
                } else if level_db > threshold {
                    // Hard knee
                    let overshoot = level_db - threshold;
                    -overshoot * (1.0 - 1.0 / ratio)
                } else {
                    0.0
                }
            }
            DynamicsType::Expander => {
                if level_db < threshold {
                    let undershoot = threshold - level_db;
                    undershoot * (1.0 / ratio - 1.0)
                } else {
                    0.0
                }
            }
            DynamicsType::Gate => {
                if level_db < threshold {
                    -120.0 // Full attenuation
                } else {
                    0.0
                }
            }
        }
    }

    /// Calculates makeup gain
    fn calculate_makeup_gain_db(&self, gain_reduction_db: f32) -> f32 {
        if self.config.auto_makeup {
            -gain_reduction_db * 0.5
        } else {
            self.config.makeup_gain_db
        }
    }

    /// Processes a single sample
    pub fn process_sample(&mut self, input: f32) -> f32 {
        // Update metering
        self.peak_level = self.peak_level.max(input.abs());
        self.rms_level = 0.999 * self.rms_level + 0.001 * input * input;

        // Sidechain processing
        let mut detector_input = input;
        if self.config.sidechain_filter {
            self.sidechain_filter.process(&mut detector_input);
        }

        // Detect level
        let level = self.detect_level(detector_input);

        // Convert to dB
        let _level_db = if level > 1e-6 {
            20.0 * level.log10()
        } else {
            -144.0
        };

        // Update envelope
        self.update_envelope(level);

        // Calculate gain reduction with stereo linking
        let envelope_db = if level > 1e-6 {
            20.0 * self.envelope.log10()
        } else {
            -144.0
        };

        let reduction_db = if self.config.stereo_link {
            let linked_db = if self.linked_envelope > 1e-6 {
                20.0 * self.linked_envelope.log10()
            } else {
                -144.0
            };
            self.calculate_gain_reduction_db(linked_db.max(envelope_db))
        } else {
            self.calculate_gain_reduction_db(envelope_db)
        };

        self.gain_reduction_db = reduction_db;

        // Calculate makeup gain
        let makeup_db = self.calculate_makeup_gain_db(reduction_db);

        // Convert to linear
        let reduction_linear = 10.0f32.powf(reduction_db / 20.0);
        let makeup_linear = 10.0f32.powf(makeup_db / 20.0);
        let target_gain = reduction_linear * makeup_linear;

        // Smooth gain changes
        let alpha = 0.01;
        self.gain_reduction_linear = self.gain_reduction_linear * (1.0 - alpha) + target_gain * alpha;

        // Apply gain with lookahead
        if self.lookahead_size > 0 {
            self.lookahead_buffer[self.lookahead_pos] = input;
            let read_pos = (self.lookahead_pos + self.lookahead_size / 2) % self.lookahead_size;
            let output = self.lookahead_buffer[read_pos] * self.gain_reduction_linear;
            self.lookahead_pos = (self.lookahead_pos + 1) % self.lookahead_size;
            output
        } else {
            input * self.gain_reduction_linear
        }
    }

    /// Processes a buffer of samples
    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        for sample in buffer {
            *sample = self.process_sample(*sample);
        }
    }

    /// Links stereo envelope
    pub fn link_envelope(&mut self, other_envelope: f32) {
        self.linked_envelope = self.envelope.max(other_envelope);
    }

    /// Resets internal state
    pub fn reset(&mut self) {
        self.envelope = 0.0;
        self.gain_reduction_linear = 1.0;
        self.lookahead_pos = 0;
        self.lookahead_buffer.fill(0.0);
        self.peak_level = 0.0;
        self.rms_level = 0.0;
        self.gain_reduction_db = 0.0;
        self.linked_envelope = 0.0;
        self.sidechain_filter.reset();
        if let Some(rms) = &mut self.rms_detector {
            rms.reset();
        }
        if let Some(peak) = &mut self.peak_detector {
            peak.reset();
        }
    }

    /// Gets current metrics
    pub fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics {
            peak_level_db: if self.peak_level > 1e-6 {
                20.0 * self.peak_level.log10()
            } else {
                -144.0
            },
            rms_level_db: if self.rms_level > 1e-6 {
                10.0 * self.rms_level.log10()
            } else {
                -144.0
            },
            gain_reduction_db: self.gain_reduction_db,
            envelope_db: if self.envelope > 1e-6 {
                20.0 * self.envelope.log10()
            } else {
                -144.0
            },
        }
    }

    // ============================================================================
    // FACTORY METHODS
    // ============================================================================

    /// Creates a de-esser for sibilance reduction
    pub fn create_deesser(threshold_db: f32, frequency_hz: f32, sample_rate: f32) -> Self {
        let config = CompressorConfig {
            dynamics_type: DynamicsType::DeEsser,
            detector_type: DetectorType::Peak,
            threshold_db,
            ratio: 10.0,
            attack_ms: 1.0,
            release_ms: 50.0,
            knee_db: 3.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 0.0,
            auto_makeup: false,
            sidechain_filter: true,
            sidechain_freq_hz: frequency_hz,
            stereo_link: true,
            sample_rate,
        };
        Self::new(config, sample_rate)
    }

    /// Creates a limiter (brick-wall)
    pub fn create_limiter(threshold_db: f32, release_ms: f32, sample_rate: f32) -> Self {
        let config = CompressorConfig {
            dynamics_type: DynamicsType::Limiter,
            detector_type: DetectorType::Peak,
            threshold_db,
            ratio: 100.0,
            attack_ms: 0.1,
            release_ms,
            knee_db: 0.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 1.0,
            auto_makeup: false,
            sidechain_filter: false,
            sidechain_freq_hz: 100.0,
            stereo_link: true,
            sample_rate,
        };
        Self::new(config, sample_rate)
    }

    /// Creates a noise gate
    pub fn create_gate(threshold_db: f32, attack_ms: f32, release_ms: f32, sample_rate: f32) -> Self {
        let config = CompressorConfig {
            dynamics_type: DynamicsType::Gate,
            detector_type: DetectorType::RMS,
            threshold_db,
            ratio: 100.0,
            attack_ms,
            release_ms,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 0.0,
            auto_makeup: false,
            sidechain_filter: false,
            sidechain_freq_hz: 100.0,
            stereo_link: true,
            sample_rate,
        };
        Self::new(config, sample_rate)
    }

    /// Creates an expander
    pub fn create_expander(threshold_db: f32, ratio: f32, attack_ms: f32, release_ms: f32, sample_rate: f32) -> Self {
        let config = CompressorConfig {
            dynamics_type: DynamicsType::Expander,
            detector_type: DetectorType::RMS,
            threshold_db,
            ratio,
            attack_ms,
            release_ms,
            knee_db: 3.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 0.0,
            auto_makeup: false,
            sidechain_filter: false,
            sidechain_freq_hz: 100.0,
            stereo_link: true,
            sample_rate,
        };
        Self::new(config, sample_rate)
    }

    // ============================================================================
    // GETTERS
    // ============================================================================

    pub fn config(&self) -> &CompressorConfig {
        &self.config
    }

    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }

    pub fn envelope(&self) -> f32 {
        self.envelope
    }
}

/// Compressor metrics for metering
#[derive(Debug, Clone, Copy, serde::Serialize)]
pub struct CompressorMetrics {
    pub peak_level_db: f32,
    pub rms_level_db: f32,
    pub gain_reduction_db: f32,
    pub envelope_db: f32,
}

impl Default for CompressorMetrics {
    fn default() -> Self {
        Self {
            peak_level_db: -144.0,
            rms_level_db: -144.0,
            gain_reduction_db: 0.0,
            envelope_db: -144.0,
        }
    }
}

/// Multiband compressor for frequency-selective dynamics
pub struct MultibandCompressor {
    bands: Vec<BandCompressor>,
    crossover_frequencies: Vec<f32>,
    sample_rate: f32,
}

struct BandCompressor {
    lowpass: Filter,
    highpass: Filter,
    compressor: Compressor,
}

impl MultibandCompressor {
    /// Creates a multiband compressor
    pub fn new(crossover_freqs: &[f32], sample_rate: f32) -> Self {
        let mut bands = Vec::new();

        for i in 0..=crossover_freqs.len() {
            let low_freq = if i == 0 { 20.0 } else { crossover_freqs[i - 1] };
            let high_freq = if i == crossover_freqs.len() { 20000.0 } else { crossover_freqs[i] };

            let mut lowpass = Filter::new(FilterType::LowPass, sample_rate);
            lowpass.set_frequency(high_freq);
            lowpass.set_q(0.707);

            let mut highpass = Filter::new(FilterType::HighPass, sample_rate);
            highpass.set_frequency(low_freq);
            highpass.set_q(0.707);

            let compressor = Compressor::new(CompressorConfig::default(), sample_rate);

            bands.push(BandCompressor { lowpass, highpass, compressor });
        }

        Self {
            bands,
            crossover_frequencies: crossover_freqs.to_vec(),
            sample_rate,
        }
    }

    /// Processes a single sample through all bands
    pub fn process_sample(&mut self, input: f32) -> f32 {
        let mut output = 0.0;

        for band in &mut self.bands {
            let mut band_signal = input;
            band.lowpass.process(&mut band_signal);
            band.highpass.process(&mut band_signal);
            output += band.compressor.process_sample(band_signal);
        }

        output
    }

    /// Processes a buffer of samples
    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        for sample in buffer {
            *sample = self.process_sample(*sample);
        }
    }

    /// Updates compressor config for a specific band
    pub fn update_band_config(&mut self, band_index: usize, config: CompressorConfig) {
        if band_index < self.bands.len() {
            self.bands[band_index].compressor.update_config(config);
        }
    }

    /// Resets all bands
    pub fn reset(&mut self) {
        for band in &mut self.bands {
            band.lowpass.reset();
            band.highpass.reset();
            band.compressor.reset();
        }
    }

    /// Returns crossover frequencies
    pub fn crossover_frequencies(&self) -> &[f32] {
        &self.crossover_frequencies
    }

    /// Returns sample rate
    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }
}
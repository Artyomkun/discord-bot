//! Эффекты дисторшена и овердрайва
//! Гитарампы, fuzz, overdrive, bitcrusher

use crate::audio::{AudioBuffer, AudioError, AudioFormat, SampleFormat};
use crate::dsp::filter::{Filter, FilterType};
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};

/// Тип дисторшена
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Encode, Decode)]
pub enum DistortionType {
    SoftClip,
    HardClip,
    Asymmetric,
    Tube,
    Fuzz,
    Overdrive,
    BitCrusher,
    WaveShaper,
    Foldback,
}

/// Конфигурация дисторшена
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct DistortionConfig {
    pub distortion_type: DistortionType,
    pub gain: f32,
    pub tone: f32,
    pub volume: f32,
    pub bias: f32,
    pub symmetry: f32,
    pub bit_depth: u8,
    pub sample_rate_reduction: f32,
    pub pre_filter_freq: f32,
    pub post_filter_freq: f32,
    pub wet: f32,
    pub dry: f32,
}

impl Default for DistortionConfig {
    fn default() -> Self {
        Self {
            distortion_type: DistortionType::SoftClip,
            gain: 10.0,
            tone: 0.5,
            volume: 0.7,
            bias: 0.0,
            symmetry: 0.5,
            bit_depth: 8,
            sample_rate_reduction: 4.0,
            pre_filter_freq: 1000.0,
            post_filter_freq: 5000.0,
            wet: 0.5,
            dry: 0.5,
        }
    }
}

/// Профессиональный дисторшен процессор
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Distortion<const N: usize> {
    config: DistortionConfig,
    format: AudioFormat,
    pre_filter: Filter,
    post_filter: Filter,
    wave_table: Vec<f32>,
    wave_table_size: usize,
    bit_crusher_accumulator: f32,
    bit_crusher_counter: f32,
    tube_state: [f32; 4],
    dc_blocker: [f32; 2],
    sample_rate: f32,
}

impl<const N: usize> Distortion<N> {
    pub fn new(config: DistortionConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;

        let mut pre_filter = Filter::new(FilterType::BandPass, sample_rate);
        pre_filter.set_frequency(config.pre_filter_freq);
        pre_filter.set_q(1.0);
        pre_filter.set_gain(config.gain * 0.5);
        pre_filter.update_coefficients();

        let mut post_filter = Filter::new(FilterType::LowShelf, sample_rate);
        post_filter.set_frequency(config.post_filter_freq);
        post_filter.set_q(0.707);
        post_filter.set_gain((config.tone - 0.5) * 12.0);
        post_filter.update_coefficients();

        let wave_table_size = 4096;
        let wave_table = Self::create_wave_table(&config, wave_table_size);

        Self {
            config,
            format,
            pre_filter,
            post_filter,
            wave_table,
            wave_table_size,
            bit_crusher_accumulator: 0.0,
            bit_crusher_counter: 0.0,
            tube_state: [0.0; 4],
            dc_blocker: [0.0; 2],
            sample_rate,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: DistortionConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid distortion config: {}", e)))?;
        Ok(Self::new(config, format))
    }

    fn create_wave_table(config: &DistortionConfig, size: usize) -> Vec<f32> {
        let mut table = vec![0.0; size];

        table.iter_mut().enumerate().take(size).for_each(|(i, entry)| {
            let x = (i as f32 / (size - 1) as f32) * 2.0 - 1.0;

            let y = match config.distortion_type {
                DistortionType::SoftClip => {
                    let threshold = 0.5;
                    if x.abs() > threshold {
                        let sign = x.signum();
                        sign * (threshold + (1.0 - threshold) * (1.0 - (-(x.abs() - threshold) * 3.0).exp()))
                    } else {
                        x
                    }
                }
                DistortionType::HardClip => {
                    let threshold = 0.7;
                    x.clamp(-threshold, threshold) / threshold
                }
                DistortionType::Asymmetric => {
                    let positive_threshold = 0.8;
                    let negative_threshold = 0.6;
                    if x > positive_threshold {
                        positive_threshold
                    } else if x < -negative_threshold {
                        -negative_threshold
                    } else {
                        x
                    }
                }
                DistortionType::Tube => {
                    let bias = config.bias * 0.3;
                    let x_biased = x + bias;
                    let v = x_biased * config.gain * 0.1;
                    v / (1.0 + v.abs()).powf(0.5)
                }
                DistortionType::Fuzz => {
                    let v = x * config.gain;
                    v.tanh() * (1.0 + config.symmetry * v.abs())
                }
                DistortionType::Overdrive => {
                    let v = x * config.gain * 0.3;
                    (v * (27.0 + v * v)) / (27.0 + 9.0 * v * v)
                }
                DistortionType::WaveShaper => {
                    let a = 0.5;
                    let b = 0.5;
                    let c = 0.5;
                    a * x + b * x.powi(3) + c * x.powi(5)
                }
                DistortionType::Foldback => {
                    let threshold = 0.7;
                    if x.abs() > threshold {
                        let folded = (x.abs() - threshold).abs();
                        x.signum() * folded
                    } else {
                        x
                    }
                }
                _ => x,
            };

            *entry = y * config.volume;
        });
        table
    }

    fn apply_distortion(&self, sample: f32) -> f32 {
        if let DistortionType::BitCrusher = self.config.distortion_type {
            return sample; // BitCrusher обрабатывается отдельно
        }
        
        let normalized = (sample + 1.0) * 0.5;
        let idx = (normalized * (self.wave_table_size - 1) as f32).clamp(0.0, (self.wave_table_size - 1) as f32);
        let idx0 = idx.floor() as usize;
        let idx1 = (idx0 + 1).min(self.wave_table_size - 1);
        let frac = idx - idx0 as f32;
        
        self.wave_table[idx0] * (1.0 - frac) + self.wave_table[idx1] * frac
    }

    fn apply_bit_crusher(&mut self, sample: f32) -> f32 {
        if self.config.distortion_type != DistortionType::BitCrusher {
            return sample;
        }

        let reduction = self.config.sample_rate_reduction.max(1.0);
        let step = self.sample_rate / reduction;

        self.bit_crusher_counter += 1.0;

        if self.bit_crusher_counter >= step {
            self.bit_crusher_counter = 0.0;
            self.bit_crusher_accumulator = sample;
        }

        let bits = self.config.bit_depth as f32;
        let levels = 2.0f32.powf(bits);
        let quantized = (self.bit_crusher_accumulator * levels).round() / levels;
        quantized.clamp(-1.0, 1.0)
    }

    fn apply_tube_simulation(&self, sample: f32) -> f32 {
        if self.config.distortion_type != DistortionType::Tube {
            return sample;
        }

        let v = sample * self.config.gain * 0.2;
        let positive_clip = 0.8;
        let negative_clip = 0.6;

        let mut result = v;
        if result > positive_clip {
            result = positive_clip;
        } else if result < -negative_clip {
            result = -negative_clip;
        }

        result * self.config.volume
    }

    fn apply_dc_block(&mut self, sample: f32) -> f32 {
        let r = 0.995;
        let output = sample - self.dc_blocker[0] + r * self.dc_blocker[1];
        self.dc_blocker[0] = sample;
        self.dc_blocker[1] = output;
        output
    }

    fn update_wave_table(&mut self) {
        self.wave_table = Self::create_wave_table(&self.config, self.wave_table_size);
    }
    
    pub fn format(&self) -> &AudioFormat {
        &self.format
    }
}

impl<const N: usize> AudioEffect<N> for Distortion<N> {
    fn get_name(&self) -> String {
        "distortion".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError> {
        let channels = buffer.channels();
        
        for ch in 0..channels {
            if let Some(channel) = buffer.get_channel_slice_mut(ch) {
                for sample in channel {
                    let input = *sample;
                    
                    // Предварительное усиление
                    let mut processed = input * self.config.gain;
                    
                    // Pre-filter
                    self.pre_filter.process(&mut processed);
                    
                    // Применение дисторшена
                    processed = match self.config.distortion_type {
                        DistortionType::BitCrusher => self.apply_bit_crusher(processed),
                        DistortionType::Tube => self.apply_tube_simulation(processed),
                        _ => self.apply_distortion(processed),
                    };
                    
                    // Post-filter
                    self.post_filter.process(&mut processed);
                    
                    // DC blocker
                    processed = self.apply_dc_block(processed);
                    
                    // Mix и выход
                    *sample = (input * self.config.dry + processed * self.config.wet).clamp(-1.0, 1.0);
                }
            }
        }
        
        Ok(())
    }

    fn reset(&mut self) {
        self.pre_filter.reset();
        self.post_filter.reset();
        self.bit_crusher_accumulator = 0.0;
        self.bit_crusher_counter = 0.0;
        self.tube_state.fill(0.0);
        self.dc_blocker.fill(0.0);
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: DistortionConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid distortion config: {}", e)))?;

        self.config = new_config;
        
        self.pre_filter.set_frequency(self.config.pre_filter_freq);
        self.pre_filter.set_gain(self.config.gain * 0.5);
        self.pre_filter.update_coefficients();
        
        self.post_filter.set_frequency(self.config.post_filter_freq);
        self.post_filter.set_gain((self.config.tone - 0.5) * 12.0);
        self.post_filter.update_coefficients();
        
        self.update_wave_table();

        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        0
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = &configs.distortion_params {
            let new_config: DistortionConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid distortion config: {}", e))?;
            self.config = new_config;
            self.update_wave_table();
            Ok(())
        } else {
            Err("No distortion parameters in config".to_string())
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }
}


//! Эффект задержки (delay)
//! Многоголосная задержка с обратной связью, фильтрацией и модуляцией

use crate::audio::{AudioBuffer, AudioError, AudioFormat, SampleFormat};
use crate::dsp::compressor::CompressorMetrics;
use crate::dsp::filter::{Filter, FilterType};
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

/// Тип задержки
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Encode, Decode)]
pub enum DelayType {
    Mono,
    Stereo,
    PingPong,
    MultiTap,
    Tape,
    Digital,
}

/// Один тап (голос) задержки
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct DelayTap {
    pub delay_time_ms: f32,    // ms, 10-5000
    pub gain: f32,             // 0.0-1.0
    pub pan: f32,              // -1.0..1.0
    pub feedback: f32,         // 0.0-0.99
    pub enabled: bool,
}

impl Default for DelayTap {
    fn default() -> Self {
        Self {
            delay_time_ms: 250.0,
            gain: 0.5,
            pan: 0.0,
            feedback: 0.5,
            enabled: true,
        }
    }
}

/// Конфигурация эффекта задержки
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct DelayConfig {
    pub delay_type: DelayType,
    pub taps: Vec<DelayTap>,
    pub modulation_rate_hz: f32,
    pub modulation_depth: f32,
    pub low_cut_hz: f32,
    pub high_cut_hz: f32,
    pub tape_saturation: f32,
    pub wow_flutter: f32,
    pub wet: f32,
    pub dry: f32,
}

impl Default for DelayConfig {
    fn default() -> Self {
        Self {
            delay_type: DelayType::Stereo,
            taps: vec![DelayTap::default()],
            modulation_rate_hz: 0.5,
            modulation_depth: 0.1,
            low_cut_hz: 100.0,
            high_cut_hz: 10000.0,
            tape_saturation: 0.3,
            wow_flutter: 0.2,
            wet: 0.3,
            dry: 0.7,
        }
    }
}

/// Многофункциональный эффект задержки
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Delay<const N: usize> {
    config: DelayConfig,
    format: AudioFormat,

    // Буферы задержки для каждого канала
    delay_buffers: Vec<Vec<Vec<f32>>>,
    write_positions: Vec<Vec<usize>>,
    read_positions: Vec<Vec<f32>>,

    // Модуляция
    lfo_phase: Vec<f32>,
    lfo_increment: f32,

    // Фильтры для каждого тапа
    low_cut_filters: Vec<Vec<Filter>>,
    high_cut_filters: Vec<Vec<Filter>>,

    // Feedback buffers
    feedback_buffers: Vec<Vec<f32>>,

    // Ping-pong state
    ping_pong_state: bool,
}

impl<const N: usize> Delay<N> {
    pub fn new(config: DelayConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;

        let max_delay_ms = 5000.0;
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;
        
        let mut delay_buffers = Vec::with_capacity(config.taps.len());
        let mut write_positions = Vec::with_capacity(config.taps.len());
        let mut read_positions = Vec::with_capacity(config.taps.len());
        let mut low_cut_filters = Vec::with_capacity(config.taps.len());
        let mut high_cut_filters = Vec::with_capacity(config.taps.len());
        let mut feedback_buffers = Vec::with_capacity(config.taps.len());

        for tap in &config.taps {
            let mut tap_buffers = Vec::with_capacity(channels);
            let mut tap_write_pos = Vec::with_capacity(channels);
            let mut tap_read_pos = Vec::with_capacity(channels);
            let mut tap_low_cut = Vec::with_capacity(channels);
            let mut tap_high_cut = Vec::with_capacity(channels);
            let mut tap_feedback = Vec::with_capacity(channels);

            for _ch in 0..channels {
                tap_buffers.push(vec![0.0; max_delay_samples]);
                tap_write_pos.push(0);

                let delay_samples = (tap.delay_time_ms * 0.001 * sample_rate) as usize;
                let read_pos = if delay_samples > 0 && delay_samples < max_delay_samples {
                    (max_delay_samples - delay_samples) % max_delay_samples
                } else {
                    0
                };
                tap_read_pos.push(read_pos as f32);

                let mut low_filter = Filter::new(FilterType::HighPass, sample_rate);
                low_filter.set_frequency(config.low_cut_hz);
                low_filter.set_q(0.707);
                low_filter.update_coefficients();
                tap_low_cut.push(low_filter);

                let mut high_filter = Filter::new(FilterType::LowPass, sample_rate);
                high_filter.set_frequency(config.high_cut_hz);
                high_filter.set_q(0.707);
                high_filter.update_coefficients();
                tap_high_cut.push(high_filter);

                tap_feedback.push(0.0);
            }

            delay_buffers.push(tap_buffers);
            write_positions.push(tap_write_pos);
            read_positions.push(tap_read_pos);
            low_cut_filters.push(tap_low_cut);
            high_cut_filters.push(tap_high_cut);
            feedback_buffers.push(tap_feedback);
        }

        let lfo_phase = vec![0.0; config.taps.len()];
        let lfo_increment = (2.0 * PI * config.modulation_rate_hz) / sample_rate;

        Self {
            config,
            format,
            delay_buffers,
            write_positions,
            read_positions,
            lfo_phase,
            lfo_increment,
            low_cut_filters,
            high_cut_filters,
            feedback_buffers,
            ping_pong_state: false,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: DelayConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid delay config: {}", e)))?;
        Ok(Self::new(config, format))
    }

    

    fn apply_tape_saturation(&self, sample: f32) -> f32 {
        if self.config.tape_saturation == 0.0 {
            return sample;
        }
        let threshold = 0.8;
        let saturation = self.config.tape_saturation;
        if sample.abs() > threshold {
            let sign = sample.signum();
            let overshoot = sample.abs() - threshold;
            let saturated = threshold + (1.0 - threshold) * (1.0 - (-overshoot * saturation).exp());
            sign * saturated
        } else {
            sample
        }
    }

    fn read_interpolated(&self, buffer: &[f32], position: f32) -> f32 {
        let buffer_len = buffer.len() as f32;
        let normalized_pos = if position < 0.0 { position + buffer_len } else { position };
        let index = (normalized_pos as usize) % buffer.len();
        let fraction = normalized_pos - index as f32;
        let next_index = (index + 1) % buffer.len();
        buffer[index] * (1.0 - fraction) + buffer[next_index] * fraction
    }

    fn process_tap(&mut self, tap_idx: usize, channel: usize, input: f32) -> f32 {
        let tap = &self.config.taps[tap_idx];
        if !tap.enabled {
            return 0.0;
        }
        
        let sample_rate = self.format.sample_rate_hz() as f32;
        let buffer_len = self.delay_buffers[tap_idx][channel].len();
        let write_pos = self.write_positions[tap_idx][channel];
        let current_read_pos = self.read_positions[tap_idx][channel];
        let current_feedback = self.feedback_buffers[tap_idx][channel];
        
        // Фильтрация feedback
        let mut filtered = current_feedback;
        self.low_cut_filters[tap_idx][channel].process(&mut filtered);
        self.high_cut_filters[tap_idx][channel].process(&mut filtered);
        
        // Применение satur
        let saturated_feedback = self.apply_tape_saturation(filtered);
        
        // Запись в буфер
        let mix = input + saturated_feedback * tap.feedback;
        self.delay_buffers[tap_idx][channel][write_pos] = mix;
        self.write_positions[tap_idx][channel] = (write_pos + 1) % buffer_len;
        
        // Модуляция
        let modulation = self.lfo_phase[tap_idx].sin() * self.config.modulation_depth;
        let base_delay_samples = tap.delay_time_ms * 0.001 * sample_rate;
        let modulated_delay = base_delay_samples * (1.0 + modulation);
        
        // Чтение с интерполяцией
        let target_read_pos = (write_pos as f32 - modulated_delay + buffer_len as f32) % buffer_len as f32;
        let alpha = 0.01;
        let new_read_pos = current_read_pos * (1.0 - alpha) + target_read_pos * alpha;
        let output = self.read_interpolated(&self.delay_buffers[tap_idx][channel], new_read_pos);
        
        self.read_positions[tap_idx][channel] = new_read_pos;
        self.feedback_buffers[tap_idx][channel] = output * tap.gain;
        
        output * tap.gain
    }

    fn update_lfo(&mut self) {
        for phase in &mut self.lfo_phase {
            *phase += self.lfo_increment;
            if *phase > 2.0 * PI {
                *phase -= 2.0 * PI;
            }
        }
    }
    
    pub fn format(&self) -> &AudioFormat {
        &self.format
    }
}

impl<const N: usize> AudioEffect<N> for Delay<N> {
    fn get_name(&self) -> String {
        "delay".to_string()
    }
    fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        let channels = buffer.channels();
        let sample_format = buffer.format().sample_format();
        let _bytes_per_sample = sample_format.bytes_per_sample();
        
        match self.config.delay_type {
            DelayType::Stereo => {
                if channels >= 2 {
                        if let Some((left, right)) = buffer.get_two_channel_slices_mut(0, 1) {
                        for i in 0..left.len().min(right.len()) {
                            let left_input = left[i];
                            let right_input = right[i];
                            
                            let left_delayed = self.process_tap(0, 0, left_input);
                            let right_delayed = self.process_tap(0, 1, right_input);
                            
                            left[i] = left_input * self.config.dry + left_delayed * self.config.wet;
                            right[i] = right_input * self.config.dry + right_delayed * self.config.wet;
                            
                            left[i] = left[i].clamp(-1.0, 1.0);
                            right[i] = right[i].clamp(-1.0, 1.0);
                        }
                        self.update_lfo();
                    }
                }
            }
            DelayType::Mono => {
                if let Some(channel) = buffer.get_channel_slice_mut(0) {
                    for sample in channel {
                        let input = *sample;
                        let delayed = self.process_tap(0, 0, input);
                        *sample = input * self.config.dry + delayed * self.config.wet;
                        *sample = sample.clamp(-1.0, 1.0);
                    }
                    self.update_lfo();
                }
            }
            DelayType::PingPong => {
                if channels >= 2 {
                    if let Some((left, right)) = buffer.get_two_channel_slices_mut(0, 1) {
                        for i in 0..left.len().min(right.len()) {
                            let left_input = left[i];
                            let right_input = right[i];
                            
                            let (left_delayed, right_delayed) = if self.ping_pong_state {
                                let l = self.process_tap(0, 0, left_input);
                                let r = self.process_tap(0, 1, right_input) * 0.7;
                                self.ping_pong_state = false;
                                (l, r)
                            } else {
                                let l = self.process_tap(0, 0, left_input) * 0.7;
                                let r = self.process_tap(0, 1, right_input);
                                self.ping_pong_state = true;
                                (l, r)
                            };
                            
                            left[i] = left_input * self.config.dry + left_delayed * self.config.wet;
                            right[i] = right_input * self.config.dry + right_delayed * self.config.wet;
                            
                            left[i] = left[i].clamp(-1.0, 1.0);
                            right[i] = right[i].clamp(-1.0, 1.0);
                        }
                        self.update_lfo();
                    }
                }
            }
            DelayType::MultiTap => {
                if let Some(channel) = buffer.get_channel_slice_mut(0) {
                    for sample in channel {
                        let input = *sample;
                        let mut delayed_sum = 0.0;
                        for tap_idx in 0..self.config.taps.len() {
                            if self.config.taps[tap_idx].enabled {
                                delayed_sum += self.process_tap(tap_idx, 0, input);
                            }
                        }
                        *sample = input * self.config.dry + delayed_sum * self.config.wet;
                        *sample = sample.clamp(-1.0, 1.0);
                    }
                    self.update_lfo();
                }
            }
            DelayType::Tape => {
                if channels >= 2 {
                    if let Some((left, right)) = buffer.get_two_channel_slices_mut(0, 1) {
                        for i in 0..left.len().min(right.len()) {
                            let left_input = self.apply_tape_saturation(left[i]);
                            let right_input = self.apply_tape_saturation(right[i]);
                            
                            let left_delayed = self.process_tap(0, 0, left_input);
                            let right_delayed = self.process_tap(0, 1, right_input);
                            
                            left[i] = left[i] * self.config.dry + left_delayed * self.config.wet;
                            right[i] = right[i] * self.config.dry + right_delayed * self.config.wet;
                            
                            left[i] = left[i].clamp(-1.0, 1.0);
                            right[i] = right[i].clamp(-1.0, 1.0);
                        }
                        self.update_lfo();
                    }
                }
            }
            DelayType::Digital => {
                if let Some(channel) = buffer.get_channel_slice_mut(0) {
                    for sample in channel {
                        let input = *sample;
                        let delayed = self.process_tap(0, 0, input);
                        *sample = input * self.config.dry + delayed * self.config.wet;
                        *sample = sample.clamp(-1.0, 1.0);
                    }
                    self.update_lfo();
                }
            }
        }
        
        Ok(())
    }

    fn reset(&mut self) {
        for tap_buffers in &mut self.delay_buffers {
            for buffer in tap_buffers {
                buffer.fill(0.0);
            }
        }
        for tap_positions in &mut self.write_positions {
            for pos in tap_positions {
                *pos = 0;
            }
        }
        for tap_read_pos in &mut self.read_positions {
            for pos in tap_read_pos {
                *pos = 0.0;
            }
        }
        for tap_feedback in &mut self.feedback_buffers {
            for feedback in tap_feedback {
                *feedback = 0.0;
            }
        }
        self.lfo_phase.fill(0.0);
        self.ping_pong_state = false;
        for tap_filters in &mut self.low_cut_filters {
            for filter in tap_filters {
                filter.reset();
            }
        }
        for tap_filters in &mut self.high_cut_filters {
            for filter in tap_filters {
                filter.reset();
            }
        }
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: DelayConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid delay config: {}", e)))?;
        *self = Self::new(new_config, self.format.clone());
        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        self.config.taps.iter()
            .map(|tap| (tap.delay_time_ms * 0.001 * self.format.sample_rate_hz() as f32) as usize)
            .max()
            .unwrap_or(0)
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = &configs.delay_params {
            let new_config: DelayConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid delay config: {}", e))?;
            self.config = new_config;
            Ok(())
        } else {
            Err("No delay parameters in config".to_string())
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }
}


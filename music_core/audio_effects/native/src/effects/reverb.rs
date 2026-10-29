//! Алгоритмический ревербератор
//! Пластинчатый, зальный, комнатный реверб с настройкой

use crate::audio::{AudioBuffer, AudioError, AudioFormat, SampleFormat};
use crate::dsp::filter::{Filter, FilterType};
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

/// Тип реверберации
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Encode, Decode)]
pub enum ReverbType {
    Room,
    Hall,
    Plate,
    Spring,
    Cathedral,
    Custom,
}

/// Конфигурация ревербератора
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct ReverbConfig {
    pub reverb_type: ReverbType,
    pub decay_time: f32,
    pub pre_delay: f32,
    pub diffusion: f32,
    pub density: f32,
    pub early_reflections: f32,
    pub late_reflections: f32,
    pub room_size: f32,
    pub damping: f32,
    pub modulation: f32,
    pub wet: f32,
    pub dry: f32,
}

impl Default for ReverbConfig {
    fn default() -> Self {
        Self {
            reverb_type: ReverbType::Hall,
            decay_time: 2.5,
            pre_delay: 20.0,
            diffusion: 0.7,
            density: 0.8,
            early_reflections: 0.6,
            late_reflections: 0.8,
            room_size: 0.7,
            damping: 0.5,
            modulation: 0.3,
            wet: 0.3,
            dry: 0.7,
        }
    }
}

/// Комбинированный ревербератор на основе FDN (Feedback Delay Network)
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Reverb<const N: usize> {
    config: ReverbConfig,
    format: AudioFormat,

    // FDN delay lines (8 каналов)
    delay_lines: [Vec<f32>; 8],
    delay_positions: [usize; 8],
    delay_lengths: [usize; 8],

    // Low-pass фильтры для damping
    damping_filters: [Filter; 8],

    // Early reflections
    early_delays: Vec<Vec<f32>>,
    early_positions: Vec<usize>,

    // Modulation (chorus-like effect)
    modulation_lfo: Vec<f32>,
    lfo_position: usize,
    lfo_rate: f32,

    // Pre-delay buffer
    pre_delay_buffer: Vec<Vec<f32>>,
    pre_delay_positions: Vec<usize>,
    pre_delay_lengths: Vec<usize>,

    // Кэшированные буферы для избежания аллокаций
    cached_left: Vec<f32>,
    cached_right: Vec<f32>,
    
    // Предвычисленный decay gain
    decay_gain: f32,
}

impl<const N: usize> Reverb<N> {
    /// Создание нового ревербератора
    pub fn new(config: ReverbConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;

        let (delay_lengths, lfo_rate) = match config.reverb_type {
            ReverbType::Room => {
                let base = (0.03 * sample_rate) as usize;
                (
                    [
                        base,
                        base * 97 / 100,
                        base * 91 / 100,
                        base * 89 / 100,
                        base * 83 / 100,
                        base * 79 / 100,
                        base * 73 / 100,
                        base * 71 / 100,
                    ],
                    0.5,
                )
            }
            ReverbType::Hall => {
                let base = (0.1 * sample_rate) as usize;
                (
                    [
                        base,
                        base * 97 / 100,
                        base * 91 / 100,
                        base * 89 / 100,
                        base * 83 / 100,
                        base * 79 / 100,
                        base * 73 / 100,
                        base * 71 / 100,
                    ],
                    0.3,
                )
            }
            ReverbType::Plate => {
                let base = (0.05 * sample_rate) as usize;
                (
                    [
                        base,
                        base * 92 / 100,
                        base * 88 / 100,
                        base * 84 / 100,
                        base * 80 / 100,
                        base * 76 / 100,
                        base * 72 / 100,
                        base * 68 / 100,
                    ],
                    0.7,
                )
            }
            ReverbType::Spring => {
                let base = (0.02 * sample_rate) as usize;
                (
                    [
                        base,
                        base * 85 / 100,
                        base * 82 / 100,
                        base * 79 / 100,
                        base * 76 / 100,
                        base * 73 / 100,
                        base * 70 / 100,
                        base * 67 / 100,
                    ],
                    1.2,
                )
            }
            ReverbType::Cathedral => {
                let base = (0.2 * sample_rate) as usize;
                (
                    [
                        base,
                        base * 98 / 100,
                        base * 96 / 100,
                        base * 94 / 100,
                        base * 92 / 100,
                        base * 90 / 100,
                        base * 88 / 100,
                        base * 86 / 100,
                    ],
                    0.2,
                )
            }
            ReverbType::Custom => {
                let base = (config.decay_time * 0.05 * sample_rate) as usize;
                (
                    [
                        base,
                        (base as f32 * 0.97) as usize,
                        (base as f32 * 0.91) as usize,
                        (base as f32 * 0.89) as usize,
                        (base as f32 * 0.83) as usize,
                        (base as f32 * 0.79) as usize,
                        (base as f32 * 0.73) as usize,
                        (base as f32 * 0.71) as usize,
                    ],
                    config.modulation,
                )
            }
        };

        let create_delay_line = |len: usize| {
            if len == 0 { vec![0.0; 1] } else { vec![0.0; len] }
        };

        let delay_lines = [
            create_delay_line(delay_lengths[0]),
            create_delay_line(delay_lengths[1]),
            create_delay_line(delay_lengths[2]),
            create_delay_line(delay_lengths[3]),
            create_delay_line(delay_lengths[4]),
            create_delay_line(delay_lengths[5]),
            create_delay_line(delay_lengths[6]),
            create_delay_line(delay_lengths[7]),
        ];

        let mut damping_filters = [
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
            Filter::new(FilterType::LowPass, sample_rate),
        ];

        let damping_freq = 6000.0 * (1.0 - config.damping);
        for filter in &mut damping_filters {
            filter.set_frequency(damping_freq);
            filter.set_q(0.707);
            filter.update_coefficients();
        }

        let early_reflection_count = 8;
        let mut early_delays = Vec::with_capacity(early_reflection_count);
        let mut early_positions = Vec::with_capacity(early_reflection_count);

        for i in 0..early_reflection_count {
            let length = ((i as f32 * 0.01 + 0.005) * sample_rate) as usize;
            let len = if length == 0 { 1 } else { length };
            early_delays.push(vec![0.0; len]);
            early_positions.push(0);
        }

        let lfo_length = if lfo_rate > 0.0 {
            (sample_rate / lfo_rate) as usize
        } else {
            1
        };
        let mut modulation_lfo = vec![0.0; lfo_length.max(1)];

        for i in 0..modulation_lfo.len() {
            modulation_lfo[i] = (2.0 * PI * i as f32 / modulation_lfo.len() as f32).sin() * 0.5;
        }

        let pre_delay_length = ((config.pre_delay / 1000.0) * sample_rate) as usize;
        let pre_delay_len = if pre_delay_length == 0 { 1 } else { pre_delay_length };
        let pre_delay_buffer = vec![vec![0.0; pre_delay_len]; channels];
        let pre_delay_positions = vec![0; channels];
        let pre_delay_lengths = vec![pre_delay_len; channels];

        let decay_gain = (-3.0 / (config.decay_time * sample_rate)).exp();

        Self {
            config,
            format,
            delay_lines,
            delay_positions: [0; 8],
            delay_lengths,
            damping_filters,
            early_delays,
            early_positions,
            modulation_lfo,
            lfo_position: 0,
            lfo_rate,
            pre_delay_buffer,
            pre_delay_positions,
            pre_delay_lengths,
            cached_left: Vec::with_capacity(N),
            cached_right: Vec::with_capacity(N),
            decay_gain,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: ReverbConfig = serde_json::from_value(params.clone()).map_err(|e| {
            AudioError::EffectConfig(format!("Invalid reverb config: {}", e))
        })?;
        Ok(Self::new(config, format))
    }

    

    fn process_fdn(&mut self, input: [f32; 4]) -> [f32; 4] {
        let mut outputs = [0.0; 4];

        let feedback_matrix = [
            [0.5, 0.5, 0.5, 0.5],
            [0.5, -0.5, 0.5, -0.5],
            [0.5, 0.5, -0.5, -0.5],
            [0.5, -0.5, -0.5, 0.5],
        ];

        for line in &self.delay_lines {
            if line.is_empty() {
                return [0.0; 4];
            }
        }

        let mut delay_outputs = [0.0; 8];
        delay_outputs.iter_mut().enumerate().for_each(|(i, output)| {
            let pos = self.delay_positions[i];
            if pos < self.delay_lines[i].len() {
                *output = self.delay_lines[i][pos];
            }
        });

        delay_outputs.iter_mut().enumerate().for_each(|(i, output)| {
            let mut sample = *output;
            self.damping_filters[i].process(&mut sample);
            *output = sample * self.config.density;
        });

        let modulation_amount = self.config.modulation * 0.01;
        let mod_value = if !self.modulation_lfo.is_empty() {
            self.modulation_lfo[self.lfo_position % self.modulation_lfo.len()] * modulation_amount
        } else {
            0.0
        };

        for i in 0..4 {
            let mut sum = input[i] * (1.0 - self.config.diffusion);

            for j in 0..4 {
                sum += delay_outputs[j * 2] * feedback_matrix[i][j] * self.config.diffusion;
            }

            let idx1 = i * 2;
            let idx2 = i * 2 + 1;

            if idx1 >= self.delay_lines.len() || idx2 >= self.delay_lines.len() {
                continue;
            }

            let len1 = self.delay_lines[idx1].len();
            let len2 = self.delay_lines[idx2].len();

            if len1 == 0 || len2 == 0 {
                continue;
            }

            let mod_length = ((self.delay_lengths[idx1] as f32 * (1.0 + mod_value.min(0.5))) as usize) % len1;
            let pos1 = (self.delay_positions[idx1] + mod_length) % len1;
            let pos2 = (pos1 + self.delay_lengths[idx2] / 2) % len2;

            self.delay_lines[idx1][pos1] = sum * 0.7;
            self.delay_lines[idx2][pos2] = sum * 0.7;

            outputs[i] = delay_outputs[idx1] + delay_outputs[idx2];
        }

        for i in 0..8 {
            let len = self.delay_lines[i].len();
            if len > 0 {
                self.delay_positions[i] = (self.delay_positions[i] + 1) % len;
            }
        }

        if !self.modulation_lfo.is_empty() {
            self.lfo_position = (self.lfo_position + 1) % self.modulation_lfo.len();
        }

        outputs
    }

    fn process_early_reflections(&mut self, input_left: f32, input_right: f32) -> (f32, f32) {
        let mut left_out = 0.0;
        let mut right_out = 0.0;

        while self.early_positions.len() < self.early_delays.len() {
            self.early_positions.push(0);
        }

        for i in 0..self.early_delays.len() {
            let buffer = &mut self.early_delays[i];
            if buffer.is_empty() {
                continue;
            }
            
            let pos = self.early_positions[i] % buffer.len();

            let pan = if i % 2 == 0 { 0.7 } else { -0.7 };
            let left_gain = 0.5 + pan * 0.5;
            let right_gain = 0.5 - pan * 0.5;

            let input = input_left * left_gain + input_right * right_gain;
            let output = buffer[pos] * self.config.early_reflections;
            buffer[pos] = input * 0.3;

            left_out += output * left_gain;
            right_out += output * right_gain;

            self.early_positions[i] = (pos + 1) % buffer.len();
        }

        (left_out, right_out)
    }

    fn apply_pre_delay(&mut self, channel: usize, sample: f32) -> f32 {
        if channel >= self.pre_delay_buffer.len() {
            return sample;
        }
        
        let buffer = &mut self.pre_delay_buffer[channel];
        if buffer.is_empty() {
            return sample;
        }
        
        let pos = self.pre_delay_positions[channel];
        let output = buffer[pos];
        
        buffer[pos] = sample;
        self.pre_delay_positions[channel] = (pos + 1) % buffer.len();
        
        output
    }

    fn channel_to_f32(buffer: &AudioBuffer<{ N }>, channel: usize) -> Result<Vec<f32>, AudioError> {
        if channel >= buffer.channels() {
            return Err(AudioError::InvalidParameter(format!(
                "Channel {} out of range (0-{})",
                channel,
                buffer.channels() - 1
            )));
        }

        let sample_format = buffer.format().sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = buffer.channels();
        let bytes_per_frame = bytes_per_sample * channels;
        let data = buffer.as_slice();
        
        let frames = data.len() / bytes_per_frame;
        let mut result = Vec::with_capacity(frames);

        for i in 0..frames {
            let frame_start = i * bytes_per_frame;
            let sample_start = frame_start + channel * bytes_per_sample;

            if sample_start + bytes_per_sample <= data.len() {
                let bytes = &data[sample_start..sample_start + bytes_per_sample];
                let sample = sample_format.normalize_to_f32(bytes);
                result.push(sample);
            }
        }

        Ok(result)
    }

    fn write_channel_from_f32(
        buffer: &mut AudioBuffer<{ N }>,
        channel: usize,
        float_data: &[f32],
    ) -> Result<(), AudioError> {
        if channel >= buffer.channels() {
            return Err(AudioError::InvalidParameter(format!(
                "Channel {} out of range (0-{})",
                channel,
                buffer.channels() - 1
            )));
        }

        let sample_format = buffer.format().sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = buffer.channels();
        let bytes_per_frame = bytes_per_sample * channels;
        let data = buffer.as_mut_slice();
        
        let frames = data.len() / bytes_per_frame;
        let samples = frames.min(float_data.len());

        for (i, _) in float_data.iter().enumerate().take(samples) {
            let frame_start = i * bytes_per_frame;
            let sample_start = frame_start + channel * bytes_per_sample;

            if sample_start + bytes_per_sample <= data.len() {
                let bytes = sample_format.from_f32(float_data[i]);
                for (j, &byte) in bytes.iter().enumerate() {
                    if sample_start + j < data.len() {
                        data[sample_start + j] = byte;
                    }
                }
            }
        }

        Ok(())
    }
}

impl<const N: usize> AudioEffect<N> for Reverb<N> {
    fn get_name(&self) -> String {
        "reverb".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError> {
        let channels = buffer.channels();

        if channels != 2 {
            return Err(AudioError::InvalidParameter(
                "Reverb currently supports only stereo audio".to_string(),
            ));
        }

        let left_data = Self::channel_to_f32(buffer, 0)?;
        let right_data = Self::channel_to_f32(buffer, 1)?;
        
        self.cached_left.clear();
        self.cached_right.clear();
        self.cached_left.extend(left_data.clone());
        self.cached_right.extend(right_data.clone());

        let samples = self.cached_left.len().min(self.cached_right.len());

        for (i, _) in left_data.iter().enumerate().take(samples) {
            let left_input = self.cached_left[i];
            let right_input = self.cached_right[i];

            let left_pre = self.apply_pre_delay(0, left_input);
            let right_pre = self.apply_pre_delay(1, right_input);

            let (early_left, early_right) = self.process_early_reflections(left_pre, right_pre);

            let fdn_input = [left_pre, right_pre, left_pre * 0.7, right_pre * 0.7];
            let fdn_output = self.process_fdn(fdn_input);

            let late_left = (fdn_output[0] + fdn_output[2] * 0.5) * self.decay_gain * self.config.late_reflections;
            let late_right = (fdn_output[1] + fdn_output[3] * 0.5) * self.decay_gain * self.config.late_reflections;

            let wet = self.config.wet;
            let dry = self.config.dry;
            let room_attenuation = 1.0 - self.config.room_size * 0.3;
            
            self.cached_left[i] = (left_input * dry + (early_left + late_left) * wet) * room_attenuation;
            self.cached_left[i] = self.cached_left[i].clamp(-1.0, 1.0);
            
            self.cached_right[i] = (right_input * dry + (early_right + late_right) * wet) * room_attenuation;
            self.cached_right[i] = self.cached_right[i].clamp(-1.0, 1.0);
        }

        Self::write_channel_from_f32(buffer, 0, &self.cached_left)?;
        Self::write_channel_from_f32(buffer, 1, &self.cached_right)?;

        Ok(())
    }

    fn reset(&mut self) {
        for line in &mut self.delay_lines {
            line.fill(0.0);
        }

        self.delay_positions = [0; 8];

        for buffer in &mut self.early_delays {
            buffer.fill(0.0);
        }
        
        while self.early_positions.len() < self.early_delays.len() {
            self.early_positions.push(0);
        }
        for pos in &mut self.early_positions {
            *pos = 0;
        }

        for buffer in &mut self.pre_delay_buffer {
            buffer.fill(0.0);
        }
        
        for pos in &mut self.pre_delay_positions {
            *pos = 0;
        }

        self.lfo_position = 0;

        for filter in &mut self.damping_filters {
            filter.reset();
        }
        
        self.cached_left.clear();
        self.cached_right.clear();
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: ReverbConfig = serde_json::from_value(params).map_err(|e| {
            AudioError::EffectConfig(format!("Invalid reverb config: {}", e))
        })?;

        self.config = new_config;

        let damping_freq = 6000.0 * (1.0 - self.config.damping);
        for filter in &mut self.damping_filters {
            filter.set_frequency(damping_freq);
            filter.update_coefficients();
        }

        let sample_rate = self.format.sample_rate_hz() as f32;
        self.decay_gain = (-3.0 / (self.config.decay_time * sample_rate)).exp();

        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or_default()
    }

    fn get_latency(&self) -> usize {
        self.pre_delay_lengths.first().copied().unwrap_or(0)
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<{ N }>> {
        Box::new(self.clone())
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = configs.reverb_params.as_ref() {
            let new_config: ReverbConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid reverb config: {}", e))?;
            self.config = new_config;
            Ok(())
        } else {
            Err("No reverb parameters in config".to_string())
        }
    }
}


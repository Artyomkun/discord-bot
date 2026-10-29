//! Эффект хоруса и фленджера
//! Многоголосный хорус с LFO модуляцией

use crate::audio::{AudioBuffer, AudioError, AudioFormat, SampleFormat};
use crate::dsp::filter::*;
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use serde::{Deserialize, Serialize};
use bincode::{Encode, Decode};
use std::f32::consts::PI;

/// Тип хоруса/фленджера
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Encode, Decode)]
pub enum ChorusType {
    Chorus,
    Flanger,
    Dimension,
    Ensemble,
    Vibrato,
}

/// Один голос хоруса
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct ChorusVoice {
    pub delay_time: f32,      // ms, 10-50
    pub depth: f32,           // 0.0-1.0
    pub rate: f32,            // Hz, 0.1-5.0
    pub feedback: f32,        // 0.0-0.9
    pub phase_offset: f32,    // degrees, 0-360
    pub pan: f32,             // -1.0..1.0
    pub enabled: bool,
}

impl Default for ChorusVoice {
    fn default() -> Self {
        Self {
            delay_time: 20.0,
            depth: 0.3,
            rate: 0.5,
            feedback: 0.2,
            phase_offset: 0.0,
            pan: 0.0,
            enabled: true,
        }
    }
}

/// Форма модуляции
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Encode, Decode, PartialEq)]
pub enum ModulationShape {
    Sine,
    Triangle,
    Square,
    Sawtooth,
}

/// Конфигурация хоруса
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct ChorusConfig {
    pub chorus_type: ChorusType,
    pub voices: Vec<ChorusVoice>,
    pub stereo_width: f32,
    pub low_cut: f32,
    pub high_cut: f32,
    pub modulation_shape: ModulationShape,
    pub wet: f32,
    pub dry: f32,
}

impl Default for ChorusConfig {
    fn default() -> Self {
        Self {
            chorus_type: ChorusType::Chorus,
            voices: vec![
                ChorusVoice { phase_offset: 0.0, pan: -0.5, ..Default::default() },
                ChorusVoice { phase_offset: 90.0, pan: 0.5, ..Default::default() },
                ChorusVoice { phase_offset: 180.0, pan: 0.0, ..Default::default() },
            ],
            stereo_width: 0.8,
            low_cut: 200.0,
            high_cut: 8000.0,
            modulation_shape: ModulationShape::Sine,
            wet: 0.5,
            dry: 0.5,
        }
    }
}

/// Многоголосный хорус с LFO модуляцией
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Chorus<const N: usize> {
    config: ChorusConfig,
    format: AudioFormat,
    delay_buffers: Vec<Vec<Vec<f32>>>,
    buffer_positions: Vec<Vec<usize>>,
    lfo_phases: Vec<f32>,
    lfo_increments: Vec<f32>,
    low_cut_filters: Vec<Vec<Filter>>,
    high_cut_filters: Vec<Vec<Filter>>,
    lfo_table: Vec<f32>,
    table_size: usize,
}

impl<const N: usize> Chorus<N> {
    pub fn new(config: ChorusConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;
        let table_size = 1024;
        let lfo_table = Self::create_lfo_table(&config, table_size);
        
        let mut delay_buffers = Vec::with_capacity(config.voices.len());
        let mut buffer_positions = Vec::with_capacity(config.voices.len());
        let mut low_cut_filters = Vec::with_capacity(config.voices.len());
        let mut high_cut_filters = Vec::with_capacity(config.voices.len());
        let mut lfo_phases = Vec::with_capacity(config.voices.len());
        let mut lfo_increments = Vec::with_capacity(config.voices.len());
        
        // Максимальная задержка: base_delay + depth * 50ms
        let max_delay_ms = 50.0 + 50.0;
        let max_delay_samples = (max_delay_ms * 0.001 * sample_rate) as usize;

        for (voice_idx, voice) in config.voices.iter().enumerate() {
            let mut voice_buffers = Vec::with_capacity(channels);
            let mut voice_positions = Vec::with_capacity(channels);
            let mut voice_low_cut = Vec::with_capacity(channels);
            let mut voice_high_cut = Vec::with_capacity(channels);

            for _ in 0..channels {
                voice_buffers.push(vec![0.0; max_delay_samples]);
                voice_positions.push(0);
                
                let mut low_filter = Filter::new(FilterType::HighPass, sample_rate);
                low_filter.set_frequency(config.low_cut);
                low_filter.set_q(0.707);
                voice_low_cut.push(low_filter);
                
                let mut high_filter = Filter::new(FilterType::LowPass, sample_rate);
                high_filter.set_frequency(config.high_cut);
                high_filter.set_q(0.707);
                voice_high_cut.push(high_filter);
            }

            delay_buffers.push(voice_buffers);
            buffer_positions.push(voice_positions);
            low_cut_filters.push(voice_low_cut);
            high_cut_filters.push(voice_high_cut);
            
            let phase_rad = voice.phase_offset.to_radians();
            let extra_offset = voice_idx as f32 * 90.0 / config.voices.len().max(1) as f32;
            lfo_phases.push(phase_rad + extra_offset.to_radians());
            
            let voice_rate = voice.rate * (1.0 + voice_idx as f32 * 0.02);
            lfo_increments.push((2.0 * PI * voice_rate) / sample_rate);
        }

        Self {
            config,
            format,
            delay_buffers,
            buffer_positions,
            lfo_phases,
            lfo_increments,
            low_cut_filters,
            high_cut_filters,
            lfo_table,
            table_size,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: ChorusConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid chorus config: {}", e)))?;
        Ok(Self::new(config, format))
    }

    fn create_lfo_table(config: &ChorusConfig, size: usize) -> Vec<f32> {
        let mut table = vec![0.0; size];
        table.iter_mut().enumerate().for_each(|(i, entry)| {
            let phase = 2.0 * PI * i as f32 / size as f32;
            let value = match config.modulation_shape {
                ModulationShape::Sine => phase.sin(),
                ModulationShape::Triangle => {
                    let normalized = phase / (2.0 * PI);
                    if normalized < 0.25 {
                        normalized * 4.0
                    } else if normalized < 0.75 {
                        2.0 - normalized * 4.0
                    } else {
                        normalized * 4.0 - 4.0
                    }
                }
                ModulationShape::Square => {
                    if phase.sin() > 0.0 { 1.0 } else { -1.0 }
                }
                ModulationShape::Sawtooth => {
                    let normalized = phase / (2.0 * PI);
                    2.0 * normalized - 1.0
                }
            };
            *entry = value;
        });
        table
    }

    fn get_lfo_value(&self, phase: f32) -> f32 {
        let idx = ((phase / (2.0 * PI)) * self.table_size as f32) as usize % self.table_size;
        self.lfo_table[idx]
    }

    fn process_voice(&mut self, voice_idx: usize, channel: usize, input: f32) -> f32 {
        let voice = &self.config.voices[voice_idx];
        if !voice.enabled {
            return 0.0;
        }
        
        let sample_rate = self.format.sample_rate_hz() as f32;
        let buffer_len = self.delay_buffers[voice_idx][channel].len();
        let write_pos = self.buffer_positions[voice_idx][channel];
        
        // LFO значение
        let phase = self.lfo_phases[voice_idx];
        let lfo_value = self.get_lfo_value(phase);
        
        // Расчёт задержки
        let base_delay_samples = voice.delay_time * 0.001 * sample_rate;
        let mod_samples = voice.depth * 50.0 * 0.001 * sample_rate;
        let total_delay = (base_delay_samples + lfo_value * mod_samples).max(1.0);
        
        // Чтение с линейной интерполяцией
        let read_pos_f = (write_pos as f32 - total_delay + buffer_len as f32) % buffer_len as f32;
        let read_pos = read_pos_f as usize;
        let next_pos = (read_pos + 1) % buffer_len;
        let frac = read_pos_f - read_pos as f32;
        
        let buffer = &mut self.delay_buffers[voice_idx][channel];
        let delayed = buffer[read_pos] * (1.0 - frac) + buffer[next_pos] * frac;
        
        // Фильтрация
        let mut filtered = delayed;
        self.low_cut_filters[voice_idx][channel].process(&mut filtered);
        self.high_cut_filters[voice_idx][channel].process(&mut filtered);
        
        // Запись с обратной связью
        let write_value = input + filtered * voice.feedback;
        buffer[write_pos] = write_value;
        
        // Обновление позиций
        self.buffer_positions[voice_idx][channel] = (write_pos + 1) % buffer_len;
        self.lfo_phases[voice_idx] = (phase + self.lfo_increments[voice_idx]) % (2.0 * PI);
        
        filtered
    }

    fn process_voice_with_feedback(&mut self, voice_idx: usize, channel: usize, input: f32, feedback: f32) -> f32 {
        let output = self.process_voice(voice_idx, channel, input);
        input * (1.0 - feedback) + output * feedback
    }

    fn apply_panning(&self, sample: f32, pan: f32, channel: usize, total_channels: usize) -> f32 {
        if total_channels < 2 {
            return sample;
        }
        
        let pan_law_gain = 0.5f32.sqrt(); // -3dB pan law
        
        if channel == 0 {
            if pan <= 0.0 {
                sample * pan_law_gain
            } else {
                sample * (1.0 - pan) * pan_law_gain
            }
        } else {
            if pan >= 0.0 {
                sample * pan_law_gain
            } else {
                sample * (1.0 + pan) * pan_law_gain
            }
        }
    }

    pub fn format(&self) -> &AudioFormat {
        &self.format
    }
}

impl<const N: usize> AudioEffect<N> for Chorus<N> {
    fn get_name(&self) -> String {
        "chorus".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        let channels = buffer.channels();
        let _sample_rate = buffer.sample_rate_hz() as f32;
        
        match self.config.chorus_type {
            ChorusType::Chorus | ChorusType::Dimension | ChorusType::Ensemble => {
                for ch in 0..channels {
                    if let Some(channel_data) = buffer.get_channel_slice_mut(ch) {
                        for sample in channel_data {
                            let input = *sample;
                            let mut chorus_sum = 0.0;
                            
                            for voice_idx in 0..self.config.voices.len() {
                                let voice_output = self.process_voice(voice_idx, ch, input);
                                let pan = self.config.voices[voice_idx].pan;
                                let panned = self.apply_panning(voice_output, pan, ch, channels);
                                chorus_sum += panned;
                            }
                            
                            let normalized = chorus_sum / self.config.voices.len() as f32;
                            
                            let stereo = if self.config.chorus_type == ChorusType::Dimension {
                                let width = self.config.stereo_width;
                                if ch == 0 {
                                    normalized * (1.0 + width)
                                } else {
                                    normalized * (1.0 - width)
                                }
                            } else {
                                normalized
                            };
                            
                            *sample = (input * self.config.dry + stereo * self.config.wet).clamp(-1.0, 1.0);
                        }
                    }
                }
            }
            
            ChorusType::Flanger => {
                let feedback = self.config.voices[0].feedback;
                
                for ch in 0..channels {
                    if let Some(channel_data) = buffer.get_channel_slice_mut(ch) {
                        for sample in channel_data {
                            let input = *sample;
                            let flanged = self.process_voice_with_feedback(0, ch, input, feedback);
                            *sample = (input * (1.0 - self.config.wet) + flanged * self.config.wet).clamp(-1.0, 1.0);
                        }
                    }
                }
            }
            
            ChorusType::Vibrato => {
                let voice = &self.config.voices[0];
                let feedback = voice.feedback;
                
                for ch in 0..channels {
                    if let Some(channel_data) = buffer.get_channel_slice_mut(ch) {
                        for sample in channel_data {
                            let input = *sample;
                            let vibrato = self.process_voice_with_feedback(0, ch, input, feedback);
                            *sample = vibrato.clamp(-1.0, 1.0);
                        }
                    }
                }
            }
        }
        
        Ok(())
    }

    fn reset(&mut self) {
        // Сброс буферов задержки
        for voice_buffers in &mut self.delay_buffers {
            for buffer in voice_buffers {
                buffer.fill(0.0);
            }
        }
        
        // Сброс позиций
        for positions in &mut self.buffer_positions {
            for pos in positions {
                *pos = 0;
            }
        }
        
        // Сброс LFO фаз
        for (i, phase) in self.lfo_phases.iter_mut().enumerate() {
            *phase = self.config.voices.get(i).map_or(0.0, |v| v.phase_offset.to_radians());
        }
        
        // Сброс фильтров
        for filters in &mut self.low_cut_filters {
            for filter in filters {
                filter.reset();
            }
        }
        
        for filters in &mut self.high_cut_filters {
            for filter in filters {
                filter.reset();
            }
        }
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: ChorusConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid chorus config: {}", e)))?;
        
        *self = Self::new(new_config, self.format.clone());
        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or_default()
    }

    fn get_latency(&self) -> usize {
        let sample_rate = self.format.sample_rate_hz() as f32;
        self.config.voices.iter()
            .map(|voice| (voice.delay_time * 0.001 * sample_rate) as usize)
            .max()
            .unwrap_or(0)
    }

    

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = configs.chorus_params.as_ref() {
            let new_config: ChorusConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid chorus config: {}", e))?;
            self.config = new_config;
            Ok(())
        } else {
            Err("No chorus parameters in config".to_string())
        }
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }
}


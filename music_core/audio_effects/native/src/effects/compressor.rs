//! Компрессор/лимитер аудио
//! Профессиональный динамический процессор

use crate::audio::{AudioBuffer, AudioError, AudioFormat};
use crate::dsp::filter::{Filter, FilterType};
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::f32::consts::LN_2;

/// Конфигурация компрессора
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct CompressorConfig {
    pub threshold_db: f32,      // dB, -60..0
    pub ratio: f32,             // 1..100
    pub attack_ms: f32,         // ms, 0.1..100
    pub release_ms: f32,        // ms, 10..5000
    pub knee_db: f32,           // dB, 0..30
    pub makeup_gain_db: f32,    // dB, -24..24
    pub lookahead_ms: f32,      // ms, 0..10
    pub auto_makeup: bool,
}

impl Default for CompressorConfig {
    fn default() -> Self {
        Self {
            threshold_db: -20.0,
            ratio: 4.0,
            attack_ms: 10.0,
            release_ms: 100.0,
            knee_db: 6.0,
            makeup_gain_db: 0.0,
            lookahead_ms: 2.0,
            auto_makeup: true,
        }
    }
}

/// Профессиональный компрессор аудио
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Compressor<const N: usize> {
    config: CompressorConfig,
    format: AudioFormat,
    
    // Состояние
    envelope_db: f32,
    gain_reduction_linear: f32,
    
    // Lookahead
    lookahead_buffer: Vec<Vec<f32>>,
    lookahead_pos: usize,
    lookahead_size: usize,
    
    // Sidechain фильтр
    sidechain_filter: Filter,
    
    // Коэффициенты
    attack_coeff: f32,
    release_coeff: f32,
    
    // Метрики
    peak_level_db: f32,
    rms_level_db: f32,
    gain_reduction_db: f32,
}

impl<const N: usize> Compressor<N> {
    pub fn new(config: CompressorConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;
        
        let attack_coeff = (-LN_2 / (config.attack_ms * 0.001 * sample_rate)).exp();
        let release_coeff = (-LN_2 / (config.release_ms * 0.001 * sample_rate)).exp();
        
        let mut sidechain_filter = Filter::new(FilterType::HighPass, sample_rate);
        sidechain_filter.set_frequency(80.0);
        sidechain_filter.set_q(0.707);
        sidechain_filter.update_coefficients();
        
        let lookahead_size = ((config.lookahead_ms * 0.001) * sample_rate) as usize;
        
        Self {
            config,
            format,
            envelope_db: -144.0,
            gain_reduction_linear: 1.0,
            lookahead_buffer: vec![vec![0.0; lookahead_size]; channels],
            lookahead_pos: 0,
            lookahead_size,
            sidechain_filter,
            attack_coeff,
            release_coeff,
            peak_level_db: -144.0,
            rms_level_db: -144.0,
            gain_reduction_db: 0.0,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: CompressorConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid compressor config: {}", e)))?;
        Ok(Self::new(config, format))
    }

    /// Преобразование сэмпла в dB
    #[inline]
    fn sample_to_db(&self, sample: f32) -> f32 {
        let peak = sample.abs();
        if peak > 1e-6 { 20.0 * peak.log10() } else { -144.0 }
    }
    
    /// Расчёт gain reduction в dB
    fn calculate_gain_reduction_db(&self, level_db: f32) -> f32 {
        let threshold = self.config.threshold_db;
        let ratio = self.config.ratio;
        let knee = self.config.knee_db;
        
        // Ниже порога - нет компрессии
        if level_db <= threshold - knee * 0.5 {
            return 0.0;
        }
        
        // Soft knee зона
        if knee > 0.0 && level_db > threshold - knee * 0.5 && level_db < threshold + knee * 0.5 {
            let overshoot = level_db - (threshold - knee * 0.5);
            let gain_reduction = (overshoot * overshoot) / (2.0 * knee);
            return -gain_reduction * (1.0 - 1.0 / ratio);
        }
        
        // Hard knee зона
        if level_db > threshold {
            let overshoot = level_db - threshold;
            return -overshoot * (1.0 - 1.0 / ratio);
        }
        
        0.0
    }
    
    /// Обновление огибающей
    fn update_envelope(&mut self, level_db: f32, _sample_rate: f32) {
        let coeff = if level_db > self.envelope_db {
            self.attack_coeff
        } else {
            self.release_coeff
        };
        self.envelope_db = coeff * self.envelope_db + (1.0 - coeff) * level_db;
    }
    
    /// Расчёт makeup gain
    fn compute_makeup_gain_db(&self, gain_reduction_db: f32) -> f32 {
        if self.config.auto_makeup {
            -gain_reduction_db * 0.5
        } else {
            self.config.makeup_gain_db
        }
    }
    
    /// Обновление коэффициентов при изменении параметров
    fn update_coefficients(&mut self) {
        let sample_rate = self.format.sample_rate_hz() as f32;
        self.attack_coeff = (-LN_2 / (self.config.attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-LN_2 / (self.config.release_ms * 0.001 * sample_rate)).exp();
    }

    
}

impl<const N: usize> AudioEffect<N> for Compressor<N> {
    fn get_name(&self) -> String {
        "compressor".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError> {
        let channels = buffer.channels();
        let sample_rate = buffer.sample_rate_hz() as f32;
        
        for ch in 0..channels {
            if let Some(channel_slice) = buffer.get_channel_slice_mut(ch) {
                let lookahead_len = self.lookahead_size;
                let half_lookahead = lookahead_len / 2;
                
                channel_slice.iter_mut().for_each(|sample| {
                    // Обновление метрик RMS
                    self.rms_level_db = 0.999 * self.rms_level_db + 0.001 * self.sample_to_db(*sample);
                    self.peak_level_db = self.peak_level_db.max(self.sample_to_db(*sample));
                    
                    if lookahead_len > 0 {
                        // Запись в lookahead буфер
                        self.lookahead_buffer[ch][self.lookahead_pos] = *sample;
                        let delayed_pos = (self.lookahead_pos + half_lookahead) % lookahead_len;
                        let delayed_sample = self.lookahead_buffer[ch][delayed_pos];
                        
                        // Sidechain обработка
                        let mut sidechain_sample = delayed_sample;
                        self.sidechain_filter.process(&mut sidechain_sample);
                        
                        // Детекция уровня
                        let level_db = self.sample_to_db(sidechain_sample);
                        self.update_envelope(level_db, sample_rate);
                        
                        // Расчёт gain reduction
                        let gain_reduction_db = self.calculate_gain_reduction_db(self.envelope_db);
                        self.gain_reduction_db = gain_reduction_db;
                        
                        // Makeup gain
                        let makeup_gain_db = self.compute_makeup_gain_db(gain_reduction_db);
                        
                        // Конвертация в линейный коэффициент
                        let gain_reduction_linear = 10.0f32.powf(gain_reduction_db / 20.0);
                        let makeup_gain_linear = 10.0f32.powf(makeup_gain_db / 20.0);
                        let target_gain = gain_reduction_linear * makeup_gain_linear;
                        
                        // Сглаживание gain reduction
                        let alpha = 0.01;
                        self.gain_reduction_linear = self.gain_reduction_linear * (1.0 - alpha) + target_gain * alpha;
                        
                        // Применение gain
                        *sample *= self.gain_reduction_linear;
                        
                        // Обновление позиции
                        self.lookahead_pos = (self.lookahead_pos + 1) % lookahead_len;
                    } else {
                        // Без lookahead
                        let level_db = self.sample_to_db(*sample);
                        self.update_envelope(level_db, sample_rate);
                        
                        let gain_reduction_db = self.calculate_gain_reduction_db(self.envelope_db);
                        self.gain_reduction_db = gain_reduction_db;
                        
                        let makeup_gain_db = self.compute_makeup_gain_db(gain_reduction_db);
                        let target_gain = 10.0f32.powf((gain_reduction_db + makeup_gain_db) / 20.0);
                        
                        let alpha = 0.01;
                        self.gain_reduction_linear = self.gain_reduction_linear * (1.0 - alpha) + target_gain * alpha;
                        
                        *sample *= self.gain_reduction_linear;
                    }
                    
                    // Клиппинг на выходе
                    *sample = sample.clamp(-1.0, 1.0);
                });
            }
        }
        
        Ok(())
    }

    fn reset(&mut self) {
        self.envelope_db = -144.0;
        self.gain_reduction_linear = 1.0;
        self.lookahead_pos = 0;
        self.peak_level_db = -144.0;
        self.rms_level_db = -144.0;
        self.gain_reduction_db = 0.0;
        
        for buffer in &mut self.lookahead_buffer {
            buffer.fill(0.0);
        }
        
        self.sidechain_filter.reset();
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: CompressorConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid compressor config: {}", e)))?;
        
        self.config = new_config;
        self.update_coefficients();
        
        let sample_rate = self.format.sample_rate_hz() as f32;
        let new_lookahead_size = ((self.config.lookahead_ms * 0.001) * sample_rate) as usize;
        
        if new_lookahead_size != self.lookahead_size {
            let channels = self.format.channels as usize;
            self.lookahead_size = new_lookahead_size;
            self.lookahead_buffer = vec![vec![0.0; new_lookahead_size]; channels];
            self.lookahead_pos = 0;
        }
        
        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        self.lookahead_size / 2
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics {
            gain_reduction_db: self.gain_reduction_db,
            envelope_db: self.envelope_db,
            peak_level_db: self.peak_level_db,
            rms_level_db: self.rms_level_db,
        }
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = &configs.compressor_params {
            let new_config: CompressorConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid compressor config: {}", e))?;
            self.config = new_config;
            self.update_coefficients();
            Ok(())
        } else {
            Err("No compressor parameters in config".to_string())
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }
}


//! Параметрический и графический эквалайзер
//! Многополосная обработка с oversampling для качественной фильтрации

use crate::audio::{AudioBuffer, AudioError, AudioFormat};
use crate::dsp::compressor::CompressorMetrics;
use crate::dsp::fft::{FFT, WindowType};
use crate::dsp::filter::{Filter, FilterType};
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};

/// Тип фильтра для эквалайзера
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Encode, Decode, PartialEq)]
pub enum EQFilterType {
    LowShelf,
    HighShelf,
    Peak,
    LowPass,
    HighPass,
    BandPass,
    Notch,
}

impl From<EQFilterType> for FilterType {
    fn from(eq_type: EQFilterType) -> Self {
        match eq_type {
            EQFilterType::LowShelf => FilterType::LowShelf,
            EQFilterType::HighShelf => FilterType::HighShelf,
            EQFilterType::Peak => FilterType::Peak,
            EQFilterType::LowPass => FilterType::LowPass,
            EQFilterType::HighPass => FilterType::HighPass,
            EQFilterType::BandPass => FilterType::BandPass,
            EQFilterType::Notch => FilterType::Notch,
        }
    }
}

/// Полоса эквалайзера
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct EQBand {
    pub frequency: f32,
    pub gain: f32,
    pub q: f32,
    pub filter_type: EQFilterType,
    pub enabled: bool,
}

impl Default for EQBand {
    fn default() -> Self {
        Self {
            frequency: 1000.0,
            gain: 0.0,
            q: 1.0,
            filter_type: EQFilterType::Peak,
            enabled: true,
        }
    }
}

/// Конфигурация эквалайзера
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct EqualizerConfig {
    pub bands: Vec<EQBand>,
    pub preamp: f32,
    pub phase_linear: bool,
    pub oversampling: u8,  // 1, 2, 4
}

impl Default for EqualizerConfig {
    fn default() -> Self {
        Self {
            bands: vec![
                EQBand { frequency: 80.0, gain: 0.0, q: 1.0, filter_type: EQFilterType::LowShelf, enabled: true },
                EQBand { frequency: 400.0, gain: 0.0, q: 1.0, filter_type: EQFilterType::Peak, enabled: true },
                EQBand { frequency: 1000.0, gain: 0.0, q: 1.0, filter_type: EQFilterType::Peak, enabled: true },
                EQBand { frequency: 3000.0, gain: 0.0, q: 1.0, filter_type: EQFilterType::Peak, enabled: true },
                EQBand { frequency: 8000.0, gain: 0.0, q: 1.0, filter_type: EQFilterType::HighShelf, enabled: true },
            ],
            preamp: 0.0,
            phase_linear: false,
            oversampling: 1,
        }
    }
}

/// Профессиональный эквалайзер с oversampling
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Equalizer<const N: usize> {
    config: EqualizerConfig,
    format: AudioFormat,
    filters: Vec<Vec<Filter>>,
    preamp_gain: f32,
    nyquist: f32,
    needs_update: bool,
    // Oversampling буферы
    oversampled_buffer: Vec<f32>,
    temp_buffer: Vec<f32>,
}

impl<const N: usize> Equalizer<N> {
    pub fn new(config: EqualizerConfig, format: AudioFormat) -> Self {
        let channels = format.channels as usize;
        let sample_rate = format.sample_rate_hz() as f32;
        let nyquist = sample_rate / 2.0;

        let filters = Self::create_filters(&config, channels, sample_rate);
        let preamp_gain = 10.0f32.powf(config.preamp / 20.0);

        Self {
            config,
            format,
            filters,
            preamp_gain,
            nyquist,
            needs_update: false,
            oversampled_buffer: Vec::new(),
            temp_buffer: Vec::new(),
        }
    }

    fn create_filters(config: &EqualizerConfig, channels: usize, sample_rate: f32) -> Vec<Vec<Filter>> {
        let mut filters = Vec::with_capacity(channels);

        for _ in 0..channels {
            let mut channel_filters = Vec::with_capacity(config.bands.len());

            for band in &config.bands {
                let filter_type: FilterType = band.filter_type.into();
                let mut filter = Filter::new(filter_type, sample_rate);
                filter.set_frequency(band.frequency);
                filter.set_gain(band.gain);
                filter.set_q(band.q);
                filter.update_coefficients();
                channel_filters.push(filter);
            }

            filters.push(channel_filters);
        }

        filters
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: EqualizerConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid EQ config: {}", e)))?;

        for band in &config.bands {
            if band.frequency <= 0.0 || band.frequency > format.sample_rate_hz() as f32 / 2.0 {
                return Err(AudioError::InvalidParameter(format!(
                    "Invalid frequency {} Hz for sample rate {}",
                    band.frequency,
                    format.sample_rate_hz()
                )));
            }

            if band.gain < -48.0 || band.gain > 48.0 {
                return Err(AudioError::InvalidParameter(format!(
                    "Gain {} dB out of range [-48, 48]",
                    band.gain
                )));
            }

            if band.q <= 0.0 || band.q > 20.0 {
                return Err(AudioError::InvalidParameter(format!(
                    "Q factor {} out of range (0, 20]",
                    band.q
                )));
            }
        }

        Ok(Self::new(config, format))
    }

    

    /// Простой anti-aliasing фильтр (low-pass)
    fn apply_anti_aliasing_filter(&self, buffer: &mut [f32], cutoff_freq: f32, sample_rate: f32) {
        let rc = 1.0 / (2.0 * std::f32::consts::PI * cutoff_freq);
        let dt = 1.0 / sample_rate;
        let alpha = dt / (rc + dt);
        
        let mut prev = 0.0;
        for sample in buffer.iter_mut() {
            *sample = alpha * *sample + (1.0 - alpha) * prev;
            prev = *sample;
        }
    }

    /// Upsampling: линейная интерполяция
    fn upsample(&self, input: &[f32], factor: usize) -> Vec<f32> {
        if factor == 1 {
            return input.to_vec();
        }
        
        let output_len = input.len() * factor;
        let mut output = vec![0.0; output_len];
        
        for i in 0..input.len() - 1 {
            let out_idx = i * factor;
            let x0 = input[i];
            let x1 = input[i + 1];
            
            output[out_idx] = x0;
            
            for j in 1..factor {
                let t = j as f32 / factor as f32;
                output[out_idx + j] = x0 * (1.0 - t) + x1 * t;
            }
        }
        
        // Последний сэмпл
        if let Some(&last) = input.last() {
            let last_idx = (input.len() - 1) * factor;
            output[last_idx] = last;
            for j in 1..factor {
                if last_idx + j < output.len() {
                    output[last_idx + j] = last;
                }
            }
        }
        
        output
    }

    /// Downsampling с anti-aliasing
    fn downsample(&self, input: &[f32], factor: usize, sample_rate: f32) -> Vec<f32> {
        if factor == 1 {
            return input.to_vec();
        }
        
        let output_len = input.len() / factor;
        let mut downsampled = vec![0.0; output_len];
        
        downsampled.iter_mut().enumerate().take(output_len).for_each(|(i, out_sample)| {
            let in_idx = i * factor;
            if in_idx < input.len() {
                *out_sample = input[in_idx];
            }
        });
        
        // Simple anti-aliasing filter после downsampling
        let nyquist = sample_rate / (2.0 * factor as f32);
        self.apply_anti_aliasing_filter(&mut downsampled, nyquist, sample_rate / factor as f32);
        
        downsampled
    }

    fn update_filters(&mut self) {
        let sample_rate = self.format.sample_rate_hz() as f32;
        
        for channel_idx in 0..self.filters.len() {
            for band_idx in 0..self.filters[channel_idx].len() {
                if band_idx < self.config.bands.len() {
                    let band = &self.config.bands[band_idx];
                    let filter = &mut self.filters[channel_idx][band_idx];
                    
                    filter.set_sample_rate(sample_rate);
                    filter.set_frequency(band.frequency.min(self.nyquist * 0.95));
                    filter.set_gain(band.gain);
                    filter.set_q(band.q);
                    filter.update_coefficients();
                }
            }
        }
        
        self.preamp_gain = 10.0f32.powf(self.config.preamp / 20.0);
        self.needs_update = false;
    }

    fn process_channel_internal(&mut self, channel_data: &mut [f32], sample_rate: f32) {
        let factor = self.config.oversampling as usize;
        
        // 1. Upsampling
        let upsampled = if factor > 1 {
            self.upsample(channel_data, factor)
        } else {
            channel_data.to_vec()
        };
        
        let upsampled_sample_rate = sample_rate * factor as f32;
        
        // 2. Применение preamp
        let mut processed = if (self.preamp_gain - 1.0).abs() > 0.001 {
            upsampled.iter().map(|&s| s * self.preamp_gain).collect()
        } else {
            upsampled
        };
        
        // 3. Применение всех фильтров
        for band_idx in 0..self.config.bands.len() {
            if band_idx < self.filters[0].len() && self.config.bands[band_idx].enabled {
                let filter = &mut self.filters[0][band_idx];
                
                // Обновляем частоту дискретизации для фильтра
                filter.set_sample_rate(upsampled_sample_rate);
                filter.set_frequency(self.config.bands[band_idx].frequency);
                filter.update_coefficients();
                
                for sample in &mut processed {
                    filter.process(sample);
                }
            }
        }
        
        // 4. Downsampling
        let downsampled = if factor > 1 {
            self.downsample(&processed, factor, upsampled_sample_rate)
        } else {
            processed
        };
        
        // 5. Копирование результата
        let len = channel_data.len().min(downsampled.len());
        channel_data[..len].copy_from_slice(&downsampled[..len]);
    }

    pub fn get_frequency_response(&self, frequencies: &[f32]) -> Vec<f32> {
        if frequencies.is_empty() || self.filters.is_empty() {
            return vec![0.0; frequencies.len()];
        }

        let mut response = vec![1.0; frequencies.len()];

        for band_idx in 0..self.config.bands.len().min(self.filters[0].len()) {
            if self.config.bands[band_idx].enabled {
                let filter = &self.filters[0][band_idx];
                for (i, &freq) in frequencies.iter().enumerate() {
                    response[i] *= filter.get_magnitude_response(freq);
                }
            }
        }

        for r in &mut response {
            *r *= self.preamp_gain;
        }

        response
    }

    pub fn analyze_spectrum(&self, buffer: &AudioBuffer<N>, channel: usize) -> Vec<f32> {
        const FFT_SIZE: usize = 1024;
        
        match buffer.get_channel_slice(channel) {
            Some(samples) if samples.len() >= FFT_SIZE => {
                let fft = FFT::new(FFT_SIZE);
                let window = fft.create_window(WindowType::Hann);
                let start = (samples.len() - FFT_SIZE) / 2;
                
                let frame: Vec<f32> = samples[start..start + FFT_SIZE]
                    .iter()
                    .zip(window.iter())
                    .map(|(&s, &w)| s * w)
                    .collect();

                let spectrum = fft.forward(&frame);
                
                let magnitudes: Vec<f32> = spectrum.iter()
                    .take(FFT_SIZE / 2)
                    .map(|c| c.norm())
                    .collect();
                
                let band_frequencies = [31.5, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
                let sample_rate = self.format.sample_rate_hz() as f32;
                let mut bands = vec![0.0; 10];

                for (i, &target_freq) in band_frequencies.iter().enumerate() {
                    let bin = (target_freq * FFT_SIZE as f32 / sample_rate) as usize;
                    if bin < magnitudes.len() {
                        bands[i] = magnitudes[bin];
                    }
                }
                bands
            }
            _ => vec![0.0; 10],
        }
    }
}

impl<const N: usize> AudioEffect<N> for Equalizer<N> {
    fn get_name(&self) -> String {
        "equalizer".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError> {
        if self.needs_update {
            self.update_filters();
        }
        
        let channels = buffer.channels();
        let sample_rate = self.format.sample_rate_hz() as f32;
        
        for ch in 0..channels {
            if let Some(channel_data) = buffer.get_channel_slice_mut(ch) {
                let mut data = channel_data.to_vec();
                self.process_channel_internal(&mut data, sample_rate);
                channel_data.copy_from_slice(&data);
            }
        }
        
        Ok(())
    }

    fn reset(&mut self) {
        for channel_filters in &mut self.filters {
            for filter in channel_filters {
                filter.reset();
            }
        }
        self.needs_update = true;
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: EqualizerConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid EQ config: {}", e)))?;

        self.config = new_config;
        self.needs_update = true;
        
        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        if self.config.phase_linear { 512 } else { 0 }
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = &configs.equalizer_params {
            let new_config: EqualizerConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid equalizer config: {}", e))?;
            self.config = new_config;
            self.needs_update = true;
            Ok(())
        } else {
            Err("No equalizer parameters in config".to_string())
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }
}


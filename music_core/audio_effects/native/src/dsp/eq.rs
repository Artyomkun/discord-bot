//! Parametric and graphic equalizer
//! Implementation of filters for precise tonal correction

use crate::audio::AudioEffect;
use crate::dsp::filter::{Filter, FilterType};
use crate::audio::{AudioBuffer, AudioFormat, AudioError};
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use crate::AudioEffectConfig;
use crate::dsp::compressor::CompressorMetrics;

/// EQ filter type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, Encode, Decode, PartialEq)]
pub enum EQFilterType {
    LowShelf,
    HighShelf,
    Peak,
    LowPass,
    HighPass,
    BandPass,
    Notch,
    AllPass,
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
            EQFilterType::AllPass => FilterType::AllPass,
        }
    }
}

/// EQ band parameters
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct EQBand {
    pub frequency: f32,
    pub gain: f32,
    pub q: f32,
    pub filter_type: EQFilterType,
    pub enabled: bool,
    pub slope: f32,
}

impl Default for EQBand {
    fn default() -> Self {
        Self {
            frequency: 1000.0,
            gain: 0.0,
            q: 1.0,
            filter_type: EQFilterType::Peak,
            enabled: true,
            slope: 1.0,
        }
    }
}

/// Graphic equalizer configuration
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct GraphicEQConfig {
    pub frequencies: Vec<f32>,
    pub gains: Vec<f32>,
    pub q_values: Vec<f32>,
    pub enabled: bool,
}

impl Default for GraphicEQConfig {
    fn default() -> Self {
        let frequencies = vec![31.5, 63.0, 125.0, 250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0, 16000.0];
        Self {
            frequencies: frequencies.clone(),
            gains: vec![0.0; frequencies.len()],
            q_values: vec![1.0; frequencies.len()],
            enabled: true,
        }
    }
}

/// Parametric equalizer
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct ParametricEQ<const N: usize> {
    bands: Vec<Vec<(EQBand, Filter)>>,
    sample_rate: f32,
    preamp_gain: f32,
    auto_reset: bool,
    num_bands: usize,
    format: AudioFormat,
    is_stereo: bool,
}

impl<const N: usize> ParametricEQ<N> {
    pub fn new(bands: Vec<EQBand>, format: AudioFormat, preamp_gain: f32) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;
        let is_stereo = channels >= 2;
        let mut bands_per_channel = Vec::with_capacity(channels);

        for _ in 0..channels {
            let mut channel_bands = Vec::with_capacity(bands.len());

            for band in &bands {
                let filter_type: FilterType = band.filter_type.into();
                let mut filter = Filter::new(filter_type, sample_rate);
                filter.set_frequency(band.frequency);
                filter.set_gain(band.gain);
                filter.set_q(band.q);
                filter.update_coefficients();

                channel_bands.push((band.clone(), filter));
            }

            bands_per_channel.push(channel_bands);
        }

        Self {
            bands: bands_per_channel,
            sample_rate,
            preamp_gain: 10.0f32.powf(preamp_gain / 20.0),
            auto_reset: true,
            num_bands: bands.len(),
            format,
            is_stereo,
        }
    }

    pub fn process_channel(&mut self, channel_idx: usize, input: f32) -> f32 {
        if channel_idx >= self.bands.len() {
            return input;
        }
        let mut output = input * self.preamp_gain;
        for (band, filter) in &mut self.bands[channel_idx] {
            if band.enabled {
                filter.process(&mut output);
            }
        }
        output
    }

    pub fn process_buffer_stereo(&mut self, left: &mut [f32], right: &mut [f32]) {
        for i in 0..left.len().min(right.len()) {
            left[i] = self.process_channel(0, left[i]);
            if self.is_stereo {
                right[i] = self.process_channel(1, right[i]);
            } else {
                right[i] = self.process_channel(0, right[i]);
            }
        }
    }

    pub fn update_band(&mut self, index: usize, band: EQBand) {
        if self.bands.is_empty() || index >= self.bands[0].len() {
            return;
        }

        let filter_type: FilterType = band.filter_type.into();

        for channel in &mut self.bands {
            if index < channel.len() {
                channel[index].0 = band.clone();
                channel[index].1.set_type(filter_type);
                channel[index].1.set_frequency(band.frequency);
                channel[index].1.set_gain(band.gain);
                channel[index].1.set_q(band.q);
                channel[index].1.update_coefficients();
            }
        }
    }

    pub fn add_band(&mut self, band: EQBand) {
        let filter_type: FilterType = band.filter_type.into();
        let _channels = self.bands.len();

        for channel in &mut self.bands {
            let mut filter = Filter::new(filter_type, self.sample_rate);
            filter.set_frequency(band.frequency);
            filter.set_gain(band.gain);
            filter.set_q(band.q);
            filter.update_coefficients();
            channel.push((band.clone(), filter));
        }
        self.num_bands = self.bands[0].len();
    }

    pub fn remove_band(&mut self, index: usize) {
        for channel in &mut self.bands {
            if index < channel.len() {
                channel.remove(index);
            }
        }
        if !self.bands.is_empty() {
            self.num_bands = self.bands[0].len();
        }
    }

    pub fn get_frequency_response(&self, frequencies: &[f32]) -> Vec<f32> {
        let mut response = vec![self.preamp_gain; frequencies.len()];
        if let Some(first_channel) = self.bands.first() {
            for (band, filter) in first_channel {
                if band.enabled {
                    for (i, &freq) in frequencies.iter().enumerate() {
                        response[i] *= filter.get_magnitude_response(freq);
                    }
                }
            }
        }
        response
    }

    pub fn calculate_frequency_response_analytical(&self, frequency: f32) -> f32 {
        let mut response = self.preamp_gain;
        if let Some(first_channel) = self.bands.first() {
            for (band, filter) in first_channel {
                if band.enabled {
                    response *= filter.get_magnitude_response(frequency);
                }
            }
        }
        response
    }

    pub fn get_bode_plot(&self, start_freq: f32, end_freq: f32, points: usize) -> Vec<(f32, f32)> {
        let mut plot = Vec::with_capacity(points);
        for i in 0..points {
            let t = i as f32 / (points - 1) as f32;
            let freq = start_freq * (end_freq / start_freq).powf(t);
            let magnitude = self.calculate_frequency_response_analytical(freq);
            let db = if magnitude > 0.0 { 20.0 * magnitude.log10() } else { -120.0 };
            plot.push((freq, db));
        }
        plot
    }

    pub fn reset_eq(&mut self) {
        for channel in &mut self.bands {
            for (_, filter) in channel {
                filter.reset();
            }
        }
    }

    pub fn set_preamp_gain_db(&mut self, gain_db: f32) {
        self.preamp_gain = 10.0f32.powf(gain_db.clamp(-24.0, 24.0) / 20.0);
    }

    pub fn format(&self) -> &AudioFormat {
        &self.format
    }

    pub fn bands(&self) -> &Vec<Vec<(EQBand, Filter)>> {
        &self.bands
    }

    pub fn num_bands(&self) -> usize {
        self.num_bands
    }
}

impl<const N: usize> AudioEffect<N> for ParametricEQ<N> {
    fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        let channels = buffer.channels();
        
        if channels == 1 {
            // Mono
            if let Some(channel) = buffer.get_channel_slice_mut(0) {
                for sample in channel {
                    *sample = self.process_channel(0, *sample);
                }
            }
        } else {
            // Stereo or more - process first two channels
            if let Some((left, right)) = buffer.get_two_channel_slices_mut(0, 1) {
                for i in 0..left.len().min(right.len()) {
                    left[i] = self.process_channel(0, left[i]);
                    right[i] = self.process_channel(1, right[i]);
                }
            }
        }
        Ok(())
    }

    fn reset(&mut self) {
        self.reset_eq();
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let bands: Vec<EQBand> = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid EQ bands: {}", e)))?;
        *self = Self::new(bands, self.format.clone(), 20.0 * self.preamp_gain.log10());
        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(self.bands.first().unwrap_or(&vec![])).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        0
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics {
            gain_reduction_db: 0.0,
            envelope_db: 0.0,
            peak_level_db: 0.0,
            rms_level_db: 0.0,
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }

    fn update_effects(&mut self, _configs: &AudioEffectConfig) -> Result<(), String> {
        Ok(())
    }

    fn get_name(&self) -> String {
        "parametric_eq".to_string()
    }
    
    fn format(&self) -> &AudioFormat {
        &self.format
    }
}

/// Graphic equalizer
pub struct GraphicEQ {
    bands: Vec<Filter>,
    config: GraphicEQConfig,
    format: AudioFormat,
}

impl GraphicEQ {
    pub fn new(config: GraphicEQConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let mut bands = Vec::with_capacity(config.frequencies.len());

        for i in 0..config.frequencies.len() {
            let mut filter = Filter::new(FilterType::Peak, sample_rate);
            filter.set_frequency(config.frequencies[i]);
            filter.set_gain(config.gains[i]);
            filter.set_q(config.q_values[i]);
            filter.update_coefficients();
            bands.push(filter);
        }

        Self {
            bands,
            config,
            format,
        }
    }

    pub fn process_sample(&mut self, input: f32) -> f32 {
        if !self.config.enabled {
            return input;
        }
        let mut output = input;
        for filter in &mut self.bands {
            filter.process(&mut output);
        }
        output
    }

    pub fn process_buffer<const N: usize>(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        if !self.config.enabled {
            return Ok(());
        }
        
        if let Some(channel) = buffer.get_channel_slice_mut(0) {
            for sample in channel {
                *sample = self.process_sample(*sample);
            }
        }
        Ok(())
    }

    pub fn update_band_gain(&mut self, band_index: usize, gain_db: f32) {
        if band_index < self.bands.len() {
            self.bands[band_index].set_gain(gain_db);
            self.config.gains[band_index] = gain_db;
            self.bands[band_index].update_coefficients();
        }
    }

    pub fn update_band_q(&mut self, band_index: usize, q: f32) {
        if band_index < self.bands.len() {
            self.bands[band_index].set_q(q);
            self.config.q_values[band_index] = q;
            self.bands[band_index].update_coefficients();
        }
    }

    pub fn auto_correct(&mut self, reference_spectrum: &[f32], target_spectrum: &[f32]) {
        for i in 0..self.bands.len().min(reference_spectrum.len()).min(target_spectrum.len()) {
            let diff_db = target_spectrum[i] - reference_spectrum[i];
            let new_gain = (self.config.gains[i] + diff_db * 0.5).clamp(-24.0, 24.0);
            self.update_band_gain(i, new_gain);
        }
    }

    pub fn reset_to_flat(&mut self) {
        for (i, filter) in self.bands.iter_mut().enumerate() {
            filter.set_gain(0.0);
            self.config.gains[i] = 0.0;
            filter.update_coefficients();
        }
    }

    pub fn save_preset(&self, name: &str) -> EQPreset {
        EQPreset {
            name: name.to_string(),
            frequencies: self.config.frequencies.clone(),
            gains: self.config.gains.clone(),
            q_values: self.config.q_values.clone(),
        }
    }

    pub fn load_preset(&mut self, preset: &EQPreset) {
        for i in 0..self.bands.len() {
            if let Some(preset_idx) = preset.frequencies.iter().position(|&f| (f - self.config.frequencies[i]).abs() < 1.0) {
                self.update_band_gain(i, preset.gains[preset_idx]);
                self.update_band_q(i, preset.q_values[preset_idx]);
            }
        }
    }
    
    pub fn format(&self) -> &AudioFormat {
        &self.format
    }
    
    pub fn reset(&mut self) {
        for filter in &mut self.bands {
            filter.reset();
        }
    }
}

/// EQ preset
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct EQPreset {
    pub name: String,
    pub frequencies: Vec<f32>,
    pub gains: Vec<f32>,
    pub q_values: Vec<f32>,
}

/// Linear phase equalizer (FIR filter)
pub struct LinearPhaseEQ {
    coefficients: Vec<f32>,
    buffer: Vec<f32>,
    position: usize,
    sample_rate: f32,
}

impl LinearPhaseEQ {
    pub fn new(coefficients: Vec<f32>, sample_rate: f32) -> Self {
        let buffer_size = coefficients.len();
        Self {
            coefficients,
            buffer: vec![0.0; buffer_size],
            position: 0,
            sample_rate,
        }
    }

    pub fn process_sample(&mut self, input: f32) -> f32 {
        self.buffer[self.position] = input;
        let mut output = 0.0;
        for i in 0..self.coefficients.len() {
            let idx = (self.position + self.coefficients.len() - i) % self.coefficients.len();
            output += self.buffer[idx] * self.coefficients[i];
        }
        self.position = (self.position + 1) % self.buffer.len();
        output
    }

    pub fn process_buffer<const N: usize>(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        if let Some(channel) = buffer.get_channel_slice_mut(0) {
            for sample in channel {
                *sample = self.process_sample(*sample);
            }
        }
        Ok(())
    }

    pub fn design_from_response(
        desired_response: &[(f32, f32)],
        filter_length: usize,
        sample_rate: f32,
    ) -> Vec<f32> {
        let mut coefficients = vec![0.0; filter_length];
        let mid_point = filter_length / 2;
        let pi = std::f32::consts::PI;

        coefficients.iter_mut().enumerate().take(filter_length).for_each(|(i, coeff)| {
                let n = i as f32 - mid_point as f32;
                let mut sum = 0.0;
                
                for &(freq, gain_db) in desired_response {
                    let gain_linear = 10.0f32.powf(gain_db / 20.0);
                    let omega = 2.0 * pi * freq / sample_rate;
                    
                    if n.abs() < 1e-6 {
                        sum += gain_linear * omega / pi;
                    } else {
                        sum += gain_linear * (omega * n).sin() / (pi * n);
                    }
                }
                
                *coeff = sum;
                
                // Hamming window
                let window = 0.54 - 0.46 * (2.0 * pi * i as f32 / (filter_length - 1) as f32).cos();
                *coeff *= window;
            });
        
        coefficients
    }

    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.position = 0;
    }
    
    pub fn sample_rate(&self) -> f32 {
        self.sample_rate
    }
}
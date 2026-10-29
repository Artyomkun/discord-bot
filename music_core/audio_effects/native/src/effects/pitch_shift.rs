//! Эффект сдвига высоты тона (питч-шифт)
//! Формант-сохраняющий pitch shifting и гармонайзер

use crate::audio::{AudioBuffer, AudioError, AudioFormat, SampleFormat};
use crate::dsp::fft::{FFT, WindowType};
use crate::dsp::filter::{Filter, FilterType};
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::AudioEffect;
use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Encode, Decode)]
pub enum PitchAlgorithm {
    PhaseVocoder,
    Granular,
    PSOLA,
    FormantPreserving,
}

#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct PitchShiftConfig {
    pub algorithm: PitchAlgorithm,
    pub pitch_shift: f32,
    pub fine_tune: f32,
    pub formant_shift: f32,
    pub window_size: usize,
    pub overlap: f32,
    pub grain_size: f32,
    pub randomness: f32,
    pub wet: f32,
    pub dry: f32,
}

impl Default for PitchShiftConfig {
    fn default() -> Self {
        Self {
            algorithm: PitchAlgorithm::PhaseVocoder,
            pitch_shift: 0.0,
            fine_tune: 0.0,
            formant_shift: 0.0,
            window_size: 1024,
            overlap: 0.75,
            grain_size: 30.0,
            randomness: 0.1,
            wet: 1.0,
            dry: 0.0,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct PitchShift<const N: usize> {
    config: PitchShiftConfig,
    format: AudioFormat,
    fft: FFT,
    fft_size: usize,
    hop_size: usize,
    last_phases: Vec<Vec<f32>>,
    sum_phases: Vec<Vec<f32>>,
    analysis_magnitudes: Vec<Vec<f32>>,
    analysis_frequencies: Vec<Vec<f32>>,
    synthesis_magnitudes: Vec<Vec<f32>>,
    synthesis_frequencies: Vec<Vec<f32>>,
    grain_buffers: Vec<Vec<f32>>,
    grain_positions: Vec<f32>,
    grain_envelopes: Vec<Vec<f32>>,
    formant_filters: Vec<Vec<Filter>>,
    analysis_window: Vec<f32>,
    synthesis_window: Vec<f32>,
    pitch_ratio: f32,
    time_ratio: f32,
    current_phase: f32,
}

impl<const N: usize> PitchShift<N> {
    pub fn new(config: PitchShiftConfig, format: AudioFormat) -> Self {
        let sample_rate = format.sample_rate_hz() as f32;
        let channels = format.channels as usize;

        let semitones = config.pitch_shift + config.fine_tune / 100.0;
        let pitch_ratio = 2.0f32.powf(semitones / 12.0);
        let time_ratio = 1.0 / pitch_ratio;

        let fft_size = config.window_size.next_power_of_two();
        let fft = FFT::new(fft_size);
        let hop_size = ((1.0 - config.overlap) * fft_size as f32) as usize;
        let num_bins = fft_size / 2 + 1;

        let last_phases = vec![vec![0.0; num_bins]; channels];
        let sum_phases = vec![vec![0.0; num_bins]; channels];
        let analysis_magnitudes = vec![vec![0.0; num_bins]; channels];
        let analysis_frequencies = vec![vec![0.0; num_bins]; channels];
        let synthesis_magnitudes = vec![vec![0.0; num_bins]; channels];
        let synthesis_frequencies = vec![vec![0.0; num_bins]; channels];

        let grain_size_samples = (config.grain_size / 1000.0 * sample_rate) as usize;
        let grain_buffers = vec![vec![0.0; grain_size_samples]; channels];
        let grain_positions = vec![0.0; channels];

        let mut grain_envelopes = vec![vec![0.0; grain_size_samples]; channels];
        grain_envelopes.iter_mut().take(channels).for_each(|channel| {
            channel.iter_mut().enumerate().take(grain_size_samples).for_each(|(i, sample)| {
                let pos = i as f32 / grain_size_samples as f32;
                *sample = 0.5 * (1.0 - (2.0 * PI * pos).cos());
            });
        });

        let mut formant_filters = Vec::with_capacity(channels);
        for _ in 0..channels {
            let mut filters = Vec::new();
            let formant_freqs = [500.0, 1500.0, 2500.0, 3500.0];
            for &freq in &formant_freqs {
                let mut filter = Filter::new(FilterType::Peak, sample_rate);
                filter.set_frequency(freq);
                filter.set_q(2.0);
                filter.set_gain(0.0);
                filters.push(filter);
            }
            formant_filters.push(filters);
        }

        let analysis_window = fft.create_window(WindowType::Hann);
        let mut synthesis_window = analysis_window.clone();

        let window_sum: f32 = analysis_window.iter().sum();
        if window_sum > 0.0 {
            for w in &mut synthesis_window {
                *w /= window_sum / (fft_size as f32 / hop_size as f32);
            }
        }

        Self {
            config,
            format,
            fft,
            fft_size,
            hop_size,
            last_phases,
            sum_phases,
            analysis_magnitudes,
            analysis_frequencies,
            synthesis_magnitudes,
            synthesis_frequencies,
            grain_buffers,
            grain_positions,
            grain_envelopes,
            formant_filters,
            analysis_window,
            synthesis_window,
            pitch_ratio,
            time_ratio,
            current_phase: 0.0,
        }
    }

    pub fn from_config(params: &serde_json::Value, format: AudioFormat) -> Result<Self, AudioError> {
        let config: PitchShiftConfig = serde_json::from_value(params.clone())
            .map_err(|e| AudioError::EffectConfig(format!("Invalid pitch shift config: {}", e)))?;
        Ok(Self::new(config, format))
    }

    

    pub fn format(&self) -> &AudioFormat {
        &self.format
    }

    fn extract_channel_f32(
        buffer: &AudioBuffer<N>,
        channel: usize,
    ) -> Result<Vec<f32>, AudioError> {
        let format = buffer.format();
        let sample_format = format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = format.channels as usize;
        let bytes_per_frame = bytes_per_sample * channels;
        let data = buffer.as_slice();
        
        let frames = data.len() / bytes_per_frame;
        let mut result = Vec::with_capacity(frames);
        
        for i in 0..frames {
            let frame_start = i * bytes_per_frame;
            let sample_start = frame_start + channel * bytes_per_sample;
            
            if sample_start + bytes_per_sample <= data.len() {
                let bytes = &data[sample_start..sample_start + bytes_per_sample];
                let sample = match sample_format {
                    SampleFormat::U8 => (bytes[0] as f32 - 128.0) / 128.0,
                    SampleFormat::S16 => i16::from_le_bytes([bytes[0], bytes[1]]) as f32 / 32768.0,
                    SampleFormat::S24 => {
                        let sign_extend = if bytes[2] & 0x80 != 0 { 0xFF } else { 0x00 };
                        let val = i32::from_le_bytes([bytes[0], bytes[1], bytes[2], sign_extend]);
                        val as f32 / 8388608.0
                    }
                    SampleFormat::S32 => {
                        i32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]]) as f32 / 2147483648.0
                    }
                    SampleFormat::F32 => {
                        f32::from_le_bytes([bytes[0], bytes[1], bytes[2], bytes[3]])
                    }
                    _ => return Err(AudioError::UnsupportedSampleFormat),
                };
                result.push(sample);
            }
        }
        
        Ok(result)
    }

    fn write_channel_f32(
        buffer: &mut AudioBuffer<N>,
        channel: usize,
        data: &[f32],
        dry: f32,
        wet: f32,
    ) -> Result<(), AudioError> {
        let format = buffer.format();
        let sample_format = format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = format.channels as usize;
        let bytes_per_frame = bytes_per_sample * channels;
        let buffer_data = buffer.as_mut_slice();
        
        let frames = buffer_data.len() / bytes_per_frame;
        let samples = frames.min(data.len());
        
        for (i, _) in data.iter().enumerate() { 
            let frame_start = i * bytes_per_frame;
            let sample_start = frame_start + channel * bytes_per_sample;
            
            if sample_start + bytes_per_sample <= buffer_data.len() {
                let original_bytes = &buffer_data[sample_start..sample_start + bytes_per_sample];
                let original = match sample_format {
                    SampleFormat::U8 => (original_bytes[0] as f32 - 128.0) / 128.0,
                    SampleFormat::S16 => i16::from_le_bytes([original_bytes[0], original_bytes[1]]) as f32 / 32768.0,
                    SampleFormat::S24 => {
                        let sign_extend = if original_bytes[2] & 0x80 != 0 { 0xFF } else { 0x00 };
                        let val = i32::from_le_bytes([original_bytes[0], original_bytes[1], original_bytes[2], sign_extend]);
                        val as f32 / 8388608.0
                    }
                    SampleFormat::S32 => {
                        i32::from_le_bytes([original_bytes[0], original_bytes[1], original_bytes[2], original_bytes[3]]) as f32 / 2147483648.0
                    }
                    SampleFormat::F32 => {
                        f32::from_le_bytes([original_bytes[0], original_bytes[1], original_bytes[2], original_bytes[3]])
                    }
                    _ => return Err(AudioError::UnsupportedSampleFormat),
                };
                
                let processed = if i < samples { data[i] } else { 0.0 };
                let mixed = (original * dry + processed * wet).clamp(-1.0, 1.0);
                
                let bytes = match sample_format {
                    SampleFormat::U8 => vec![((mixed + 1.0) * 127.5) as u8],
                    SampleFormat::S16 => ((mixed * 32767.0) as i16).to_le_bytes().to_vec(),
                    SampleFormat::S24 => {
                        let val = (mixed * 8388607.0) as i32;
                        val.to_le_bytes()[0..3].to_vec()
                    }
                    SampleFormat::S32 => ((mixed * 2147483647.0) as i32).to_le_bytes().to_vec(),
                    SampleFormat::F32 => mixed.to_le_bytes().to_vec(),
                    _ => return Err(AudioError::UnsupportedSampleFormat),
                };
                
                for (j, &byte) in bytes.iter().enumerate() {
                    if sample_start + j < buffer_data.len() {
                        buffer_data[sample_start + j] = byte;
                    }
                }
            }
        }
        
        Ok(())
    }

    fn process_phase_vocoder(&mut self, input: &[f32], channel: usize) -> Vec<f32> {
        let output_len = (input.len() as f32 * self.time_ratio) as usize;
        let mut output = vec![0.0; output_len];

        for start in (0..input.len().saturating_sub(self.fft_size)).step_by(self.hop_size) {
            let mut windowed = vec![0.0; self.fft_size];
            for i in 0..self.fft_size {
                if start + i < input.len() {
                    windowed[i] = input[start + i] * self.analysis_window[i];
                }
            }

            let spectrum = self.fft.forward(&windowed);
            let num_bins = spectrum.len();

            let bin_freq = self.format.sample_rate_hz() as f32 / self.fft_size as f32;
            let hop_factor = 2.0 * PI * self.hop_size as f32 / self.fft_size as f32;

            for (bin, _) in spectrum.iter().enumerate().take(num_bins) {
                let real = spectrum[bin].re;
                let imag = spectrum[bin].im;
                let magnitude = (real * real + imag * imag).sqrt();
                let phase = imag.atan2(real);

                let phase_diff = phase - self.last_phases[channel][bin];
                self.last_phases[channel][bin] = phase;
                
                let wrapped_phase_diff = ((phase_diff - hop_factor * bin as f32 + PI) % (2.0 * PI)) - PI;
                let frequency = bin_freq * (bin as f32 + wrapped_phase_diff / hop_factor);
                
                let shifted_bin = (bin as f32 * self.pitch_ratio) as usize;
                if shifted_bin < num_bins {
                    self.synthesis_magnitudes[channel][shifted_bin] = magnitude;
                    self.synthesis_frequencies[channel][shifted_bin] = frequency * self.pitch_ratio;
                }
            }

            let synthesis_hop_size = (self.hop_size as f32 * self.time_ratio) as usize;
            let synthesis_hop_factor = 2.0 * PI * synthesis_hop_size as f32 / self.fft_size as f32;
            self.current_phase += synthesis_hop_factor;
            
            let mut synthesis_spectrum = vec![num_complex::Complex32::new(0.0, 0.0); num_bins];

            synthesis_spectrum.iter_mut().enumerate().take(num_bins).for_each(|(bin, bin_ref)| {
                if self.synthesis_magnitudes[channel][bin] > 0.0 {
                    self.sum_phases[channel][bin] += synthesis_hop_size as f32;
                    let total_phase = self.sum_phases[channel][bin] + self.current_phase;
                    *bin_ref = num_complex::Complex32::new(
                        self.synthesis_magnitudes[channel][bin] * total_phase.cos(),
                        self.synthesis_magnitudes[channel][bin] * total_phase.sin(),
                    );
                }
            });

            let synthesized = self.fft.inverse(&synthesis_spectrum);
            let output_start = (start as f32 * self.time_ratio) as usize;
            for i in 0..self.fft_size {
                if output_start + i < output.len() {
                    output[output_start + i] += synthesized[i] * self.synthesis_window[i];
                }
            }
        }

        output
    }

    fn process_granular(&mut self, input: &[f32], channel: usize) -> Vec<f32> {
        let grain_size = self.grain_buffers[channel].len();
        let output_len = (input.len() as f32 * self.time_ratio) as usize;
        let mut output = vec![0.0; output_len];

        let mut grain_pos = self.grain_positions[channel];
        let mut output_pos = 0;

        while output_pos < output_len {
            let randomness = self.config.randomness;
            let random_offset = if randomness > 0.0 {
                (rand::random::<f32>() * 2.0 - 1.0) * grain_size as f32 * randomness
            } else {
                0.0
            };
            let read_pos = (grain_pos + random_offset).max(0.0) as usize;

            for i in 0..grain_size {
                self.grain_buffers[channel][i] = if read_pos + i < input.len() {
                    input[read_pos + i]
                } else {
                    0.0
                };
            }

            let step = self.pitch_ratio;
            let mut write_pos = output_pos as f32;
            let mut grain_sample_pos = 0.0;

            while write_pos < output_len as f32 && grain_sample_pos < grain_size as f32 {
                let idx = write_pos as usize;
                if idx < output_len {
                    let pos = grain_sample_pos as usize;
                    let fraction = grain_sample_pos - pos as f32;
                    
                    let sample1 = if pos < grain_size {
                        self.grain_buffers[channel][pos] * self.grain_envelopes[channel][pos]
                    } else {
                        0.0
                    };
                    let sample2 = if pos + 1 < grain_size {
                        self.grain_buffers[channel][pos + 1] * self.grain_envelopes[channel][pos + 1]
                    } else {
                        0.0
                    };
                    let sample = sample1 * (1.0 - fraction) + sample2 * fraction;
                    output[idx] += sample;
                }
                write_pos += 1.0;
                grain_sample_pos += step;
            }

            grain_pos += grain_size as f32 * (1.0 - self.config.overlap);
            output_pos += (grain_size as f32 * (1.0 - self.config.overlap) * self.time_ratio) as usize;
        }

        self.grain_positions[channel] = grain_pos;
        output
    }

    fn apply_formant_shift(&mut self, buffer: &mut [f32], channel: usize) {
        if self.config.formant_shift == 0.0 {
            return;
        }

        for sample in buffer.iter_mut() {
            let mut filtered = *sample;
            for filter in &mut self.formant_filters[channel] {
                filter.process(&mut filtered);
            }
            *sample = *sample * (1.0 - self.config.formant_shift.abs()) + filtered * self.config.formant_shift.abs();
        }
    }

    fn update_pitch_ratio(&mut self) {
        let semitones = self.config.pitch_shift + self.config.fine_tune / 100.0;
        self.pitch_ratio = 2.0f32.powf(semitones / 12.0);
        self.time_ratio = 1.0 / self.pitch_ratio;
    }
}

impl<const N: usize> AudioEffect<N> for PitchShift<N> {
    fn get_name(&self) -> String {
        "pitch_shift".to_string()
    }

    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError> {
        let channels = buffer.format().channels as usize;
        
        for ch in 0..channels {
            let channel_data = Self::extract_channel_f32(buffer, ch)?;

            let processed = match self.config.algorithm {
                PitchAlgorithm::PhaseVocoder => self.process_phase_vocoder(&channel_data, ch),
                PitchAlgorithm::Granular => self.process_granular(&channel_data, ch),
                PitchAlgorithm::PSOLA | PitchAlgorithm::FormantPreserving => {
                    let mut processed = self.process_granular(&channel_data, ch);
                    if self.config.algorithm == PitchAlgorithm::FormantPreserving {
                        self.apply_formant_shift(&mut processed, ch);
                    }
                    processed
                }
            };

            Self::write_channel_f32(buffer, ch, &processed, self.config.dry, self.config.wet)?;
        }

        Ok(())
    }

    fn reset(&mut self) {
        for channel_buffers in &mut self.last_phases {
            channel_buffers.fill(0.0);
        }
        for channel_buffers in &mut self.sum_phases {
            channel_buffers.fill(0.0);
        }
        for channel_buffers in &mut self.analysis_magnitudes {
            channel_buffers.fill(0.0);
        }
        for channel_buffers in &mut self.analysis_frequencies {
            channel_buffers.fill(0.0);
        }
        for channel_buffers in &mut self.synthesis_magnitudes {
            channel_buffers.fill(0.0);
        }
        for channel_buffers in &mut self.synthesis_frequencies {
            channel_buffers.fill(0.0);
        }
        for buffer in &mut self.grain_buffers {
            buffer.fill(0.0);
        }
        self.grain_positions.fill(0.0);
        for channel_filters in &mut self.formant_filters {
            for filter in channel_filters {
                filter.reset();
            }
        }
        self.current_phase = 0.0;
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        let new_config: PitchShiftConfig = serde_json::from_value(params)
            .map_err(|e| AudioError::EffectConfig(format!("Invalid pitch shift config: {}", e)))?;

        self.config = new_config;
        self.update_pitch_ratio();

        let sample_rate = self.format.sample_rate_hz() as f32;
        let new_grain_size = (self.config.grain_size / 1000.0 * sample_rate) as usize;
        
        if new_grain_size != self.grain_buffers[0].len() {
            let channels = self.format.channels as usize;
            self.grain_buffers = vec![vec![0.0; new_grain_size]; channels];
            self.grain_envelopes = vec![vec![0.0; new_grain_size]; channels];
            for ch in 0..channels {
                for i in 0..new_grain_size {
                    let pos = i as f32 / new_grain_size as f32;
                    self.grain_envelopes[ch][i] = 0.5 * (1.0 - (2.0 * PI * pos).cos());
                }
            }
        }

        let new_fft_size = self.config.window_size.next_power_of_two();
        if new_fft_size != self.fft_size {
            self.fft = FFT::new(new_fft_size);
            self.fft_size = new_fft_size;
            self.hop_size = ((1.0 - self.config.overlap) * new_fft_size as f32) as usize;
            self.analysis_window = self.fft.create_window(WindowType::Hann);
            self.synthesis_window = self.analysis_window.clone();

            let window_sum: f32 = self.analysis_window.iter().sum();
            if window_sum > 0.0 {
                for w in &mut self.synthesis_window {
                    *w /= window_sum / (new_fft_size as f32 / self.hop_size as f32);
                }
            }

            let channels = self.format.channels as usize;
            let num_bins = new_fft_size / 2 + 1;
            self.last_phases = vec![vec![0.0; num_bins]; channels];
            self.sum_phases = vec![vec![0.0; num_bins]; channels];
            self.analysis_magnitudes = vec![vec![0.0; num_bins]; channels];
            self.analysis_frequencies = vec![vec![0.0; num_bins]; channels];
            self.synthesis_magnitudes = vec![vec![0.0; num_bins]; channels];
            self.synthesis_frequencies = vec![vec![0.0; num_bins]; channels];
        }

        Ok(())
    }

    fn get_parameters(&self) -> serde_json::Value {
        serde_json::to_value(&self.config).unwrap_or(serde_json::json!({}))
    }

    fn get_latency(&self) -> usize {
        match self.config.algorithm {
            PitchAlgorithm::PhaseVocoder => self.fft_size,
            PitchAlgorithm::Granular => self.grain_buffers[0].len(),
            _ => self.fft_size,
        }
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics {
            gain_reduction_db: 0.0,
            envelope_db: 0.0,
            peak_level_db: 0.0,
            rms_level_db: 0.0,
        }
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        if let Some(params) = &configs.pitch_shift_params {
            let new_config: PitchShiftConfig = serde_json::from_value(params.clone().into())
                .map_err(|e| format!("Invalid pitch shift config: {}", e))?;
            self.config = new_config;
            self.update_pitch_ratio();
            Ok(())
        } else {
            Err("No pitch shift parameters in config".to_string())
        }
    }

    fn format(&self) -> &AudioFormat {
        &self.format
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        Box::new(self.clone())
    }
}


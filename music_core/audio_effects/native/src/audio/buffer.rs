//! Audio buffer for storing and processing audio data

use crate::audio::error::AudioError;
use crate::audio::sample_format::SampleFormat;
use crate::audio::resampler::Resampler;
use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::format::AudioFormat;

/// Audio buffer
#[derive(Debug, Clone)]
pub struct AudioBuffer<const N: usize> {
    data: [u8; N],
    format: AudioFormat,
    position: usize,
}

/// Trait for all audio effects
pub trait AudioEffect<const N: usize>: Send + Sync {
    fn process(&mut self, buffer: &mut AudioBuffer<{ N }>) -> Result<(), AudioError>;
    fn reset(&mut self);
    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError>;
    fn get_parameters(&self) -> serde_json::Value;
    fn get_latency(&self) -> usize;
    fn get_metrics(&self) -> CompressorMetrics;
    fn clone_box(&self) -> Box<dyn AudioEffect<N>>;
    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String>;
    fn get_name(&self) -> String;
    fn format(&self) -> &AudioFormat;
}

impl<const N: usize> AudioBuffer<N> {
    pub fn new(format: AudioFormat) -> Self {
        Self {
            data: [0; N],
            format,
            position: 0,
        }
    }

    pub fn samples(&self) -> usize {
        let bytes_per_sample = self.format.sample_format().bytes_per_sample();
        let channels = self.format.channels as usize;
        if channels == 0 || bytes_per_sample == 0 {
            return 0;
        }
        N / (bytes_per_sample * channels)
    }

    pub fn as_slice(&self) -> &[u8] {
        &self.data
    }

    pub fn as_mut_slice(&mut self) -> &mut [u8] {
        &mut self.data
    }

    pub fn channels(&self) -> usize {
        self.format.channels as usize
    }

    pub fn sample_rate_hz(&self) -> u32 {
        self.format.sample_rate_hz()
    }

    pub fn sample_rate(&self) -> f32 {
        self.format.sample_rate_hz() as f32
    }

    pub fn format(&self) -> &AudioFormat {
        &self.format
    }

    pub fn position(&self) -> usize {
        self.position
    }

    pub fn set_position(&mut self, pos: usize) {
        self.position = pos.min(self.samples());
    }

    pub fn to_interleaved(&self) -> Vec<f32> {
        let sample_format = self.format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = self.channels();
        let frames = self.samples();
        let frame_size = bytes_per_sample * channels;
        
        let mut result = Vec::with_capacity(frames * channels);
        
        for i in 0..frames {
            for ch in 0..channels {
                let sample_start = i * frame_size + ch * bytes_per_sample;
                if sample_start + bytes_per_sample <= N {
                    let sample = sample_format.normalize_to_f32(
                        &self.data[sample_start..sample_start + bytes_per_sample]
                    );
                    result.push(sample);
                } else {
                    result.push(0.0);
                }
            }
        }
        
        result
    }

    pub fn from_interleaved(interleaved: &[f32], format: AudioFormat) -> Option<Self> {
        let channels = format.channels as usize;
        if !interleaved.len().is_multiple_of(channels) {
            return None;
        }
        
        let sample_format = format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let total_bytes = interleaved.len() * bytes_per_sample;
        
        if total_bytes > N {
            return None;
        }
        
        let mut data = [0; N];
        let mut offset = 0;
        
        for &sample in interleaved {
            let bytes = sample_format.from_f32(sample);
            if offset + bytes.len() <= N {
                data[offset..offset + bytes.len()].copy_from_slice(&bytes);
                offset += bytes.len();
            } else {
                break;
            }
        }
        
        Some(Self {
            data,
            format,
            position: 0,
        })
    }

    pub fn from_slice(samples: &[f32], format: AudioFormat) -> Option<Self> {
        Self::from_interleaved(samples, format)
    }

    pub fn get_channel_slice_mut(&mut self, channel: usize) -> Option<&mut [f32]> {
        if channel >= self.channels() {
            return None;
        }
        
        let sample_format = self.format.sample_format();
        if sample_format != SampleFormat::F32 {
            return None;
        }
        
        let frames = self.samples();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let frame_size = bytes_per_sample * self.channels();
        let total_bytes = frames * frame_size;
        
        if total_bytes > self.data.len() {
            return None;
        }
        
        if !total_bytes.is_multiple_of(std::mem::size_of::<f32>()) {
            return None;
        }
        
        let f32_ptr = self.data.as_mut_ptr() as *mut f32;
        let total_f32_elements = total_bytes / std::mem::size_of::<f32>();
        
        unsafe {
            let f32_slice = std::slice::from_raw_parts_mut(f32_ptr, total_f32_elements);
            let start = channel * frames;
            let end = (channel + 1) * frames;
            if end <= f32_slice.len() {
                Some(&mut f32_slice[start..end])
            } else {
                None
            }
        }
    }

    /// Get two mutable channel slices at once. This avoids multiple simultaneous
    /// `&mut self` borrows when callers need two channels for stereo processing.
    pub fn get_two_channel_slices_mut(&mut self, a: usize, b: usize) -> Option<(&mut [f32], &mut [f32])> {
        if a >= self.channels() || b >= self.channels() || a == b {
            return None;
        }

        let sample_format = self.format.sample_format();
        if sample_format != SampleFormat::F32 {
            return None;
        }

        let frames = self.samples();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let frame_size = bytes_per_sample * self.channels();
        let total_bytes = frames * frame_size;

        if total_bytes > self.data.len() {
            return None;
        }

        if !total_bytes.is_multiple_of(std::mem::size_of::<f32>()) {
            return None;
        }

        let f32_ptr = self.data.as_mut_ptr() as *mut f32;
        let total_f32_elements = total_bytes / std::mem::size_of::<f32>();

        unsafe {
            let f32_slice = std::slice::from_raw_parts_mut(f32_ptr, total_f32_elements);
            let start_a = a * frames;
            let start_b = b * frames;
            // Ensure start_a < start_b for split_at_mut convenience
            if start_a < start_b {
                let (left_part, right_part) = f32_slice.split_at_mut(start_b);
                let left = &mut left_part[start_a..start_a + frames];
                let right = &mut right_part[0..frames];
                Some((left, right))
            } else {
                let (left_part, right_part) = f32_slice.split_at_mut(start_a);
                let right = &mut left_part[start_b..start_b + frames];
                let left = &mut right_part[0..frames];
                Some((left, right))
            }
        }
    }

    pub fn get_channel_slice(&self, channel: usize) -> Option<&[f32]> {
        if channel >= self.channels() {
            return None;
        }
        
        let sample_format = self.format.sample_format();
        if sample_format != SampleFormat::F32 {
            return None;
        }
        
        let frames = self.samples();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let frame_size = bytes_per_sample * self.channels();
        let total_bytes = frames * frame_size;
        
        if total_bytes > self.data.len() {
            return None;
        }
        
        if !total_bytes.is_multiple_of(std::mem::size_of::<f32>()) {
            return None;
        }
        
        let f32_ptr = self.data.as_ptr() as *const f32;
        let total_f32_elements = total_bytes / std::mem::size_of::<f32>();
        
        unsafe {
            let f32_slice = std::slice::from_raw_parts(f32_ptr, total_f32_elements);
            let start = channel * frames;
            let end = (channel + 1) * frames;
            if end <= f32_slice.len() {
                Some(&f32_slice[start..end])
            } else {
                None
            }
        }
    }

    pub fn calculate_peak(&self) -> f32 {
        let sample_format = self.format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = self.channels();
        let frames = self.samples();
        let frame_size = bytes_per_sample * channels;
        
        let mut peak: f32 = 0.0;
        
        for i in 0..frames {
            for ch in 0..channels {
                let sample_start = i * frame_size + ch * bytes_per_sample;
                if sample_start + bytes_per_sample <= N {
                    let sample = sample_format.normalize_to_f32(
                        &self.data[sample_start..sample_start + bytes_per_sample]
                    );
                    peak = peak.max(sample.abs());
                }
            }
        }
        
        peak
    }

    pub fn calculate_rms(&self) -> f32 {
        let sample_format = self.format.sample_format();
        let bytes_per_sample = sample_format.bytes_per_sample();
        let channels = self.channels();
        let frames = self.samples();
        let frame_size = bytes_per_sample * channels;
        
        let mut sum_squares = 0.0;
        let mut count = 0;
        
        for i in 0..frames {
            for ch in 0..channels {
                let sample_start = i * frame_size + ch * bytes_per_sample;
                if sample_start + bytes_per_sample <= N {
                    let sample = sample_format.normalize_to_f32(
                        &self.data[sample_start..sample_start + bytes_per_sample]
                    );
                    sum_squares += sample * sample;
                    count += 1;
                }
            }
        }
        
        if count > 0 {
            (sum_squares / count as f32).sqrt()
        } else {
            0.0
        }
    }
}

impl<const N: usize> Default for AudioBuffer<N> {
    fn default() -> Self {
        Self::new(AudioFormat::default())
    }
}
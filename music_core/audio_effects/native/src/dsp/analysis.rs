//! Audio analysis utilities
//! Pitch detection, spectral analysis, loudness measurement

use crate::audio::buffer::AudioBuffer;
use crate::dsp::fft::{FFT, WindowType};
use crate::dsp::utils::utils::*;
use crate::AudioError;

// ============================================================================
// SPECTRAL ANALYSIS
// ============================================================================

/// Spectral analyzer
pub struct SpectralAnalyzer<const N: usize> {
    fft: FFT,
    window_size: usize,
    hop_size: usize,
    window: Vec<f32>,
}

impl<const N: usize> SpectralAnalyzer<N> {
    pub fn new(window_size: usize, hop_size: usize) -> Self {
        let fft = FFT::new(window_size);
        let window = create_window(window_size, WindowType::Hann);
        Self { 
            fft, 
            window_size, 
            hop_size, 
            window 
        }
    }

    /// Analyze mono signal
    pub fn analyze(&self, signal: &[f32]) -> Vec<Vec<f32>> {
        let mut frames = Vec::new();
        let mut start = 0;
        
        while start + self.window_size <= signal.len() {
            // Apply window
            let frame: Vec<f32> = signal[start..start + self.window_size]
                .iter()
                .zip(self.window.iter())
                .map(|(&s, &w)| s * w)
                .collect();
            
            // FFT
            let spectrum = self.fft.forward(&frame);
            
            // Get magnitudes
            let magnitudes: Vec<f32> = spectrum
                .iter()
                .map(|c| (c.re * c.re + c.im * c.im).sqrt())
                .collect();
            
            frames.push(magnitudes);
            start += self.hop_size;
        }
        
        frames
    }

    /// Analyze stereo buffer
    pub fn analyze_buffer(&self, buffer: &AudioBuffer<N>) -> Result<Vec<Vec<Vec<f32>>>, AudioError> {
        let channels = buffer.format().channels as usize;
        let mut result = Vec::with_capacity(channels);
        
        for ch in 0..channels {
            let channel_data = extract_channel(buffer, ch)?;
            let spectra = self.analyze(&channel_data);
            result.push(spectra);
        }
        
        Ok(result)
    }

    /// Compute average spectrum across all frames
    pub fn average_spectrum(&self, signal: &[f32]) -> Vec<f32> {
        let frames = self.analyze(signal);
        if frames.is_empty() {
            return vec![0.0; self.window_size / 2 + 1];
        }
        
        let mut avg = vec![0.0; frames[0].len()];
        for frame in &frames {
            for (i, &mag) in frame.iter().enumerate() {
                if i < avg.len() {
                    avg[i] += mag;
                }
            }
        }
        
        for mag in &mut avg {
            *mag /= frames.len() as f32;
        }
        
        avg
    }
}

// ============================================================================
// PITCH DETECTOR
// ============================================================================

/// Pitch detector wrapper
pub struct PitchDetector<const N: usize> {
    sample_rate: f32,
    min_freq: f32,
    max_freq: f32,
}

impl<const N: usize> PitchDetector<N> {
    pub fn new(sample_rate: f32, min_freq: f32, max_freq: f32) -> Self {
        Self { 
            sample_rate, 
            min_freq: min_freq.max(20.0), 
            max_freq: max_freq.min(20000.0) 
        }
    }

    pub fn detect(&self, signal: &[f32]) -> Option<f32> {
        yin_pitch_detection(signal, self.sample_rate, self.min_freq, self.max_freq)
    }
    
    pub fn detect_buffer(&self, buffer: &AudioBuffer<N>, channel: usize) -> Result<Option<f32>, AudioError> {
        let channel_data = extract_channel(buffer, channel)?;
        Ok(self.detect(&channel_data))
    }
}

// ============================================================================
// LOUDNESS ANALYZER
// ============================================================================

/// Loudness analyzer
pub struct LoudnessAnalyzer<const N: usize> {
    window_size: usize,
}

impl<const N: usize> LoudnessAnalyzer<N> {
    pub fn new(window_size: usize) -> Self {
        Self { window_size: window_size.max(64) }
    }

    /// Analyze loudness over time
    pub fn analyze(&self, signal: &[f32], _sample_rate: f32) -> Vec<f32> {
        let hop_size = self.window_size / 2;
        let mut loudness = Vec::new();
        let mut start = 0;
        
        while start < signal.len() {
            let end = (start + self.window_size).min(signal.len());
            let window = &signal[start..end];
            let rms = calculate_rms(window);
            loudness.push(linear_to_db(rms));
            start += hop_size;
        }
        
        loudness
    }
    
    /// Calculate overall loudness (RMS in dB)
    pub fn overall_loudness(&self, signal: &[f32]) -> f32 {
        let rms = calculate_rms(signal);
        linear_to_db(rms)
    }
    
    /// Calculate peak loudness
    pub fn peak_loudness(&self, signal: &[f32]) -> f32 {
        let peak = signal.iter().map(|&x| x.abs()).fold(0.0, f32::max);
        linear_to_db(peak)
    }
}

/// Root Mean Square — среднеквадратичное значение сигнала
pub fn rms(data: &[f32]) -> f32 {
    if data.is_empty() {
        return 0.0;
    }
    let sum_sq: f32 = data.iter().map(|&x| x * x).sum();
    (sum_sq / data.len() as f32).sqrt()
}

/// Peak — максимальное абсолютное значение в сигнале
pub fn peak(data: &[f32]) -> f32 {
    data.iter()
        .map(|&x| x.abs())
        .fold(0.0f32, f32::max)
}

/// Crest Factor — отношение пика к RMS
pub fn crest_factor(data: &[f32]) -> f32 {
    let rms_val = rms(data);
    let peak_val = peak(data);
    if rms_val > 0.0 {
        peak_val / rms_val
    } else {
        1.0
    }
}

/// Dynamic Range — разница между пиком и RMS в децибелах
pub fn dynamic_range(data: &[f32]) -> f32 {
    let peak_val = peak(data);
    let rms_val = rms(data);
    if rms_val > 0.0 {
        20.0 * (peak_val / rms_val).log10()
    } else {
        0.0
    }
}
// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

/// Create window function
fn create_window(size: usize, window_type: WindowType) -> Vec<f32> {
    if size == 0 {
        return vec![];
    }
    
    let mut window = vec![0.0; size];
    let n_minus_1 = (size - 1) as f32;
    
    match window_type {
        WindowType::Hann => {
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                let n = i as f32 / n_minus_1;
                *w = 0.5 * (1.0 - (2.0 * std::f32::consts::PI * n).cos());
            });
        }
        WindowType::Hamming => {
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                let n = i as f32 / n_minus_1;
                *w = 0.54 - 0.46 * (2.0 * std::f32::consts::PI * n).cos();
            });
        }
        WindowType::Blackman => {
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                let n = i as f32 / n_minus_1;
                *w = 0.42 - 0.5 * (2.0 * std::f32::consts::PI * n).cos() + 0.08 * (4.0 * std::f32::consts::PI * n).cos();
            });
        }
        _ => window.fill(1.0),
    }
    
    window
}

/// Extract single channel from AudioBuffer
fn extract_channel<const N: usize>(
    buffer: &AudioBuffer<N>, 
    channel: usize
) -> Result<Vec<f32>, AudioError> {
    let channels = buffer.format().channels as usize;
    if channel >= channels {
        return Err(AudioError::InvalidParameter(format!(
            "Channel {} out of range (0-{})",
            channel, channels - 1
        )));
    }
    
    let sample_format = buffer.format().sample_format();
    let bytes_per_sample = sample_format.bytes_per_sample();
    let bytes_per_frame = bytes_per_sample * channels;
    // Use AudioBuffer::samples() which returns number of frames available
    let frames = buffer.samples();
    
    let mut result = Vec::with_capacity(frames);
    let data = buffer.as_slice();
    
    for i in 0..frames {
        let frame_start = i * bytes_per_frame;
        let sample_start = frame_start + channel * bytes_per_sample;
        
        if sample_start + bytes_per_sample <= data.len() {
            let sample_data = &data[sample_start..sample_start + bytes_per_sample];
            let sample = sample_format.normalize_to_f32(sample_data);
            result.push(sample);
        }
    }
    
    Ok(result)
}
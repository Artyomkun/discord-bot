//! Fast Fourier Transform (FFT) and spectral analysis
//! Optimized FFT implementations for real-time processing

use crate::dsp::utils::utils::*;
use bincode::{Decode, Encode};
use rustfft::{Fft, FftPlanner};
use serde::{Deserialize, Deserializer, Serialize, Serializer};
use std::f32::consts::PI;
use std::fmt;
use std::sync::Arc;
use serde::ser::SerializeStruct;

type ComplexF32 = rustfft::num_complex::Complex<f32>;

/// Window function type
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize, Encode, Decode)]
pub enum WindowType {
    Rectangular,
    Hann,
    Hamming,
    Blackman,
    BlackmanHarris,
    Kaiser,
    FlatTop,
    Gaussian
}

/// Fast Fourier Transform
pub struct FFT {
    fft_forward: Arc<dyn Fft<f32>>,
    fft_inverse: Arc<dyn Fft<f32>>,
    size: usize,
    scratch_forward: Vec<ComplexF32>,
    scratch_inverse: Vec<ComplexF32>,
}

impl fmt::Debug for FFT {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("FFT")
            .field("size", &self.size)
            .finish()
    }
}

impl Clone for FFT {
    fn clone(&self) -> Self {
        Self::new(self.size)
    }
}

impl Serialize for FFT {
    fn serialize<S>(&self, serializer: S) -> Result<S::Ok, S::Error>
    where
        S: Serializer,
    {
        let mut state = serializer.serialize_struct("FFT", 1)?;
        state.serialize_field("size", &(self.size as u64))?;
        state.end()
    }
}

impl<'de> Deserialize<'de> for FFT {
    fn deserialize<D>(deserializer: D) -> Result<Self, D::Error>
    where
        D: Deserializer<'de>,
    {
        #[derive(Deserialize)]
        struct FFTDef {
            size: u64,
        }

        let helper = FFTDef::deserialize(deserializer)?;
        Ok(FFT::new(helper.size as usize))
    }
}

impl Encode for FFT {
    fn encode<E: bincode::enc::Encoder>(&self, encoder: &mut E) -> Result<(), bincode::error::EncodeError> {
        let size = self.size as u64;
        size.encode(encoder)
    }
}

impl<C> Decode<C> for FFT {
    fn decode<D: bincode::de::Decoder<Context = C>>(decoder: &mut D) -> Result<Self, bincode::error::DecodeError> {
        let size = u64::decode(decoder)?;
        Ok(FFT::new(size as usize))
    }
}

impl<'de, C> bincode::de::BorrowDecode<'de, C> for FFT {
    fn borrow_decode<D: bincode::de::Decoder<Context = C>>(decoder: &mut D) -> Result<Self, bincode::error::DecodeError> {
        Self::decode(decoder)
    }
}

impl FFT {
    pub fn new(size: usize) -> Self {
        assert!(size.is_power_of_two(), "FFT size must be power of two");

        let mut planner = FftPlanner::new();
        let fft_forward = planner.plan_fft_forward(size);
        let fft_inverse = planner.plan_fft_inverse(size);
        let scratch_forward_len = fft_forward.get_inplace_scratch_len();
        let scratch_inverse_len = fft_inverse.get_inplace_scratch_len();

        Self {
            fft_forward: fft_forward.clone(),
            fft_inverse: fft_inverse.clone(),
            size,
            scratch_forward: vec![ComplexF32::new(0.0, 0.0); scratch_forward_len],
            scratch_inverse: vec![ComplexF32::new(0.0, 0.0); scratch_inverse_len],
        }
    }

    pub fn forward(&self, input: &[f32]) -> Vec<ComplexF32> {
        assert_eq!(input.len(), self.size);
        let mut buffer: Vec<ComplexF32> = input.iter().map(|&x| ComplexF32::new(x, 0.0)).collect();
        self.fft_forward
            .process_with_scratch(&mut buffer, &mut self.scratch_forward.clone());
        let norm = 1.0 / (self.size as f32).sqrt();
        for sample in &mut buffer {
            *sample *= norm;
        }
        buffer
    }

    pub fn inverse(&self, spectrum: &[ComplexF32]) -> Vec<f32> {
        assert_eq!(spectrum.len(), self.size);
        let mut buffer = spectrum.to_vec();
        self.fft_inverse
            .process_with_scratch(&mut buffer, &mut self.scratch_inverse.clone());
        let norm = 1.0 / (self.size as f32).sqrt();
        buffer.iter().map(|c| c.re * norm).collect()
    }

    pub fn create_window(&self, window_type: WindowType) -> Vec<f32> {
        create_window_with_size(self.size, window_type)
    }

    pub fn stft(&mut self, signal: &[f32], hop_size: usize, window: &[f32]) -> Vec<Vec<ComplexF32>> {
        assert_eq!(window.len(), self.size);
        let mut frames = Vec::new();
        let mut start = 0;
        while start + self.size <= signal.len() {
            let mut frame: Vec<ComplexF32> = signal[start..start + self.size]
                .iter()
                .zip(window.iter())
                .map(|(&s, &w)| ComplexF32::new(s * w, 0.0))
                .collect();
            self.fft_forward
                .process_with_scratch(&mut frame, &mut self.scratch_forward);
            let norm = 1.0 / (self.size as f32).sqrt();
            for sample in &mut frame {
                *sample *= norm;
            }
            frames.push(frame);
            start += hop_size;
        }
        frames
    }

    pub fn istft(&mut self, frames: &[Vec<ComplexF32>], hop_size: usize, window: &[f32]) -> Vec<f32> {
        assert_eq!(window.len(), self.size);
        let output_len = (frames.len() - 1) * hop_size + self.size;
        let mut output = vec![0.0; output_len];
        let mut window_sq_sum = vec![0.0; output_len];
        
        for (i, frame) in frames.iter().enumerate() {
            assert_eq!(frame.len(), self.size);
            let mut time_frame = frame.to_vec();
            self.fft_inverse
                .process_with_scratch(&mut time_frame, &mut self.scratch_inverse);
            let norm = 1.0 / (self.size as f32).sqrt();
            let time_real: Vec<f32> = time_frame.iter().map(|c| c.re * norm).collect();
            let start = i * hop_size;
            for j in 0..self.size {
                if start + j < output_len {
                    output[start + j] += time_real[j] * window[j];
                    window_sq_sum[start + j] += window[j] * window[j];
                }
            }
        }
        
        // Normalize by window squared sum
        for i in 0..output_len {
            if window_sq_sum[i] > 1e-10 {
                output[i] /= window_sq_sum[i];
            }
        }
        output
    }

    pub fn power_spectrum(spectrum: &[ComplexF32]) -> Vec<f32> {
        spectrum.iter().map(|c| c.norm_sqr()).collect()
    }

    pub fn magnitude_spectrum(spectrum: &[ComplexF32]) -> Vec<f32> {
        spectrum.iter().map(|c| c.norm()).collect()
    }

    pub fn phase_spectrum(spectrum: &[ComplexF32]) -> Vec<f32> {
        spectrum.iter().map(|c| c.im.atan2(c.re)).collect()
    }

    pub fn spectrum_to_db(spectrum: &[f32], reference: f32) -> Vec<f32> {
        spectrum
            .iter()
            .map(|&mag| {
                if reference > 0.0 && mag > 0.0 {
                    20.0 * (mag / reference).log10()
                } else {
                    -144.0
                }
            })
            .collect()
    }

    pub fn frequency_bins(&self, sample_rate: f32) -> Vec<f32> {
        (0..self.size / 2 + 1)
            .map(|i| i as f32 * sample_rate / self.size as f32)
            .collect()
    }

    pub fn resize(&mut self, new_size: usize) {
        if new_size != self.size && new_size.is_power_of_two() {
            let mut planner = FftPlanner::new();
            self.fft_forward = planner.plan_fft_forward(new_size);
            self.fft_inverse = planner.plan_fft_inverse(new_size);
            self.size = new_size;
            self.scratch_forward = vec![ComplexF32::new(0.0, 0.0); self.fft_forward.get_inplace_scratch_len()];
            self.scratch_inverse = vec![ComplexF32::new(0.0, 0.0); self.fft_inverse.get_inplace_scratch_len()];
        }
    }
    
    pub fn size(&self) -> usize {
        self.size
    }
}

pub fn create_window_with_size(size: usize, window_type: WindowType) -> Vec<f32> {
    if size <= 1 {
        return vec![1.0; size];
    }
    
    let mut window = vec![0.0; size];
    match window_type {
        WindowType::Rectangular => window.fill(1.0),
        WindowType::Hann => {
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = i as f32 / (size - 1) as f32;
                    *w = 0.5 * (1.0 - (2.0 * PI * n).cos());
                });
        }
        WindowType::Hamming => {
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = i as f32 / (size - 1) as f32;
                    *w = 0.54 - 0.46 * (2.0 * PI * n).cos();
                });
        }
        WindowType::Blackman => {
            let a0 = 0.42;
            let a1 = 0.5;
            let a2 = 0.08;
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = i as f32 / (size - 1) as f32;
                    *w = a0 - a1 * (2.0 * PI * n).cos() + a2 * (4.0 * PI * n).cos();
                });
        }
        WindowType::BlackmanHarris => {
            let a0 = 0.35875;
            let a1 = 0.48829;
            let a2 = 0.14128;
            let a3 = 0.01168;
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = i as f32 / (size - 1) as f32;
                    *w = a0 - a1 * (2.0 * PI * n).cos()
                        + a2 * (4.0 * PI * n).cos()
                        - a3 * (6.0 * PI * n).cos();
                });
        }
        WindowType::FlatTop => {
            let a0 = 1.0;
            let a1 = 1.93;
            let a2 = 1.29;
            let a3 = 0.388;
            let a4 = 0.032;
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = i as f32 / (size - 1) as f32;
                    *w = a0 - a1 * (2.0 * PI * n).cos()
                        + a2 * (4.0 * PI * n).cos()
                        - a3 * (6.0 * PI * n).cos()
                        + a4 * (8.0 * PI * n).cos();
                });
        }
        WindowType::Gaussian => {
            let alpha = 2.5;
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = (i as f32 - (size - 1) as f32 / 2.0) / ((size - 1) as f32 / 2.0);
                    *w = (-0.5 * (alpha * n).powi(2)).exp();
                });
        }
        WindowType::Kaiser => {
            let beta = 12.0;
            let i0_beta = modified_bessel_i0(beta);
            window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                    let n = (i as f32 - (size - 1) as f32 / 2.0) / ((size - 1) as f32 / 2.0);
                    let arg = beta * (1.0 - n * n).max(0.0).sqrt();
                    *w = modified_bessel_i0(arg) / i0_beta;
                });
        }
    }
    window
}

/// Modified Bessel function I0(x)
fn modified_bessel_i0(x: f32) -> f32 {
    let x_abs = x.abs();
    if x_abs < 3.75 {
        let t = x_abs / 3.75;
        let t2 = t * t;
        1.0 + 3.5156229 * t2
            + 3.0899424 * t2 * t2
            + 1.2067492 * t2.powi(3)
            + 0.2659732 * t2.powi(4)
            + 0.360768e-1 * t2.powi(5)
            + 0.45813e-2 * t2.powi(6)
    } else {
        let t = 3.75 / x_abs;
        (x_abs.exp() / x_abs.sqrt())
            * (0.398_942_3
                + 0.1328592e-1 * t
                + 0.225319e-2 * t * t
                - 0.157565e-2 * t.powi(3)
                + 0.916281e-2 * t.powi(4)
                - 0.2057706e-1 * t.powi(5)
                + 0.2635537e-1 * t.powi(6)
                - 0.1647633e-1 * t.powi(7)
                + 0.392377e-2 * t.powi(8))
    }
}

/// Create mel filter bank
pub fn mel_filter_bank(
    num_filters: usize,
    fft_size: usize,
    sample_rate: f32,
    min_freq: f32,
    max_freq: f32,
) -> Vec<Vec<f32>> {
    let min_mel = hz_to_mel(min_freq);
    let max_mel = hz_to_mel(max_freq);
    let mel_step = (max_mel - min_mel) / (num_filters + 1) as f32;
    
    let mel_points: Vec<f32> = (0..num_filters + 2)
        .map(|i| min_mel + i as f32 * mel_step)
        .collect();
    
    let freq_points: Vec<f32> = mel_points.iter().map(|&mel| mel_to_hz(mel)).collect();
    let bin_points: Vec<usize> = freq_points
        .iter()
        .map(|&freq| (freq * fft_size as f32 / sample_rate) as usize)
        .collect();
    
    let mut filter_bank = vec![vec![0.0; fft_size / 2 + 1]; num_filters];
    
    for i in 0..num_filters {
        let start = bin_points[i];
        let center = bin_points[i + 1];
        let end = bin_points[i + 2];
        
        for j in start..center {
            let weight = (j - start) as f32 / (center - start) as f32;
            if j < filter_bank[i].len() {
                filter_bank[i][j] = weight;
            }
        }
        
        for j in center..end {
            let weight = (end - j) as f32 / (end - center) as f32;
            if j < filter_bank[i].len() {
                filter_bank[i][j] = weight;
            }
        }
    }
    
    filter_bank
}
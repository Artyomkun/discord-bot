//! Audio converter for format conversion

use crate::audio::error::AudioError;
use crate::audio::sample_format::SampleFormat;
use crate::audio::resampler::Resampler;

/// Resample quality
#[derive(Debug, Clone, Copy, PartialEq, Default)]
pub enum ResampleQuality {
    #[default]
    Fast,
    Medium,
    High,
    Best,
}

pub struct AudioConverter {
    quality: ResampleQuality,
}

impl AudioConverter {
    pub fn new(quality: ResampleQuality) -> Self {
        Self { quality }
    }

    pub fn convert_format(
        &self,
        input_data: &[u8],
        input_format: SampleFormat,
        output_format: SampleFormat,
        _channels: usize,
    ) -> Result<Vec<u8>, AudioError> {
        if input_format == output_format {
            return Ok(input_data.to_vec());
        }

        match (input_format, output_format) {
            (SampleFormat::F32, SampleFormat::S16) => self.f32_to_i16(input_data),
            (SampleFormat::S16, SampleFormat::F32) => self.i16_to_f32(input_data),
            (SampleFormat::F32, SampleFormat::U8) => self.f32_to_u8(input_data),
            (SampleFormat::U8, SampleFormat::F32) => self.u8_to_f32(input_data),
            (SampleFormat::S16, SampleFormat::U8) => self.i16_to_u8(input_data),
            (SampleFormat::U8, SampleFormat::S16) => self.u8_to_i16(input_data),
            (SampleFormat::F32, SampleFormat::F64) => self.f32_to_f64(input_data),
            (SampleFormat::F64, SampleFormat::F32) => self.f64_to_f32(input_data),
            (SampleFormat::S32, SampleFormat::F32) => self.s32_to_f32(input_data),
            (SampleFormat::F32, SampleFormat::S32) => self.f32_to_s32(input_data),
            _ => Err(AudioError::ConversionError(format!(
                "Unsupported conversion: {:?} -> {:?}",
                input_format, output_format
            ))),
        }
    }

    pub fn resample(
        &self,
        input_data: &[f32],
        input_rate: u32,
        output_rate: u32,
        _channels: usize,
    ) -> Result<Vec<f32>, AudioError> {
        if input_rate == output_rate {
            return Ok(input_data.to_vec());
        }
        
        if input_rate == 0 || output_rate == 0 {
            return Err(AudioError::InvalidParameter("Sample rate cannot be zero".to_string()));
        }

        match self.quality {
            ResampleQuality::Fast => self.resample_linear(input_data, input_rate, output_rate),
            ResampleQuality::Medium => self.resample_cubic(input_data, input_rate, output_rate),
            ResampleQuality::High => self.resample_sinc_short(input_data, input_rate, output_rate),
            ResampleQuality::Best => self.resample_sinc_long(input_data, input_rate, output_rate),
        }
    }

    // ============================================================================
    // БЕЗОПАСНЫЕ КОНВЕРТЕРЫ (без unsafe)
    // ============================================================================

    fn f32_to_i16(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(4) {
            return Err(AudioError::InvalidData("F32 data length must be multiple of 4".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() / 2);
        
        for chunk in input.chunks_exact(4) {
            let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
            let clamped = sample.clamp(-1.0, 1.0);
            let int_sample = (clamped * 32767.0).round() as i16;
            output.extend_from_slice(&int_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    fn i16_to_f32(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(2) {
            return Err(AudioError::InvalidData("I16 data length must be multiple of 2".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() * 2);
        
        for chunk in input.chunks_exact(2) {
            let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
            let float_sample = sample as f32 / 32768.0;
            output.extend_from_slice(&float_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    fn f32_to_u8(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(4) {
            return Err(AudioError::InvalidData("F32 data length must be multiple of 4".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() / 4);
        
        for chunk in input.chunks_exact(4) {
            let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
            let clamped = sample.clamp(-1.0, 1.0);
            let byte_sample = ((clamped + 1.0) * 127.5).round() as u8;
            output.push(byte_sample);
        }
        
        Ok(output)
    }

    fn u8_to_f32(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        let mut output = Vec::with_capacity(input.len() * 4);
        
        for &byte in input {
            let float_sample = (byte as f32 / 127.5) - 1.0;
            output.extend_from_slice(&float_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    fn i16_to_u8(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(2) {
            return Err(AudioError::InvalidData("I16 data length must be multiple of 2".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() / 2);
        
        for chunk in input.chunks_exact(2) {
            let sample = i16::from_le_bytes([chunk[0], chunk[1]]);
            let normalized = sample as f32 / 32768.0;
            let byte_sample = ((normalized + 1.0) * 127.5).round() as u8;
            output.push(byte_sample);
        }
        
        Ok(output)
    }

    fn u8_to_i16(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        let mut output = Vec::with_capacity(input.len() * 2);
        
        for &byte in input {
            let normalized = (byte as f32 / 127.5) - 1.0;
            let int_sample = (normalized * 32767.0).round() as i16;
            output.extend_from_slice(&int_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    fn f32_to_f64(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(4) {
            return Err(AudioError::InvalidData("F32 data length must be multiple of 4".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() * 2);
        
        for chunk in input.chunks_exact(4) {
            let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
            output.extend_from_slice(&(sample as f64).to_le_bytes());
        }
        
        Ok(output)
    }

    fn f64_to_f32(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(8) {
            return Err(AudioError::InvalidData("F64 data length must be multiple of 8".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len() / 2);
        
        for chunk in input.chunks_exact(8) {
            let sample = f64::from_le_bytes([
                chunk[0], chunk[1], chunk[2], chunk[3],
                chunk[4], chunk[5], chunk[6], chunk[7]
            ]);
            output.extend_from_slice(&(sample as f32).to_le_bytes());
        }
        
        Ok(output)
    }

    fn s32_to_f32(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(4) {
            return Err(AudioError::InvalidData("S32 data length must be multiple of 4".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len());
        
        for chunk in input.chunks_exact(4) {
            let sample = i32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
            let float_sample = sample as f32 / 2147483648.0;
            output.extend_from_slice(&float_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    fn f32_to_s32(&self, input: &[u8]) -> Result<Vec<u8>, AudioError> {
        if !input.len().is_multiple_of(4) {
            return Err(AudioError::InvalidData("F32 data length must be multiple of 4".to_string()));
        }
        
        let mut output = Vec::with_capacity(input.len());
        
        for chunk in input.chunks_exact(4) {
            let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
            let clamped = sample.clamp(-1.0, 1.0);
            let int_sample = (clamped * 2147483647.0).round() as i32;
            output.extend_from_slice(&int_sample.to_le_bytes());
        }
        
        Ok(output)
    }

    // ============================================================================
    // РЕСЕМПЛИНГ
    // ============================================================================

    fn resample_linear(
        &self,
        input: &[f32],
        input_rate: u32,
        output_rate: u32,
    ) -> Result<Vec<f32>, AudioError> {
        if input.is_empty() {
            return Ok(Vec::new());
        }

        let ratio = input_rate as f64 / output_rate as f64;
        let output_len = ((input.len() - 1) as f64 / ratio).ceil() as usize;
        let mut output = Vec::with_capacity(output_len);

        for i in 0..output_len {
            let src_pos = i as f64 * ratio;
            let idx = src_pos.floor() as usize;
            let frac = (src_pos - idx as f64) as f32;

            if idx + 1 < input.len() {
                let sample = input[idx] * (1.0 - frac) + input[idx + 1] * frac;
                output.push(sample);
            } else if idx < input.len() {
                output.push(input[idx]);
            } else {
                output.push(0.0);
            }
        }

        Ok(output)
    }

    fn resample_cubic(
        &self,
        input: &[f32],
        input_rate: u32,
        output_rate: u32,
    ) -> Result<Vec<f32>, AudioError> {
        if input.is_empty() {
            return Ok(Vec::new());
        }

        let ratio = input_rate as f64 / output_rate as f64;
        let output_len = ((input.len() - 1) as f64 / ratio).ceil() as usize;
        let mut output = Vec::with_capacity(output_len);

        for i in 0..output_len {
            let src_pos = i as f64 * ratio;
            let idx = src_pos.floor() as usize;
            let frac = (src_pos - idx as f64) as f32;

            let p0 = if idx > 0 { input[idx - 1] } else { input[0] };
            let p1 = input[idx];
            let p2 = if idx + 1 < input.len() { input[idx + 1] } else { input[input.len() - 1] };
            let p3 = if idx + 2 < input.len() { input[idx + 2] } else { input[input.len() - 1] };

            let sample = cubic_interpolate(p0, p1, p2, p3, frac);
            output.push(sample);
        }

        Ok(output)
    }

    fn resample_sinc_short(
        &self,
        input: &[f32],
        input_rate: u32,
        output_rate: u32,
    ) -> Result<Vec<f32>, AudioError> {
        self.resample_sinc(input, input_rate, output_rate, 16)
    }

    fn resample_sinc_long(
        &self,
        input: &[f32],
        input_rate: u32,
        output_rate: u32,
    ) -> Result<Vec<f32>, AudioError> {
        self.resample_sinc(input, input_rate, output_rate, 64)
    }

    fn resample_sinc(
        &self,
        input: &[f32],
        input_rate: u32,
        output_rate: u32,
        window_size: usize,
    ) -> Result<Vec<f32>, AudioError> {
        if input.is_empty() {
            return Ok(Vec::new());
        }

        let ratio = input_rate as f64 / output_rate as f64;
        let output_len = ((input.len() - 1) as f64 / ratio).ceil() as usize;
        let mut output = Vec::with_capacity(output_len);

        let half_window = window_size / 2;
        let pi = std::f32::consts::PI;

        for i in 0..output_len {
            let src_pos = i as f64 * ratio;
            let mut sum = 0.0;
            let mut weight_sum = 0.0;

            let start = -(half_window as isize);
            let end = half_window as isize;

            for j in start..=end {
                let sample_idx = src_pos as isize + j;
                if sample_idx >= 0 && (sample_idx as usize) < input.len() {
                    let sample_pos = sample_idx as usize;
                    let distance = (src_pos - sample_idx as f64).abs() as f32;
                    let weight = self.sinc(distance * pi);
                    sum += input[sample_pos] * weight;
                    weight_sum += weight;
                }
            }

            output.push(if weight_sum > 1e-6 { sum / weight_sum } else { 0.0 });
        }

        Ok(output)
    }

    #[inline]
    fn sinc(&self, x: f32) -> f32 {
        if x.abs() < 1e-6 {
            1.0
        } else {
            x.sin() / x
        }
    }
}

impl Default for AudioConverter {
    fn default() -> Self {
        Self::new(ResampleQuality::Medium)
    }
}

#[inline]
fn cubic_interpolate(y0: f32, y1: f32, y2: f32, y3: f32, mu: f32) -> f32 {
    let mu2 = mu * mu;
    let a0 = y3 - y2 - y0 + y1;
    let a1 = y0 - y1 - a0;
    let a2 = y2 - y0;
    let a3 = y1;

    a0 * mu * mu2 + a1 * mu2 + a2 * mu + a3
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_f32_to_i16_conversion() {
        let converter = AudioConverter::default();
        let input_f32: Vec<f32> = vec![0.5, -0.5, 1.0, -1.0];
        let mut bytes = Vec::new();
        for &s in &input_f32 {
            bytes.extend_from_slice(&s.to_le_bytes());
        }
        
        let result = converter.f32_to_i16(&bytes).unwrap();
        assert_eq!(result.len(), input_f32.len() * 2);
    }

    #[test]
    fn test_resample_linear() {
        let converter = AudioConverter::default();
        let input: Vec<f32> = (0..100).map(|i| (i as f32 / 100.0).sin()).collect();
        
        let result = converter.resample_linear(&input, 48000, 44100).unwrap();
        assert!(!result.is_empty());
        assert!(result.len() < input.len());
    }

    #[test]
    fn test_resample_cubic() {
        let converter = AudioConverter::default();
        let input: Vec<f32> = (0..100).map(|i| (i as f32 / 100.0).sin()).collect();
        
        let result = converter.resample_cubic(&input, 48000, 44100).unwrap();
        assert!(!result.is_empty());
    }
}
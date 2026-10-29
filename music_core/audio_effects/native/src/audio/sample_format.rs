use crate::dsp::analysis::*;
use crate::dsp::fft::*;
use crate::dsp::utils::utils::*;

/// Поддерживаемые форматы семплов
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum SampleFormat {
    U8,
    S16,
    S24,
    S32,
    F32,
    F64,
    PlanarU8,
    PlanarS16,
    PlanarS24,
    PlanarS32,
    PlanarF32,
    PlanarF64,
}

impl SampleFormat {
    pub fn bytes_per_sample(&self) -> usize {
        match self {
            SampleFormat::U8 | SampleFormat::PlanarU8 => 1,
            SampleFormat::S16 | SampleFormat::PlanarS16 => 2,
            SampleFormat::S24 | SampleFormat::PlanarS24 => 3,
            SampleFormat::S32 | SampleFormat::PlanarS32 => 4,
            SampleFormat::F32 | SampleFormat::PlanarF32 => 4,
            SampleFormat::F64 | SampleFormat::PlanarF64 => 8,
        }
    }

    /// Get bit depth
    pub fn bits_per_sample(&self) -> u8 {
        match self {
            SampleFormat::U8 | SampleFormat::PlanarU8 => 8,
            SampleFormat::S16 | SampleFormat::PlanarS16 => 16,
            SampleFormat::S24 | SampleFormat::PlanarS24 => 24,
            SampleFormat::S32 | SampleFormat::PlanarS32 => 32,
            SampleFormat::F32 | SampleFormat::PlanarF32 => 32,
            SampleFormat::F64 | SampleFormat::PlanarF64 => 64,
        }
    }

    /// Check if format is planar
    pub fn is_planar(&self) -> bool {
        matches!(
            self,
            SampleFormat::PlanarU8
                | SampleFormat::PlanarS16
                | SampleFormat::PlanarS24
                | SampleFormat::PlanarS32
                | SampleFormat::PlanarF32
                | SampleFormat::PlanarF64
        )
    }

    /// Check if format is interleaved
    pub fn is_interleaved(&self) -> bool {
        !self.is_planar()
    }

    /// Check if format is floating point
    pub fn is_floating(&self) -> bool {
        matches!(
            self,
            SampleFormat::F32 | SampleFormat::F64 | SampleFormat::PlanarF32 | SampleFormat::PlanarF64
        )
    }

    /// Check if format is integer
    pub fn is_integer(&self) -> bool {
        !self.is_floating()
    }

    /// Get maximum value for integer formats
    pub fn max_integer_value(&self) -> f64 {
        match self {
            SampleFormat::S16 | SampleFormat::PlanarS16 => 32767.0,
            SampleFormat::S24 | SampleFormat::PlanarS24 => 8388607.0,
            SampleFormat::S32 | SampleFormat::PlanarS32 => 2147483647.0,
            _ => 1.0,
        }
    }

    /// Normalize value to range [-1.0, 1.0]
    pub fn normalize_to_f32(&self, sample: &[u8]) -> f32 {
        match self {
            SampleFormat::U8 | SampleFormat::PlanarU8 => {
                let value = sample[0] as f32;
                (value - 127.5) / 127.5
            }
            SampleFormat::S16 | SampleFormat::PlanarS16 => {
                let value = i16::from_le_bytes([sample[0], sample[1]]);
                value as f32 / 32768.0
            }
            SampleFormat::S24 | SampleFormat::PlanarS24 => {
                let sign_extend = if sample[2] & 0x80 != 0 { 0xFF } else { 0x00 };
                let bytes = [sample[0], sample[1], sample[2], sign_extend];
                let value = i32::from_le_bytes(bytes);
                value as f32 / 8388608.0
            }
            SampleFormat::S32 | SampleFormat::PlanarS32 => {
                let value = i32::from_le_bytes([sample[0], sample[1], sample[2], sample[3]]);
                value as f32 / 2147483648.0
            }
            SampleFormat::F32 | SampleFormat::PlanarF32 => {
                f32::from_le_bytes([sample[0], sample[1], sample[2], sample[3]])
            }
            SampleFormat::F64 | SampleFormat::PlanarF64 => {
                let value = f64::from_le_bytes([
                    sample[0], sample[1], sample[2], sample[3],
                    sample[4], sample[5], sample[6], sample[7],
                ]);
                value as f32
            }
        }
    }

    /// Convert f32 sample to target format
    pub fn from_f32(&self, sample: f32) -> Vec<u8> {
        let clamped = sample.clamp(-1.0, 1.0);
        
        match self {
            SampleFormat::U8 | SampleFormat::PlanarU8 => {
                let value = (clamped * 127.5 + 127.5) as u8;
                vec![value]
            }
            SampleFormat::S16 | SampleFormat::PlanarS16 => {
                let value = (clamped * 32767.0) as i16;
                value.to_le_bytes().to_vec()
            }
            SampleFormat::S24 | SampleFormat::PlanarS24 => {
                let value = (clamped * 8388607.0) as i32;
                let bytes = value.to_le_bytes();
                bytes[0..3].to_vec()
            }
            SampleFormat::S32 | SampleFormat::PlanarS32 => {
                let value = (clamped * 2147483647.0) as i32;
                value.to_le_bytes().to_vec()
            }
            SampleFormat::F32 | SampleFormat::PlanarF32 => {
                clamped.to_le_bytes().to_vec()
            }
            SampleFormat::F64 | SampleFormat::PlanarF64 => {
                (clamped as f64).to_le_bytes().to_vec()
            }
        }
    }

    /// Convert to interleaved format
    pub fn to_interleaved(&self) -> Option<SampleFormat> {
        match self {
            SampleFormat::PlanarU8 => Some(SampleFormat::U8),
            SampleFormat::PlanarS16 => Some(SampleFormat::S16),
            SampleFormat::PlanarS24 => Some(SampleFormat::S24),
            SampleFormat::PlanarS32 => Some(SampleFormat::S32),
            SampleFormat::PlanarF32 => Some(SampleFormat::F32),
            SampleFormat::PlanarF64 => Some(SampleFormat::F64),
            _ => None,
        }
    }

    /// Convert to planar format
    pub fn to_planar(&self) -> Option<SampleFormat> {
        match self {
            SampleFormat::U8 => Some(SampleFormat::PlanarU8),
            SampleFormat::S16 => Some(SampleFormat::PlanarS16),
            SampleFormat::S24 => Some(SampleFormat::PlanarS24),
            SampleFormat::S32 => Some(SampleFormat::PlanarS32),
            SampleFormat::F32 => Some(SampleFormat::PlanarF32),
            SampleFormat::F64 => Some(SampleFormat::PlanarF64),
            _ => None,
        }
    }
}
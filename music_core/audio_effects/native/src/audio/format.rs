//! Audio formats and specifications

use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use crate::audio::sample_format::SampleFormat;
use crate::audio::error::AudioError;

/// Sample rate enumeration
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize, Encode, Decode, Default)]
pub enum SampleRate {
    Hz8000,
    Hz11025,
    Hz16000,
    Hz22050,
    Hz32000,
    Hz44100,
    #[default]
    Hz48000,
    Hz88200,
    Hz96000,
    Hz176400,
    Hz192000,
    Hz352800,
    Hz384000,
    Custom(u32),
}

impl SampleRate {
    pub fn value(&self) -> u32 {
        match self {
            SampleRate::Hz8000 => 8000,
            SampleRate::Hz11025 => 11025,
            SampleRate::Hz16000 => 16000,
            SampleRate::Hz22050 => 22050,
            SampleRate::Hz32000 => 32000,
            SampleRate::Hz44100 => 44100,
            SampleRate::Hz48000 => 48000,
            SampleRate::Hz88200 => 88200,
            SampleRate::Hz96000 => 96000,
            SampleRate::Hz176400 => 176400,
            SampleRate::Hz192000 => 192000,
            SampleRate::Hz352800 => 352800,
            SampleRate::Hz384000 => 384000,
            SampleRate::Custom(rate) => *rate,
        }
    }

    pub fn is_standard(&self) -> bool {
        matches!(
            self,
            SampleRate::Hz44100
                | SampleRate::Hz48000
                | SampleRate::Hz88200
                | SampleRate::Hz96000
                | SampleRate::Hz192000
        )
    }

    pub fn as_f32(&self) -> f32 {
        self.value() as f32
    }

    pub fn to_nearest_standard(&self) -> SampleRate {
        let rate = self.value();
        let standards = [
            (8000, SampleRate::Hz8000),
            (11025, SampleRate::Hz11025),
            (16000, SampleRate::Hz16000),
            (22050, SampleRate::Hz22050),
            (32000, SampleRate::Hz32000),
            (44100, SampleRate::Hz44100),
            (48000, SampleRate::Hz48000),
            (88200, SampleRate::Hz88200),
            (96000, SampleRate::Hz96000),
            (176400, SampleRate::Hz176400),
            (192000, SampleRate::Hz192000),
            (352800, SampleRate::Hz352800),
            (384000, SampleRate::Hz384000),
        ];
        
        let mut nearest = SampleRate::Hz44100;
        let mut min_diff = u32::MAX;
        
        for (std_rate, layout) in standards {
            let diff = rate.abs_diff(std_rate);
            if diff < min_diff {
                min_diff = diff;
                nearest = layout;
            }
        }
        
        nearest
    }

    pub fn period(&self) -> f32 {
        let rate = self.value();
        if rate == 0 {
            return 0.0;
        }
        1.0 / rate as f32
    }

    pub fn period_in_samples(&self, frequency: f32) -> f32 {
        let rate = self.value();
        if frequency <= 0.0 || rate == 0 {
            return 0.0;
        }
        rate as f32 / frequency
    }
}

impl From<u32> for SampleRate {
    fn from(rate: u32) -> Self {
        match rate {
            8000 => SampleRate::Hz8000,
            11025 => SampleRate::Hz11025,
            16000 => SampleRate::Hz16000,
            22050 => SampleRate::Hz22050,
            32000 => SampleRate::Hz32000,
            44100 => SampleRate::Hz44100,
            48000 => SampleRate::Hz48000,
            88200 => SampleRate::Hz88200,
            96000 => SampleRate::Hz96000,
            176400 => SampleRate::Hz176400,
            192000 => SampleRate::Hz192000,
            352800 => SampleRate::Hz352800,
            384000 => SampleRate::Hz384000,
            _ => SampleRate::Custom(rate),
        }
    }
}

/// Channel layout
#[derive(Debug, Clone, PartialEq, Eq, Hash, Serialize, Deserialize, Encode, Decode, Default)]
pub enum ChannelLayout {
    Mono,
    #[default]
    Stereo,
    Stereo21,
    Quad,
    Surround50,
    Surround51,
    Surround61,
    Surround71,
    Ambisonics1,
    Ambisonics2,
    Ambisonics3,
    Custom(String),
}

impl ChannelLayout {
    pub fn channels(&self) -> u8 {
        match self {
            ChannelLayout::Mono => 1,
            ChannelLayout::Stereo => 2,
            ChannelLayout::Stereo21 => 3,
            ChannelLayout::Quad => 4,
            ChannelLayout::Surround50 => 5,
            ChannelLayout::Surround51 => 6,
            ChannelLayout::Surround61 => 7,
            ChannelLayout::Surround71 => 8,
            ChannelLayout::Ambisonics1 => 4,
            ChannelLayout::Ambisonics2 => 9,
            ChannelLayout::Ambisonics3 => 16,
            ChannelLayout::Custom(names) => {
                if names.is_empty() { 0 } else { names.split(',').count() as u8 }
            }
        }
    }

    pub fn channel_names(&self) -> Vec<String> {
        match self {
            ChannelLayout::Mono => vec!["Mono".to_string()],
            ChannelLayout::Stereo => vec!["Left".to_string(), "Right".to_string()],
            ChannelLayout::Stereo21 => {
                vec!["Left".to_string(), "Right".to_string(), "LFE".to_string()]
            }
            ChannelLayout::Quad => vec![
                "Front Left".to_string(),
                "Front Right".to_string(),
                "Rear Left".to_string(),
                "Rear Right".to_string(),
            ],
            ChannelLayout::Surround50 => {
                vec![
                    "Front Left".to_string(),
                    "Front Right".to_string(),
                    "Center".to_string(),
                    "Rear Left".to_string(),
                    "Rear Right".to_string(),
                ]
            }
            ChannelLayout::Surround51 => {
                vec![
                    "Front Left".to_string(),
                    "Front Right".to_string(),
                    "Center".to_string(),
                    "LFE".to_string(),
                    "Rear Left".to_string(),
                    "Rear Right".to_string(),
                ]
            }
            ChannelLayout::Surround61 => vec![
                "Front Left".to_string(),
                "Front Right".to_string(),
                "Center".to_string(),
                "LFE".to_string(),
                "Rear Left".to_string(),
                "Rear Right".to_string(),
                "Rear Center".to_string(),
            ],
            ChannelLayout::Surround71 => vec![
                "Front Left".to_string(),
                "Front Right".to_string(),
                "Center".to_string(),
                "LFE".to_string(),
                "Rear Left".to_string(),
                "Rear Right".to_string(),
                "Side Left".to_string(),
                "Side Right".to_string(),
            ],
            ChannelLayout::Ambisonics1 => {
                vec!["W".to_string(), "X".to_string(), "Y".to_string(), "Z".to_string()]
            }
            ChannelLayout::Ambisonics2 => vec![
                "W".to_string(), "X".to_string(), "Y".to_string(), "Z".to_string(),
                "R".to_string(), "S".to_string(), "T".to_string(), "U".to_string(), "V".to_string(),
            ],
            ChannelLayout::Ambisonics3 => (0..16)
                .map(|i| match i {
                    0 => "W", 1 => "X", 2 => "Y", 3 => "Z",
                    4 => "R", 5 => "S", 6 => "T", 7 => "U",
                    8 => "V", 9 => "K", 10 => "L", 11 => "M",
                    12 => "N", 13 => "O", 14 => "P", 15 => "Q",
                    _ => "Unknown",
                }.to_string())
                .collect(),
            ChannelLayout::Custom(names) => {
                if names.is_empty() {
                    vec![]
                } else {
                    names.split(',').map(|s| s.trim().to_string()).collect()
                }
            }
        }
    }

    pub fn is_surround(&self) -> bool {
        matches!(
            self,
            ChannelLayout::Surround50
                | ChannelLayout::Surround51
                | ChannelLayout::Surround61
                | ChannelLayout::Surround71
        )
    }

    pub fn is_ambisonics(&self) -> bool {
        matches!(
            self,
            ChannelLayout::Ambisonics1 | ChannelLayout::Ambisonics2 | ChannelLayout::Ambisonics3
        )
    }

    pub fn channel_mask(&self) -> u32 {
        match self {
            ChannelLayout::Mono => 0x4,
            ChannelLayout::Stereo => 0x1 | 0x2,
            ChannelLayout::Stereo21 => 0x1 | 0x2 | 0x8,
            ChannelLayout::Quad => 0x1 | 0x2 | 0x10 | 0x20,
            ChannelLayout::Surround50 => 0x1 | 0x2 | 0x4 | 0x10 | 0x20,
            ChannelLayout::Surround51 => 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20,
            ChannelLayout::Surround61 => 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x100,
            ChannelLayout::Surround71 => 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20 | 0x40 | 0x80,
            _ => 0,
        }
    }
}

/// Audio format
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize, Encode, Decode)]
pub struct AudioFormat {
    pub sample_rate: SampleRate,
    pub channels: u8,
    pub bit_depth: u8,
    pub floating_point: bool,
    pub channel_layout: ChannelLayout,
    pub little_endian: bool,
    pub planar: bool,
}

impl AudioFormat {
    pub fn new(sample_rate: SampleRate, channels: u8) -> Self {
        assert!(channels > 0, "Channels must be > 0");
        assert!(sample_rate.value() > 0, "Sample rate must be > 0");
        
        let channel_layout = match channels {
            1 => ChannelLayout::Mono,
            2 => ChannelLayout::Stereo,
            3 => ChannelLayout::Stereo21,
            4 => ChannelLayout::Quad,
            5 => ChannelLayout::Surround50,
            6 => ChannelLayout::Surround51,
            7 => ChannelLayout::Surround61,
            8 => ChannelLayout::Surround71,
            _ => ChannelLayout::Custom(format!("{}ch", channels)),
        };
        
        Self {
            sample_rate,
            channels,
            bit_depth: 32,
            floating_point: true,
            channel_layout,
            little_endian: true,
            planar: false,
        }
    }

    pub fn new_with_bit_depth(
        sample_rate: SampleRate,
        channels: u8,
        bit_depth: u8,
        floating_point: bool,
    ) -> Self {
        assert!(channels > 0, "Channels must be > 0");
        assert!(sample_rate.value() > 0, "Sample rate must be > 0");
        assert!((8..=64).contains(&bit_depth), "Bit depth must be between 8 and 64");
        
        let channel_layout = match channels {
            1 => ChannelLayout::Mono,
            2 => ChannelLayout::Stereo,
            3 => ChannelLayout::Stereo21,
            4 => ChannelLayout::Quad,
            5 => ChannelLayout::Surround50,
            6 => ChannelLayout::Surround51,
            7 => ChannelLayout::Surround61,
            8 => ChannelLayout::Surround71,
            _ => ChannelLayout::Custom(format!("{}ch", channels)),
        };
        
        Self {
            sample_rate,
            channels,
            bit_depth,
            floating_point,
            channel_layout,
            little_endian: true,
            planar: false,
        }
    }

    pub fn cd_quality() -> Self {
        Self {
            sample_rate: SampleRate::Hz44100,
            channels: 2,
            bit_depth: 16,
            floating_point: false,
            channel_layout: ChannelLayout::Stereo,
            little_endian: true,
            planar: false,
        }
    }

    pub fn dvd_quality() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            channels: 6,
            bit_depth: 24,
            floating_point: false,
            channel_layout: ChannelLayout::Surround51,
            little_endian: true,
            planar: false,
        }
    }

    pub fn studio_quality() -> Self {
        Self {
            sample_rate: SampleRate::Hz96000,
            channels: 2,
            bit_depth: 32,
            floating_point: true,
            channel_layout: ChannelLayout::Stereo,
            little_endian: true,
            planar: false,
        }
    }

    pub fn sample_rate_hz(&self) -> u32 {
        self.sample_rate.value()
    }

    pub fn sample_rate_f32(&self) -> f32 {
        self.sample_rate_hz() as f32
    }

    pub fn bytes_per_sample(&self) -> usize {
        let bytes = (self.bit_depth as usize).div_ceil(8);
        bytes.max(1)
    }

    pub fn bytes_per_frame(&self) -> usize {
        self.bytes_per_sample() * self.channels as usize
    }

    pub fn bitrate(&self) -> u32 {
        self.sample_rate_hz() * self.channels as u32 * self.bit_depth as u32
    }

    pub fn bitrate_kbps(&self) -> u32 {
        self.bitrate() / 1000
    }

    pub fn calculate_size(&self, duration_seconds: f32) -> usize {
        let samples = (duration_seconds * self.sample_rate_hz() as f32) as usize;
        samples * self.channels as usize * self.bytes_per_sample()
    }

    pub fn calculate_duration(&self, size_bytes: usize) -> f32 {
        let bytes_per_frame = self.bytes_per_frame();
        if bytes_per_frame == 0 {
            return 0.0;
        }
        let frames = size_bytes / bytes_per_frame;
        frames as f32 / self.sample_rate_hz() as f32
    }

    pub fn calculate_frames(&self, data_len: usize) -> usize {
        self.bytes_per_frame().checked_div(data_len).unwrap_or(0)
    }

    pub fn is_compatible(&self, other: &AudioFormat) -> bool {
        self.sample_rate == other.sample_rate
            && self.channels == other.channels
            && self.bit_depth == other.bit_depth
            && self.floating_point == other.floating_point
    }

    pub fn is_valid(&self) -> bool {
        self.channels > 0
            && self.sample_rate.value() > 0
            && self.bit_depth >= 8
            && self.bit_depth <= 64
            && self.channels == self.channel_layout.channels()
    }

    pub fn validate(&self) -> Result<(), AudioError> {
        if self.channels == 0 {
            return Err(AudioError::InvalidFormat("Channel count cannot be zero".to_string()));
        }
        if self.sample_rate.value() == 0 {
            return Err(AudioError::InvalidFormat("Sample rate cannot be zero".to_string()));
        }
        if self.bit_depth < 8 || self.bit_depth > 64 {
            return Err(AudioError::InvalidFormat(format!("Invalid bit depth: {}", self.bit_depth)));
        }
        if self.channels != self.channel_layout.channels() {
            return Err(AudioError::InvalidFormat(format!(
                "Channel count mismatch: {} vs {}",
                self.channels, self.channel_layout.channels()
            )));
        }
        Ok(())
    }

    pub fn to_planar(&self) -> Self {
        let mut format = self.clone();
        format.planar = true;
        format
    }

    pub fn to_interleaved(&self) -> Self {
        let mut format = self.clone();
        format.planar = false;
        format
    }

    pub fn sample_format(&self) -> SampleFormat {
        if self.floating_point {
            match self.bit_depth {
                32 => SampleFormat::F32,
                64 => SampleFormat::F64,
                _ => SampleFormat::F32,
            }
        } else {
            match self.bit_depth {
                8 => SampleFormat::U8,
                16 => SampleFormat::S16,
                24 => SampleFormat::S24,
                32 => SampleFormat::S32,
                _ => SampleFormat::F32,
            }
        }
    }

    pub fn set_bit_depth(mut self, bit_depth: u8, floating_point: bool) -> Self {
        assert!((8..=64).contains(&bit_depth), "Invalid bit depth");
        self.bit_depth = bit_depth;
        self.floating_point = floating_point;
        self
    }

    pub fn set_channel_layout(mut self, layout: ChannelLayout) -> Self {
        assert_eq!(self.channels, layout.channels(), "Channel count mismatch");
        self.channel_layout = layout;
        self
    }
}

impl Default for AudioFormat {
    fn default() -> Self {
        Self {
            sample_rate: SampleRate::Hz48000,
            channels: 2,
            bit_depth: 32,
            floating_point: true,
            channel_layout: ChannelLayout::Stereo,
            little_endian: true,
            planar: false,
        }
    }
}

/// Format converter
#[derive(Debug, Clone)]
pub struct FormatConverter {
    source: AudioFormat,
    target: AudioFormat,
}

impl FormatConverter {
    pub fn new(source: AudioFormat, target: AudioFormat) -> Self {
        Self { source, target }
    }

    pub fn needs_conversion(&self) -> bool {
        !self.source.is_compatible(&self.target) || self.source.planar != self.target.planar
    }

    pub fn size_ratio(&self) -> f32 {
        let source_size = self.source.bytes_per_frame();
        let target_size = self.target.bytes_per_frame();
        if source_size == 0 {
            return 1.0;
        }
        target_size as f32 / source_size as f32
    }

    fn calculate_frames(&self, data_len: usize) -> Result<usize, AudioError> {
        let bytes_per_frame = self.source.bytes_per_frame();
        if bytes_per_frame == 0 {
            return Err(AudioError::InvalidFormat("Bytes per frame is zero".to_string()));
        }
        if !data_len.is_multiple_of(bytes_per_frame) {
            return Err(AudioError::InvalidData(format!(
                "Data length {} not multiple of frame size {}",
                data_len, bytes_per_frame
            )));
        }
        Ok(data_len / bytes_per_frame)
    }

    pub fn convert_buffer(&self, source_data: &[u8]) -> Result<Vec<u8>, AudioError> {
        let _frames = self.calculate_frames(source_data.len())?;

        if !self.needs_conversion() {
            return Ok(source_data.to_vec());
        }

        if self.source.is_compatible(&self.target) {
            if self.source.planar != self.target.planar {
                return self.convert_planar_interleaved(source_data);
            }
            return Ok(source_data.to_vec());
        }

        Err(AudioError::ConversionError(
            format!(
                "Conversion from {:?} to {:?} not implemented",
                self.source, self.target
            )
        ))
    }

    fn convert_planar_interleaved(&self, source_data: &[u8]) -> Result<Vec<u8>, AudioError> {
        let bytes_per_sample = self.source.bytes_per_sample();
        let channels = self.source.channels as usize;
        
        if bytes_per_sample == 0 || channels == 0 {
            return Err(AudioError::InvalidFormat("Invalid format parameters".to_string()));
        }
        
        let frames = source_data.len() / (bytes_per_sample * channels);
        
        if frames == 0 {
            return Ok(Vec::new());
        }

        let mut target_data = vec![0u8; source_data.len()];

        if self.source.planar && !self.target.planar {
            for frame in 0..frames {
                for ch in 0..channels {
                    let src_offset = (ch * frames + frame) * bytes_per_sample;
                    let dst_offset = (frame * channels + ch) * bytes_per_sample;
                    
                    for b in 0..bytes_per_sample {
                        if src_offset + b < source_data.len() && dst_offset + b < target_data.len() {
                            target_data[dst_offset + b] = source_data[src_offset + b];
                        }
                    }
                }
            }
        } else if !self.source.planar && self.target.planar {
            for frame in 0..frames {
                for ch in 0..channels {
                    let src_offset = (frame * channels + ch) * bytes_per_sample;
                    let dst_offset = (ch * frames + frame) * bytes_per_sample;
                    
                    for b in 0..bytes_per_sample {
                        if src_offset + b < source_data.len() && dst_offset + b < target_data.len() {
                            target_data[dst_offset + b] = source_data[src_offset + b];
                        }
                    }
                }
            }
        }

        Ok(target_data)
    }
}
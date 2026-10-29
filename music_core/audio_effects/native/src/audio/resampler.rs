use crate::audio::converter::ResampleQuality;

pub struct Resampler {
    quality: ResampleQuality,
    input_rate: u32,
    output_rate: u32
}

impl Resampler {
    pub fn new(quality: ResampleQuality) -> Self {
        Self {
            quality,
            input_rate: 44100,
            output_rate: 44100,
        }
    }
}

impl Default for Resampler {
    fn default() -> Self {
        Self::new(ResampleQuality::Medium)
    }
}
pub mod utils {
    /// Calculate duration in seconds from samples
    pub fn calculate_duration(samples: usize, sample_rate: u32, channels: u32) -> f32 {
        if sample_rate == 0 || channels == 0 {
            return 0.0;
        }
        samples as f32 / (sample_rate as f32 * channels as f32)
    }

    /// Calculate number of samples from duration
    pub fn calculate_samples(duration: f32, sample_rate: u32, channels: u32) -> usize {
        if duration <= 0.0 {
            return 0;
        }
        (duration * sample_rate as f32 * channels as f32) as usize
    }

    /// Calculate bitrate
    pub fn calculate_bitrate(sample_rate: u32, channels: u32, bits_per_sample: u32) -> u32 {
        sample_rate * channels * bits_per_sample
    }
}
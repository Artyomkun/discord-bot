use crate::audio::AudioBuffer;

pub trait DspEffect<const N: usize>: Send + Sync {
    fn process(&mut self, buffer: &mut AudioBuffer<N>);
    fn reset(&mut self);
    fn set_sample_rate(&mut self, sample_rate: f32);
    fn set_channels(&mut self, channels: usize);
}
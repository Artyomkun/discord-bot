use crate::audio::buffer::AudioBuffer;
use crate::dsp::effect::DspEffect;

/// DSP processor for effect chain
pub struct DspProcessor<const N: usize> {
    effects: Vec<Box<dyn DspEffect<N> + Send + Sync>>,
    sample_rate: f32,
    channels: usize,
}

impl DspProcessor<1024> {
    pub fn new(sample_rate: f32, channels: usize) -> Self {
        Self { effects: Vec::new(), sample_rate, channels }
    }

    pub fn add_effect(&mut self, effect: Box<dyn DspEffect<1024> + Send + Sync>) {
        self.effects.push(effect);
    }

    pub fn process(&mut self, buffer: &mut AudioBuffer<1024>) {
        for effect in &mut self.effects {
            effect.process(buffer);
        }
    }

    pub fn reset(&mut self) {
        for effect in &mut self.effects {
            effect.reset();
        }
    }

    pub fn set_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        for effect in &mut self.effects {
            effect.set_sample_rate(sample_rate);
        }
    }

    pub fn set_channels(&mut self, channels: usize) {
        self.channels = channels;
        for effect in &mut self.effects {
            effect.set_channels(channels);
        }
    }
}
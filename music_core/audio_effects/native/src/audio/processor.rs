use crate::audio::buffer::AudioBuffer;
use crate::audio::error::AudioError;
use crate::audio::format::AudioFormat;
use crate::effects::effect::{EffectConfig, EffectChain};

#[cfg(feature = "buffer_1024")]
pub const N: usize = 1024;

/// Audio processor - основной класс для работы с цепочкой эффектов
pub struct AudioProcessor<const N: usize> {
    chain: EffectChain<N>,
}

impl<const N: usize> AudioProcessor<N> {
    pub fn new(configs: Vec<EffectConfig<N>>, format: AudioFormat) -> Result<Self, AudioError> {
        let chain = EffectChain::new(configs, format)?;
        Ok(Self { chain })
    }

    pub fn update_effects(&mut self, configs: Vec<EffectConfig<N>>) -> Result<(), AudioError> {
        self.chain.update(configs, self.chain.format().clone())
    }

    pub fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        self.chain.process(buffer)
    }

    pub fn format(&self) -> &AudioFormat {
        self.chain.format()
    }

    pub fn get_metrics(&self) -> serde_json::Value {
        serde_json::json!({
            "latency": self.chain.get_latency(),
            "effects_count": self.chain.get_configs().len(),
            "bypass": self.chain.is_bypass()
        })
    }

    pub fn reset(&mut self) {
        self.chain.reset();
    }
    
    pub fn set_bypass(&mut self, bypass: bool) {
        self.chain.set_bypass(bypass);
    }
}
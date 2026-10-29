use bincode::{Encode, Decode};
use serde::{Serialize, Deserialize};
use crate::effects::{
    Compressor, Equalizer, Reverb, Delay, 
    Distortion, Chorus, PitchShift, JsonValue
};
use crate::dsp::compressor::CompressorMetrics;
use crate::audio::{AudioError, AudioBuffer, AudioFormat};
use crate::audio::AudioEffect;

#[cfg(feature = "buffer_1024")]
const N: usize = 1024;

/// Effect type enum (container для всех эффектов)
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub enum EffectType<const N: usize> {
    Compressor(Compressor<N>),
    Equalizer(Equalizer<N>),
    Reverb(Box<Reverb<N>>),
    Delay(Delay<N>),
    Distortion(Distortion<N>),
    Chorus(Chorus<N>),
    PitchShift(Box<PitchShift<N>>),
}

// Реализация AudioEffect для EffectType (делегирование)
impl<const N: usize> AudioEffect<N> for EffectType<N> {
    fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        match self {
            EffectType::Compressor(c) => c.process(buffer),
            EffectType::Reverb(r) => r.process(buffer),
            EffectType::Delay(d) => d.process(buffer),
            EffectType::Distortion(d) => d.process(buffer),
            EffectType::Chorus(c) => c.process(buffer),
            EffectType::PitchShift(p) => p.process(buffer),
            EffectType::Equalizer(e) => e.process(buffer),
        }
    }

    fn get_latency(&self) -> usize {
        match self {
            EffectType::Compressor(c) => c.get_latency(),
            EffectType::Reverb(r) => r.get_latency(),
            EffectType::Delay(d) => d.get_latency(),
            EffectType::Distortion(d) => d.get_latency(),
            EffectType::Chorus(c) => c.get_latency(),
            EffectType::PitchShift(p) => p.get_latency(),
            EffectType::Equalizer(e) => e.get_latency(),
        }
    }

    fn reset(&mut self) {
        match self {
            EffectType::Compressor(c) => c.reset(),
            EffectType::Reverb(r) => r.reset(),
            EffectType::Delay(d) => d.reset(),
            EffectType::Distortion(d) => d.reset(),
            EffectType::Chorus(c) => c.reset(),
            EffectType::PitchShift(p) => p.reset(),
            EffectType::Equalizer(e) => e.reset(),
        }
    }

    fn update_parameters(&mut self, params: serde_json::Value) -> Result<(), AudioError> {
        match self {
            EffectType::Compressor(c) => c.update_parameters(params),
            EffectType::Equalizer(e) => e.update_parameters(params),
            EffectType::Reverb(r) => r.update_parameters(params),
            EffectType::Delay(d) => d.update_parameters(params),
            EffectType::Distortion(d) => d.update_parameters(params),
            EffectType::Chorus(c) => c.update_parameters(params),
            EffectType::PitchShift(p) => p.update_parameters(params),
        }
    }

    fn get_parameters(&self) -> serde_json::Value {
        match self {
            EffectType::Compressor(c) => c.get_parameters(),
            EffectType::Equalizer(e) => e.get_parameters(),
            EffectType::Reverb(r) => r.get_parameters(),
            EffectType::Delay(d) => d.get_parameters(),
            EffectType::Distortion(d) => d.get_parameters(),
            EffectType::Chorus(c) => c.get_parameters(),
            EffectType::PitchShift(p) => p.get_parameters(),
        }
    }

    fn get_metrics(&self) -> CompressorMetrics {
        match self {
            EffectType::Compressor(c) => c.get_metrics(),
            EffectType::Equalizer(e) => e.get_metrics(),
            EffectType::Reverb(r) => r.get_metrics(),
            EffectType::Delay(d) => d.get_metrics(),
            EffectType::Distortion(d) => d.get_metrics(),
            EffectType::Chorus(c) => c.get_metrics(),
            EffectType::PitchShift(p) => p.get_metrics(),
        }
    }

    fn clone_box(&self) -> Box<dyn AudioEffect<N>> {
        match self {
            EffectType::Compressor(c) => c.clone_box(),
            EffectType::Equalizer(e) => e.clone_box(),
            EffectType::Reverb(r) => r.clone_box(),
            EffectType::Delay(d) => d.clone_box(),
            EffectType::Distortion(d) => d.clone_box(),
            EffectType::Chorus(c) => c.clone_box(),
            EffectType::PitchShift(p) => p.clone_box(),
        }
    }

    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String> {
        match self {
            EffectType::Compressor(c) => {
                if let Some(params) = &configs.compressor_params {
                    c.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Compressor error: {}", e))
                } else {
                    Err("No compressor params".to_string())
                }
            }
            EffectType::Equalizer(e) => {
                if let Some(params) = &configs.equalizer_params {
                    e.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Equalizer error: {}", e))
                } else {
                    Err("No equalizer params".to_string())
                }
            }
            EffectType::Reverb(r) => {
                if let Some(params) = &configs.reverb_params {
                    r.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Reverb error: {}", e))
                } else {
                    Err("No reverb params".to_string())
                }
            }
            EffectType::Delay(d) => {
                if let Some(params) = &configs.delay_params {
                    d.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Delay error: {}", e))
                } else {
                    Err("No delay params".to_string())
                }
            }
            EffectType::Distortion(d) => {
                if let Some(params) = &configs.distortion_params {
                    d.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Distortion error: {}", e))
                } else {
                    Err("No distortion params".to_string())
                }
            }
            EffectType::Chorus(c) => {
                if let Some(params) = &configs.chorus_params {
                    c.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Chorus error: {}", e))
                } else {
                    Err("No chorus params".to_string())
                }
            }
            EffectType::PitchShift(p) => {
                if let Some(params) = &configs.pitch_shift_params {
                    p.update_parameters(params.inner().clone())
                        .map_err(|e| format!("Pitch shift error: {}", e))
                } else {
                    Err("No pitch shift params".to_string())
                }
            }
        }
    }

    fn get_name(&self) -> String {
        match self {
            EffectType::Compressor(c) => c.get_name(),
            EffectType::Equalizer(e) => e.get_name(),
            EffectType::Reverb(r) => r.get_name(),
            EffectType::Delay(d) => d.get_name(),
            EffectType::Distortion(d) => d.get_name(),
            EffectType::Chorus(c) => c.get_name(),
            EffectType::PitchShift(p) => p.get_name(),
        }
    }

    fn format(&self) -> &AudioFormat {
        match self {
            EffectType::Compressor(c) => c.format(),
            EffectType::Equalizer(e) => e.format(),
            EffectType::Reverb(r) => r.format(),
            EffectType::Delay(d) => d.format(),
            EffectType::Distortion(d) => d.format(),
            EffectType::Chorus(c) => c.format(),
            EffectType::PitchShift(p) => p.format(),
        }
    }
}

/// Effect configuration
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct EffectConfig<const N: usize> {
    pub effect_type: EffectType<N>,
    pub enabled: bool,
    pub mix: f32,
    pub parameters: JsonValue,
    pub position: usize,
}

/// Audio effects configuration for batch update
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode, Default)]
pub struct AudioEffectConfig {
    pub pitch_shift_params: Option<JsonValue>,
    pub reverb_params: Option<JsonValue>,
    pub compressor_params: Option<JsonValue>,
    pub delay_params: Option<JsonValue>,
    pub distortion_params: Option<JsonValue>,
    pub chorus_params: Option<JsonValue>,
    pub equalizer_params: Option<JsonValue>,
}

impl AudioEffectConfig {
    /// Create new empty configuration
    pub fn new() -> Self {
        Self::default()
    }
    
    /// Set pitch shift parameters
    pub fn with_pitch_shift(mut self, params: JsonValue) -> Self {
        self.pitch_shift_params = Some(params);
        self
    }
    
    /// Set reverb parameters
    pub fn with_reverb(mut self, params: JsonValue) -> Self {
        self.reverb_params = Some(params);
        self
    }
    
    /// Set compressor parameters
    pub fn with_compressor(mut self, params: JsonValue) -> Self {
        self.compressor_params = Some(params);
        self
    }
    
    /// Set delay parameters
    pub fn with_delay(mut self, params: JsonValue) -> Self {
        self.delay_params = Some(params);
        self
    }
    
    /// Set distortion parameters
    pub fn with_distortion(mut self, params: JsonValue) -> Self {
        self.distortion_params = Some(params);
        self
    }
    
    /// Set chorus parameters
    pub fn with_chorus(mut self, params: JsonValue) -> Self {
        self.chorus_params = Some(params);
        self
    }
    
    /// Set equalizer parameters
    pub fn with_equalizer(mut self, params: JsonValue) -> Self {
        self.equalizer_params = Some(params);
        self
    }
    
    /// Check if any effects are configured
    pub fn has_any_effect(&self) -> bool {
        self.pitch_shift_params.is_some()
            || self.reverb_params.is_some()
            || self.compressor_params.is_some()
            || self.delay_params.is_some()
            || self.distortion_params.is_some()
            || self.chorus_params.is_some()
            || self.equalizer_params.is_some()
    }
    
    /// Get list of enabled effect types
    pub fn enabled_effects(&self) -> Vec<String> {
        let mut effects = Vec::new();
        if self.pitch_shift_params.is_some() { effects.push("pitch_shift".to_string()); }
        if self.reverb_params.is_some() { effects.push("reverb".to_string()); }
        if self.compressor_params.is_some() { effects.push("compressor".to_string()); }
        if self.delay_params.is_some() { effects.push("delay".to_string()); }
        if self.distortion_params.is_some() { effects.push("distortion".to_string()); }
        if self.chorus_params.is_some() { effects.push("chorus".to_string()); }
        if self.equalizer_params.is_some() { effects.push("equalizer".to_string()); }
        effects
    }
    
    /// Clear all parameters
    pub fn clear(&mut self) {
        self.pitch_shift_params = None;
        self.reverb_params = None;
        self.compressor_params = None;
        self.delay_params = None;
        self.distortion_params = None;
        self.chorus_params = None;
        self.equalizer_params = None;
    }
    
    /// Merge another config into this one (non-overwriting)
    pub fn merge(&mut self, other: AudioEffectConfig) {
        if self.pitch_shift_params.is_none() {
            self.pitch_shift_params = other.pitch_shift_params;
        }
        if self.reverb_params.is_none() {
            self.reverb_params = other.reverb_params;
        }
        if self.compressor_params.is_none() {
            self.compressor_params = other.compressor_params;
        }
        if self.delay_params.is_none() {
            self.delay_params = other.delay_params;
        }
        if self.distortion_params.is_none() {
            self.distortion_params = other.distortion_params;
        }
        if self.chorus_params.is_none() {
            self.chorus_params = other.chorus_params;
        }
        if self.equalizer_params.is_none() {
            self.equalizer_params = other.equalizer_params;
        }
    }
    
    /// Merge overwriting existing values
    pub fn merge_overwrite(&mut self, other: AudioEffectConfig) {
        if other.pitch_shift_params.is_some() {
            self.pitch_shift_params = other.pitch_shift_params;
        }
        if other.reverb_params.is_some() {
            self.reverb_params = other.reverb_params;
        }
        if other.compressor_params.is_some() {
            self.compressor_params = other.compressor_params;
        }
        if other.delay_params.is_some() {
            self.delay_params = other.delay_params;
        }
        if other.distortion_params.is_some() {
            self.distortion_params = other.distortion_params;
        }
        if other.chorus_params.is_some() {
            self.chorus_params = other.chorus_params;
        }
        if other.equalizer_params.is_some() {
            self.equalizer_params = other.equalizer_params;
        }
    }
}


/// Effect chain - контейнер для последовательности эффектов
#[derive(Debug, Serialize, Deserialize, Encode, Decode)]
pub struct EffectChain<const N: usize> {
    effects: Vec<(EffectConfig<N>, EffectType<N>)>,
    format: AudioFormat,
    bypass: bool,
    latency: usize,
}

impl<const N: usize> EffectChain<N> {
    pub fn new(configs: Vec<EffectConfig<N>>, format: AudioFormat) -> Result<Self, AudioError> {
        let mut effects = Vec::new();
        let mut total_latency = 0;

        for config in configs {
            if config.enabled {
                let effect = create_effect::<N>(&config, format.clone())?;
                total_latency += effect.get_latency();
                effects.push((config, effect));
            }
        }

        effects.sort_by_key(|(config, _)| config.position);

        Ok(Self { effects, format, bypass: false, latency: total_latency })
    }

    pub fn process(&mut self, buffer: &mut AudioBuffer<N>) -> Result<(), AudioError> {
        if self.bypass || self.effects.is_empty() {
            return Ok(());
        }

        // Проверка sample rate
        let expected_rate = self.format.sample_rate_hz() as f32;
        let actual_rate = buffer.sample_rate();
        if (actual_rate - expected_rate).abs() > 0.1 {
            return Err(AudioError::InvalidFormat(format!(
                "Expected {} Hz, got {} Hz",
                expected_rate, actual_rate
            )));
        }

        for (config, effect) in &mut self.effects {
            if config.enabled {
                effect.process(buffer)?;
            }
        }

        Ok(())
    }

    pub fn update(&mut self, configs: Vec<EffectConfig<N>>, format: AudioFormat) -> Result<(), AudioError> {
        *self = Self::new(configs, format)?;
        Ok(())
    }

    pub fn reset(&mut self) {
        for (_, effect) in &mut self.effects {
            effect.reset();
        }
    }

    pub fn set_bypass(&mut self, bypass: bool) {
        self.bypass = bypass;
    }

    pub fn get_latency(&self) -> usize {
        self.latency
    }

    pub fn get_configs(&self) -> Vec<EffectConfig<N>> {
        self.effects.iter().map(|(config, _)| config.clone()).collect()
    }

    pub fn get_effect(&mut self, index: usize) -> Option<&mut dyn AudioEffect<N>> {
        self.effects.get_mut(index).map(|(_, e)| e as &mut dyn AudioEffect<N>)
    }

    pub fn format(&self) -> &AudioFormat {
        &self.format
    }
    
    pub fn is_bypass(&self) -> bool {
        self.bypass
    }
}

// Helper function to create effect from config
pub fn create_effect<const N: usize>(
    config: &EffectConfig<N>,
    format: AudioFormat,
) -> Result<EffectType<N>, AudioError> {
    match &config.effect_type {
        EffectType::Compressor(_) => {
            let compressor = Compressor::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Compressor(compressor))
        }
        EffectType::Equalizer(_) => {
            let eq = Equalizer::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Equalizer(eq))
        }
        EffectType::Reverb(_) => {
            let reverb = Reverb::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Reverb(Box::new(reverb)))
        }
        EffectType::Delay(_) => {
            let delay = Delay::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Delay(delay))
        }
        EffectType::Distortion(_) => {
            let distortion = Distortion::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Distortion(distortion))
        }
        EffectType::Chorus(_) => {
            let chorus = Chorus::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::Chorus(chorus))
        }
        EffectType::PitchShift(_) => {
            let pitch_shift = PitchShift::from_config(config.parameters.inner(), format)?;
            Ok(EffectType::PitchShift(Box::new(pitch_shift)))
        }
    }
}
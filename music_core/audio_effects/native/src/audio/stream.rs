//! Audio stream module
//! Stream processing without effects

use crate::audio::StreamEffect;
use rustler::NifStruct;
use std::sync::Mutex;

// Маркеры для Elixir
rustler::atoms! {
    ok,
    error,
    invalid_parameters,
    buffer_too_small,
    stream_closed
}

// ==================== Структуры данных ====================

/// Main audio stream structure (без эффектов, только стрим)
pub struct AudioStream<const N: usize> {
    pub sample_rate: u32,
    pub channels: u16,
    pub buffer: Mutex<Vec<f32>>,
    pub effects: Mutex<Vec<Box<dyn StreamEffect<N> + Send>>>,
    pub volume: Mutex<f32>,
    pub is_playing: Mutex<bool>,
    pub position: Mutex<usize>,
}

/// Parameters for creating a stream
#[derive(NifStruct, Clone, Copy)]
#[module = "AudioEffects.Native.StreamConfig"]
pub struct StreamConfig {
    pub sample_rate: u32,
    pub channels: u16,
    pub buffer_size: usize,
    pub initial_volume: f32,
}

/// Stream information for return to Elixir
#[derive(Debug)]
pub struct StreamInfo {
    pub sample_rate: u32,
    pub channels: u16,
    pub volume: f32,
    pub is_playing: bool,
    pub position: usize,
    pub num_effects: usize,
    pub effect_names: Vec<String>,
}

// ==================== Реализация AudioStream ====================
impl AudioStream<1024> {
    pub fn new(config: StreamConfig) -> Self {
        AudioStream {
            sample_rate: config.sample_rate,
            channels: config.channels,
            buffer: Mutex::new(vec![0.0; config.buffer_size]),
            effects: Mutex::new(Vec::new()),
            volume: Mutex::new(config.initial_volume.clamp(0.0, 2.0)),
            is_playing: Mutex::new(false),
            position: Mutex::new(0),
        }
    }

    pub fn process(&self, input: &[f32], output: &mut [f32]) -> Result<(), String> {
        if output.len() < input.len() {
            return Err("Output buffer too small".to_string());
        }

        output[..input.len()].copy_from_slice(input);
        let buffer_slice = &mut output[..input.len()];

        let volume = *self.volume.lock().map_err(|_| "Volume lock poisoned")?;
        if (volume - 1.0).abs() > 0.001 {
            for sample in buffer_slice.iter_mut() {
                *sample *= volume;
            }
        }

        let mut effects = self.effects.lock().map_err(|_| "Effects lock poisoned")?;
        for effect in effects.iter_mut() {
            effect.process(buffer_slice);
        }

        for sample in buffer_slice.iter_mut() {
            *sample = sample.clamp(-1.0, 1.0);
        }

        Ok(())
    }

    pub fn add_effect(&self, effect: Box<dyn StreamEffect<1024> + Send>) {
        if let Ok(mut effects) = self.effects.lock() {
            effects.push(effect);
        }
    }

    pub fn clear_effects(&self) {
        if let Ok(mut effects) = self.effects.lock() {
            effects.clear();
        }
    }

    pub fn set_volume(&self, volume: f32) {
        if let Ok(mut vol) = self.volume.lock() {
            *vol = volume.clamp(0.0, 2.0);
        }
    }

    pub fn get_volume(&self) -> f32 {
        if let Ok(g) = self.volume.lock() { *g } else { 1.0 }
    }

    pub fn set_playing(&self, playing: bool) {
        if let Ok(mut flag) = self.is_playing.lock() {
            *flag = playing;
        }
    }

    pub fn is_playing(&self) -> bool {
        if let Ok(g) = self.is_playing.lock() { *g } else { false }
    }

    pub fn get_info(&self) -> StreamInfo {
        let (num_effects, effect_names) = match self.effects.lock() {
            Ok(effects) => (effects.len(), effects.iter().map(|e| e.get_name()).collect()),
            Err(_) => (0, Vec::new()),
        };

        let volume = if let Ok(g) = self.volume.lock() { *g } else { 1.0 };
        let is_playing = if let Ok(g) = self.is_playing.lock() { *g } else { false };
        let position = if let Ok(p) = self.position.lock() { *p } else { 0 };

        StreamInfo {
            sample_rate: self.sample_rate,
            channels: self.channels,
            volume,
            is_playing,
            position,
            num_effects,
            effect_names,
        }
    }
}
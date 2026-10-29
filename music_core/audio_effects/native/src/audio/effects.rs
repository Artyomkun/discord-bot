//! Audio effects for stream processing
//! Простые эффекты для AudioStream (VolumeEffect, EqualizerEffect, EchoEffect)

use crate::dsp::compressor::CompressorMetrics;
use crate::effects::effect::AudioEffectConfig;
use crate::audio::error::AudioError;
use serde_json::Value;
use std::f32::consts::PI;

/// Трейт для стрим-эффектов (работает с сырым слайсом f32)
pub trait StreamEffect<const N: usize>: Send + Sync {
    fn process(&mut self, buffer: &mut [f32]);
    fn reset(&mut self);
    fn update_parameters(&mut self, params: Value) -> Result<(), AudioError>;
    fn get_parameters(&self) -> Value;
    fn get_latency(&self) -> usize;
    fn get_metrics(&self) -> CompressorMetrics;
    fn clone_box(&self) -> Box<dyn StreamEffect<N>>;
    fn update_effects(&mut self, configs: &AudioEffectConfig) -> Result<(), String>;
    fn get_name(&self) -> String;
}

// ==================== ЭФФЕКТ ГРОМКОСТИ ====================

/// Volume effect (gain/attenuation)
pub struct VolumeEffect {
    gain: f32,
}

impl Clone for VolumeEffect {
    fn clone(&self) -> Self {
        Self { gain: self.gain }
    }
}

impl VolumeEffect {
    pub fn new(gain: f32) -> Self {
        VolumeEffect { gain: gain.clamp(0.0, 2.0) }
    }
}

impl<const N: usize> StreamEffect<N> for VolumeEffect {
    fn process(&mut self, buffer: &mut [f32]) {
        for sample in buffer.iter_mut() {
            *sample *= self.gain;
        }
    }

    fn reset(&mut self) {}

    fn update_parameters(&mut self, params: Value) -> Result<(), AudioError> {
        if let Some(gain) = params.get("gain").and_then(|v| v.as_f64()) {
            self.gain = (gain as f32).clamp(0.0, 2.0);
        }
        Ok(())
    }

    fn get_parameters(&self) -> Value {
        serde_json::json!({"gain": self.gain})
    }

    fn get_latency(&self) -> usize {
        0
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn clone_box(&self) -> Box<dyn StreamEffect<N>> {
        Box::new(self.clone())
    }

    fn update_effects(&mut self, _configs: &AudioEffectConfig) -> Result<(), String> {
        Ok(())
    }

    fn get_name(&self) -> String {
        "volume".to_string()
    }
}

// ==================== ЭФФЕКТ ЭКВАЛАЙЗЕРА ====================

/// Simple equalizer (3-band filter)
pub struct EqualizerEffect {
    low_gain: f32,
    mid_gain: f32,
    high_gain: f32,
    sample_rate: u32,
    low_history: [f32; 2],
    high_history: [f32; 2],
}

impl Clone for EqualizerEffect {
    fn clone(&self) -> Self {
        Self {
            low_gain: self.low_gain,
            mid_gain: self.mid_gain,
            high_gain: self.high_gain,
            sample_rate: self.sample_rate,
            low_history: self.low_history,
            high_history: self.high_history,
        }
    }
}

impl EqualizerEffect {
    pub fn new(low_gain: f32, mid_gain: f32, high_gain: f32, sample_rate: u32) -> Self {
        EqualizerEffect {
            low_gain: low_gain.clamp(-12.0, 12.0),
            mid_gain: mid_gain.clamp(-12.0, 12.0),
            high_gain: high_gain.clamp(-12.0, 12.0),
            sample_rate,
            low_history: [0.0; 2],
            high_history: [0.0; 2],
        }
    }
}

impl<const N: usize> StreamEffect<N> for EqualizerEffect {
    fn process(&mut self, buffer: &mut [f32]) {
        let sr = self.sample_rate as f32;
        let dt = 1.0 / sr;
        
        // Low-pass filter coefficients (~250 Hz)
        let rc_low = 1.0 / (2.0 * PI * 250.0);
        let alpha_low = dt / (rc_low + dt);
        
        // High-pass filter coefficients (~4000 Hz)
        let rc_high = 1.0 / (2.0 * PI * 4000.0);
        let alpha_high = rc_high / (rc_high + dt);

        for sample in buffer.iter_mut() {
            let input = *sample;
            
            // Low-pass filter
            self.low_history[0] = alpha_low * input + (1.0 - alpha_low) * self.low_history[0];
            
            // High-pass filter
            self.high_history[0] = alpha_high * (self.high_history[0] + input - self.high_history[1]);
            
            let low = self.low_history[0] * self.low_gain;
            let high = (input - self.high_history[0]) * self.high_gain;
            let mid = (input - self.low_history[0] - (input - self.high_history[0])) * self.mid_gain;
            
            self.low_history[1] = self.low_history[0];
            self.high_history[1] = input;
            
            *sample = (low + mid + high).clamp(-1.0, 1.0);
        }
    }

    fn reset(&mut self) {
        self.low_history.fill(0.0);
        self.high_history.fill(0.0);
    }

    fn update_parameters(&mut self, params: Value) -> Result<(), AudioError> {
        if let Some(low) = params.get("low_gain").and_then(|v| v.as_f64()) {
            self.low_gain = (low as f32).clamp(-12.0, 12.0);
        }
        if let Some(mid) = params.get("mid_gain").and_then(|v| v.as_f64()) {
            self.mid_gain = (mid as f32).clamp(-12.0, 12.0);
        }
        if let Some(high) = params.get("high_gain").and_then(|v| v.as_f64()) {
            self.high_gain = (high as f32).clamp(-12.0, 12.0);
        }
        Ok(())
    }

    fn get_parameters(&self) -> Value {
        serde_json::json!({
            "low_gain": self.low_gain,
            "mid_gain": self.mid_gain,
            "high_gain": self.high_gain
        })
    }

    fn get_latency(&self) -> usize {
        0
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn clone_box(&self) -> Box<dyn StreamEffect<N>> {
        Box::new(self.clone())
    }

    fn update_effects(&mut self, _configs: &AudioEffectConfig) -> Result<(), String> {
        Ok(())
    }

    fn get_name(&self) -> String {
        "equalizer".to_string()
    }
}

// ==================== ЭФФЕКТ ЭХО ====================

/// Echo/delay effect
pub struct EchoEffect {
    delay_buffer: Vec<f32>,
    write_position: usize,
    delay_samples: usize,
    feedback: f32,
    mix: f32,
    sample_rate: u32,
    channels: u16,
}

impl Clone for EchoEffect {
    fn clone(&self) -> Self {
        Self {
            delay_buffer: self.delay_buffer.clone(),
            write_position: self.write_position,
            delay_samples: self.delay_samples,
            feedback: self.feedback,
            mix: self.mix,
            sample_rate: self.sample_rate,
            channels: self.channels,
        }
    }
}

impl EchoEffect {
    pub fn new(delay_ms: f32, feedback: f32, mix: f32, sample_rate: u32, channels: u16) -> Self {
        let delay_samples = ((delay_ms * sample_rate as f32 / 1000.0) as usize).max(1);
        EchoEffect {
            delay_buffer: vec![0.0; delay_samples * channels as usize],
            write_position: 0,
            delay_samples,
            feedback: feedback.clamp(0.0, 0.99),
            mix: mix.clamp(0.0, 1.0),
            sample_rate,
            channels,
        }
    }
}

impl<const N: usize> StreamEffect<N> for EchoEffect {
    fn process(&mut self, buffer: &mut [f32]) {
        let channels = self.channels as usize;
        let buffer_len = buffer.len();
        
        for i in 0..(buffer_len / channels) {
            for ch in 0..channels {
                let idx = i * channels + ch;
                let sample = buffer[idx];
                
                let delay_idx = (self.write_position * channels + ch) % self.delay_buffer.len();
                let delayed = self.delay_buffer[delay_idx];
                
                let output = sample * (1.0 - self.mix) + delayed * self.mix;
                self.delay_buffer[delay_idx] = sample + delayed * self.feedback;
                
                buffer[idx] = output.clamp(-1.0, 1.0);
            }
            
            self.write_position = (self.write_position + 1) % (self.delay_buffer.len() / channels);
        }
    }

    fn reset(&mut self) {
        self.delay_buffer.fill(0.0);
        self.write_position = 0;
    }

    fn update_parameters(&mut self, params: Value) -> Result<(), AudioError> {
        if let Some(delay_ms) = params.get("delay_ms").and_then(|v| v.as_f64()) {
            let new_samples = ((delay_ms as f32 * self.sample_rate as f32 / 1000.0) as usize).max(1);
            if new_samples != self.delay_samples {
                self.delay_samples = new_samples;
                self.delay_buffer = vec![0.0; self.delay_samples * self.channels as usize];
                self.write_position = 0;
            }
        }
        if let Some(feedback) = params.get("feedback").and_then(|v| v.as_f64()) {
            self.feedback = (feedback as f32).clamp(0.0, 0.99);
        }
        if let Some(mix) = params.get("mix").and_then(|v| v.as_f64()) {
            self.mix = (mix as f32).clamp(0.0, 1.0);
        }
        Ok(())
    }

    fn get_parameters(&self) -> Value {
        serde_json::json!({
            "delay_ms": self.delay_samples as f32 * 1000.0 / self.sample_rate as f32,
            "feedback": self.feedback,
            "mix": self.mix
        })
    }

    fn get_latency(&self) -> usize {
        self.delay_samples
    }

    fn get_metrics(&self) -> CompressorMetrics {
        CompressorMetrics::default()
    }

    fn clone_box(&self) -> Box<dyn StreamEffect<N>> {
        Box::new(self.clone())
    }

    fn update_effects(&mut self, _configs: &AudioEffectConfig) -> Result<(), String> {
        Ok(())
    }

    fn get_name(&self) -> String {
        "echo".to_string()
    }
}
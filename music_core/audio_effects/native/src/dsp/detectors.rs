use std::collections::VecDeque;

/// Detector mode
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum DetectorMode {
    RMS,
    Peak,
    TruePeak,
    Median,
}

/// Detector configuration
#[derive(Debug, Clone, Copy)]
pub struct DetectorConfig {
    pub mode: DetectorMode,
    pub window_ms: f32,
    pub attack_ms: f32,
    pub release_ms: f32,
    pub hold_ms: f32,
    pub oversampling: u8,
    pub calibration_db: f32,
}

impl Default for DetectorConfig {
    fn default() -> Self {
        Self {
            mode: DetectorMode::RMS,
            window_ms: 10.0,
            attack_ms: 5.0,
            release_ms: 50.0,
            hold_ms: 0.0,
            oversampling: 4,
            calibration_db: 0.0,
        }
    }
}

/// Level detector trait
pub trait LevelDetector: Send + Sync {
    fn process(&mut self, sample: f32) -> f32;
    fn get_level_db(&self) -> f32;
    fn reset(&mut self);
    fn update_config(&mut self, config: DetectorConfig);
    fn set_sample_rate(&mut self, sample_rate: f32);
}

/// Advanced RMS detector
pub struct RmsDetector {
    config: DetectorConfig,
    sample_rate: f32,
    buffer: VecDeque<f32>,
    sum_squares: f32,
    current_rms: f32,
    smoothed_rms: f32,
    attack_coeff: f32,
    release_coeff: f32,
    hold_counter: usize,
    hold_samples: usize,
}

impl RmsDetector {
    pub fn new(config: DetectorConfig, sample_rate: f32) -> Self {
        let window_samples = (config.window_ms * sample_rate / 1000.0) as usize;
        
        // Исправлено: правильный расчёт коэффициентов
        let attack_coeff = (-1.0 / (config.attack_ms * 0.001 * sample_rate)).exp();
        let release_coeff = (-1.0 / (config.release_ms * 0.001 * sample_rate)).exp();
        let hold_samples = (config.hold_ms * sample_rate / 1000.0) as usize;

        Self {
            config,
            sample_rate,
            buffer: VecDeque::with_capacity(window_samples),
            sum_squares: 0.0,
            current_rms: 0.0,
            smoothed_rms: 0.0,
            attack_coeff,
            release_coeff,
            hold_counter: 0,
            hold_samples,
        }
    }

    pub fn process_sample(&mut self, sample: f32) -> f32 {
        let square = sample * sample;

        if self.buffer.len() == self.buffer.capacity() {
            if let Some(old) = self.buffer.pop_front() {
                self.sum_squares -= old * old;
            }
        }

        self.buffer.push_back(sample);
        self.sum_squares += square;

        self.current_rms = if !self.buffer.is_empty() {
            (self.sum_squares / self.buffer.len() as f32).sqrt()
        } else {
            0.0
        };

        let target = self.current_rms;
        let current = self.smoothed_rms;

        // Исправлена логика hold
        if target > current {
            // Attack
            self.smoothed_rms = self.attack_coeff * current + (1.0 - self.attack_coeff) * target;
            self.hold_counter = self.hold_samples;
        } else if self.hold_counter > 0 {
            // Hold
            self.hold_counter -= 1;
            // Keep current value
        } else {
            // Release
            self.smoothed_rms = self.release_coeff * current + (1.0 - self.release_coeff) * target;
        }

        self.smoothed_rms
    }

    pub fn get_level_db(&self) -> f32 {
        20.0 * (self.smoothed_rms + 1e-12).log10() + self.config.calibration_db
    }

    pub fn reset_detector(&mut self) {
        self.buffer.clear();
        self.sum_squares = 0.0;
        self.current_rms = 0.0;
        self.smoothed_rms = 0.0;
        self.hold_counter = 0;
    }

    pub fn update_detector_config(&mut self, config: DetectorConfig) {
        self.config = config;
        let window_samples = (config.window_ms * self.sample_rate / 1000.0) as usize;
        self.buffer = VecDeque::with_capacity(window_samples);
        self.reset_detector();
        
        // Пересчитываем коэффициенты
        self.attack_coeff = (-1.0 / (config.attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (config.release_ms * 0.001 * self.sample_rate)).exp();
        self.hold_samples = (config.hold_ms * self.sample_rate / 1000.0) as usize;
    }
}

impl LevelDetector for RmsDetector {
    fn process(&mut self, sample: f32) -> f32 { self.process_sample(sample) }
    fn get_level_db(&self) -> f32 { self.get_level_db() }
    fn reset(&mut self) { self.reset_detector() }
    fn update_config(&mut self, config: DetectorConfig) { self.update_detector_config(config) }
    fn set_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        self.attack_coeff = (-1.0 / (self.config.attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-1.0 / (self.config.release_ms * 0.001 * sample_rate)).exp();
        self.hold_samples = (self.config.hold_ms * sample_rate / 1000.0) as usize;
    }
}

/// Advanced Peak detector
pub struct PeakDetector {
    config: DetectorConfig,
    sample_rate: f32,
    buffer: VecDeque<f32>,
    current_peak: f32,
    smoothed_peak: f32,
    attack_coeff: f32,
    release_coeff: f32,
    hold_counter: usize,
    hold_samples: usize,
    oversampling_buffer: Vec<f32>,
    oversampling_factor: usize,
}

impl PeakDetector {
    pub fn new(config: DetectorConfig, sample_rate: f32) -> Self {
        let window_samples = (config.window_ms * sample_rate / 1000.0) as usize;
        
        // Исправлено: правильный расчёт коэффициентов
        let attack_coeff = (-1.0 / (config.attack_ms * 0.001 * sample_rate)).exp();
        let release_coeff = (-1.0 / (config.release_ms * 0.001 * sample_rate)).exp();
        let hold_samples = (config.hold_ms * sample_rate / 1000.0) as usize;
        let oversampling_factor = config.oversampling as usize;

        Self {
            config,
            sample_rate,
            buffer: VecDeque::with_capacity(window_samples),
            current_peak: 0.0,
            smoothed_peak: 0.0,
            attack_coeff,
            release_coeff,
            hold_counter: 0,
            hold_samples,
            oversampling_buffer: vec![0.0; oversampling_factor],
            oversampling_factor,
        }
    }

    /// Cubic Hermite interpolation for true peak
    fn cubic_hermite_interp(p0: f32, p1: f32, p2: f32, p3: f32, t: f32) -> f32 {
        let a0 = p1;
        let a1 = 0.5 * (p2 - p0);
        let a2 = p0 - 2.5 * p1 + 2.0 * p2 - 0.5 * p3;
        let a3 = 0.5 * (p3 - p0) + 1.5 * (p1 - p2);
        ((a3 * t + a2) * t + a1) * t + a0
    }

    fn true_peak_detection(&self, samples: &[f32]) -> f32 {
        let mut max_peak: f32 = 0.0;
        let len = samples.len();
        
        for i in 0..len - 1 {
            let p0 = if i > 0 { samples[i - 1] } else { samples[i] };
            let p1 = samples[i];
            let p2 = samples[i + 1];
            let p3 = if i + 2 < len { samples[i + 2] } else { samples[i + 1] };
            
            // Check for zero crossing of derivative
            let diff1 = p2 - p1;
            let diff0 = p1 - p0;
            
            if diff0 * diff1 <= 0.0 {
                // Find peak position using quadratic interpolation
                let a = 0.5 * (p2 - 2.0 * p1 + p0);
                let b = 0.5 * (p2 - p0);
                
                if a.abs() > 1e-6 {
                    let t = -b / (2.0 * a);
                    if t > 0.0 && t < 1.0 {
                        let interpolated = Self::cubic_hermite_interp(p0, p1, p2, p3, t);
                        max_peak = max_peak.max(interpolated.abs());
                    }
                }
            }
            max_peak = max_peak.max(p1.abs());
        }
        
        max_peak
    }

    fn median_filter(&mut self, sample: f32) -> f32 {
        if self.buffer.is_empty() { return sample; }
        let mut sorted: Vec<f32> = self.buffer.iter().copied().collect();
        sorted.sort_by(|a, b| a.partial_cmp(b).unwrap());
        sorted[sorted.len() / 2]
    }

    pub fn process_sample(&mut self, sample: f32) -> f32 {
        let abs_sample = sample.abs();

        let detected = match self.config.mode {
            DetectorMode::TruePeak if self.oversampling_factor > 1 => {
                // Для true peak нужно больше сэмплов
                if self.oversampling_buffer.len() >= self.oversampling_factor {
                    
                    self.true_peak_detection(&self.oversampling_buffer)
                } else {
                    abs_sample
                }
            }
            DetectorMode::TruePeak => abs_sample,
            DetectorMode::Median => self.median_filter(abs_sample),
            _ => abs_sample,
        };

        // Обновляем oversampling буфер
        self.oversampling_buffer.push(abs_sample);
        if self.oversampling_buffer.len() > self.oversampling_factor {
            self.oversampling_buffer.remove(0);
        }

        let target = self.current_peak.max(detected);
        
        if self.buffer.len() == self.buffer.capacity() {
            self.buffer.pop_front();
        }
        self.buffer.push_back(detected);

        let window_peak = self.buffer.iter().fold(0.0f32, |max, &x| max.max(x));
        let target_peak = window_peak.max(target);

        // Исправлена логика hold
        if target_peak > self.smoothed_peak {
            // Attack
            self.smoothed_peak = self.attack_coeff * self.smoothed_peak + (1.0 - self.attack_coeff) * target_peak;
            self.hold_counter = self.hold_samples;
        } else if self.hold_counter > 0 {
            // Hold
            self.hold_counter -= 1;
        } else {
            // Release
            self.smoothed_peak = self.release_coeff * self.smoothed_peak + (1.0 - self.release_coeff) * target_peak;
        }

        self.current_peak = detected;
        self.smoothed_peak
    }

    pub fn get_level_db(&self) -> f32 {
        20.0 * (self.smoothed_peak + 1e-12).log10() + self.config.calibration_db
    }

    pub fn reset_detector(&mut self) {
        self.buffer.clear();
        self.current_peak = 0.0;
        self.smoothed_peak = 0.0;
        self.hold_counter = 0;
        self.oversampling_buffer.fill(0.0);
    }

    pub fn update_detector_config(&mut self, config: DetectorConfig) {
        self.config = config;
        let window_samples = (config.window_ms * self.sample_rate / 1000.0) as usize;
        self.buffer = VecDeque::with_capacity(window_samples);
        self.oversampling_factor = config.oversampling as usize;
        self.oversampling_buffer.resize(self.oversampling_factor, 0.0);
        self.reset_detector();
        
        // Пересчитываем коэффициенты
        self.attack_coeff = (-1.0 / (config.attack_ms * 0.001 * self.sample_rate)).exp();
        self.release_coeff = (-1.0 / (config.release_ms * 0.001 * self.sample_rate)).exp();
        self.hold_samples = (config.hold_ms * self.sample_rate / 1000.0) as usize;
    }
}

impl LevelDetector for PeakDetector {
    fn process(&mut self, sample: f32) -> f32 { self.process_sample(sample) }
    fn get_level_db(&self) -> f32 { self.get_level_db() }
    fn reset(&mut self) { self.reset_detector() }
    fn update_config(&mut self, config: DetectorConfig) { self.update_detector_config(config) }
    fn set_sample_rate(&mut self, sample_rate: f32) {
        self.sample_rate = sample_rate;
        self.attack_coeff = (-1.0 / (self.config.attack_ms * 0.001 * sample_rate)).exp();
        self.release_coeff = (-1.0 / (self.config.release_ms * 0.001 * sample_rate)).exp();
        self.hold_samples = (self.config.hold_ms * sample_rate / 1000.0) as usize;
    }
}

/// Factory function
pub fn create_detector(config: DetectorConfig, sample_rate: f32) -> Box<dyn LevelDetector> {
    match config.mode {
        DetectorMode::RMS => Box::new(RmsDetector::new(config, sample_rate)),
        DetectorMode::Peak | DetectorMode::TruePeak | DetectorMode::Median => {
            Box::new(PeakDetector::new(config, sample_rate))
        }
    }
}
//! Digital filters: biquad, FIR, IIR
//! Professional audio filter implementations

use bincode::{Decode, Encode};
use serde::{Deserialize, Serialize};
use std::f32::consts::PI;

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Encode, Decode)]
pub enum FilterType {
    LowPass,
    HighPass,
    BandPass,
    BandStop,
    LowShelf,
    HighShelf,
    Peak,
    AllPass,
    Notch,
}

#[derive(Debug, Copy, Clone, Serialize, Deserialize, Encode, Decode, Default)]
pub struct Biquad {
    pub b0: f32,
    pub b1: f32,
    pub b2: f32,
    pub a0: f32,
    pub a1: f32,
    pub a2: f32,
    x1: f32,
    x2: f32,
    y1: f32,
    y2: f32,
}

impl Biquad {
    pub fn new() -> Self {
        Self {
            b0: 1.0, b1: 0.0, b2: 0.0,
            a0: 1.0, a1: 0.0, a2: 0.0,
            x1: 0.0, x2: 0.0, y1: 0.0, y2: 0.0,
        }
    }

    pub fn calculate_coefficients(
        filter_type: FilterType,
        frequency: f32,
        sample_rate: f32,
        q: f32,
        gain_db: f32,
    ) -> Self {
        if !frequency.is_finite() || !sample_rate.is_finite() || !q.is_finite() || !gain_db.is_finite() {
            return Self::new();
        }

        let mut biquad = Self::new();
        let a = 10.0f32.powf(gain_db / 40.0);
        let omega = 2.0 * PI * frequency / sample_rate;
        let sn = omega.sin();
        let cs = omega.cos();
        let alpha = (sn / (2.0 * q)).min(0.99);
        let beta = ((a + a).sqrt() * sn / (2.0 * q)).min(0.99);

        match filter_type {
            FilterType::LowPass => {
                biquad.b0 = (1.0 - cs) / 2.0;
                biquad.b1 = 1.0 - cs;
                biquad.b2 = (1.0 - cs) / 2.0;
                biquad.a0 = 1.0 + alpha;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha;
            }
            FilterType::HighPass => {
                biquad.b0 = (1.0 + cs) / 2.0;
                biquad.b1 = -(1.0 + cs);
                biquad.b2 = (1.0 + cs) / 2.0;
                biquad.a0 = 1.0 + alpha;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha;
            }
            FilterType::BandPass => {
                biquad.b0 = alpha;
                biquad.b1 = 0.0;
                biquad.b2 = -alpha;
                biquad.a0 = 1.0 + alpha;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha;
            }
            FilterType::BandStop | FilterType::Notch => {
                biquad.b0 = 1.0;
                biquad.b1 = -2.0 * cs;
                biquad.b2 = 1.0;
                biquad.a0 = 1.0 + alpha;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha;
            }
            FilterType::LowShelf => {
                biquad.b0 = a * ((a + 1.0) - (a - 1.0) * cs + beta);
                biquad.b1 = 2.0 * a * ((a - 1.0) - (a + 1.0) * cs);
                biquad.b2 = a * ((a + 1.0) - (a - 1.0) * cs - beta);
                biquad.a0 = (a + 1.0) + (a - 1.0) * cs + beta;
                biquad.a1 = -2.0 * ((a - 1.0) + (a + 1.0) * cs);
                biquad.a2 = (a + 1.0) + (a - 1.0) * cs - beta;
            }
            FilterType::HighShelf => {
                biquad.b0 = a * ((a + 1.0) + (a - 1.0) * cs + beta);
                biquad.b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * cs);
                biquad.b2 = a * ((a + 1.0) + (a - 1.0) * cs - beta);
                biquad.a0 = (a + 1.0) - (a - 1.0) * cs + beta;
                biquad.a1 = 2.0 * ((a - 1.0) - (a + 1.0) * cs);
                biquad.a2 = (a + 1.0) - (a - 1.0) * cs - beta;
            }
            FilterType::Peak => {
                biquad.b0 = 1.0 + alpha * a;
                biquad.b1 = -2.0 * cs;
                biquad.b2 = 1.0 - alpha * a;
                biquad.a0 = 1.0 + alpha / a;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha / a;
            }
            FilterType::AllPass => {
                biquad.b0 = 1.0 - alpha;
                biquad.b1 = -2.0 * cs;
                biquad.b2 = 1.0 + alpha;
                biquad.a0 = 1.0 + alpha;
                biquad.a1 = -2.0 * cs;
                biquad.a2 = 1.0 - alpha;
            }
        }

        // Normalize coefficients
        let inv_a0 = 1.0 / biquad.a0;
        biquad.b0 *= inv_a0;
        biquad.b1 *= inv_a0;
        biquad.b2 *= inv_a0;
        biquad.a1 *= inv_a0;
        biquad.a2 *= inv_a0;
        biquad.a0 = 1.0;

        biquad
    }

    pub fn process(&mut self, sample: f32) -> f32 {
        let sample = if sample.is_finite() { sample } else { 0.0 };
        let output = self.b0 * sample + self.b1 * self.x1 + self.b2 * self.x2
            - self.a1 * self.y1 - self.a2 * self.y2;
        let output = if output.is_finite() { output } else { 0.0 };
        self.x2 = self.x1;
        self.x1 = sample;
        self.y2 = self.y1;
        self.y1 = output;
        output
    }

    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        for sample in buffer {
            *sample = self.process(*sample);
        }
    }

    pub fn reset(&mut self) {
        self.x1 = 0.0;
        self.x2 = 0.0;
        self.y1 = 0.0;
        self.y2 = 0.0;
    }

    pub fn get_frequency_response(&self, frequency: f32, sample_rate: f32) -> (f32, f32) {
        let omega = 2.0 * PI * frequency / sample_rate;
        let z_re = omega.cos();
        let z_im = -omega.sin();

        let numerator_re = self.b0 + self.b1 * z_re + self.b2 * (z_re * z_re - z_im * z_im);
        let numerator_im = self.b1 * z_im + self.b2 * 2.0 * z_re * z_im;
        let denominator_re = 1.0 + self.a1 * z_re + self.a2 * (z_re * z_re - z_im * z_im);
        let denominator_im = self.a1 * z_im + self.a2 * 2.0 * z_re * z_im;
        let denom = denominator_re * denominator_re + denominator_im * denominator_im;
        
        if denom < 1e-12 {
            return (0.0, 0.0);
        }
        
        let response_re = (numerator_re * denominator_re + numerator_im * denominator_im) / denom;
        let response_im = (numerator_im * denominator_re - numerator_re * denominator_im) / denom;
        let magnitude = (response_re * response_re + response_im * response_im).sqrt();
        let phase = response_im.atan2(response_re);
        (magnitude, phase)
    }

    pub fn get_magnitude_response(&self, frequency: f32, sample_rate: f32) -> f32 {
        let (magnitude, _) = self.get_frequency_response(frequency, sample_rate);
        magnitude
    }
}

/// Professional digital filter
#[derive(Debug, Clone, Serialize, Deserialize, Encode, Decode)]
pub struct Filter {
    pub filter_type: FilterType,
    pub frequency: f32,
    pub sample_rate: f32,
    pub q: f32,
    pub gain_db: f32,
    biquad: Biquad,
    dirty: bool,
}

impl Filter {
    pub fn new(filter_type: FilterType, sample_rate: f32) -> Self {
        let biquad = Biquad::calculate_coefficients(filter_type, 1000.0, sample_rate, 1.0, 0.0);
        Self {
            filter_type,
            frequency: 1000.0,
            sample_rate,
            q: 1.0,
            gain_db: 0.0,
            biquad,
            dirty: false,
        }
    }

    pub fn update_coefficients(&mut self) {
        self.biquad = Biquad::calculate_coefficients(
            self.filter_type, self.frequency, self.sample_rate, self.q, self.gain_db
        );
        self.dirty = false;
    }

    pub fn process(&mut self, sample: &mut f32) {
        if self.dirty {
            self.update_coefficients();
        }
        *sample = self.biquad.process(*sample);
    }

    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        if self.dirty {
            self.update_coefficients();
        }
        for sample in buffer {
            *sample = self.biquad.process(*sample);
        }
    }

    pub fn set_frequency(&mut self, frequency: f32) {
        let new_freq = frequency.clamp(20.0, self.sample_rate / 2.0);
        if (new_freq - self.frequency).abs() > 0.1 {
            self.frequency = new_freq;
            self.dirty = true;
        }
    }

    pub fn set_q(&mut self, q: f32) {
        let new_q = q.clamp(0.1, 100.0);
        if (new_q - self.q).abs() > 0.001 {
            self.q = new_q;
            self.dirty = true;
        }
    }

    pub fn set_gain(&mut self, gain_db: f32) {
        let new_gain = gain_db.clamp(-48.0, 48.0);
        if (new_gain - self.gain_db).abs() > 0.1 {
            self.gain_db = new_gain;
            self.dirty = true;
        }
    }

    pub fn set_type(&mut self, filter_type: FilterType) {
        if self.filter_type != filter_type {
            self.filter_type = filter_type;
            self.dirty = true;
        }
    }

    pub fn set_sample_rate(&mut self, sample_rate: f32) {
        if (sample_rate - self.sample_rate).abs() > 0.1 {
            self.sample_rate = sample_rate;
            self.dirty = true;
        }
    }

    pub fn get_frequency_response(&self, frequency: f32) -> (f32, f32) {
        let biquad = if self.dirty {
            Biquad::calculate_coefficients(
                self.filter_type, self.frequency, self.sample_rate, self.q, self.gain_db
            )
        } else {
            self.biquad
        };
        biquad.get_frequency_response(frequency, self.sample_rate)
    }

    pub fn get_magnitude_response(&self, frequency: f32) -> f32 {
        let (magnitude, _) = self.get_frequency_response(frequency);
        magnitude
    }

    pub fn reset(&mut self) {
        self.biquad.reset();
    }

    // Factory methods
    pub fn lowpass(frequency: f32, sample_rate: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::LowPass, sample_rate);
        filter.set_frequency(frequency);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn highpass(frequency: f32, sample_rate: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::HighPass, sample_rate);
        filter.set_frequency(frequency);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn bandpass(frequency: f32, sample_rate: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::BandPass, sample_rate);
        filter.set_frequency(frequency);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn notch(frequency: f32, sample_rate: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::BandStop, sample_rate);
        filter.set_frequency(frequency);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn lowshelf(frequency: f32, sample_rate: f32, gain_db: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::LowShelf, sample_rate);
        filter.set_frequency(frequency);
        filter.set_gain(gain_db);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn highshelf(frequency: f32, sample_rate: f32, gain_db: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::HighShelf, sample_rate);
        filter.set_frequency(frequency);
        filter.set_gain(gain_db);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }

    pub fn peak(frequency: f32, sample_rate: f32, gain_db: f32, q: f32) -> Self {
        let mut filter = Self::new(FilterType::Peak, sample_rate);
        filter.set_frequency(frequency);
        filter.set_gain(gain_db);
        filter.set_q(q);
        filter.update_coefficients();
        filter
    }
}

/// Window types for FIR design
#[derive(Debug, Clone, Copy, PartialEq)]
pub enum WindowType {
    Rectangular,
    Hamming,
    Hann,
    Blackman,
}

/// FIR filter
pub struct FIRFilter {
    coefficients: Vec<f32>,
    buffer: Vec<f32>,
    position: usize,
}

impl FIRFilter {
    pub fn new(coefficients: Vec<f32>) -> Self {
        let buffer_size = coefficients.len();
        Self {
            coefficients,
            buffer: vec![0.0; buffer_size],
            position: 0,
        }
    }

    pub fn process(&mut self, sample: f32) -> f32 {
        let sample = if sample.is_finite() { sample } else { 0.0 };
        self.buffer[self.position] = sample;
        let mut output = 0.0;
        for i in 0..self.coefficients.len() {
            let idx = (self.position + self.coefficients.len() - i) % self.coefficients.len();
            output += self.buffer[idx] * self.coefficients[i];
        }
        let output = if output.is_finite() { output } else { 0.0 };
        self.position = (self.position + 1) % self.buffer.len();
        output
    }

    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        for sample in buffer {
            *sample = self.process(*sample);
        }
    }

    pub fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.position = 0;
    }

    pub fn design_lowpass(
        cutoff_freq: f32,
        sample_rate: f32,
        filter_length: usize,
        window: WindowType,
    ) -> Vec<f32> {
        assert!(filter_length % 2 == 1, "Filter length must be odd");
        let mut coeffs = vec![0.0; filter_length];
        let mid = filter_length / 2;
        let omega_c = 2.0 * PI * cutoff_freq / sample_rate;
        
        coeffs.iter_mut().enumerate().take(filter_length).for_each(|(i, coeff)| {
            let n = i as f32 - mid as f32;
            *coeff = if n.abs() < 1e-9 {
                omega_c / PI
            } else {
                (omega_c * n).sin() / (PI * n)
            };
            
            let window_value = match window {
                WindowType::Rectangular => 1.0,
                WindowType::Hamming => 0.54 - 0.46 * (2.0 * PI * i as f32 / (filter_length - 1) as f32).cos(),
                WindowType::Hann => 0.5 - 0.5 * (2.0 * PI * i as f32 / (filter_length - 1) as f32).cos(),
                WindowType::Blackman => {
                    0.42 - 0.5 * (2.0 * PI * i as f32 / (filter_length - 1) as f32).cos()
                    + 0.08 * (4.0 * PI * i as f32 / (filter_length - 1) as f32).cos()
                }
            };
            *coeff *= window_value;
        });
        
        coeffs
    }
}

/// Filter cascade
pub struct FilterCascade {
    filters: Vec<Filter>,
}

impl FilterCascade {
    pub fn new(filters: Vec<Filter>) -> Self {
        Self { filters }
    }

    pub fn process(&mut self, sample: f32) -> f32 {
        let mut output = sample;
        for filter in &mut self.filters {
            filter.process(&mut output);
        }
        output
    }

    pub fn process_buffer(&mut self, buffer: &mut [f32]) {
        for sample in buffer {
            *sample = self.process(*sample);
        }
    }

    pub fn reset(&mut self) {
        for filter in &mut self.filters {
            filter.reset();
        }
    }

    pub fn linkwitz_riley(crossover_freq: f32, sample_rate: f32, order: usize) -> (Self, Self) {
        assert!(order.is_multiple_of(2), "Order must be even");
        let mut low_filters = Vec::new();
        let mut high_filters = Vec::new();
        let q = 0.707; // Butterworth Q
        
        for _ in 0..(order / 2) {
            low_filters.push(Filter::lowpass(crossover_freq, sample_rate, q));
            high_filters.push(Filter::highpass(crossover_freq, sample_rate, q));
        }
        
        (Self::new(low_filters), Self::new(high_filters))
    }
}
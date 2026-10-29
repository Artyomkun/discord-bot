//! Reverb algorithms and spatial processing
//! Plate, hall, room reverb

use crate::dsp::filter::{Filter, FilterType};
use serde::{Deserialize, Serialize};

/// Reverb type
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq)]
pub enum ReverbAlgorithm {
    Schroeder,
    Moorer,
    FDN,
    Waveguide,
    Convolution,
    Plate,
    Spring,
}

/// Reverb parameters
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReverbParams {
    pub algorithm: ReverbAlgorithm,
    pub room_size: f32,
    pub damping: f32,
    pub width: f32,
    pub pre_delay: f32,
    pub decay_time: f32,
    pub diffusion: f32,
    pub modulation: f32,
    pub early_reflections: f32,
    pub late_reflections: f32,
    pub wet: f32,
    pub dry: f32,
}

impl Default for ReverbParams {
    fn default() -> Self {
        Self {
            algorithm: ReverbAlgorithm::FDN,
            room_size: 0.7,
            damping: 0.5,
            width: 0.8,
            pre_delay: 20.0,
            decay_time: 2.5,
            diffusion: 0.7,
            modulation: 0.3,
            early_reflections: 0.6,
            late_reflections: 0.8,
            wet: 0.3,
            dry: 0.7,
        }
    }
}

/// Delay with feedback
#[derive(Clone)]
pub struct DelayLine {
    buffer: Vec<f32>,
    position: usize,
}

impl DelayLine {
    fn new(length: usize) -> Self {
        Self {
            buffer: vec![0.0; length.max(1)],
            position: 0,
        }
    }

    fn read(&self) -> f32 {
        if self.position < self.buffer.len() {
            self.buffer[self.position]
        } else {
            0.0
        }
    }

    fn write(&mut self, value: f32) {
        if self.position < self.buffer.len() {
            self.buffer[self.position] = value;
            self.position = (self.position + 1) % self.buffer.len();
        }
    }

    fn reset(&mut self) {
        self.buffer.fill(0.0);
        self.position = 0;
    }
}

/// Schroeder reverb (classic algorithm)
pub struct SchroederReverb {
    params: ReverbParams,
    sample_rate: f32,
    comb_filters: Vec<(DelayLine, f32)>,
    allpass_filters: Vec<(DelayLine, f32)>,
    damping_filters: Vec<Filter>,
    early_delay: DelayLine,
    pre_delay: DelayLine,
    wet_gain: f32,
    dry_gain: f32,
    decay_coeff: f32,
}

impl SchroederReverb {
    pub fn new(params: ReverbParams, sample_rate: f32) -> Self {
        let mut reverb = Self {
            params: params.clone(),
            sample_rate,
            comb_filters: Vec::new(),
            allpass_filters: Vec::new(),
            damping_filters: Vec::new(),
            early_delay: DelayLine::new(1),
            pre_delay: DelayLine::new(1),
            wet_gain: params.wet,
            dry_gain: params.dry,
            decay_coeff: (-1.0 / (params.decay_time * sample_rate)).exp(),
        };
        reverb.initialize();
        reverb
    }

    fn initialize(&mut self) {
        self.comb_filters.clear();
        self.allpass_filters.clear();
        self.damping_filters.clear();

        let comb_delays = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116];
        let comb_gains = [0.805, 0.827, 0.783, 0.764, 0.742, 0.733, 0.715, 0.697];

        for (&delay_samples, &gain) in comb_delays.iter().zip(comb_gains.iter()) {
            let scaled_delay = (delay_samples as f32 * self.params.room_size) as usize;
            let scaled_gain = gain * (1.0 - self.params.damping * 0.5);
            self.comb_filters.push((DelayLine::new(scaled_delay), scaled_gain));
            let mut filter = Filter::new(FilterType::LowPass, self.sample_rate);
            filter.set_frequency(6000.0 * (1.0 - self.params.damping));
            filter.set_q(0.707);
            self.damping_filters.push(filter);
        }

        let allpass_delays = [225, 556];
        let allpass_gains = [0.7, 0.7];
        for (&delay_samples, &gain) in allpass_delays.iter().zip(allpass_gains.iter()) {
            let scaled_delay = (delay_samples as f32 * self.params.room_size) as usize;
            self.allpass_filters.push((DelayLine::new(scaled_delay), gain));
        }

        let early_delay_samples = ((self.params.pre_delay / 1000.0) * self.sample_rate) as usize;
        self.early_delay = DelayLine::new(early_delay_samples);
        self.pre_delay = DelayLine::new(early_delay_samples);
        
        self.decay_coeff = (-1.0 / (self.params.decay_time * self.sample_rate)).exp();
    }

    pub fn process_sample(&mut self, input_left: f32, input_right: f32) -> (f32, f32) {
        let mono_input = (input_left + input_right) * 0.5;
        
        let pre_delayed = self.pre_delay.read();
        self.pre_delay.write(mono_input);
        let early = self.early_delay.read() * self.params.early_reflections;
        self.early_delay.write(pre_delayed);

        let mut comb_sum = 0.0;
        for (idx, ((delay_line, gain), damping_filter)) in self.comb_filters.iter_mut().zip(&mut self.damping_filters).enumerate() {
            let delayed = delay_line.read();
            let mut filtered = delayed;
            damping_filter.process(&mut filtered);
            let feedback = filtered * *gain;
            delay_line.write(pre_delayed + feedback);
            comb_sum += delayed * (1.0 + (idx as f32 * 0.05));
        }

        let mut allpass_output = comb_sum / self.comb_filters.len() as f32;
        for (delay_line, gain) in &mut self.allpass_filters {
            let delayed = delay_line.read();
            let output = -allpass_output * *gain + delayed;
            delay_line.write(allpass_output + delayed * *gain);
            allpass_output = output;
        }

        let late = allpass_output * self.params.late_reflections * self.decay_coeff;
        
        let left_output = early * (1.0 - self.params.width * 0.5) + late * (0.5 + self.params.width * 0.5);
        let right_output = early * (1.0 - self.params.width * 0.5) + late * (0.5 - self.params.width * 0.5);

        (input_left * self.dry_gain + left_output * self.wet_gain,
         input_right * self.dry_gain + right_output * self.wet_gain)
    }

    pub fn process_stereo(&mut self, left_buffer: &mut [f32], right_buffer: &mut [f32]) {
        for i in 0..left_buffer.len().min(right_buffer.len()) {
            let (l, r) = self.process_sample(left_buffer[i], right_buffer[i]);
            left_buffer[i] = l;
            right_buffer[i] = r;
        }
    }

    pub fn update_params(&mut self, params: ReverbParams) {
        self.params = params;
        self.wet_gain = self.params.wet;
        self.dry_gain = self.params.dry;
        self.decay_coeff = (-1.0 / (self.params.decay_time * self.sample_rate)).exp();
        self.initialize();
    }

    pub fn reset(&mut self) {
        for (delay_line, _) in &mut self.comb_filters { delay_line.reset(); }
        for (delay_line, _) in &mut self.allpass_filters { delay_line.reset(); }
        self.early_delay.reset();
        self.pre_delay.reset();
        for filter in &mut self.damping_filters { filter.reset(); }
    }
}

/// Universal reverb processor
pub struct ReverbProcessor {
    algorithm: ReverbAlgorithm,
    schroeder: Option<SchroederReverb>,
    params: ReverbParams,
    sample_rate: f32,
}

impl ReverbProcessor {
    pub fn new(params: ReverbParams, sample_rate: f32) -> Self {
        let mut processor = Self {
            algorithm: params.algorithm,
            schroeder: None,
            params: params.clone(),
            sample_rate,
        };
        processor.initialize();
        processor
    }

    fn initialize(&mut self) {
        match self.algorithm {
            ReverbAlgorithm::Schroeder => {
                self.schroeder = Some(SchroederReverb::new(self.params.clone(), self.sample_rate));
            }
            // Fallback to Schroeder for unsupported algorithms currently
            _ => {
                self.schroeder = Some(SchroederReverb::new(self.params.clone(), self.sample_rate));
            }
        }
    }

    pub fn process_sample(&mut self, input_left: f32, input_right: f32) -> (f32, f32) {
        match self.algorithm {
            ReverbAlgorithm::Schroeder => {
                self.schroeder.as_mut().map_or((input_left, input_right), |r| r.process_sample(input_left, input_right))
            }
            _ => (input_left, input_right),
        }
    }

    pub fn process_stereo(&mut self, left_buffer: &mut [f32], right_buffer: &mut [f32]) {
        if let Some(r) = &mut self.schroeder {
            r.process_stereo(left_buffer, right_buffer);
        }
    }

    pub fn update_params(&mut self, params: ReverbParams) {
        self.params = params.clone();
        self.algorithm = params.algorithm;
        self.initialize();
    }

    pub fn reset(&mut self) {
        if let Some(r) = &mut self.schroeder { r.reset(); }
    }

    pub fn get_impulse_response(&self, length_samples: usize) -> Vec<f32> {
        let mut response = vec![0.0; length_samples];
        let mut left = vec![0.0; length_samples];
        let mut right = vec![0.0; length_samples];
        
        if length_samples > 0 {
            left[0] = 1.0;
            right[0] = 1.0;
        }

        // Создаём копию для обработки
        let mut temp = ReverbProcessor::new(self.params.clone(), self.sample_rate);
        temp.process_stereo(&mut left, &mut right);

        for i in 0..length_samples {
            response[i] = (left[i] + right[i]) * 0.5;
        }
        response
    }
    
    pub fn set_wet_dry(&mut self, wet: f32, dry: f32) {
        self.params.wet = wet;
        self.params.dry = dry;
        self.initialize();
    }
}
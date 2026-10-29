//! DSP utilities and helper functions
//! Mathematical operations, conversions, analytical functions

pub mod utils{
    use std::f32::consts::PI;
    use rustfft::FftPlanner;
    use num_complex::Complex32;
    use rayon::prelude::*;
    use rand::RngExt;
    use crate::dsp::filter::WindowType;

    const TAU: f32 = 2.0 * PI;
    const MINUS_INFINITY_DB: f32 = -144.0;

    // ============================================================================
    // INTERPOLATION
    // ============================================================================

    #[inline]
    pub fn lerp(a: f32, b: f32, t: f32) -> f32 {
        a + (b - a) * t
    }

    #[inline]
    pub fn quadratic_interp(y0: f32, y1: f32, y2: f32, x: f32) -> f32 {
        let a = y0 - 2.0 * y1 + y2;
        let b = 4.0 * y1 - 3.0 * y0 - y2;
        y0 + x * (b + x * a) / 2.0
    }

    #[inline]
    pub fn cubic_interp(y0: f32, y1: f32, y2: f32, y3: f32, mu: f32) -> f32 {
        let mu2 = mu * mu;
        let a0 = y3 - y2 - y0 + y1;
        let a1 = y0 - y1 - a0;
        let a2 = y2 - y0;
        let a3 = y1;
        a0 * mu * mu2 + a1 * mu2 + a2 * mu + a3
    }

    // ============================================================================
    // WINDOW FUNCTIONS
    // ============================================================================

    #[inline]
    pub fn sinc(x: f32) -> f32 {
        if x == 0.0 { 1.0 } else { (PI * x).sin() / (PI * x) }
    }

    #[inline]
    pub fn sinc_norm(x: f32) -> f32 {
        if x == 0.0 { 1.0 } else { (x * PI).sin() / (x * PI) }
    }

    #[inline]
    pub fn blackman_nuttall(x: f32) -> f32 {
        let a0 = 0.3635819;
        let a1 = 0.4891775;
        let a2 = 0.1365995;
        let a3 = 0.0106411;
        a0 - a1 * (TAU * x).cos() + a2 * (2.0 * TAU * x).cos() - a3 * (3.0 * TAU * x).cos()
    }

    // ============================================================================
    // CONVERSIONS
    // ============================================================================

    #[inline]
    pub fn db_to_linear(db: f32) -> f32 {
        if db > MINUS_INFINITY_DB { 10.0f32.powf(db / 20.0) } else { 0.0 }
    }

    #[inline]
    pub fn linear_to_db(linear: f32) -> f32 {
        if linear > 0.0 { 20.0 * linear.log10() } else { MINUS_INFINITY_DB }
    }

    #[inline]
    pub fn db_to_amplitude(db: f32) -> f32 { db_to_linear(db) }

    #[inline]
    pub fn amplitude_to_db(amplitude: f32) -> f32 { linear_to_db(amplitude) }

    #[inline]
    pub fn db_to_power(db: f32) -> f32 {
        if db > MINUS_INFINITY_DB { 10.0f32.powf(db / 10.0) } else { 0.0 }
    }

    #[inline]
    pub fn power_to_db(power: f32) -> f32 {
        if power > 0.0 { 10.0 * power.log10() } else { MINUS_INFINITY_DB }
    }

    // ============================================================================
    // MIDI & FREQUENCY
    // ============================================================================

    #[inline]
    pub fn midi_to_frequency(note: u8) -> f32 {
        const A4_FREQ: f32 = 440.0;
        const A4_NOTE: u8 = 69;
        A4_FREQ * 2.0f32.powf((note as f32 - A4_NOTE as f32) / 12.0)
    }

    #[inline]
    pub fn frequency_to_midi(freq: f32) -> u8 {
        const A4_FREQ: f32 = 440.0;
        const A4_NOTE: u8 = 69;
        (12.0 * (freq / A4_FREQ).log2() + A4_NOTE as f32).round() as u8
    }

    #[inline]
    pub fn frequency_to_samples(freq: f32, sample_rate: f32) -> f32 {
        sample_rate / freq
    }

    #[inline]
    pub fn samples_to_frequency(samples: f32, sample_rate: f32) -> f32 {
        sample_rate / samples
    }

    // ============================================================================
    // NORMALIZATION
    // ============================================================================

    #[inline]
    pub fn normalize_peak(signal: &mut [f32], target_peak: f32) {
        let peak = signal.iter().map(|&x| x.abs()).fold(0.0f32, |a, b| a.max(b));
        if peak > 0.0 {
            let gain = target_peak / peak;
            for sample in signal { *sample *= gain; }
        }
    }

    #[inline]
    pub fn normalize_rms(signal: &mut [f32], target_rms: f32) {
        let rms = calculate_rms(signal);
        if rms > 0.0 {
            let gain = target_rms / rms;
            for sample in signal { *sample *= gain; }
        }
    }

    // ============================================================================
    // SIGNAL ANALYSIS
    // ============================================================================

    #[inline]
    pub fn calculate_rms(signal: &[f32]) -> f32 {
        if signal.is_empty() { return 0.0; }
        let sum_squares: f32 = signal.iter().map(|&x| x * x).sum();
        (sum_squares / signal.len() as f32).sqrt()
    }

    #[inline]
    pub fn calculate_peak(signal: &[f32]) -> f32 {
        signal.iter().map(|&x| x.abs()).fold(0.0f32, |a, b| a.max(b))
    }

    #[inline]
    pub fn calculate_crest_factor(signal: &[f32]) -> f32 {
        let peak = calculate_peak(signal);
        let rms = calculate_rms(signal);
        if rms > 0.0 { peak / rms } else { 0.0 }
    }

    #[inline]
    pub fn calculate_dynamic_range(signal: &[f32]) -> f32 {
        linear_to_db(calculate_peak(signal)) - estimate_noise_floor(signal)
    }

    #[inline]
    pub fn estimate_noise_floor(signal: &[f32]) -> f32 {
        if signal.len() < 100 { return MINUS_INFINITY_DB; }
        let start = signal.len().saturating_sub(100);
        linear_to_db(calculate_rms(&signal[start..]))
    }

    // ============================================================================
    // DC OFFSET REMOVAL
    // ============================================================================

    #[inline]
    pub fn remove_dc_offset(signal: &mut [f32]) {
        let mean: f32 = signal.iter().sum::<f32>() / signal.len() as f32;
        for sample in signal { *sample -= mean; }
    }

    #[inline]
    pub fn remove_dc_offset_filter(signal: &mut [f32], sample_rate: f32) {
        let cutoff = 10.0;
        let rc = 1.0 / (2.0 * PI * cutoff);
        let dt = 1.0 / sample_rate;
        let alpha = dt / (rc + dt);
        let mut y = 0.0;
        for sample in signal {
            y = alpha * (*sample - y) + y;
            *sample -= y;
        }
    }

    // ============================================================================
    // DISTORTION
    // ============================================================================

    #[inline]
    pub fn soft_clip(sample: f32, threshold: f32) -> f32 {
        if sample.abs() > threshold { sample.tanh() * threshold } else { sample }
    }

    #[inline]
    pub fn hard_clip(sample: f32, threshold: f32) -> f32 {
        sample.clamp(-threshold, threshold)
    }

    #[inline]
    pub fn asymmetric_clip(sample: f32, positive_threshold: f32, negative_threshold: f32) -> f32 {
        if sample > positive_threshold { positive_threshold }
        else if sample < -negative_threshold { -negative_threshold }
        else { sample }
    }

    #[inline]
    pub fn foldback_distortion(sample: f32, threshold: f32) -> f32 {
        if sample.abs() > threshold {
            let folded = (sample.abs() - threshold) % (4.0 * threshold);
            if folded > 2.0 * threshold {
                sample.signum() * (4.0 * threshold - folded)
            } else {
                sample.signum() * folded
            }
        } else { sample }
    }

    #[inline]
    pub fn wave_shape(sample: f32, coefficients: &[f32]) -> f32 {
        coefficients.iter().enumerate().fold(0.0, |acc, (i, &coeff)| acc + coeff * sample.powi(i as i32))
    }

    // ============================================================================
    // TIME DOMAIN ANALYSIS
    // ============================================================================

    #[inline]
    pub fn zero_crossing_rate(signal: &[f32]) -> f32 {
        if signal.len() < 2 { return 0.0; }
        let crossings = (1..signal.len()).filter(|&i| signal[i] * signal[i - 1] < 0.0).count();
        crossings as f32 / (signal.len() - 1) as f32
    }

    #[inline]
    pub fn autocorrelation(signal: &[f32], max_lag: usize) -> Vec<f32> {
        let n = signal.len();
        let max_lag = max_lag.min(n - 1);
        (0..max_lag).map(|lag| {
            (0..n - lag).map(|i| signal[i] * signal[i + lag]).sum::<f32>() / (n - lag) as f32
        }).collect()
    }

    // ============================================================================
    // PITCH DETECTION (YIN)
    // ============================================================================
    #[inline]
    pub fn yin_pitch_detection(signal: &[f32], sample_rate: f32, min_freq: f32, max_freq: f32) -> Option<f32> {
        let min_period = (sample_rate / max_freq) as usize;
        let max_period = (sample_rate / min_freq) as usize;
        if signal.len() < max_period * 2 { return None; }

        let mut diff = vec![0.0; max_period];
        for tau in min_period..max_period {
            diff[tau] = (0..tau).map(|i| (signal[i] - signal[i + tau]).powi(2)).sum();
        }

        let mut running_sum = diff[min_period];
        let mut cmnd = vec![0.0; max_period];
        cmnd[min_period] = 1.0;
        for tau in min_period + 1..max_period {
            running_sum += diff[tau];
            cmnd[tau] = diff[tau] * tau as f32 / running_sum;
        }

        let threshold = 0.1;
        let tau_estimate = cmnd.iter().skip(min_period).position(|&v| v < threshold).map(|p| p + min_period).unwrap_or(min_period);

        if tau_estimate > min_period && tau_estimate < max_period - 1 {
            let alpha = cmnd[tau_estimate - 1];
            let beta = cmnd[tau_estimate];
            let gamma = cmnd[tau_estimate + 1];
            let period = tau_estimate as f32 + 0.5 * (alpha - gamma) / (alpha - 2.0 * beta + gamma);
            if period > 0.0 { return Some(sample_rate / period); }
        }
        None
    }

    // ============================================================================
    // SPECTRAL ANALYSIS
    // ============================================================================

    #[inline]
    pub fn spectral_centroid(magnitudes: &[f32], sample_rate: f32) -> f32 {
        let mut weighted_sum = 0.0;
        let mut total = 0.0;
        let bin_freq = sample_rate / (2.0 * magnitudes.len() as f32);
        for (i, &mag) in magnitudes.iter().enumerate() {
            weighted_sum += i as f32 * bin_freq * mag;
            total += mag;
        }
        if total > 0.0 { weighted_sum / total } else { 0.0 }
    }

    #[inline]
    pub fn spectral_spread(magnitudes: &[f32], centroid: f32, sample_rate: f32) -> f32 {
        let mut variance = 0.0;
        let mut total = 0.0;
        let bin_freq = sample_rate / (2.0 * magnitudes.len() as f32);
        for (i, &mag) in magnitudes.iter().enumerate() {
            let freq = i as f32 * bin_freq;
            let diff = freq - centroid;
            variance += diff * diff * mag;
            total += mag;
        }
        if total > 0.0 { (variance / total).sqrt() } else { 0.0 }
    }

    #[inline]
    pub fn spectral_flatness(magnitudes: &[f32]) -> f32 {
        if magnitudes.is_empty() { return 0.0; }
        let geometric_mean = magnitudes.iter().map(|&x| if x > 0.0 { x.ln() } else { -1e10 }).sum::<f32>() / magnitudes.len() as f32;
        let arithmetic_mean = magnitudes.iter().sum::<f32>() / magnitudes.len() as f32;
        if arithmetic_mean > 0.0 { geometric_mean.exp() / arithmetic_mean } else { 0.0 }
    }

    #[inline]
    pub fn spectral_rolloff(magnitudes: &[f32], sample_rate: f32, percentile: f32) -> f32 {
        let total_energy: f32 = magnitudes.iter().map(|&x| x * x).sum();
        let target = total_energy * percentile;
        let mut accumulated = 0.0;
        let bin_freq = sample_rate / (2.0 * magnitudes.len() as f32);
        for (i, &mag) in magnitudes.iter().enumerate() {
            accumulated += mag * mag;
            if accumulated >= target {
                return i as f32 * bin_freq;
            }
        }
        0.0
    }

    #[inline]
    pub fn spectral_slope(magnitudes: &[f32], sample_rate: f32) -> f32 {
        if magnitudes.len() < 2 { return 0.0; }
        let n = magnitudes.len() as f32;
        let bin_freq = sample_rate / (2.0 * n);
        let (sum_x, sum_y, sum_xy, sum_x2) = magnitudes.iter().enumerate().fold((0.0, 0.0, 0.0, 0.0), |(sx, sy, sxy, sx2), (i, &mag)| {
            let x = i as f32 * bin_freq;
            (sx + x, sy + mag, sxy + x * mag, sx2 + x * x)
        });
        let denom = n * sum_x2 - sum_x * sum_x;
        if denom.abs() > f32::EPSILON { (n * sum_xy - sum_x * sum_y) / denom } else { 0.0 }
    }

    // ============================================================================
    // MFCC
    // ============================================================================
    #[inline]
    pub fn mfcc(mel_spectrum: &[f32], num_coeffs: usize) -> Vec<f32> {
        let n = mel_spectrum.len() as f32;
        (0..num_coeffs).map(|k| {
            let sum: f32 = (0..mel_spectrum.len()).map(|m| {
                mel_spectrum[m].ln() * (PI * (m as f32 + 0.5) * k as f32 / n).cos()
            }).sum();
            sum * (2.0 / n).sqrt()
        }).collect()
    }
    // ============================================================================
    // MFCC EXTRACTION (для Oban Worker)
    // ============================================================================
    #[inline]
    pub fn compute_mfcc(
        samples: &[f32],
        sample_rate: f32,
        frame_size: usize,
        hop_size: usize,
        num_coeffs: usize,
    ) -> Vec<Vec<f32>> {
        if samples.is_empty() || frame_size == 0 || hop_size == 0 {
            return vec![];
        }

        let window = create_window(frame_size, WindowType::Hann);
        let mut planner = FftPlanner::new();
        let fft = planner.plan_fft_forward(frame_size);
        let mut scratch = vec![Complex32::new(0.0, 0.0); fft.get_inplace_scratch_len()];
        let num_mels = 40;
        let mel_filters = create_mel_filter_bank(num_mels, frame_size, sample_rate, 0.0, sample_rate / 2.0);
        let mut mfcc_features = Vec::new();
        let mut start = 0;
        
        while start + frame_size <= samples.len() {
            let mut frame: Vec<Complex32> = samples[start..start + frame_size]
                .iter()
                .zip(window.iter())
                .map(|(&s, &w)| Complex32::new(s * w, 0.0))
                .collect();
            fft.process_with_scratch(&mut frame, &mut scratch);
            let magnitudes: Vec<f32> = frame.iter().take(frame_size / 2 + 1).map(|c| c.norm()).collect();
            let mut mel_energies = vec![0.0; num_mels];
            for (i, filter) in mel_filters.iter().enumerate() {
                let energy: f32 = magnitudes.iter().zip(filter.iter()).map(|(&mag, &f)| mag * f).sum();
                mel_energies[i] = if energy > 0.0 { energy.ln() } else { 0.0 };
            }
            
            let mfcc = dct(&mel_energies, num_coeffs);
            mfcc_features.push(mfcc);
            
            start += hop_size;
        }
        
        mfcc_features
    }

    #[inline]
    fn create_mel_filter_bank(
        num_filters: usize,
        fft_size: usize,
        sample_rate: f32,
        min_freq: f32,
        max_freq: f32,
    ) -> Vec<Vec<f32>> {
        let min_mel = hz_to_mel(min_freq);
        let max_mel = hz_to_mel(max_freq);
        let mel_step = (max_mel - min_mel) / (num_filters + 1) as f32;
        let mel_points: Vec<f32> = (0..num_filters + 2).map(|i| min_mel + i as f32 * mel_step).collect();
        let freq_points: Vec<f32> = mel_points.iter().map(|&mel| mel_to_hz(mel)).collect();
        let bin_points: Vec<usize> = freq_points.iter().map(|&freq| (freq * fft_size as f32 / sample_rate) as usize).collect();
        let mut filter_bank = vec![vec![0.0; fft_size / 2 + 1]; num_filters];
        
        for i in 0..num_filters {
            let start = bin_points[i];
            let center = bin_points[i + 1];
            let end = bin_points[i + 2];
            
            for j in start..center.min(filter_bank[i].len()) {
                let weight = (j - start) as f32 / (center - start) as f32;
                filter_bank[i][j] = weight;
            }
            
            for j in center..end.min(filter_bank[i].len()) {
                let weight = (end - j) as f32 / (end - center) as f32;
                filter_bank[i][j] = weight;
            }
        }
        
        filter_bank
    }

    #[inline]
    fn dct(input: &[f32], num_coeffs: usize) -> Vec<f32> {
        let n = input.len() as f32;
        let mut output = vec![0.0; num_coeffs];
        output.iter_mut().enumerate().take(num_coeffs).for_each(|(k, out_val)| {
                let sum: f32 = input.iter().enumerate().map(|(i, &x)| x * (PI * (i as f32 + 0.5) * k as f32 / n).cos()).sum();
                *out_val = (2.0 / n).sqrt() * sum;
            });
        output
    }

    #[inline]
    pub fn create_window(size: usize, window_type: WindowType) -> Vec<f32> {
        if size == 0 { return vec![]; }
        
        let mut window = vec![0.0; size];
        let n_minus_1 = (size - 1) as f32;
        
        match window_type {
            WindowType::Rectangular => window.fill(1.0),
            WindowType::Hann => {
                window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                        let n = i as f32 / n_minus_1;
                        *w = 0.5 * (1.0 - (2.0 * PI * n).cos());
                    });
            }
            WindowType::Hamming => {
                window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                        let n = i as f32 / n_minus_1;
                        *w = 0.54 - 0.46 * (2.0 * PI * n).cos();
                    });
            }
            WindowType::Blackman => {
                window.iter_mut().enumerate().take(size).for_each(|(i, w)| {
                        let n = i as f32 / n_minus_1;
                        *w = 0.42 - 0.5 * (2.0 * PI * n).cos() + 0.08 * (4.0 * PI * n).cos();
                    });
            }
        }
        
        window
    }

    #[inline]
    pub fn hz_to_mel(freq: f32) -> f32 {
        if freq <= 0.0 { return 0.0; }
        2595.0 * (1.0 + freq / 700.0).log10()
    }

    #[inline]
    pub fn mel_to_hz(mel: f32) -> f32 {
        if mel <= 0.0 { return 0.0; }
        700.0 * (10.0f32.powf(mel / 2595.0) - 1.0)
    }

    #[inline]
    pub fn compute_embedding(mfcc_features: &[Vec<f32>]) -> Vec<f32> {
        if mfcc_features.is_empty() {
            return vec![0.0; 128];
        }
        
        let num_frames = mfcc_features.len();
        let num_coeffs = mfcc_features[0].len();
        let mut embedding = Vec::with_capacity(num_coeffs * 2);

        let results: Vec<(f32, f32)> = (0..num_coeffs).into_par_iter().map(|coeff| {
            let sum: f32 = mfcc_features.par_iter()
                .take(num_frames)
                .map(|frame| frame[coeff])
                .sum();
            let mean = sum / num_frames as f32;
            
            let variance: f32 = mfcc_features.par_iter()
                .take(num_frames)
                .map(|frame| {
                    let diff = frame[coeff] - mean;
                    diff * diff
                })
                .sum();
            let std = (variance / num_frames as f32).sqrt();
            
            (mean, std)
        }).collect();

        for (mean, std) in results {
            embedding.push(mean);
            embedding.push(std);
        }
        
        embedding
    }

    #[inline]
    pub fn convert_to_f32(audio_data: &[u8], _sample_rate: u32, channels: u16) -> Result<Vec<f32>, String> {
        if audio_data.is_empty() {
            return Err("Audio data is empty".to_string());
        }

        if audio_data.len() > 44 && &audio_data[0..4] == b"RIFF" {
            return convert_wav_to_f32(audio_data);
        }

        convert_raw_pcm_to_f32(audio_data, channels)
    }

    #[inline]
    fn convert_wav_to_f32(audio_data: &[u8]) -> Result<Vec<f32>, String> {
        if audio_data.len() < 44 {
            return Err("WAV header too short".to_string());
        }

        let audio_format = u16::from_le_bytes([audio_data[20], audio_data[21]]);
        let num_channels = u16::from_le_bytes([audio_data[22], audio_data[23]]);
        let _sample_rate = u32::from_le_bytes([audio_data[24], audio_data[25], audio_data[26], audio_data[27]]);
        let bits_per_sample = u16::from_le_bytes([audio_data[34], audio_data[35]]);
        
        let mut data_start = 36;
        let mut data_size = 0;
        
        let mut pos = 36;
        while pos + 8 <= audio_data.len() {
            let chunk_id = &audio_data[pos..pos + 4];
            let chunk_size = u32::from_le_bytes([audio_data[pos + 4], audio_data[pos + 5], audio_data[pos + 6], audio_data[pos + 7]]) as usize;
            
            if chunk_id == b"data" {
                data_start = pos + 8;
                data_size = chunk_size;
                break;
            }
            pos += 8 + chunk_size;
        }
        
        if data_size == 0 {
            return Err("No data chunk found in WAV".to_string());
        }
        
        let data_end = (data_start + data_size).min(audio_data.len());
        let pcm_data = &audio_data[data_start..data_end];
        
        convert_pcm_to_f32(pcm_data, audio_format, num_channels, bits_per_sample)
    }

    #[inline]
    fn convert_pcm_to_f32(
        pcm_data: &[u8],
        audio_format: u16,
        num_channels: u16,
        bits_per_sample: u16,
    ) -> Result<Vec<f32>, String> {
        let bytes_per_sample = (bits_per_sample / 8) as usize;
        let expected_len = pcm_data.len() / bytes_per_sample;
        
        let mut samples = Vec::with_capacity(expected_len);
        
        match audio_format {
            1 => {
                match bits_per_sample {
                    16 => {
                        if !pcm_data.len().is_multiple_of(2) {
                            return Err("S16 data not aligned".to_string());
                        }
                        for chunk in pcm_data.chunks_exact(2) {
                            let sample = i16::from_le_bytes([chunk[0], chunk[1]]) as f32 / 32768.0;
                            samples.push(sample);
                        }
                    }
                    24 => {
                        if !pcm_data.len().is_multiple_of(3) {
                            return Err("S24 data not aligned".to_string());
                        }
                        for chunk in pcm_data.chunks_exact(3) {
                            let sign_extend = if chunk[2] & 0x80 != 0 { 0xFF } else { 0x00 };
                            let val = i32::from_le_bytes([chunk[0], chunk[1], chunk[2], sign_extend]);
                            let sample = val as f32 / 8388608.0;
                            samples.push(sample);
                        }
                    }
                    32 => {
                        if !pcm_data.len().is_multiple_of(4) {
                            return Err("S32/F32 data not aligned".to_string());
                        }
                        for chunk in pcm_data.chunks_exact(4) {
                            let float_sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                            if float_sample.is_finite() && float_sample.abs() <= 1.0 {
                                samples.push(float_sample);
                            } else {
                                let int_sample = i32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]) as f32 / 2147483648.0;
                                samples.push(int_sample);
                            }
                        }
                    }
                    _ => {
                        return Err(format!("Unsupported bits per sample: {}", bits_per_sample));
                    }
                }
            }
            3 => {
                if bits_per_sample != 32 {
                    return Err(format!("Float format with {} bits not supported", bits_per_sample));
                }
                for chunk in pcm_data.chunks_exact(4) {
                    let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                    samples.push(sample);
                }
            }
            _ => {
                return Err(format!("Unsupported audio format: {}", audio_format));
            }
        }
        if num_channels == 2 {
            let mono_len = samples.len() / 2;
            let mut mono = Vec::with_capacity(mono_len);
            for i in 0..mono_len {
                let left = samples[i * 2];
                let right = samples[i * 2 + 1];
                mono.push((left + right) * 0.5);
            }
            Ok(mono)
        } else {
            Ok(samples)
        }
    }

    #[inline]
    fn convert_raw_pcm_to_f32(audio_data: &[u8], channels: u16) -> Result<Vec<f32>, String> {
        if audio_data.len().is_multiple_of(4) && channels == 1 {
            let mut samples = Vec::with_capacity(audio_data.len() / 4);
            for chunk in audio_data.chunks_exact(4) {
                let sample = f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]);
                if sample.is_finite() && sample.abs() <= 1.0 {
                    samples.push(sample);
                } else {
                    return convert_raw_pcm_as_s16(audio_data, channels);
                }
            }
            Ok(samples)
        } else if audio_data.len().is_multiple_of(2) {
            convert_raw_pcm_as_s16(audio_data, channels)
        } else {
            Err("Unknown PCM format".to_string())
        }
    }

    #[inline]
    fn convert_raw_pcm_as_s16(audio_data: &[u8], channels: u16) -> Result<Vec<f32>, String> {
        if !audio_data.len().is_multiple_of(2) {
            return Err("S16 data not aligned".to_string());
        }
        
        let mut samples = Vec::with_capacity(audio_data.len() / 2);
        for chunk in audio_data.chunks_exact(2) {
            let sample = i16::from_le_bytes([chunk[0], chunk[1]]) as f32 / 32768.0;
            samples.push(sample);
        }
        
        if channels == 2 {
            let mono_len = samples.len() / 2;
            let mut mono = Vec::with_capacity(mono_len);
            for i in 0..mono_len {
                let left = samples[i * 2];
                let right = samples[i * 2 + 1];
                mono.push((left + right) * 0.5);
            }
            Ok(mono)
        } else {
            Ok(samples)
        }
    }

    #[inline]
    pub fn resample_to_target_rate(
        samples: &[f32],
        original_rate: u32,
        target_rate: u32,
    ) -> Vec<f32> {
        if original_rate == target_rate {
            return samples.to_vec();
        }
        
        let ratio = original_rate as f32 / target_rate as f32;
        let output_len = (samples.len() as f32 / ratio).ceil() as usize;
        let mut output = Vec::with_capacity(output_len);
        
        for i in 0..output_len {
            let src_pos = i as f32 * ratio;
            let idx = src_pos as usize;
            let frac = src_pos - idx as f32;
            
            if idx + 1 < samples.len() {
                let sample = samples[idx] * (1.0 - frac) + samples[idx + 1] * frac;
                output.push(sample);
            } else if idx < samples.len() {
                output.push(samples[idx]);
            } else {
                output.push(0.0);
            }
        }
        
        output
    }

    #[inline]
    pub fn normalize_audio(samples: &mut [f32], target_peak: f32) {
        let peak = calculate_peak(samples);
        if peak > 0.0 {
            let gain = target_peak / peak;
            for sample in samples {
                *sample *= gain;
            }
        }
    }

    #[inline]
    pub fn extract_mfcc_features(
        samples: &[f32],
        sample_rate: f32,
        frame_size_ms: f32,
        hop_size_ms: f32,
        num_coeffs: usize,
    ) -> Vec<Vec<f32>> {
        let frame_size = (frame_size_ms * 0.001 * sample_rate) as usize;
        let hop_size = (hop_size_ms * 0.001 * sample_rate) as usize;
        
        compute_mfcc(samples, sample_rate, frame_size, hop_size, num_coeffs)
    }

    #[inline]
    pub fn compute_audio_embedding(
        samples: &[f32],
        sample_rate: f32,
    ) -> Vec<f32> {
        let frame_size_ms = 25.0;
        let hop_size_ms = 10.0;
        let num_mfcc = 13;
        let mfcc_features = extract_mfcc_features(
            samples,
            sample_rate,
            frame_size_ms,
            hop_size_ms,
            num_mfcc,
        );
        
        compute_embedding(&mfcc_features)
    }

    // ============================================================================
    // SIGNAL GENERATION
    // ============================================================================
    #[inline]
    pub fn generate_sine_signal(frequency: f32, sample_rate: f32, duration: f32, amplitude: f32) -> Vec<f32> {
        let samples = (duration * sample_rate) as usize;
        let angular_freq = 2.0 * PI * frequency / sample_rate;
        (0..samples).map(|i| amplitude * (angular_freq * i as f32).sin()).collect()
    }

    #[inline]
    pub fn generate_white_noise(samples: usize, amplitude: f32) -> Vec<f32> {
        let mut rng = rand::rng();
        (0..samples).map(|_| rng.random_range(-amplitude..amplitude)).collect()
    }

    #[inline]
    pub fn generate_pink_noise(samples: usize, amplitude: f32) -> Vec<f32> {
        let mut noise = vec![0.0; samples];
        let mut b0 = 0.0; let mut b1 = 0.0; let mut b2 = 0.0;
        let mut b3 = 0.0; let mut b4 = 0.0; let mut b5 = 0.0;
        let mut rng = rand::rng();

        for (i, val) in noise.iter_mut().enumerate() {
            if i % 2 == 0 { b0 = rng.random_range(-1.0..1.0); }
            if i % 4 == 0 { b1 = rng.random_range(-1.0..1.0); }
            if i % 8 == 0 { b2 = rng.random_range(-1.0..1.0); }
            if i % 16 == 0 { b3 = rng.random_range(-1.0..1.0); }
            if i % 32 == 0 { b4 = rng.random_range(-1.0..1.0); }
            if i % 64 == 0 { b5 = rng.random_range(-1.0..1.0); }
            *val = (b0 + b1 + b2 + b3 + b4 + b5) * amplitude * 0.1666667;
        }
        noise
    }

    // ============================================================================
    // FADING & CROSSFADING
    // ============================================================================

    #[inline]
    pub fn apply_fade_in(signal: &mut [f32], fade_samples: usize) {
        let fade_len = fade_samples.min(signal.len());
        signal.iter_mut().enumerate().take(fade_len).for_each(|(i, val)| *val *= i as f32 / fade_len as f32);
    }

    #[inline]
    pub fn apply_fade_out_effect(signal: &mut [f32], fade_samples: usize) {
        let fade_len = fade_samples.min(signal.len());
        let start = signal.len().saturating_sub(fade_len);
        for i in 0..fade_len { signal[start + i] *= 1.0 - i as f32 / fade_len as f32; }
    }

    #[inline]
    pub fn crossfade(signal1: &[f32], signal2: &[f32], fade_samples: usize) -> Vec<f32> {
        let len = signal1.len().max(signal2.len());
        let fade_len = fade_samples.min(len);
        (0..len).map(|i| {
            let mut sample = 0.0;
            if i < signal1.len() {
                let fade_out = if i < fade_len { 1.0 - i as f32 / fade_len as f32 } else { 0.0 };
                sample += signal1[i] * fade_out;
            }
            if i < signal2.len() {
                let fade_in = if i >= len - fade_len { (i - (len - fade_len)) as f32 / fade_len as f32 } else { 0.0 };
                sample += signal2[i] * fade_in;
            }
            sample
        }).collect()
    }

    // ============================================================================
    // LOUDNESS (LUFS)
    // ============================================================================

    #[inline]
    pub fn calculate_lufs(signal: &[f32], sample_rate: f32) -> f32 {
        let filtered = apply_k_filter(signal, sample_rate);
        let mean_square = filtered.iter().map(|&x| x * x).sum::<f32>() / filtered.len() as f32;
        -0.691 + 10.0 * mean_square.log10()
    }

    #[inline]
    fn apply_k_filter(signal: &[f32], sample_rate: f32) -> Vec<f32> {
        let mut filtered = vec![0.0; signal.len()];
        let f0 = 1681.0;
        let g: f32 = 4.0;
        let q = 0.707;
        let w0 = 2.0 * PI * f0 / sample_rate;
        let alpha = w0.sin() / (2.0 * q);
        let a = g.sqrt();
        let b0 = a * ((a + 1.0) + (a - 1.0) * w0.cos() + 2.0 * a.sqrt() * alpha);
        let b1 = -2.0 * a * ((a - 1.0) + (a + 1.0) * w0.cos());
        let b2 = a * ((a + 1.0) + (a - 1.0) * w0.cos() - 2.0 * a.sqrt() * alpha);
        let a0 = (a + 1.0) - (a - 1.0) * w0.cos() + 2.0 * a.sqrt() * alpha;
        let a1 = 2.0 * ((a - 1.0) - (a + 1.0) * w0.cos());
        let a2 = (a + 1.0) - (a - 1.0) * w0.cos() - 2.0 * a.sqrt() * alpha;
        let mut x1 = 0.0; let mut x2 = 0.0; let mut y1 = 0.0; let mut y2 = 0.0;
        for (i, &sample) in signal.iter().enumerate() {
            let x0 = sample;
            let y0 = (b0 * x0 + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0;
            filtered[i] = y0;
            x2 = x1; x1 = x0; y2 = y1; y1 = y0;
        }
        filtered
    }

    // ============================================================================
    // TIME & SAMPLES
    // ============================================================================

    #[inline]
    pub fn samples_to_time(samples: usize, sample_rate: f32) -> f32 {
        samples as f32 / sample_rate
    }

    #[inline]
    pub fn time_to_samples(time: f32, sample_rate: f32) -> usize {
        (time * sample_rate) as usize
    }

    // ============================================================================
    // POWER OF TWO
    // ============================================================================

    pub fn next_power_of_two(mut n: usize) -> usize {
        if n == 0 { return 1; }
        n -= 1;
        n |= n >> 1;
        n |= n >> 2;
        n |= n >> 4;
        n |= n >> 8;
        n |= n >> 16;
        n += 1;
        n
    }

    #[inline]
    pub fn is_power_of_two(n: usize) -> bool {
        n > 0 && (n & (n - 1)) == 0
    }

    #[inline]
    pub fn log2_power_of_two(n: usize) -> u32 {
        n.trailing_zeros()
    }

    // ============================================================================
    // TYPE CONVERSIONS
    // ============================================================================

    #[inline]
    pub fn clone_slice_as_f32(slice: &[f64]) -> Vec<f32> {
        slice.iter().map(|&x| x as f32).collect()
    }

    #[inline]
    pub fn clone_slice_as_f64(slice: &[f32]) -> Vec<f64> {
        slice.iter().map(|&x| x as f64).collect()
    }

    // ============================================================================
    // ADDITIONAL UTILITIES
    // ============================================================================

    #[inline]
    pub fn clamp(value: f32, min: f32, max: f32) -> f32 {
        value.max(min).min(max)
    }

    #[inline]
    pub fn ms_to_samples(ms: f32, sample_rate: f32) -> usize {
        ((ms * 0.001) * sample_rate) as usize
    }

    #[inline]
    pub fn samples_to_ms(samples: usize, sample_rate: f32) -> f32 {
        samples as f32 / sample_rate * 1000.0
    }

    #[inline]
    pub fn linear_interpolate(x0: f32, x1: f32, fraction: f32) -> f32 {
        x0 + (x1 - x0) * fraction
    }

    #[inline]
    pub fn hermite_interpolate(y0: f32, y1: f32, y2: f32, y3: f32, t: f32) -> f32 {
        let t2 = t * t;
        let _t3 = t2 * t;
        
        let a0 = y1;
        let a1 = 0.5 * (y2 - y0);
        let a2 = y0 - 2.5 * y1 + 2.0 * y2 - 0.5 * y3;
        let a3 = 0.5 * (y3 - y0) + 1.5 * (y1 - y2);
        
        ((a3 * t + a2) * t + a1) * t + a0
    }

    #[inline]
    pub fn sanitize(value: f32, default: f32) -> f32 {
        if value.is_finite() { value } else { default }
    }

    #[inline]
    pub fn apply_gain(sample: f32, gain: f32) -> f32 {
        (sample * gain).clamp(-1.0, 1.0)
    }

    #[inline]
    pub fn calculate_std_dev(signal: &[f32]) -> f32 {
        if signal.is_empty() { return 0.0; }
        let mean = signal.iter().sum::<f32>() / signal.len() as f32;
        let variance = signal.iter().map(|&x| (x - mean).powi(2)).sum::<f32>() / signal.len() as f32;
        variance.sqrt()
    }

    #[inline]
    pub fn ema(current: f32, previous: f32, alpha: f32) -> f32 {
        previous + alpha * (current - previous)
    }

    pub fn moving_average(signal: &[f32], window_size: usize) -> Vec<f32> {
        if signal.is_empty() || window_size == 0 {
            return vec![];
        }
        
        let window_size = window_size.min(signal.len());
        let mut result = vec![0.0; signal.len()];
        let mut sum: f32 = signal.iter().take(window_size).sum();
        
        for i in 0..signal.len() {
            if i >= window_size {
                sum += signal[i] - signal[i - window_size];
            }
            result[i] = sum / window_size as f32;
        }
        
        result
    }
}
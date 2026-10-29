//! Интеграционные тесты для аудио эффектов

#[cfg(test)]
mod integration_tests {
    use audio_effects_native::{
        audio::AudioBuffer,
        dsp::utils::{calculate_peak, calculate_rms, generate_sine},
        effects::{EffectChain, EffectConfig, EffectType},
        AudioFormat, AudioProcessor, SampleRate,
    };

    #[test]
    fn test_processor_chain() {
        let format = AudioFormat {
            sample_rate: SampleRate::Hz44100,
            channels: 2,
            bit_depth: 32,
            floating_point: true,
        };

        let effect_configs = vec![EffectConfig {
            effect_type: EffectType::Compressor,
            enabled: true,
            mix: 1.0,
            parameters: serde_json::json!({
                "threshold": -10.0,
                "ratio": 2.0,
                "attack": 10.0,
                "release": 100.0
            }),
            position: 0,
        }];

        let mut processor = AudioProcessor::new(effect_configs, format).unwrap();

        // Создание тестового сигнала
        let sample_rate = format.sample_rate_hz() as f32;
        let samples = (1.0 * sample_rate) as usize; // 1 секунда

        let mut test_signal = Vec::with_capacity(samples * 2);
        for (i, _) in float_data.iter().enumerate().take(samples) {
            let t = i as f32 / sample_rate;
            let sample = (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.8;
            test_signal.push(sample);
            test_signal.push(sample * 0.9);
        }

        let mut buffer = AudioBuffer::from_slice(&test_signal, format).unwrap();

        // Обработка
        processor.process(&mut buffer).unwrap();

        // Проверки
        let output_peak = buffer.calculate_peak();
        assert!(output_peak <= 1.0, "Пиковое значение не должно превышать 1.0");

        let output_rms = buffer.calculate_rms();
        assert!(output_rms > 0.0, "RMS должно быть больше 0");
    }

    #[test]
    fn test_effect_chain_serialization() {
        let format = AudioFormat {
            sample_rate: SampleRate::Hz48000,
            channels: 2,
            bit_depth: 32,
            floating_point: true,
        };

        let effect_configs = vec![EffectConfig {
            effect_type: EffectType::Equalizer,
            enabled: true,
            mix: 1.0,
            parameters: serde_json::json!({
                "bands": [
                    {"frequency": 100.0, "gain": 3.0, "q": 1.0}
                ]
            }),
            position: 0,
        }];

        let chain = EffectChain::new(effect_configs.clone(), format).unwrap();

        // Сериализация
        let serialized = bincode::serialize(&chain).unwrap();

        // Десериализация
        let deserialized: EffectChain = bincode::deserialize(&serialized).unwrap();

        assert_eq!(chain.get_configs().len(), deserialized.get_configs().len());
    }

    #[test]
    fn test_compressor_dynamics() {
        use audio_effects_native::dsp::compressor::{Compressor, CompressorConfig, DynamicsType};

        let sample_rate = 44100.0;
        let mut compressor = Compressor::new(CompressorConfig::default(), sample_rate);

        // Тихий сигнал не должен сжиматься
        let mut quiet_signal = vec![0.1; 1000];
        let quiet_before = quiet_signal.clone();
        compressor.process_buffer(&mut quiet_signal);

        // Разница должна быть минимальной
        let max_diff = quiet_signal
            .iter()
            .zip(quiet_before.iter())
            .map(|(a, b)| (a - b).abs())
            .fold(0.0, f32::max);

        assert!(max_diff < 0.01, "Тихий сигнал не должен сжиматься");

        // Громкий сигнал должен сжиматься
        compressor.reset();
        let mut loud_signal = vec![0.8; 1000];
        let loud_before = loud_signal.clone();
        compressor.process_buffer(&mut loud_signal);

        let compression_ratio = loud_before[0] / loud_signal[0];
        assert!(compression_ratio > 1.0, "Громкий сигнал должен сжиматься");
    }

    #[test]
    fn test_eq_frequency_response() {
        use audio_effects_native::dsp::eq::{EQBand, EQFilterType, ParametricEQ};

        let sample_rate = 44100.0;
        let bands = vec![EQBand {
            frequency: 1000.0,
            gain: 6.0, // +6 dB усиление
            q: 1.0,
            filter_type: EQFilterType::Peak,
            enabled: true,
            slope: 1.0,
        }];

        let eq = ParametricEQ::new(bands, sample_rate, 0.0);

        // Проверка частотной характеристики на частоте фильтра
        let response = eq.calculate_frequency_response_analytical(1000.0);
        let response_db = 20.0 * response.log10();

        // Должно быть примерно +6 dB
        assert!(
            (response_db - 6.0).abs() < 1.0,
            "На частоте 1000 Гц должно быть усиление около +6 dB, получено: {} dB",
            response_db
        );
    }

    #[test]
    fn test_reverb_impulse_response() {
        use audio_effects_native::dsp::reverb::{ReverbAlgorithm, ReverbParams, ReverbProcessor};

        let sample_rate = 44100.0;
        let params = ReverbParams {
            algorithm: ReverbAlgorithm::FDN,
            decay_time: 1.0,
            room_size: 0.5,
            ..Default::default()
        };

        let reverb = ReverbProcessor::new(params, sample_rate);

        // Получение импульсной характеристики
        let impulse_response = reverb.get_impulse_response(44100); // 1 секунда

        // Импульсная характеристика должна затухать
        let early_energy: f32 = impulse_response[0..1000].iter().map(|x| x * x).sum();
        let late_energy: f32 = impulse_response[40000..].iter().map(|x| x * x).sum();

        assert!(late_energy < early_energy * 0.1, "Энергия должна затухать со временем");
    }

    #[test]
    fn test_pitch_shifting() {
        use audio_effects_native::audio::AudioFormat;
        use audio_effects_native::effects::{PitchAlgorithm, PitchShift, PitchShiftConfig};

        let format = AudioFormat {
            sample_rate: SampleRate::Hz44100,
            channels: 1,
            bit_depth: 32,
            floating_point: true,
        };

        let config = PitchShiftConfig {
            algorithm: PitchAlgorithm::PhaseVocoder,
            pitch_shift: 7.0, // +7 semitones
            ..Default::default()
        };

        let mut pitch_shifter = PitchShift::new(config, format);

        // Синусоида 440 Hz (A4)
        let sample_rate = format.sample_rate_hz() as f32;
        let mut signal = generate_sine(440.0, sample_rate, 0.5, 0.5);

        let mut buffer = AudioBuffer::from_slice(&signal, format).unwrap();
        pitch_shifter.process(&mut buffer).unwrap();

        // После pitch shift на +7 semitones должна быть частота ~659 Hz (E5)
        // (440 * 2^(7/12) ≈ 659.25)

        // Простая проверка что сигнал изменился
        let processed = buffer.into_vec();
        let correlation: f32 = signal.iter().zip(processed.iter()).map(|(a, b)| a * b).sum();

        assert!(correlation < 0.5, "Сигнал должен измениться после pitch shifting");
    }

    #[test]
    fn test_batch_processing_performance() {
        let format = AudioFormat {
            sample_rate: SampleRate::Hz44100,
            channels: 2,
            bit_depth: 32,
            floating_point: true,
        };

        let effect_configs = vec![EffectConfig {
            effect_type: EffectType::Compressor,
            enabled: true,
            mix: 1.0,
            parameters: serde_json::json!({}),
            position: 0,
        }];

        let mut processor = AudioProcessor::new(effect_configs, format).unwrap();

        // Создание нескольких буферов
        let sample_rate = format.sample_rate_hz() as f32;
        let mut buffers = Vec::new();

        for _ in 0..10 {
            let samples = (0.1 * sample_rate) as usize; // 100 ms
            let mut signal = Vec::with_capacity(samples * 2);

            for (i, _) in float_data.iter().enumerate().take(samples) {
                let t = i as f32 / sample_rate;
                let sample = (2.0 * std::f32::consts::PI * 1000.0 * t).sin() * 0.5;
                signal.push(sample);
                signal.push(sample);
            }

            let buffer = AudioBuffer::from_slice(&signal, format).unwrap();
            buffers.push(buffer);
        }

        // Пакетная обработка
        let start_time = std::time::Instant::now();

        for buffer in &mut buffers {
            let mut buffer_mut = buffer.clone();
            processor.process(&mut buffer_mut).unwrap();
        }

        let elapsed = start_time.elapsed();

        // Проверка что обработка выполнена за разумное время
        // 10 буферов по 100 ms каждый = 1 секунда аудио
        assert!(
            elapsed.as_millis() < 100,
            "Обработка 1 секунды аудио должна занимать меньше 100 мс, заняло: {} мс",
            elapsed.as_millis()
        );
    }
}

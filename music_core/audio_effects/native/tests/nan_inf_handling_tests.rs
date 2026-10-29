//! Тесты для обработки NaN/Inf значений
//! Фокус на предотвращении распространения нечисловых значений

#[cfg(test)]
mod tests {
    use crate::audio::format::*;
    use crate::dsp::fft::*;
    use crate::dsp::filter::*;
    use crate::effects::delay::*;
    use num::complex::Complex32;

    #[test]
    fn test_biquad_nan_inf_input_handling() {
        // Тест обработки NaN/Inf на входе биквад фильтра
        let mut biquad = Biquad::new();
        biquad = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 1.0, 0.0);

        // Тест с NaN
        let nan_result = biquad.process(f32::NAN);
        assert!(nan_result.is_finite());
        assert_eq!(nan_result, 0.0);

        // Тест с +Inf
        let inf_result = biquad.process(f32::INFINITY);
        assert!(inf_result.is_finite());
        assert_eq!(inf_result, 0.0);

        // Тест с -Inf
        let neg_inf_result = biquad.process(f32::NEG_INFINITY);
        assert!(neg_inf_result.is_finite());
        assert_eq!(neg_inf_result, 0.0);

        // Проверяем, что фильтр остается стабильным после NaN/Inf
        let normal_result = biquad.process(1.0);
        assert!(normal_result.is_finite());
        assert!(normal_result.abs() <= 1.0);
    }

    #[test]
    fn test_biquad_coefficient_calculation_with_nan_inf() {
        // Тест расчета коэффициентов с NaN/Inf параметрами
        let biquad = Biquad::new();

        // Тест с NaN частотой
        let nan_freq =
            biquad.calculate_coefficients(FilterType::LowPass, f32::NAN, 48000.0, 1.0, 0.0);
        // Должен вернуть новый (нулевой) биквад
        assert_eq!(nan_freq.b0, 1.0);
        assert_eq!(nan_freq.a0, 1.0);

        // Тест с Inf частотой
        let inf_freq =
            biquad.calculate_coefficients(FilterType::LowPass, f32::INFINITY, 48000.0, 1.0, 0.0);
        assert_eq!(inf_freq.b0, 1.0);

        // Тест с NaN sample rate
        let nan_sr = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, f32::NAN, 1.0, 0.0);
        assert_eq!(nan_sr.b0, 1.0);

        // Тест с NaN Q
        let nan_q =
            biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, f32::NAN, 0.0);
        assert_eq!(nan_q.b0, 1.0);

        // Тест с NaN gain
        let nan_gain =
            biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 1.0, f32::NAN);
        assert_eq!(nan_gain.b0, 1.0);
    }

    #[test]
    fn test_filter_nan_inf_processing() {
        // Тест обработки NaN/Inf в высокоуровневом фильтре
        let mut filter = Filter::new(FilterType::LowPass, 48000.0);

        // Тест с NaN входом
        let mut nan_input = f32::NAN;
        filter.process(&mut nan_input);
        assert!(nan_input.is_finite());
        assert_eq!(nan_input, 0.0);

        // Тест с Inf входом
        let mut inf_input = f32::INFINITY;
        filter.process(&mut inf_input);
        assert!(inf_input.is_finite());
        assert_eq!(inf_input, 0.0);

        // Тест буфера с NaN/Inf
        let mut buffer = vec![1.0, f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 0.5];
        filter.process_buffer(&mut buffer);

        for &sample in &buffer {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_fir_filter_nan_inf_handling() {
        // Тест обработки NaN/Inf в FIR фильтре
        let coefficients = vec![0.1, 0.2, 0.4, 0.2, 0.1];
        let mut fir = FIRFilter::new(coefficients);

        // Тест с NaN
        let nan_result = fir.process(f32::NAN);
        assert!(nan_result.is_finite());
        assert_eq!(nan_result, 0.0);

        // Тест с Inf
        let inf_result = fir.process(f32::INFINITY);
        assert!(inf_result.is_finite());
        assert_eq!(inf_result, 0.0);

        // Тест буфера
        let mut buffer = vec![1.0, f32::NAN, f32::INFINITY];
        fir.process_buffer(&mut buffer);

        for &sample in &buffer {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_fft_nan_inf_handling() {
        // Тест обработки NaN/Inf в FFT
        let fft = FFT::new(8);

        // Тест с NaN в сигнале
        let mut signal_with_nan = vec![1.0, 2.0, f32::NAN, 4.0, 5.0, 6.0, 7.0, 8.0];
        let spectrum = fft.forward(&signal_with_nan);

        for &complex_val in &spectrum {
            assert!(complex_val.re.is_finite());
            assert!(complex_val.im.is_finite());
        }

        // Тест обратного FFT с NaN в спектре
        let mut spectrum_with_nan = spectrum.clone();
        spectrum_with_nan[0] = Complex::new(f32::NAN, f32::INFINITY);

        let reconstructed = fft.inverse(&spectrum_with_nan);

        for &sample in &reconstructed {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_delay_nan_inf_processing() {
        // Тест обработки NaN/Inf в delay эффекте
        let config = DelayConfig::default();
        let format = AudioFormat::new(SampleRate::Hz48000, 2);
        let mut delay = Delay::<1024>::new(config, format);

        // Тест с NaN входом
        let nan_result = delay.process_tap(0, 0, f32::NAN);
        assert!(nan_result.is_finite());

        // Тест с Inf входом
        let inf_result = delay.process_tap(0, 0, f32::INFINITY);
        assert!(inf_result.is_finite());

        // Тест modulated delay с NaN
        let mut test_delay = delay.clone();
        test_delay.config.taps[0].delay_time = f32::NAN;

        let nan_delay_result = test_delay.process_tap(0, 0, 1.0);
        assert!(nan_delay_result.is_finite());
    }

    #[test]
    fn test_delay_modulation_nan_inf() {
        // Тест модуляции delay с NaN/Inf
        let mut config = DelayConfig::default();
        config.modulation_rate = f32::NAN;
        config.modulation_depth = f32::INFINITY;

        let format = AudioFormat::new(SampleRate::Hz48000, 2);
        let mut delay = Delay::<1024>::new(config, format);

        // Обновляем LFO (должен обработать NaN/Inf)
        delay.update_lfo();

        // Проверяем, что LFO фазы конечны
        for &phase in &delay.lfo_phase {
            assert!(phase.is_finite());
        }

        // Тест обработки тапа
        let result = delay.process_tap(0, 0, 1.0);
        assert!(result.is_finite());
    }

    #[test]
    fn test_tape_saturation_nan_inf() {
        // Тест tape saturation с NaN/Inf
        let config = DelayConfig { tape_saturation: 0.5, ..DelayConfig::default() };
        let format = AudioFormat::new(SampleRate::Hz48000, 2);
        let delay = Delay::<1024>::new(config, format);

        // Тест с NaN
        let nan_saturated = delay.apply_tape_saturation(f32::NAN);
        assert!(nan_saturated.is_finite());

        // Тест с Inf
        let inf_saturated = delay.apply_tape_saturation(f32::INFINITY);
        assert!(inf_saturated.is_finite());

        // Тест с нормальными значениями
        let normal_saturated = delay.apply_tape_saturation(2.0);
        assert!(normal_saturated.is_finite());
        assert!(normal_saturated.abs() <= 2.0); // Не должно превышать вход
    }

    #[test]
    fn test_frequency_response_calculation_with_nan_inf() {
        // Тест расчета частотной характеристики с NaN/Inf
        let biquad = Biquad::new();

        // Тест с NaN частотой
        let (mag_nan, phase_nan) = biquad.get_frequency_response(f32::NAN, 48000.0);
        assert!(mag_nan.is_finite());
        assert!(phase_nan.is_finite());

        // Тест с Inf частотой
        let (mag_inf, phase_inf) = biquad.get_frequency_response(f32::INFINITY, 48000.0);
        assert!(mag_inf.is_finite());
        assert!(phase_inf.is_finite());

        // Тест с NaN sample rate
        let (mag_nan_sr, phase_nan_sr) = biquad.get_frequency_response(1000.0, f32::NAN);
        assert!(mag_nan_sr.is_finite());
        assert!(phase_nan_sr.is_finite());
    }

    #[test]
    fn test_filter_parameter_setting_with_nan_inf() {
        // Тест установки параметров фильтра с NaN/Inf
        let mut filter = Filter::new(FilterType::LowPass, 48000.0);

        // Тест установки NaN частоты
        filter.set_frequency(f32::NAN);
        assert!(filter.frequency.is_finite());

        // Тест установки Inf частоты
        filter.set_frequency(f32::INFINITY);
        assert!(filter.frequency.is_finite());

        // Тест установки NaN Q
        filter.set_q(f32::NAN);
        assert!(filter.q.is_finite());

        // Тест установки NaN gain
        filter.set_gain(f32::NAN);
        assert!(filter.gain_db.is_finite());
    }

    #[test]
    fn test_complex_fft_operations_with_nan_inf() {
        // Тест комплексных FFT операций с NaN/Inf
        let fft = FFT::new(8);

        // Тест STFT с NaN в сигнале
        let signal_with_nan = vec![1.0, f32::NAN, 3.0, 4.0, 5.0, 6.0, 7.0, 8.0];
        let window = fft.create_window(WindowType::Hann);
        let stft_result = fft.stft(&signal_with_nan, 4, &window);

        for frame in &stft_result {
            for &complex_val in frame {
                assert!(complex_val.re.is_finite());
                assert!(complex_val.im.is_finite());
            }
        }

        // Тест ISTFT с NaN в фреймах
        let mut frames_with_nan = stft_result.clone();
        if let Some(frame) = frames_with_nan.get_mut(0) {
            frame[0] = Complex::new(f32::NAN, f32::INFINITY);
        }

        let istft_result = fft.istft(&frames_with_nan, 4, &window);

        for &sample in &istft_result {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_spectrum_calculations_with_nan_inf() {
        // Тест расчетов спектра с NaN/Inf
        let mut spectrum = vec![
            Complex::new(1.0, 0.0),
            Complex::new(f32::NAN, 1.0),
            Complex::new(0.0, f32::INFINITY),
            Complex::new(f32::NEG_INFINITY, 0.0),
        ];

        // Тест спектра мощности
        let power_spec = FFT::power_spectrum(&spectrum);
        for &power in &power_spec {
            assert!(power.is_finite());
            assert!(power >= 0.0);
        }

        // Тест спектра амплитуд
        let mag_spec = FFT::magnitude_spectrum(&spectrum);
        for &mag in &mag_spec {
            assert!(mag.is_finite());
            assert!(mag >= 0.0);
        }

        // Тест фазового спектра
        let phase_spec = FFT::phase_spectrum(&spectrum);
        for &phase in &phase_spec {
            assert!(phase.is_finite());
        }

        // Тест конвертации в dB
        let db_spec = FFT::spectrum_to_db(&mag_spec, 1.0);
        for &db in &db_spec {
            assert!(db.is_finite());
            assert!(db <= 0.0 || db == -144.0);
        }
    }

    #[test]
    fn test_delay_buffer_interpolation_with_nan_inf() {
        // Тест интерполяции буфера delay с NaN/Inf
        let mut buffer = vec![1.0, f32::NAN, f32::INFINITY, 4.0];

        // Тест интерполяции (используем вспомогательную функцию)
        let result_1_5 = read_interpolated(&buffer, 1.5);
        // Результат может быть NaN, но должен быть определен

        let result_2_5 = read_interpolated(&buffer, 2.5);
        // Аналогично

        // Тест с нормальными значениями
        let normal_buffer = vec![0.0, 1.0, 2.0, 3.0];
        let normal_result = read_interpolated(&normal_buffer, 1.5);
        assert!((normal_result - 1.5).abs() < 0.001);
    }

    #[test]
    fn test_filter_cascade_nan_inf_propagation() {
        // Тест каскада фильтров с NaN/Inf
        let filter1 = Filter::lowpass(1000.0, 48000.0, 1.0);
        let filter2 = Filter::highpass(100.0, 48000.0, 1.0);
        let mut cascade = FilterCascade::new(vec![filter1, filter2]);

        // Тест с NaN входом
        let nan_result = cascade.process(f32::NAN);
        assert!(nan_result.is_finite());

        // Тест с Inf входом
        let inf_result = cascade.process(f32::INFINITY);
        assert!(inf_result.is_finite());

        // Тест буфера
        let mut buffer = vec![1.0, f32::NAN, f32::INFINITY, 0.5];
        cascade.process_buffer(&mut buffer);

        for &sample in &buffer {
            assert!(sample.is_finite());
        }
    }

    // Вспомогательная функция для тестирования интерполяции
    fn read_interpolated(buffer: &[f32], position: f32) -> f32 {
        let buffer_len_f32 = buffer.len() as f32;
        let normalized_pos = if position < 0.0 { position + buffer_len_f32 } else { position };
        let index = (normalized_pos as usize) % buffer.len();
        let fraction = normalized_pos - index as f32;

        let next_index = (index + 1) % buffer.len();

        let current = buffer[index];
        let next = buffer[next_index];

        current * (1.0 - fraction) + next * fraction
    }
}

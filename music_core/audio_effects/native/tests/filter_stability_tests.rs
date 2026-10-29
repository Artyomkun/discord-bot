//! Тесты для стабильности фильтров
//! Фокус на предотвращении нестабильности и осцилляций

#[cfg(test)]
mod tests {
    use crate::dsp::filter::*;
    use std::f32::consts::PI;

    #[test]
    fn test_biquad_stability_basic() {
        // Тест базовой стабильности биквад фильтра
        let biquad = Biquad::new();

        // Тест с различными типами фильтров
        let filter_types = vec![
            FilterType::LowPass,
            FilterType::HighPass,
            FilterType::BandPass,
            FilterType::BandStop,
            FilterType::LowShelf,
            FilterType::HighShelf,
            FilterType::Peak,
            FilterType::AllPass,
            FilterType::Notch,
        ];

        for &filter_type in &filter_types {
            let stable_biquad =
                biquad.calculate_coefficients(filter_type, 1000.0, 48000.0, 1.0, 0.0);

            // Проверяем, что полюса находятся внутри единичной окружности
            assert!(stable_biquad.is_stable(), "Filter type {:?} is unstable", filter_type);
        }
    }

    #[test]
    fn test_biquad_stability_extreme_parameters() {
        // Тест стабильности с экстремальными параметрами
        let biquad = Biquad::new();

        // Очень низкая частота
        let low_freq = biquad.calculate_coefficients(FilterType::LowPass, 1.0, 48000.0, 1.0, 0.0);
        assert!(low_freq.is_stable());

        // Очень высокая частота (близко к Nyquist)
        let high_freq =
            biquad.calculate_coefficients(FilterType::LowPass, 20000.0, 48000.0, 1.0, 0.0);
        assert!(high_freq.is_stable());

        // Очень высокое Q
        let high_q = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 50.0, 0.0);
        assert!(high_q.is_stable());

        // Очень низкое Q
        let low_q = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 0.1, 0.0);
        assert!(low_q.is_stable());

        // Экстремальный gain для shelf фильтров
        let high_gain =
            biquad.calculate_coefficients(FilterType::LowShelf, 1000.0, 48000.0, 1.0, 24.0);
        assert!(high_gain.is_stable());

        let low_gain =
            biquad.calculate_coefficients(FilterType::LowShelf, 1000.0, 48000.0, 1.0, -24.0);
        assert!(low_gain.is_stable());
    }

    #[test]
    fn test_biquad_pole_analysis() {
        // Тест анализа полюсов биквад фильтра
        let biquad = Biquad::new();

        let test_biquad =
            biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 1.0, 0.0);

        // Вычисляем полюса (roots of denominator)
        let a1 = test_biquad.a1 / test_biquad.a0;
        let a2 = test_biquad.a2 / test_biquad.a0;

        // Дискриминант
        let discriminant = a1 * a1 - 4.0 * a2;

        if discriminant >= 0.0 {
            // Действительные полюса
            let r1 = (-a1 + discriminant.sqrt()) / 2.0;
            let r2 = (-a1 - discriminant.sqrt()) / 2.0;

            assert!(r1.abs() < 1.0, "Pole r1 = {} is outside unit circle", r1);
            assert!(r2.abs() < 1.0, "Pole r2 = {} is outside unit circle", r2);
        } else {
            // Комплексные полюса
            let real_part = -a1 / 2.0;
            let imag_part_sq = (4.0 * a2 - a1 * a1) / 4.0;
            let modulus = (real_part * real_part + imag_part_sq).sqrt();

            assert!(modulus < 1.0, "Complex pole modulus = {} >= 1.0", modulus);
        }
    }

    #[test]
    fn test_filter_cascade_stability() {
        // Тест стабильности каскада фильтров
        let filters = vec![
            Filter::lowpass(100.0, 48000.0, 1.0),
            Filter::highpass(10000.0, 48000.0, 1.0),
            Filter::bandpass(1000.0, 48000.0, 5.0),
            Filter::peak(2000.0, 48000.0, 6.0, 2.0),
        ];

        let cascade = FilterCascade::new(filters);

        // Тест обработки сигнала
        let mut buffer = vec![1.0; 100];

        // Каскад должен оставаться стабильным
        cascade.process_buffer(&mut buffer);

        for &sample in &buffer {
            assert!(sample.is_finite());
            assert!(sample.abs() < 10.0); // Не должно быть чрезмерного усиления
        }
    }

    #[test]
    fn test_filter_impulse_response_stability() {
        // Тест стабильности импульсной характеристики
        let mut filter = Filter::lowpass(1000.0, 48000.0, 1.0);

        // Импульсная характеристика
        let mut impulse_response = vec![0.0; 1000];
        impulse_response[0] = 1.0;

        filter.process_buffer(&mut impulse_response);

        // Проверяем затухание
        let mut max_amplitude = 0.0;
        for &sample in &impulse_response {
            max_amplitude = max_amplitude.max(sample.abs());
            assert!(sample.is_finite());
        }

        // Импульсная характеристика должна затухать
        let final_amplitude =
            impulse_response.last().expect("Impulse response should not be empty").abs();
        let initial_amplitude = impulse_response[0].abs();

        assert!(
            final_amplitude < initial_amplitude * 0.01,
            "Impulse response not decaying: final={}, initial={}",
            final_amplitude,
            initial_amplitude
        );
    }

    #[test]
    fn test_filter_step_response_stability() {
        // Тест стабильности переходной характеристики
        let mut filter = Filter::lowpass(500.0, 48000.0, 1.0);

        // Ступенчатая функция
        let mut step_response = vec![1.0; 1000];

        filter.process_buffer(&mut step_response);

        // Проверяем, что отклик сходится
        let mut converged = false;
        for i in 900..1000 {
            let diff = (step_response[i] - step_response[i - 1]).abs();
            if diff < 0.001 {
                converged = true;
                break;
            }
        }

        assert!(converged, "Step response did not converge");

        // Все значения должны быть конечными
        for &sample in &step_response {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_filter_frequency_response_continuity() {
        // Тест непрерывности частотной характеристики
        let filter = Filter::lowpass(1000.0, 48000.0, 1.0);

        let frequencies = vec![20.0, 100.0, 500.0, 1000.0, 2000.0, 5000.0, 10000.0, 20000.0];

        let mut prev_magnitude = 1.0;
        for &freq in &frequencies {
            let (magnitude, _) = filter.get_frequency_response(freq);

            // Амплитудная характеристика должна быть непрерывной
            assert!(
                (magnitude - prev_magnitude).abs() < 2.0,
                "Discontinuity at {} Hz: prev={}, current={}",
                freq,
                prev_magnitude,
                magnitude
            );

            prev_magnitude = magnitude;
        }
    }

    #[test]
    fn test_biquad_resonance_stability() {
        // Тест стабильности резонансных фильтров
        let biquad = Biquad::new();

        // Высокий Q фактор (узкая полоса)
        let resonant = biquad.calculate_coefficients(
            FilterType::BandPass,
            1000.0,
            48000.0,
            20.0, // Высокий Q
            0.0,
        );

        assert!(resonant.is_stable());

        // Тест обработки сигнала
        let mut test_biquad = resonant;
        let mut buffer = vec![0.0; 100];
        buffer[0] = 1.0; // Импульс

        for sample in &mut buffer {
            *sample = test_biquad.process(*sample);
        }

        // Резонансный фильтр может давать пики, но должен оставаться стабильным
        for &sample in &buffer {
            assert!(sample.is_finite());
            assert!(sample.abs() < 100.0); // Разумная граница
        }
    }

    #[test]
    fn test_filter_reset_stability() {
        // Тест стабильности после сброса
        let mut filter = Filter::lowpass(1000.0, 48000.0, 1.0);

        // Обработаем сигнал
        let mut buffer1 = vec![1.0; 50];
        filter.process_buffer(&mut buffer1);

        // Сбросим фильтр
        filter.reset();

        // Обработаем новый сигнал
        let mut buffer2 = vec![1.0; 50];
        filter.process_buffer(&mut buffer2);

        // Результаты должны быть идентичными
        for (s1, s2) in buffer1.iter().zip(buffer2.iter()) {
            assert!((s1 - s2).abs() < 0.001, "Filter not properly reset: {} vs {}", s1, s2);
        }
    }

    #[test]
    fn test_linkwitz_riley_crossover_stability() {
        // Тест стабильности Linkwitz-Riley crossover
        let (lowpass, highpass) = FilterCascade::linkwitz_riley(1000.0, 48000.0, 4);

        // Тест с белым шумом
        let mut white_noise = vec![0.0; 1000];
        for i in 0..white_noise.len() {
            white_noise[i] = (i as f32 * 0.1).sin() * 0.1; // Простой шум
        }

        let mut low_output = white_noise.clone();
        lowpass.process_buffer(&mut low_output);

        let mut high_output = white_noise.clone();
        highpass.process_buffer(&mut high_output);

        // Сумма должна быть близка к оригиналу (комплементарность)
        for i in 0..white_noise.len() {
            let sum = low_output[i] + high_output[i];
            assert!(
                (sum - white_noise[i]).abs() < 0.1,
                "Crossover not complementary at index {}: sum={}, original={}",
                i,
                sum,
                white_noise[i]
            );
        }

        // Все значения конечны
        for &sample in &low_output {
            assert!(sample.is_finite());
        }
        for &sample in &high_output {
            assert!(sample.is_finite());
        }
    }

    #[test]
    fn test_filter_parameter_change_stability() {
        // Тест стабильности при изменении параметров
        let mut filter = Filter::lowpass(1000.0, 48000.0, 1.0);

        // Постепенно меняем частоту
        let frequencies = vec![500.0, 2000.0, 500.0, 10000.0, 1000.0];

        for &freq in &frequencies {
            filter.set_frequency(freq);

            // Тест обработки после изменения
            let mut test_signal = vec![1.0, 0.5, 0.0, -0.5, -1.0];
            filter.process_buffer(&mut test_signal);

            for &sample in &test_signal {
                assert!(sample.is_finite());
                assert!(sample.abs() <= 2.0); // Разумные границы
            }
        }
    }

    #[test]
    fn test_biquad_coefficient_normalization() {
        // Тест нормализации коэффициентов
        let biquad = Biquad::new();

        let mut test_biquad =
            biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 48000.0, 1.0, 0.0);

        // После нормализации a0 должен быть 1.0
        assert!((test_biquad.a0 - 1.0).abs() < 0.001);

        // Все коэффициенты должны быть конечными
        assert!(test_biquad.a1.is_finite());
        assert!(test_biquad.a2.is_finite());
        assert!(test_biquad.b0.is_finite());
        assert!(test_biquad.b1.is_finite());
        assert!(test_biquad.b2.is_finite());
    }

    #[test]
    fn test_fir_filter_stability() {
        // Тест стабильности FIR фильтра
        let coefficients = vec![0.1, 0.2, 0.4, 0.2, 0.1]; // Пример коэффициентов
        let mut fir = FIRFilter::new(coefficients);

        // FIR фильтры всегда стабильны (BIBO stable)
        // Тест с различными входами
        let inputs = vec![1.0, -1.0, 0.0, f32::NAN, f32::INFINITY];

        for input in inputs {
            let output = fir.process(input);
            assert!(output.is_finite());
        }

        // Тест с длинным сигналом
        let mut long_signal = vec![0.0; 1000];
        long_signal[0] = 1.0; // Импульс

        fir.process_buffer(&mut long_signal);

        for &sample in &long_signal {
            assert!(sample.is_finite());
        }
    }

    // Вспомогательный trait для проверки стабильности
    impl Biquad {
        fn is_stable(&self) -> bool {
            // Проверяем, что полюса находятся внутри единичной окружности
            let a1 = self.a1 / self.a0;
            let a2 = self.a2 / self.a0;

            let discriminant = a1 * a1 - 4.0 * a2;

            if discriminant >= 0.0 {
                let r1 = (-a1 + discriminant.sqrt()) / 2.0;
                let r2 = (-a1 - discriminant.sqrt()) / 2.0;
                r1.abs() < 1.0 && r2.abs() < 1.0
            } else {
                let real_part = -a1 / 2.0;
                let imag_part_sq = (4.0 * a2 - a1 * a1) / 4.0;
                let modulus = (real_part * real_part + imag_part_sq).sqrt();
                modulus < 1.0
            }
        }
    }
}

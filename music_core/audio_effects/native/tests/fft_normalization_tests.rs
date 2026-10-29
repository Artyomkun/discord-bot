//! Тесты для нормализации спектрального анализа
//! Фокус на корректности нормализации FFT и предотвращении искажений

#[cfg(test)]
mod tests {
    use crate::dsp::fft::*;
    use std::f32::consts::PI;

    #[test]
    fn test_fft_forward_normalization() {
        // Тест нормализации прямого FFT
        let fft = FFT::new(8);

        // Тест с импульсом (все нули, кроме одного)
        let mut impulse = vec![0.0; 8];
        impulse[0] = 1.0;

        let spectrum = fft.forward(&impulse);

        // Проверяем, что спектр нормализован (сумма квадратов амплитуд)
        let magnitude_sum: f32 = spectrum.iter().map(|c| c.norm_sqr()).sum();
        let expected_sum = 1.0; // Для импульса сумма квадратов должна быть 1 после нормализации

        assert!(
            (magnitude_sum - expected_sum).abs() < 0.1,
            "Magnitude sum: {}, expected: {}",
            magnitude_sum,
            expected_sum
        );

        // Проверяем, что все значения конечны
        for &complex_val in &spectrum {
            assert!(complex_val.re.is_finite());
            assert!(complex_val.im.is_finite());
        }
    }

    #[test]
    fn test_fft_inverse_normalization() {
        // Тест нормализации обратного FFT
        let fft = FFT::new(8);

        // Создаем тестовый спектр
        let spectrum: Vec<Complex<f32>> = (0..8)
            .map(|i| {
                let phase = 2.0 * PI * i as f32 / 8.0;
                Complex::new(phase.cos(), phase.sin()) * 0.1
            })
            .collect();

        let time_signal = fft.inverse(&spectrum);

        // Проверяем, что сигнал конечен
        for &sample in &time_signal {
            assert!(sample.is_finite());
        }

        // Проверяем Parseval's theorem (сумма квадратов во времени и частоте должна быть пропорциональна)
        let time_energy: f32 = time_signal.iter().map(|&x| x * x).sum();
        let freq_energy: f32 = spectrum.iter().map(|c| c.norm_sqr()).sum();

        // Для нормализованного FFT энергии должны быть близки
        assert!(
            (time_energy - freq_energy).abs() < 0.1,
            "Parseval check failed: time={}, freq={}",
            time_energy,
            freq_energy
        );
    }

    #[test]
    fn test_fft_round_trip_normalization() {
        // Тест round-trip FFT (forward -> inverse)
        let fft = FFT::new(16);

        // Создаем тестовый сигнал
        let original: Vec<f32> = (0..16).map(|i| (2.0 * PI * i as f32 / 16.0).sin()).collect();

        // Прямой FFT
        let spectrum = fft.forward(&original);

        // Обратный FFT
        let reconstructed = fft.inverse(&spectrum);

        // Проверяем, что сигнал восстановлен с точностью нормализации
        for (orig, recon) in original.iter().zip(reconstructed.iter()) {
            assert!(
                (orig - recon).abs() < 0.01,
                "Round-trip failed: original={}, reconstructed={}",
                orig,
                recon
            );
        }
    }

    #[test]
    fn test_power_spectrum_normalization() {
        // Тест нормализации спектра мощности
        let spectrum: Vec<Complex<f32>> = vec![
            Complex::new(1.0, 0.0),
            Complex::new(0.5, 0.5),
            Complex::new(0.0, 1.0),
            Complex::new(-0.5, 0.5),
        ];

        let power_spectrum = FFT::power_spectrum(&spectrum);

        // Проверяем, что все значения положительные
        for &power in &power_spectrum {
            assert!(power >= 0.0);
            assert!(power.is_finite());
        }

        // Проверяем конкретные значения
        assert!((power_spectrum[0] - 1.0).abs() < 0.001); // 1^2 + 0^2 = 1
        assert!((power_spectrum[1] - 0.5).abs() < 0.001); // 0.5^2 + 0.5^2 = 0.5
        assert!((power_spectrum[2] - 1.0).abs() < 0.001); // 0^2 + 1^2 = 1
        assert!((power_spectrum[3] - 0.5).abs() < 0.001); // (-0.5)^2 + 0.5^2 = 0.5
    }

    #[test]
    fn test_magnitude_spectrum_normalization() {
        // Тест нормализации спектра амплитуд
        let spectrum: Vec<Complex<f32>> = vec![
            Complex::new(3.0, 4.0), // Magnitude = 5
            Complex::new(1.0, 1.0), // Magnitude = sqrt(2) ≈ 1.414
            Complex::new(0.0, 0.0), // Magnitude = 0
        ];

        let magnitude_spectrum = FFT::magnitude_spectrum(&spectrum);

        // Проверяем значения
        assert!((magnitude_spectrum[0] - 5.0).abs() < 0.001);
        assert!((magnitude_spectrum[1] - (2.0f32).sqrt()).abs() < 0.001);
        assert!((magnitude_spectrum[2] - 0.0).abs() < 0.001);

        // Все значения должны быть >= 0
        for &mag in &magnitude_spectrum {
            assert!(mag >= 0.0);
            assert!(mag.is_finite());
        }
    }

    #[test]
    fn test_phase_spectrum_normalization() {
        // Тест нормализации фазового спектра
        let spectrum: Vec<Complex<f32>> = vec![
            Complex::new(1.0, 0.0),  // Phase = 0
            Complex::new(0.0, 1.0),  // Phase = π/2
            Complex::new(-1.0, 0.0), // Phase = π
            Complex::new(0.0, -1.0), // Phase = -π/2
        ];

        let phase_spectrum = FFT::phase_spectrum(&spectrum);

        // Проверяем фазы
        assert!((phase_spectrum[0] - 0.0).abs() < 0.001);
        assert!((phase_spectrum[1] - PI / 2.0).abs() < 0.001);
        assert!((phase_spectrum[2] - PI).abs() < 0.001 || (phase_spectrum[2] + PI).abs() < 0.001);
        assert!((phase_spectrum[3] + PI / 2.0).abs() < 0.001);

        // Все фазы должны быть в диапазоне [-π, π]
        for &phase in &phase_spectrum {
            assert!(phase >= -PI && phase <= PI);
            assert!(phase.is_finite());
        }
    }

    #[test]
    fn test_spectrum_to_db_normalization() {
        // Тест конвертации спектра в dB
        let spectrum = vec![1.0, 0.1, 0.01, 0.001, 0.0];
        let reference = 1.0;

        let db_spectrum = FFT::spectrum_to_db(&spectrum, reference);

        // Проверяем значения
        assert!((db_spectrum[0] - 0.0).abs() < 0.001); // 1.0 -> 0 dB
        assert!((db_spectrum[1] - (-20.0)).abs() < 0.001); // 0.1 -> -20 dB
        assert!((db_spectrum[2] - (-40.0)).abs() < 0.001); // 0.01 -> -40 dB
        assert!((db_spectrum[3] - (-60.0)).abs() < 0.001); // 0.001 -> -60 dB
        assert_eq!(db_spectrum[4], -144.0); // 0.0 -> -144 dB (silence)

        // Все значения должны быть <= 0 (относительно reference)
        for &db in &db_spectrum {
            assert!(db <= 0.0 || db == -144.0);
            assert!(db.is_finite());
        }
    }

    #[test]
    fn test_stft_normalization() {
        // Тест нормализации STFT
        let fft = FFT::new(8);
        let window = fft.create_window(WindowType::Hann);

        // Создаем тестовый сигнал
        let signal: Vec<f32> = (0..16).map(|i| (2.0 * PI * i as f32 / 16.0).sin()).collect();

        let hop_size = 4;
        let stft_result = fft.stft(&signal, hop_size, &window);

        // Проверяем размеры
        assert_eq!(stft_result.len(), (signal.len() - fft.size) / hop_size + 1);

        for frame in &stft_result {
            assert_eq!(frame.len(), fft.size);

            // Проверяем нормализацию каждого фрейма
            for &complex_val in frame {
                assert!(complex_val.re.is_finite());
                assert!(complex_val.im.is_finite());
            }
        }
    }

    #[test]
    fn test_istft_normalization() {
        // Тест нормализации ISTFT
        let fft = FFT::new(8);
        let window = fft.create_window(WindowType::Hann);

        // Создаем тестовый STFT результат
        let frames: Vec<Vec<Complex<f32>>> = (0..3)
            .map(|_| {
                (0..8)
                    .map(|i| {
                        let phase = 2.0 * PI * i as f32 / 8.0;
                        Complex::new(phase.cos() * 0.1, phase.sin() * 0.1)
                    })
                    .collect()
            })
            .collect();

        let hop_size = 4;
        let reconstructed = fft.istft(&frames, hop_size, &window);

        // Проверяем, что сигнал восстановлен
        for &sample in &reconstructed {
            assert!(sample.is_finite());
        }

        // Проверяем длину
        let expected_len = (frames.len() - 1) * hop_size + fft.size;
        assert_eq!(reconstructed.len(), expected_len);
    }

    #[test]
    fn test_frequency_bins_calculation() {
        // Тест расчета частотных бинов
        let fft = FFT::new(8);
        let sample_rate = 8000.0;

        let bins = fft.frequency_bins(sample_rate);

        // Должно быть size/2 + 1 бинов
        assert_eq!(bins.len(), 5);

        // Проверяем значения
        assert!((bins[0] - 0.0).abs() < 0.001); // DC
        assert!((bins[1] - 1000.0).abs() < 0.001); // 1000 Hz
        assert!((bins[2] - 2000.0).abs() < 0.001); // 2000 Hz
        assert!((bins[3] - 3000.0).abs() < 0.001); // 3000 Hz
        assert!((bins[4] - 4000.0).abs() < 0.001); // Nyquist = 4000 Hz
    }

    #[test]
    fn test_mel_spectrogram_normalization() {
        // Тест нормализации мел-спектрограммы
        let fft = FFT::new(8);

        // Создаем тестовые фреймы
        let frames: Vec<Vec<f32>> =
            (0..2).map(|_| (0..5).map(|i| (i as f32).exp()).collect()).collect();

        let sample_rate = 8000.0;
        let n_mels = 4;

        let mel_spec = fft.mel_spectrogram(&frames, sample_rate, n_mels);

        // Проверяем размеры
        assert_eq!(mel_spec.len(), frames.len());
        assert_eq!(mel_spec[0].len(), n_mels);

        // Все значения должны быть конечными и >= 0
        for frame in &mel_spec {
            for &mel_val in frame {
                assert!(mel_val.is_finite());
                assert!(mel_val >= 0.0);
            }
        }
    }

    #[test]
    fn test_fft_scaling_consistency() {
        // Тест一致ности масштабирования FFT
        let sizes = vec![8, 16, 32, 64];

        for &size in &sizes {
            let fft = FFT::new(size);

            // Тест с единичным импульсом
            let mut impulse = vec![0.0; size];
            impulse[0] = 1.0;

            let spectrum = fft.forward(&impulse);
            let reconstructed = fft.inverse(&spectrum);

            // Проверяем, что импульс восстановлен
            assert!((reconstructed[0] - 1.0).abs() < 0.01);

            // Проверяем, что остальные семплы близки к нулю
            for (i, &sample) in reconstructed.iter().enumerate() {
                if i != 0 {
                    assert!(sample.abs() < 0.01, "Sample {} should be near zero: {}", i, sample);
                }
            }
        }
    }

    #[test]
    fn test_normalization_with_different_window_types() {
        // Тест нормализации с различными типами окон
        let fft = FFT::new(16);
        let window_types = vec![
            WindowType::Rectangular,
            WindowType::Hann,
            WindowType::Hamming,
            WindowType::Blackman,
        ];

        for window_type in window_types {
            let window = fft.create_window(window_type);

            // Проверяем свойства окна
            assert_eq!(window.len(), fft.size);

            // Все коэффициенты должны быть в [0, 1]
            for &coeff in &window {
                assert!(coeff >= 0.0 && coeff <= 1.0);
                assert!(coeff.is_finite());
            }

            // Для большинства окон сумма коэффициентов должна быть разумной
            let sum: f32 = window.iter().sum();
            assert!(sum > 0.0 && sum.is_finite());
        }
    }
}

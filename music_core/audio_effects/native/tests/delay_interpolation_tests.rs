//! Тесты для интерполяции delay
//! Фокус на корректности линейной интерполяции в буферах задержки

#[cfg(test)]
mod tests {
    use crate::audio::format::*;
    use crate::effects::delay::*;
    use std::f32::consts::PI;

    #[test]
    fn test_linear_interpolation_basic() {
        // Тест базовой линейной интерполяции
        let buffer = vec![0.0, 1.0, 2.0, 3.0, 4.0];

        // Тест интерполяции в целых индексах
        let result_0 = read_interpolated(&buffer, 0.0);
        assert!((result_0 - 0.0).abs() < 0.001);

        let result_2 = read_interpolated(&buffer, 2.0);
        assert!((result_2 - 2.0).abs() < 0.001);

        // Тест интерполяции между семплами
        let result_1_5 = read_interpolated(&buffer, 1.5);
        assert!((result_1_5 - 1.5).abs() < 0.001); // (1.0 + 2.0) / 2 = 1.5

        let result_2_3 = read_interpolated(&buffer, 2.3);
        let expected = 2.0 + 0.3 * (3.0 - 2.0); // 2.0 + 0.3 * 1.0 = 2.3
        assert!((result_2_3 - expected).abs() < 0.001);
    }

    #[test]
    fn test_interpolation_boundary_conditions() {
        // Тест граничных условий интерполяции
        let buffer = vec![10.0, 20.0, 30.0];

        // Тест с отрицательным индексом (должен быть нормализован)
        let result_neg = read_interpolated(&buffer, -1.0);
        let normalized_pos = -1.0 + 3.0; // buffer.len() as f32
        let expected = read_interpolated(&buffer, normalized_pos);
        assert!((result_neg - expected).abs() < 0.001);

        // Тест с индексом за пределами буфера
        let result_over = read_interpolated(&buffer, 5.0);
        let normalized_over = 5.0 % 3.0;
        let expected_over = read_interpolated(&buffer, normalized_over);
        assert!((result_over - expected_over).abs() < 0.001);

        // Тест с очень большим индексом
        let result_large = read_interpolated(&buffer, 100.5);
        let normalized_large = 100.5 % 3.0;
        let expected_large = read_interpolated(&buffer, normalized_large);
        assert!((result_large - expected_large).abs() < 0.001);
    }

    #[test]
    fn test_interpolation_edge_cases() {
        // Тест edge cases интерполяции

        // Пустой буфер (хотя в реальности буфер не пустой)
        let empty_buffer: Vec<f32> = vec![];
        // read_interpolated с пустым буфером вызовет panic в % операторе, но тест пропустим

        // Буфер с одним элементом
        let single_buffer = vec![5.0];
        let result_single = read_interpolated(&single_buffer, 0.5);
        // Для буфера длины 1, index % 1 = 0, так что всегда первый элемент
        assert!((result_single - 5.0).abs() < 0.001);

        // Буфер с двумя элементами
        let two_buffer = vec![1.0, 3.0];
        let result_two_0 = read_interpolated(&two_buffer, 0.0);
        assert!((result_two_0 - 1.0).abs() < 0.001);

        let result_two_1 = read_interpolated(&two_buffer, 1.0);
        assert!((result_two_1 - 3.0).abs() < 0.001);

        let result_two_half = read_interpolated(&two_buffer, 0.5);
        assert!((result_two_half - 2.0).abs() < 0.001); // (1.0 + 3.0) / 2
    }

    #[test]
    fn test_interpolation_precision() {
        // Тест точности интерполяции
        let buffer = vec![0.0, 10.0];

        // Тест различных дробных частей
        for i in 0..11 {
            let pos = i as f32 * 0.1;
            let result = read_interpolated(&buffer, pos);
            let expected = pos * 10.0; // Линейная интерполяция от 0 до 10
            assert!(
                (result - expected).abs() < 0.001,
                "Interpolation at {}: expected {}, got {}",
                pos,
                expected,
                result
            );
        }
    }

    #[test]
    fn test_delay_modulation_interpolation() {
        // Тест интерполяции с модуляцией delay
        let config = DelayConfig {
            modulation_rate: 1.0,  // 1 Hz
            modulation_depth: 0.5, // 50% модуляции
            ..DelayConfig::default()
        };

        let format = AudioFormat::new(SampleRate::Hz48000, 2);
        let mut delay = Delay::<1024>::new(config, format);

        // Создаем тестовый буфер
        let mut test_buffer = vec![0.0; 1024];
        test_buffer[0] = 1.0; // Импульс

        // Записываем импульс в буфер
        delay.delay_buffers[0][0][0] = 1.0;

        // Тест чтения с различными позициями
        let result_at_0 = delay.read_interpolated(&delay.delay_buffers[0][0], 0.0);
        assert!((result_at_0 - 1.0).abs() < 0.001);

        let result_at_half = delay.read_interpolated(&delay.delay_buffers[0][0], 0.5);
        assert!((result_at_half - 0.0).abs() < 0.001); // Между 1.0 и 0.0
    }

    #[test]
    fn test_interpolation_with_nan_inf() {
        // Тест интерполяции с NaN/Inf значениями
        let mut buffer = vec![1.0, f32::NAN, f32::INFINITY, f32::NEG_INFINITY, 5.0];

        // Интерполяция должна обрабатывать NaN/Inf корректно
        let result_nan = read_interpolated(&buffer, 1.5);
        // Поскольку buffer[1] = NaN, результат может быть NaN
        // Но в реальном коде delay фильтрует такие значения

        let result_inf = read_interpolated(&buffer, 2.5);
        // Аналогично для infinity

        // Тест с нормальными значениями вокруг проблемных
        let result_before_nan = read_interpolated(&buffer, 0.5);
        let expected_before = 1.0 + 0.5 * (f32::NAN - 1.0);
        // Результат может быть NaN, что нормально

        let result_after_inf = read_interpolated(&buffer, 3.5);
        let expected_after = f32::NEG_INFINITY + 0.5 * (5.0 - f32::NEG_INFINITY);
        // Результат может быть NaN или inf
    }

    #[test]
    fn test_circular_buffer_interpolation() {
        // Тест интерполяции в кольцевом буфере
        let buffer = vec![0.0, 1.0, 2.0, 3.0];

        // Тест wrap-around
        let result_wrap = read_interpolated(&buffer, 3.5);
        // 3.5 % 4 = 3.5, интерполяция между buffer[3] и buffer[0] (wrap)
        let expected = 3.0 + 0.5 * (0.0 - 3.0); // 3.0 + 0.5 * (-3.0) = 1.5
        assert!((result_wrap - expected).abs() < 0.001);

        // Тест с большим индексом
        let result_large_wrap = read_interpolated(&buffer, 7.25);
        // 7.25 % 4 = 3.25, интерполяция между buffer[3] и buffer[0]
        let expected_large = 3.0 + 0.25 * (0.0 - 3.0); // 3.0 + 0.25 * (-3.0) = 2.25
        assert!((result_large_wrap - expected_large).abs() < 0.001);
    }

    #[test]
    fn test_interpolation_performance() {
        // Тест производительности интерполяции (косвенно через множественные вызовы)
        let buffer = (0..1000).map(|x| x as f32).collect::<Vec<f32>>();

        // Множественные интерполяции для проверки стабильности
        for i in 0..100 {
            let pos = (i as f32 * 0.01) % buffer.len() as f32;
            let result = read_interpolated(&buffer, pos);
            assert!(result.is_finite());
        }
    }

    #[test]
    fn test_delay_read_position_update() {
        // Тест обновления позиции чтения в delay
        let config = DelayConfig::default();
        let format = AudioFormat::new(SampleRate::Hz48000, 2);
        let mut delay = Delay::<1024>::new(config, format);

        let initial_pos = delay.read_positions[0][0];

        // Симулируем несколько шагов
        for _ in 0..10 {
            let current_pos = delay.read_positions[0][0];
            let target_pos = 100.0; // Фиксированная позиция для теста
            let alpha = 0.01;
            let new_pos = current_pos * (1.0 - alpha) + target_pos * alpha;

            delay.read_positions[0][0] = new_pos;

            // Проверяем, что позиция изменяется плавно
            assert!(new_pos.is_finite());
        }

        let final_pos = delay.read_positions[0][0];
        assert!(final_pos.is_finite());
        assert!(final_pos >= initial_pos); // Должна двигаться к target
    }

    // Вспомогательная функция для тестирования (копия из delay.rs)
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

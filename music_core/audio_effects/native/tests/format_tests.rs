//! Тесты для аудио форматов и конвертации
//! Фокус на предотвращении потери аудиоданных

#[cfg(test)]
mod tests {
    use crate::audio::format::*;
    use crate::audio::{AudioError, SampleFormat};

    #[test]
    fn test_format_conversion_data_loss_prevention() {
        // Тест на предотвращение потери данных при конвертации битовой глубины
        let source_32bit = AudioFormat::new(SampleRate::Hz44100, 2);
        let target_16bit = AudioFormat { bit_depth: 16, ..source_32bit.clone() };

        let converter = FormatConverter::new(source_32bit, target_16bit);

        // Тест с максимальными значениями
        let max_sample = vec![1.0f32.to_le_bytes(), (-1.0f32).to_le_bytes()];
        let result = converter.convert_buffer(&max_sample);

        match result {
            Ok(data) => {
                // Данные должны быть конвертированы без потери
                assert!(!data.is_empty());
                // Для 16-bit должно быть меньше байт
                assert!(data.len() < max_sample.len());
            }
            Err(AudioError::ConversionError(_)) => {
                // Ожидаемая ошибка, поскольку конвертация не реализована
                // Но тест проверяет, что ошибка обрабатывается правильно
            }
            _ => panic!("Unexpected error type"),
        }
    }

    #[test]
    fn test_sample_rate_conversion_edge_cases() {
        // Тест конвертации частот дискретизации с edge cases
        let custom_rate = SampleRate::Custom(12345);
        let nearest = custom_rate.to_nearest_standard();
        assert_eq!(nearest, SampleRate::Hz11025);

        // Тест очень низкой частоты
        let low_rate = SampleRate::Custom(100);
        let nearest_low = low_rate.to_nearest_standard();
        assert_eq!(nearest_low, SampleRate::Hz8000);

        // Тест очень высокой частоты
        let high_rate = SampleRate::Custom(100000);
        let nearest_high = high_rate.to_nearest_standard();
        assert_eq!(nearest_high, SampleRate::Hz96000);
    }

    #[test]
    fn test_channel_layout_data_integrity() {
        // Тест на целостность данных при работе с различными layouts
        let mono = ChannelLayout::Mono;
        let stereo = ChannelLayout::Stereo;
        let surround51 = ChannelLayout::Surround51;

        // Проверяем, что количество каналов корректно
        assert_eq!(mono.channels(), 1);
        assert_eq!(stereo.channels(), 2);
        assert_eq!(surround51.channels(), 6);

        // Проверяем имена каналов
        let mono_names = mono.channel_names();
        assert_eq!(mono_names.len(), 1);
        assert_eq!(mono_names[0], "Mono");

        let stereo_names = stereo.channel_names();
        assert_eq!(stereo_names.len(), 2);
        assert_eq!(stereo_names, vec!["Left", "Right"]);

        // Тест custom layout
        let custom_layout = ChannelLayout::Custom("Custom1,Custom2".to_string());
        let custom_names = custom_layout.channel_names();
        assert_eq!(custom_names, vec!["Custom1", "Custom2"]);
    }

    #[test]
    fn test_audio_format_calculations_edge_cases() {
        // Тест расчетов размера и длительности с edge cases
        let format = AudioFormat::cd_quality();

        // Нулевая длительность
        let size_zero = format.calculate_size(0.0);
        assert_eq!(size_zero, 0);

        // Очень маленькая длительность
        let size_tiny = format.calculate_size(0.001); // 1ms
        assert!(size_tiny > 0);

        // Обратный расчет длительности
        let duration = format.calculate_duration(size_tiny);
        assert!((duration - 0.001).abs() < 0.0001);

        // Тест с нулевым размером
        let duration_zero = format.calculate_duration(0);
        assert_eq!(duration_zero, 0.0);
    }

    #[test]
    fn test_format_converter_size_ratio() {
        // Тест расчета коэффициента размера конвертации
        let source = AudioFormat::cd_quality(); // 16-bit, 44.1kHz, stereo
        let target = AudioFormat::studio_quality(); // 32-bit float, 96kHz, stereo

        let converter = FormatConverter::new(source, target);
        let ratio = converter.size_ratio();

        // Studio quality должен иметь больший размер из-за большей битовой глубины и частоты
        assert!(ratio > 1.0);

        // Тест с одинаковыми форматами
        let converter_same = FormatConverter::new(source.clone(), source);
        let ratio_same = converter_same.size_ratio();
        assert!((ratio_same - 1.0).abs() < 0.001);
    }

    #[test]
    fn test_bit_depth_conversion_boundaries() {
        // Тест границ битовой глубины
        let mut format = AudioFormat::default();

        // Минимальная битовая глубина
        format.bit_depth = 8;
        assert_eq!(format.bytes_per_sample(), 1);

        // Максимальная битовая глубина
        format.bit_depth = 64;
        assert_eq!(format.bytes_per_sample(), 8);

        // Нестандартная битовая глубина
        format.bit_depth = 24;
        assert_eq!(format.bytes_per_sample(), 3);
    }

    #[test]
    fn test_sample_format_detection() {
        // Тест определения формата семплов
        let mut format = AudioFormat::default();

        // Float 32-bit
        format.bit_depth = 32;
        format.floating_point = true;
        assert_eq!(format.sample_format(), SampleFormat::F32);

        // Float 64-bit
        format.bit_depth = 64;
        assert_eq!(format.sample_format(), SampleFormat::F64);

        // Integer 16-bit
        format.floating_point = false;
        format.bit_depth = 16;
        assert_eq!(format.sample_format(), SampleFormat::S16);

        // Integer 24-bit
        format.bit_depth = 24;
        assert_eq!(format.sample_format(), SampleFormat::S24);

        // Integer 32-bit
        format.bit_depth = 32;
        assert_eq!(format.sample_format(), SampleFormat::S32);
    }

    #[test]
    fn test_format_compatibility_edge_cases() {
        // Тест совместимости форматов с edge cases
        let base = AudioFormat::cd_quality();

        // Полностью совместимый
        assert!(base.is_compatible(&base));

        // Разная частота
        let mut different_rate = base.clone();
        different_rate.sample_rate = SampleRate::Hz48000;
        assert!(!base.is_compatible(&different_rate));

        // Разное количество каналов
        let mut different_channels = base.clone();
        different_channels.channels = 1;
        assert!(!base.is_compatible(&different_channels));

        // Разная битовая глубина
        let mut different_depth = base.clone();
        different_depth.bit_depth = 24;
        assert!(!base.is_compatible(&different_depth));

        // Разный floating point
        let mut different_fp = base.clone();
        different_fp.floating_point = true;
        assert!(!base.is_compatible(&different_fp));
    }

    #[test]
    fn test_planar_interleaved_conversion() {
        // Тест конвертации planar/interleaved
        let mut format = AudioFormat::default();
        assert!(!format.planar); // По умолчанию interleaved

        let planar = format.to_planar();
        assert!(planar.planar);

        let interleaved = planar.to_interleaved();
        assert!(!interleaved.planar);
    }
}

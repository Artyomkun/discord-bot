//! Тесты для сопоставления каналов
//! Фокус на корректном mapping между различными channel layouts

#[cfg(test)]
mod tests {
    use crate::audio::format::*;

    #[test]
    fn test_mono_to_stereo_mapping() {
        // Тест сопоставления mono -> stereo
        let mono = ChannelLayout::Mono;
        let stereo = ChannelLayout::Stereo;

        assert_eq!(mono.channels(), 1);
        assert_eq!(stereo.channels(), 2);

        // Проверяем имена каналов
        let mono_names = mono.channel_names();
        let stereo_names = stereo.channel_names();

        assert_eq!(mono_names, vec!["Mono"]);
        assert_eq!(stereo_names, vec!["Left", "Right"]);

        // Тест channel mask
        assert_eq!(mono.channel_mask(), 0x4); // SPEAKER_FRONT_CENTER
        assert_eq!(stereo.channel_mask(), 0x1 | 0x2); // LEFT | RIGHT
    }

    #[test]
    fn test_stereo_to_surround_mapping() {
        // Тест stereo -> 5.1 surround
        let stereo = ChannelLayout::Stereo;
        let surround51 = ChannelLayout::Surround51;

        assert_eq!(stereo.channels(), 2);
        assert_eq!(surround51.channels(), 6);

        let stereo_names = stereo.channel_names();
        let surround_names = surround51.channel_names();

        assert_eq!(stereo_names.len(), 2);
        assert_eq!(surround_names.len(), 6);

        // Проверяем, что surround включает stereo каналы
        assert!(surround_names.contains(&"Front Left".to_string()));
        assert!(surround_names.contains(&"Front Right".to_string()));
        assert!(surround_names.contains(&"Center".to_string()));
        assert!(surround_names.contains(&"LFE".to_string()));
        assert!(surround_names.contains(&"Rear Left".to_string()));
        assert!(surround_names.contains(&"Rear Right".to_string()));
    }

    #[test]
    fn test_ambisonics_channel_mapping() {
        // Тест ambisonics layouts
        let ambi1 = ChannelLayout::Ambisonics1;
        let ambi2 = ChannelLayout::Ambisonics2;
        let ambi3 = ChannelLayout::Ambisonics3;

        assert_eq!(ambi1.channels(), 4);
        assert_eq!(ambi2.channels(), 9);
        assert_eq!(ambi3.channels(), 16);

        // Проверяем имена каналов для first order
        let ambi1_names = ambi1.channel_names();
        assert_eq!(ambi1_names, vec!["W", "X", "Y", "Z"]);

        // Проверяем, что все layouts являются ambisonics
        assert!(ambi1.is_ambisonics());
        assert!(ambi2.is_ambisonics());
        assert!(ambi3.is_ambisonics());

        // Проверяем, что не-surround layouts не являются ambisonics
        assert!(!ChannelLayout::Stereo.is_ambisonics());
        assert!(!ChannelLayout::Mono.is_ambisonics());
    }

    #[test]
    fn test_custom_channel_layout() {
        // Тест custom channel layout
        let custom = ChannelLayout::Custom("FL,FR,FC,LFE,RL,RR".to_string());

        assert_eq!(custom.channels(), 0); // Custom не имеет фиксированного количества
        assert!(!custom.is_surround());
        assert!(!custom.is_ambisonics());

        let custom_names = custom.channel_names();
        assert_eq!(custom_names, vec!["FL", "FR", "FC", "LFE", "RL", "RR"]);

        // Тест пустого custom layout
        let empty_custom = ChannelLayout::Custom("".to_string());
        let empty_names = empty_custom.channel_names();
        assert!(empty_names.is_empty());
    }

    #[test]
    fn test_channel_layout_properties() {
        // Тест свойств различных layouts
        let layouts = vec![
            ChannelLayout::Mono,
            ChannelLayout::Stereo,
            ChannelLayout::Quad,
            ChannelLayout::Surround50,
            ChannelLayout::Surround51,
            ChannelLayout::Surround61,
            ChannelLayout::Surround71,
        ];

        for layout in layouts {
            // Все стандартные layouts должны иметь корректное количество каналов
            assert!(layout.channels() > 0);

            // Имена каналов должны соответствовать количеству
            assert_eq!(layout.channel_names().len(), layout.channels() as usize);

            // Surround layouts должны быть распознаны
            if matches!(
                layout,
                ChannelLayout::Surround50
                    | ChannelLayout::Surround51
                    | ChannelLayout::Surround61
                    | ChannelLayout::Surround71
            ) {
                assert!(layout.is_surround());
            } else {
                assert!(!layout.is_surround());
            }
        }
    }

    #[test]
    fn test_channel_mask_computation() {
        // Тест вычисления channel mask
        let mono = ChannelLayout::Mono;
        let stereo = ChannelLayout::Stereo;
        let quad = ChannelLayout::Quad;
        let surround51 = ChannelLayout::Surround51;

        // Mono: только center
        assert_eq!(mono.channel_mask(), 0x4);

        // Stereo: left + right
        assert_eq!(stereo.channel_mask(), 0x1 | 0x2);

        // Quad: front left/right + back left/right
        assert_eq!(quad.channel_mask(), 0x1 | 0x2 | 0x10 | 0x20);

        // 5.1: front left/right/center + lfe + back left/right
        assert_eq!(surround51.channel_mask(), 0x1 | 0x2 | 0x4 | 0x8 | 0x10 | 0x20);
    }

    #[test]
    fn test_audio_format_channel_layout_integration() {
        // Тест интеграции channel layout с AudioFormat
        let mono_format = AudioFormat::new(SampleRate::Hz44100, 1);
        let stereo_format = AudioFormat::new(SampleRate::Hz44100, 2);
        let surround_format = AudioFormat {
            channels: 6,
            channel_layout: ChannelLayout::Surround51,
            ..AudioFormat::default()
        };

        // Проверяем соответствие количества каналов
        assert_eq!(mono_format.channels, 1);
        assert_eq!(stereo_format.channels, 2);
        assert_eq!(surround_format.channels, 6);

        // Проверяем layout
        match mono_format.channel_layout {
            ChannelLayout::Mono => {}
            _ => panic!("Mono format should have Mono layout"),
        }

        match stereo_format.channel_layout {
            ChannelLayout::Stereo => {}
            _ => panic!("Stereo format should have Stereo layout"),
        }

        match surround_format.channel_layout {
            ChannelLayout::Surround51 => {}
            _ => panic!("Surround format should have Surround51 layout"),
        }
    }

    #[test]
    fn test_channel_layout_edge_cases() {
        // Тест edge cases для channel layouts

        // Ambisonics3 имеет 16 каналов с именами от W до Q
        let ambi3 = ChannelLayout::Ambisonics3;
        let names = ambi3.channel_names();
        assert_eq!(names.len(), 16);
        assert_eq!(names[0], "W");
        assert_eq!(names[15], "Q");

        // Surround71 имеет все surround каналы
        let surround71 = ChannelLayout::Surround71;
        let surround_names = surround71.channel_names();
        assert_eq!(surround_names.len(), 8);
        assert!(surround_names.contains(&"Side Left".to_string()));
        assert!(surround_names.contains(&"Side Right".to_string()));
    }

    #[test]
    fn test_channel_layout_serialization() {
        // Тест сериализации/десериализации (через bincode)
        use bincode::{Decode, Encode};

        let layouts = vec![
            ChannelLayout::Mono,
            ChannelLayout::Stereo,
            ChannelLayout::Surround51,
            ChannelLayout::Ambisonics1,
            ChannelLayout::Custom("Test".to_string()),
        ];

        for layout in layouts {
            // Тест bincode сериализации
            let encoded = bincode::encode_to_vec(&layout, bincode::config::standard()).unwrap();
            let decoded: ChannelLayout =
                bincode::decode_from_slice(&encoded, bincode::config::standard()).unwrap().0;

            // Должны быть равны после сериализации
            assert_eq!(layout, decoded);
        }
    }
}

//! Бенчмарки производительности аудио эффектов

use audio_effects_native::{
    audio::AudioFormat,
    dsp::{
        compressor::{Compressor, CompressorConfig},
        eq::{EQBand, EQFilterType, ParametricEQ},
        reverb::{ReverbAlgorithm, ReverbParams, ReverbProcessor},
        utils::generate_sine,
        AudioBuffer,
    },
    SampleRate,
};
use criterion::{criterion_group, criterion_main, BenchmarkId, Criterion};

fn bench_compressor(c: &mut Criterion) {
    let mut group = c.benchmark_group("compressor");

    let sample_rate = 44100.0;
    let config = CompressorConfig::default();

    for buffer_size in [1024, 4096, 16384, 65536].iter() {
        let signal = generate_sine(440.0, sample_rate, *buffer_size as f32 / sample_rate, 0.8);

        group.bench_with_input(
            BenchmarkId::from_parameter(buffer_size),
            buffer_size,
            |b, &_size| {
                let mut compressor = Compressor::new(config.clone(), sample_rate);
                let mut buffer = signal.clone();

                b.iter(|| {
                    compressor.process_buffer(&mut buffer);
                    compressor.reset();
                });
            },
        );
    }

    group.finish();
}

fn bench_eq(c: &mut Criterion) {
    let mut group = c.benchmark_group("eq");

    let sample_rate = 44100.0;
    let bands = vec![
        EQBand {
            frequency: 100.0,
            gain: 3.0,
            q: 1.0,
            filter_type: EQFilterType::LowShelf,
            enabled: true,
            slope: 1.0,
        },
        EQBand {
            frequency: 1000.0,
            gain: -2.0,
            q: 2.0,
            filter_type: EQFilterType::Peak,
            enabled: true,
            slope: 1.0,
        },
        EQBand {
            frequency: 8000.0,
            gain: 1.0,
            q: 1.0,
            filter_type: EQFilterType::HighShelf,
            enabled: true,
            slope: 1.0,
        },
    ];

    for buffer_size in [1024, 4096, 16384, 65536].iter() {
        let signal = generate_sine(440.0, sample_rate, *buffer_size as f32 / sample_rate, 0.5);

        group.bench_with_input(
            BenchmarkId::from_parameter(buffer_size),
            buffer_size,
            |b, &_size| {
                let mut eq = ParametricEQ::new(bands.clone(), sample_rate, 0.0);
                let mut buffer = signal.clone();

                b.iter(|| {
                    eq.process_buffer(&mut buffer);
                });
            },
        );
    }

    group.finish();
}

fn bench_reverb(c: &mut Criterion) {
    let mut group = c.benchmark_group("reverb");

    let sample_rate = 44100.0;
    let params = ReverbParams {
        algorithm: ReverbAlgorithm::FDN,
        decay_time: 2.0,
        room_size: 0.7,
        ..Default::default()
    };

    for buffer_size in [1024, 4096, 16384].iter() {
        let signal = generate_sine(440.0, sample_rate, *buffer_size as f32 / sample_rate, 0.5);

        group.bench_with_input(
            BenchmarkId::from_parameter(buffer_size),
            buffer_size,
            |b, &_size| {
                let mut reverb = ReverbProcessor::new(params.clone(), sample_rate);
                let mut left = signal.clone();
                let mut right = signal.clone();

                b.iter(|| {
                    reverb.process_stereo(&mut left, &mut right);
                });
            },
        );
    }

    group.finish();
}

fn bench_audio_buffer_operations(c: &mut Criterion) {
    let mut group = c.benchmark_group("audio_buffer");

    let format = AudioFormat {
        sample_rate: SampleRate::Hz44100,
        channels: 2,
        bit_depth: 32,
        floating_point: true,
    };

    for buffer_size in [1024, 4096, 16384, 65536].iter() {
        let samples = *buffer_size;
        let mut data = Vec::with_capacity(samples * 2);

        for (i, _) in float_data.iter().enumerate().take(samples) {
            let t = i as f32 / 44100.0;
            let sample = (2.0 * std::f32::consts::PI * 440.0 * t).sin() * 0.5;
            data.push(sample);
            data.push(sample * 0.8);
        }

        group.bench_with_input(
            BenchmarkId::new("from_slice", buffer_size),
            buffer_size,
            |b, &_size| {
                b.iter(|| {
                    let _buffer = AudioBuffer::from_slice(&data, format).unwrap();
                });
            },
        );

        let buffer = AudioBuffer::from_slice(&data, format).unwrap();

        group.bench_with_input(
            BenchmarkId::new("to_interleaved", buffer_size),
            buffer_size,
            |b, &_size| {
                b.iter(|| {
                    let _interleaved = buffer.to_interleaved();
                });
            },
        );

        group.bench_with_input(
            BenchmarkId::new("normalize_peak", buffer_size),
            buffer_size,
            |b, &_size| {
                let mut buffer_clone = buffer.clone();
                b.iter(|| {
                    buffer_clone.normalize_peak(0.5);
                });
            },
        );

        group.bench_with_input(
            BenchmarkId::new("calculate_rms", buffer_size),
            buffer_size,
            |b, &_size| {
                b.iter(|| {
                    let _rms = buffer.calculate_rms();
                });
            },
        );
    }

    group.finish();
}

fn bench_parallel_processing(c: &mut Criterion) {
    let mut group = c.benchmark_group("parallel");
    group.sample_size(10); // Меньше семплов для длительных тестов

    let sample_rate = 44100.0;
    let config = CompressorConfig::default();

    // Большие буферы для тестирования параллельной обработки
    for buffer_size in [65536, 131072, 262144, 524288].iter() {
        let signal = generate_sine(440.0, sample_rate, *buffer_size as f32 / sample_rate, 0.8);

        group.bench_with_input(
            BenchmarkId::new("compressor_serial", buffer_size),
            buffer_size,
            |b, &_size| {
                let mut compressor = Compressor::new(config.clone(), sample_rate);
                let mut buffer = signal.clone();

                b.iter(|| {
                    compressor.process_buffer(&mut buffer);
                    compressor.reset();
                });
            },
        );

        // Тест с параллельной обработкой (если включена фича)
        #[cfg(feature = "parallel")]
        {
            use audio_effects_native::dsp::compressor::MultibandCompressor;

            group.bench_with_input(
                BenchmarkId::new("multiband_compressor", buffer_size),
                buffer_size,
                |b, &_size| {
                    let crossover_freqs = vec![200.0, 2000.0, 8000.0];
                    let mut mb_compressor = MultibandCompressor::new(&crossover_freqs, sample_rate);
                    let mut buffer = signal.clone();

                    b.iter(|| {
                        mb_compressor.process_buffer(&mut buffer);
                        mb_compressor.reset();
                    });
                },
            );
        }
    }

    group.finish();
}

criterion_group!(
    name = benches;
    config = Criterion::default()
        .sample_size(20)
        .warm_up_time(std::time::Duration::from_secs(1))
        .measurement_time(std::time::Duration::from_secs(3));
    targets =
        bench_compressor,
        bench_eq,
        bench_reverb,
        bench_audio_buffer_operations,
        bench_parallel_processing
);

criterion_main!(benches);

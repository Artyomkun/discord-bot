use criterion::{black_box, criterion_group, criterion_main, Criterion};
use music_core_audio_effects_native::audio::converter::{AudioConverter, ResampleQuality};
use music_core_audio_effects_native::audio::SampleFormat;
use rand::prelude::*;

// Создание тестовых данных в формате F32
fn create_test_data_f32(size: usize) -> Vec<u8> {
    let mut rng = rand::thread_rng();
    let samples: Vec<f32> = (0..size).map(|_| rng.gen::<f32>() * 2.0 - 1.0).collect();
    samples.iter().flat_map(|&s| s.to_le_bytes()).collect()
}

// Создание тестовых данных в формате I16
fn create_test_data_i16(size: usize) -> Vec<u8> {
    let mut rng = rand::thread_rng();
    let samples: Vec<i16> = (0..size).map(|_| (rng.gen::<f32>() * 32767.0) as i16).collect();
    samples.iter().flat_map(|&s| s.to_le_bytes()).collect()
}

fn bench_convert_f32_to_i16(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::Fast);
    let data = create_test_data_f32(1024);

    c.bench_function("convert_f32_to_i16", |b| {
        b.iter(|| {
            black_box(converter.convert_format(&data, SampleFormat::F32, SampleFormat::S16, 1))
                .unwrap();
        })
    });
}

fn bench_convert_i16_to_f32(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::Fast);
    let data = create_test_data_i16(1024);

    c.bench_function("convert_i16_to_f32", |b| {
        b.iter(|| {
            black_box(converter.convert_format(&data, SampleFormat::S16, SampleFormat::F32, 1))
                .unwrap();
        })
    });
}

fn bench_convert_f32_to_u8(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::Fast);
    let data = create_test_data_f32(1024);

    c.bench_function("convert_f32_to_u8", |b| {
        b.iter(|| {
            black_box(converter.convert_format(&data, SampleFormat::F32, SampleFormat::U8, 1))
                .unwrap();
        })
    });
}

fn bench_resample_linear(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::Fast);
    let data: Vec<f32> = create_test_data_f32(1024)
        .chunks(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect();

    c.bench_function("resample_linear", |b| {
        b.iter(|| {
            black_box(converter.resample(&data, 44100, 48000, 1)).unwrap();
        })
    });
}

fn bench_resample_cubic(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::Medium);
    let data: Vec<f32> = create_test_data_f32(1024)
        .chunks(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect();

    c.bench_function("resample_cubic", |b| {
        b.iter(|| {
            black_box(converter.resample(&data, 44100, 48000, 1)).unwrap();
        })
    });
}

fn bench_resample_sinc(c: &mut Criterion) {
    let converter = AudioConverter::new(ResampleQuality::High);
    let data: Vec<f32> = create_test_data_f32(1024)
        .chunks(4)
        .map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]]))
        .collect();

    c.bench_function("resample_sinc", |b| {
        b.iter(|| {
            black_box(converter.resample(&data, 44100, 48000, 1)).unwrap();
        })
    });
}

criterion_group!(
    converter,
    bench_convert_f32_to_i16,
    bench_convert_i16_to_f32,
    bench_convert_f32_to_u8,
    bench_resample_linear,
    bench_resample_cubic,
    bench_resample_sinc
);
criterion_main!(converter);

extern crate audio_effects_native;

use audio_effects_native::audio::{AudioBuffer, AudioFormat, SampleFormat};
use criterion::{black_box, criterion_group, criterion_main, Criterion};
use rand::prelude::*;

// Создание тестового буфера
fn create_test_buffer() -> AudioBuffer<1024> {
    let mut rng = rand::rng();
    let samples: Vec<f32> = (0..512).map(|_| rng.random::<f32>() * 2.0 - 1.0).collect();

    AudioBuffer::from_samples(&samples, 2, 44100).unwrap()
}

fn bench_buffer_apply(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_apply", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.apply(|x| x * 0.5)).unwrap();
        })
    });
}

fn bench_buffer_normalize_peak(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_normalize_peak", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.normalize_peak(0.8)).unwrap();
        })
    });
}

fn bench_buffer_normalize_rms(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_normalize_rms", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            buffer.normalize_rms(0.5);
        })
    });
}

fn bench_buffer_calculate_rms(c: &mut Criterion) {
    let buffer = create_test_buffer();

    c.bench_function("buffer_calculate_rms", |b: &mut criterion::Bencher| {
        b.iter(|| {
            black_box(buffer.calculate_rms());
        })
    });
}

fn bench_buffer_calculate_peak(c: &mut Criterion) {
    let buffer = create_test_buffer();

    c.bench_function("buffer_calculate_peak", |b: &mut criterion::Bencher| {
        b.iter(|| {
            black_box(buffer.calculate_peak());
        })
    });
}

fn bench_buffer_remove_dc_offset(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_remove_dc_offset", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.remove_dc_offset()).unwrap();
        })
    });
}

fn bench_buffer_fade_in(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_fade_in", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.fade_in(0.1)).unwrap();
        })
    });
}

fn bench_buffer_fade_out(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_fade_out", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.fade_out(0.1)).unwrap();
        })
    });
}

fn bench_buffer_trim_silence(c: &mut Criterion) {
    let mut buffer = create_test_buffer();

    c.bench_function("buffer_trim_silence", |b: &mut criterion::Bencher| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(buffer.trim_silence(-60.0)).unwrap();
        })
    });
}

fn bench_buffer_to_planar(c: &mut Criterion) {
    let buffer = create_test_buffer();

    c.bench_function("buffer_to_planar", |b: &mut criterion::Bencher| {
        b.iter(|| {
            black_box(buffer.to_planar());
        })
    });
}

fn bench_buffer_to_interleaved(c: &mut Criterion) {
    let buffer = create_test_buffer();

    c.bench_function("buffer_to_interleaved", |b: &mut criterion::Bencher| {
        b.iter(|| {
            black_box(buffer.to_interleaved());
        })
    });
}

fn bench_buffer_resample(c: &mut Criterion) {
    let buffer = create_test_buffer();

    c.bench_function("buffer_resample", |b: &mut criterion::Bencher| {
        b.iter(|| {
            black_box(buffer.resample(48000));
        })
    });
}

criterion_group!(
    buffer,
    bench_buffer_apply,
    bench_buffer_normalize_peak,
    bench_buffer_normalize_rms,
    bench_buffer_calculate_rms,
    bench_buffer_calculate_peak,
    bench_buffer_remove_dc_offset,
    bench_buffer_fade_in,
    bench_buffer_fade_out,
    bench_buffer_trim_silence,
    bench_buffer_to_planar,
    bench_buffer_to_interleaved,
    bench_buffer_resample
);
criterion_main!(buffer);

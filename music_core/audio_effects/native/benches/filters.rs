use criterion::{black_box, criterion_group, criterion_main, Criterion};
use music_core_audio_effects_native::dsp::filter::{Biquad, FIRFilter, Filter, FilterType};
use rand::prelude::*;

// Создание тестовых данных
fn create_test_signal(size: usize) -> Vec<f32> {
    let mut rng = rand::thread_rng();
    (0..size).map(|_| rng.gen::<f32>() * 2.0 - 1.0).collect()
}

fn bench_biquad_process(c: &mut Criterion) {
    let mut biquad = Biquad::new();
    biquad = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 44100.0, 1.0, 0.0);
    let signal = create_test_signal(1024);

    c.bench_function("biquad_process", |b| {
        b.iter(|| {
            let mut biquad = biquad.clone();
            for &sample in &signal {
                black_box(biquad.process(sample));
            }
        })
    });
}

fn bench_biquad_process_buffer(c: &mut Criterion) {
    let mut biquad = Biquad::new();
    biquad = biquad.calculate_coefficients(FilterType::LowPass, 1000.0, 44100.0, 1.0, 0.0);
    let mut signal = create_test_signal(1024);

    c.bench_function("biquad_process_buffer", |b| {
        b.iter(|| {
            let mut biquad = biquad.clone();
            biquad.process_buffer(black_box(&mut signal));
        })
    });
}

fn bench_filter_process(c: &mut Criterion) {
    let mut filter = Filter::new(FilterType::LowPass, 44100.0);
    filter.set_frequency(1000.0);
    filter.set_q(1.0);
    let signal = create_test_signal(1024);

    c.bench_function("filter_process", |b| {
        b.iter(|| {
            let mut filter = filter.clone();
            for &sample in &signal {
                let mut sample = sample;
                filter.process(black_box(&mut sample));
            }
        })
    });
}

fn bench_filter_process_buffer(c: &mut Criterion) {
    let mut filter = Filter::new(FilterType::LowPass, 44100.0);
    filter.set_frequency(1000.0);
    filter.set_q(1.0);
    let mut signal = create_test_signal(1024);

    c.bench_function("filter_process_buffer", |b| {
        b.iter(|| {
            let mut filter = filter.clone();
            filter.process_buffer(black_box(&mut signal));
        })
    });
}

fn bench_fir_process(c: &mut Criterion) {
    // Создаем FIR фильтр low-pass
    let coefficients = FIRFilter::design_lowpass(1000.0, 44100.0, 51);
    let mut fir = FIRFilter::new(coefficients);
    let signal = create_test_signal(1024);

    c.bench_function("fir_process", |b| {
        b.iter(|| {
            let mut fir = fir.clone();
            for &sample in &signal {
                black_box(fir.process(sample));
            }
        })
    });
}

fn bench_fir_process_buffer(c: &mut Criterion) {
    // Создаем FIR фильтр low-pass
    let coefficients = FIRFilter::design_lowpass(1000.0, 44100.0, 51);
    let mut fir = FIRFilter::new(coefficients);
    let mut signal = create_test_signal(1024);

    c.bench_function("fir_process_buffer", |b| {
        b.iter(|| {
            let mut fir = fir.clone();
            fir.process_buffer(black_box(&mut signal));
        })
    });
}

criterion_group!(
    filters,
    bench_biquad_process,
    bench_biquad_process_buffer,
    bench_filter_process,
    bench_filter_process_buffer,
    bench_fir_process,
    bench_fir_process_buffer
);
criterion_main!(filters);

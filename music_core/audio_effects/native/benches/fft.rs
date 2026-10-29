use criterion::{black_box, criterion_group, criterion_main, Criterion};
use music_core_audio_effects_native::dsp::fft::{WindowType, FFT};
use rand::prelude::*;

// Создание тестового сигнала
fn create_test_signal(size: usize) -> Vec<f32> {
    let mut rng = rand::thread_rng();
    (0..size).map(|_| rng.gen::<f32>() * 2.0 - 1.0).collect()
}

fn bench_fft_forward(c: &mut Criterion) {
    let fft = FFT::new(1024);
    let signal = create_test_signal(1024);

    c.bench_function("fft_forward", |b| {
        b.iter(|| {
            black_box(fft.forward(&signal));
        })
    });
}

fn bench_fft_inverse(c: &mut Criterion) {
    let fft = FFT::new(1024);
    let spectrum = fft.forward(&create_test_signal(1024));

    c.bench_function("fft_inverse", |b| {
        b.iter(|| {
            black_box(fft.inverse(&spectrum));
        })
    });
}

fn bench_fft_stft(c: &mut Criterion) {
    let fft = FFT::new(512);
    let signal = create_test_signal(2048);
    let window = fft.create_window(WindowType::Hann);
    let hop_size = 256;

    c.bench_function("fft_stft", |b| {
        b.iter(|| {
            black_box(fft.stft(&signal, hop_size, &window));
        })
    });
}

fn bench_fft_istft(c: &mut Criterion) {
    let fft = FFT::new(512);
    let signal = create_test_signal(2048);
    let window = fft.create_window(WindowType::Hann);
    let hop_size = 256;
    let stft_frames = fft.stft(&signal, hop_size, &window);

    c.bench_function("fft_istft", |b| {
        b.iter(|| {
            black_box(fft.istft(&stft_frames, hop_size, &window));
        })
    });
}

fn bench_fft_analyze(c: &mut Criterion) {
    let mut fft = FFT::new(1024);
    let signal = create_test_signal(1024);
    let window = fft.create_window(WindowType::Hann);

    c.bench_function("fft_analyze", |b| {
        b.iter(|| {
            black_box(fft.analyze(&signal, &window));
        })
    });
}

fn bench_fft_power_spectrum(c: &mut Criterion) {
    let fft = FFT::new(1024);
    let spectrum = fft.forward(&create_test_signal(1024));

    c.bench_function("fft_power_spectrum", |b| {
        b.iter(|| {
            black_box(FFT::power_spectrum(&spectrum));
        })
    });
}

fn bench_fft_magnitude_spectrum(c: &mut Criterion) {
    let fft = FFT::new(1024);
    let spectrum = fft.forward(&create_test_signal(1024));

    c.bench_function("fft_magnitude_spectrum", |b| {
        b.iter(|| {
            black_box(FFT::magnitude_spectrum(&spectrum));
        })
    });
}

criterion_group!(
    fft,
    bench_fft_forward,
    bench_fft_inverse,
    bench_fft_stft,
    bench_fft_istft,
    bench_fft_analyze,
    bench_fft_power_spectrum,
    bench_fft_magnitude_spectrum
);
criterion_main!(fft);

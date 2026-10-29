use criterion::{black_box, criterion_group, criterion_main, Criterion};
use music_core_audio_effects_native::audio::{AudioBuffer, AudioFormat, SampleFormat};
use music_core_audio_effects_native::effects::{
    Chorus, ChorusConfig, ChorusType, ChorusVoice, Delay, DelayConfig, DelayTap, DelayType, Reverb,
    ReverbConfig, ReverbType,
};
use rand::prelude::*;

// Создание тестового буфера
fn create_test_buffer() -> AudioBuffer<1024> {
    let mut rng = rand::thread_rng();
    let samples: Vec<f32> = (0..512).map(|_| rng.gen::<f32>() * 2.0 - 1.0).collect(); // 512 семплов для стерео

    AudioBuffer::from_samples(&samples, 2, 44100).unwrap()
}

fn bench_delay_process(c: &mut Criterion) {
    let config = DelayConfig {
        delay_type: DelayType::Stereo,
        taps: vec![DelayTap::default()],
        modulation_rate: 0.5,
        modulation_depth: 0.1,
        low_cut: 100.0,
        high_cut: 10000.0,
        tape_saturation: 0.0,
        wow_flutter: 0.0,
        wet: 0.3,
        dry: 0.7,
    };
    let format = AudioFormat::new(44100, 2, SampleFormat::F32);
    let mut delay = Delay::<1024>::new(config, format);
    let mut buffer = create_test_buffer();

    c.bench_function("delay_process", |b| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(delay.process(&mut buffer)).unwrap();
        })
    });
}

fn bench_reverb_process(c: &mut Criterion) {
    let config = ReverbConfig {
        reverb_type: ReverbType::Hall,
        decay_time: 2.0,
        pre_delay: 20.0,
        diffusion: 0.7,
        density: 0.8,
        early_reflections: 0.6,
        late_reflections: 0.8,
        room_size: 0.7,
        damping: 0.5,
        modulation: 0.3,
        wet: 0.3,
        dry: 0.7,
    };
    let format = AudioFormat::new(44100, 2, SampleFormat::F32);
    let mut reverb = Reverb::<1024>::new(config, format);
    let mut buffer = create_test_buffer();

    c.bench_function("reverb_process", |b| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(reverb.process(&mut buffer)).unwrap();
        })
    });
}

fn bench_chorus_process(c: &mut Criterion) {
    let config = ChorusConfig {
        chorus_type: ChorusType::Chorus,
        voices: vec![
            ChorusVoice {
                delay_time: 20.0,
                depth: 0.3,
                rate: 0.5,
                feedback: 0.2,
                phase_offset: 0.0,
                pan: -0.5,
                enabled: true,
            },
            ChorusVoice {
                delay_time: 25.0,
                depth: 0.3,
                rate: 0.6,
                feedback: 0.2,
                phase_offset: 90.0,
                pan: 0.5,
                enabled: true,
            },
        ],
        stereo_width: 0.8,
        low_cut: 200.0,
        high_cut: 8000.0,
        modulation_shape: music_core_audio_effects_native::effects::ModulationShape::Sine,
        wet: 0.5,
        dry: 0.5,
    };
    let format = AudioFormat::new(44100, 2, SampleFormat::F32);
    let mut chorus = Chorus::<1024>::new(config, format);
    let mut buffer = create_test_buffer();

    c.bench_function("chorus_process", |b| {
        b.iter(|| {
            let mut buffer = buffer.clone();
            black_box(chorus.process(&mut buffer)).unwrap();
        })
    });
}

criterion_group!(effects, bench_delay_process, bench_reverb_process, bench_chorus_process);
criterion_main!(effects);

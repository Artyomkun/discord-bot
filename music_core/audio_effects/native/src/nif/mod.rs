pub mod utils;
pub mod cache;

use crate::effects::*;
use crate::audio::*;
use crate::audio::stream::{AudioStream, StreamConfig};
use crate::dsp::analysis::SpectralAnalyzer;
use crate::effects::reverb::{Reverb, ReverbConfig};
use crate::dsp::eq::{EQBand, ParametricEQ};
use crate::audio::buffer::AudioBuffer;
use crate::nif::utils::*;
use crate::dsp::utils::utils as dsp_utils;
use rustler::{
    Binary, Env, Error, NifResult, Term,
    Atom, types::atom::ok, nif
};

use std::sync::{Arc, Mutex, LazyLock};
use std::collections::HashMap;

const BUFFER_SIZE: usize = 1024;

// ============================================================================
// GLOBAL STORAGE FOR AUDIO STREAMS
// ============================================================================

static STREAMS: LazyLock<Mutex<HashMap<u64, Arc<AudioStream<1024>>>>> = LazyLock::new(|| Mutex::new(HashMap::new()));
static NEXT_ID: LazyLock<Mutex<u64>> = LazyLock::new(|| Mutex::new(1));

// ============================================================================
// AUDIO STREAM NIF FUNCTIONS
// ============================================================================

#[nif]
fn rustc_version() -> String {
    format!("rustc {}", rustc_version_runtime::version())
}

#[nif]
fn version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

#[nif]
fn create_stream(config: StreamConfig) -> NifResult<u64> {
    let stream = Arc::new(AudioStream::new(config));
    let mut next_id = NEXT_ID.lock().unwrap();
    let id = *next_id;
    *next_id += 1;
    let mut streams = STREAMS.lock().unwrap();
    streams.insert(id, stream);
    Ok(id)
}

#[nif]
fn process_stream<'a>(
    env: Env<'a>,
    stream_id: u64,
    input_binary: Binary<'a>,
) -> NifResult<Binary<'a>> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    let input_samples = unsafe {
        std::slice::from_raw_parts(
            input_binary.as_ptr() as *const f32,
            input_binary.len() / std::mem::size_of::<f32>(),
        )
    };
    
    let mut output_samples = vec![0.0f32; input_samples.len()];
    
    match stream.process(input_samples, &mut output_samples) {
        Ok(()) => {
            let bytes: Vec<u8> = output_samples.iter().flat_map(|&s| s.to_le_bytes()).collect();
            to_binary(env, &bytes)
        }
        Err(e) => {
            log::error!("Audio processing error: {}", e);
            to_binary(env, &vec![0u8; input_samples.len() * 4])
        }
    }
}

#[nif]
fn add_volume_effect(stream_id: u64, gain: f32) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    let effect = Box::new(VolumeEffect::new(gain));
    stream.add_effect(effect);
    Ok(ok())
}

#[nif]
fn add_equalizer_effect(
    stream_id: u64,
    low_gain: f32,
    mid_gain: f32,
    high_gain: f32,
) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    let effect = Box::new(EqualizerEffect::new(
        low_gain, mid_gain, high_gain, stream.sample_rate,
    ));
    stream.add_effect(effect);
    Ok(ok())
}

#[nif]
fn add_echo_effect(
    stream_id: u64,
    delay_ms: f32,
    feedback: f32,
    mix: f32,
) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    let effect = Box::new(EchoEffect::new(delay_ms, feedback, mix, stream.sample_rate, stream.channels));
    stream.add_effect(effect);
    Ok(ok())
}

#[nif]
fn clear_stream_effects(stream_id: u64) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    stream.clear_effects();
    Ok(ok())
}

#[nif]
fn set_stream_volume(stream_id: u64, volume: f32) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    stream.set_volume(volume);
    Ok(ok())
}

#[nif]
fn get_stream_volume(stream_id: u64) -> NifResult<f32> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    Ok(stream.get_volume())
}

#[nif]
fn set_stream_playing(stream_id: u64, playing: bool) -> NifResult<Atom> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    stream.set_playing(playing);
    Ok(ok())
}

#[nif]
fn get_stream_info(env: Env, stream_id: u64) -> NifResult<Term> {
    let streams = STREAMS.lock().unwrap();
    let stream = streams.get(&stream_id).ok_or(Error::RaiseAtom("stream_not_found"))?;
    let info = stream.get_info();

    let effect_names_atoms: Vec<Term> = info
        .effect_names
        .iter()
        .map(|name| {
            let atom = Atom::from_str(env, name.as_str())
                .unwrap_or(Atom::from_str(env, "unknown").unwrap());
            atom.to_term(env)
        })
        .collect();

    let mut map = rustler::types::map::map_new(env);
    map = map.map_put(Atom::from_str(env, "sample_rate").unwrap(), info.sample_rate).unwrap();
    map = map.map_put(Atom::from_str(env, "channels").unwrap(), info.channels).unwrap();
    map = map.map_put(Atom::from_str(env, "volume").unwrap(), info.volume).unwrap();
    map = map.map_put(Atom::from_str(env, "is_playing").unwrap(), info.is_playing).unwrap();
    map = map.map_put(Atom::from_str(env, "position").unwrap(), info.position as i64).unwrap();
    map = map.map_put(Atom::from_str(env, "num_effects").unwrap(), info.num_effects as i64).unwrap();

    use rustler::Encoder;
    let list = effect_names_atoms.encode(env);
    map = map.map_put(Atom::from_str(env, "effect_names").unwrap(), list).unwrap();

    Ok(map)
}

#[nif]
fn destroy_stream(stream_id: u64) -> NifResult<Atom> {
    let mut streams = STREAMS.lock().unwrap();
    streams.remove(&stream_id);
    Ok(ok())
}

// ============================================================================
// МАКРОСЫ ДЛЯ ЭФФЕКТОВ (без изменений)
// ============================================================================

macro_rules! create_effect_nif {
    ($name:ident, $type:ty, $config_type:ty) => {
        #[nif]
        fn $name<'a>(env: Env<'a>, config_json: String, sample_rate: f32) -> NifResult<Binary<'a>> {
            let config: $config_type = serde_json::from_str(&config_json)
                .map_err(|e| Error::RaiseTerm(Box::new(format!("config_error: {}", e))))?;
            
            let effect = <$type>::new(config, stereo_format(sample_rate));
            let data = encode_effect(&effect)?;
            to_binary(env, &data)
        }
    };
}

macro_rules! process_effect_nif {
    ($name:ident, $type:ty) => {
        #[nif]
        fn $name<'a>(env: Env<'a>, effect_data: Binary<'a>, audio_data: Binary<'a>) -> NifResult<Binary<'a>> {
            let mut effect: $type = decode_effect(effect_data.as_slice())?;
            let audio_f32 = binary_to_f32(&audio_data);

            if audio_f32.is_empty() {
                return f32_to_binary(env, &[]);
            }

            let mut buffer = AudioBuffer::<BUFFER_SIZE>::from_slice(&audio_f32, effect.format().clone())
                .ok_or(Error::RaiseAtom("buffer_error"))?;

            effect.process(&mut buffer)
                .map_err(|e| Error::RaiseTerm(Box::new(format!("process_error: {}", e))))?;

            f32_to_binary(env, &buffer.to_interleaved())
        }
    };
}

// ============================================================================
// PROCESSOR CACHE OPERATIONS
// ============================================================================

#[nif]
fn init_processor(sample_rate: u32, channels: u8) -> NifResult<u64> {
    if channels == 0 || channels > 8 {
        return Err(Error::RaiseAtom("invalid_channels"));
    }

    let format = AudioFormat {
        sample_rate: SampleRate::Custom(sample_rate),
        channels,
        bit_depth: 32,
        floating_point: true,
        channel_layout: if channels == 1 { ChannelLayout::Mono } else { ChannelLayout::Stereo },
        little_endian: true,
        planar: false,
    };

    let processor = AudioProcessor::new(vec![], format)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("init_error: {}", e))))?;

    let mut cache = get_cache()?;
    Ok(cache.add(processor))
}

#[nif]
fn process_processor<'a>(
    env: Env<'a>,
    processor_id: u64,
    audio_data: Binary<'a>,
    config_json: String,
) -> NifResult<Binary<'a>> {
    let cache = get_cache()?;
    let processor_arc = cache.get(processor_id)
        .ok_or(Error::RaiseAtom("processor_not_found"))?;
    drop(cache);
    
    let mut processor = processor_arc.lock()
        .map_err(|_| Error::RaiseAtom("processor_lock_failed"))?;

    let configs: Vec<EffectConfig<1024>> = serde_json::from_str(&config_json)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("config_error: {}", e))))?;
    
    processor.update_effects(configs)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("update_error: {}", e))))?;

    let audio_f32 = binary_to_f32(&audio_data);
    if audio_f32.is_empty() {
        return f32_to_binary(env, &[]);
    }
    
    let mut buffer = AudioBuffer::<BUFFER_SIZE>::from_slice(&audio_f32, processor.format().clone())
        .ok_or(Error::RaiseAtom("buffer_error"))?;

    processor.process(&mut buffer)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("process_error: {}", e))))?;

    f32_to_binary(env, &buffer.to_interleaved())
}

#[nif]
fn get_processor_stats(processor_id: u64) -> NifResult<String> {
    let cache = get_cache()?;
    let processor_arc = cache.get(processor_id)
        .ok_or(Error::RaiseAtom("processor_not_found"))?;
    drop(cache);
    
    let processor = processor_arc.lock()
        .map_err(|_| Error::RaiseAtom("processor_lock_failed"))?;
    
    let stats = processor.get_metrics();
    serde_json::to_string(&stats)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("json_error: {}", e))))
}

#[nif]
fn reset_processor(processor_id: u64) -> NifResult<&'static str> {
    let cache = get_cache()?;
    let processor_arc = cache.get(processor_id)
        .ok_or(Error::RaiseAtom("processor_not_found"))?;
    drop(cache);
    
    processor_arc.lock()
        .map_err(|_| Error::RaiseAtom("processor_lock_failed"))?
        .reset();
    
    Ok("ok")
}

#[nif]
fn remove_processor(processor_id: u64) -> NifResult<&'static str> {
    let mut cache = get_cache()?;
    if cache.remove(processor_id) {
        Ok("ok")
    } else {
        Err(Error::RaiseAtom("not_found"))
    }
}

#[nif]
fn clear_processor_cache() -> NifResult<&'static str> {
    let mut cache = get_cache()?;
    cache.clear();
    Ok("ok")
}

// ============================================================================
// ЭФФЕКТЫ (создание)
// ============================================================================

create_effect_nif!(create_compressor, Compressor<BUFFER_SIZE>, CompressorConfig);
create_effect_nif!(create_reverb, Reverb<BUFFER_SIZE>, ReverbConfig);
create_effect_nif!(create_delay, Delay<BUFFER_SIZE>, DelayConfig);
create_effect_nif!(create_distortion, Distortion<BUFFER_SIZE>, DistortionConfig);
create_effect_nif!(create_chorus, Chorus<BUFFER_SIZE>, ChorusConfig);

// ============================================================================
// ЭФФЕКТЫ (обработка)
// ============================================================================

process_effect_nif!(process_compressor, Compressor<BUFFER_SIZE>);
process_effect_nif!(process_reverb_simple, Reverb<BUFFER_SIZE>);
process_effect_nif!(process_delay, Delay<BUFFER_SIZE>);
process_effect_nif!(process_distortion, Distortion<BUFFER_SIZE>);
process_effect_nif!(process_chorus, Chorus<BUFFER_SIZE>);

#[nif]
fn process_reverb_stereo<'a>(
    env: Env<'a>,
    reverb_data: Binary<'a>,
    left_audio: Binary<'a>,
    right_audio: Binary<'a>,
) -> NifResult<(Binary<'a>, Binary<'a>)> {
    let mut reverb: Reverb<BUFFER_SIZE> = decode_effect(reverb_data.as_slice())?;
    let left_f32 = binary_to_f32(&left_audio);
    let right_f32 = binary_to_f32(&right_audio);
    
    if left_f32.is_empty() || right_f32.is_empty() {
        return Ok((f32_to_binary(env, &[])?, f32_to_binary(env, &[])?));
    }
    
    if left_f32.len() != right_f32.len() {
        return Err(Error::RaiseTerm(Box::new("channel_length_mismatch")));
    }
    
    let mut interleaved = Vec::with_capacity(left_f32.len() * 2);
    for i in 0..left_f32.len() {
        interleaved.push(left_f32[i]);
        interleaved.push(right_f32[i]);
    }
    
    let sample_rate = reverb.format().sample_rate_hz() as f32;
    let format = stereo_format(sample_rate);
    let mut buffer = AudioBuffer::<BUFFER_SIZE>::from_interleaved(&interleaved, format)
        .ok_or(Error::RaiseAtom("buffer_creation_failed"))?;
    
    reverb.process(&mut buffer)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("reverb_error: {}", e))))?;
    
    let processed = buffer.to_interleaved();
    let mut left_out = Vec::with_capacity(processed.len() / 2);
    let mut right_out = Vec::with_capacity(processed.len() / 2);
    
    for chunk in processed.chunks_exact(2) {
        left_out.push(chunk[0]);
        right_out.push(chunk[1]);
    }
    
    Ok((f32_to_binary(env, &left_out)?, f32_to_binary(env, &right_out)?))
}

// ============================================================================
// ЭКВАЛАЙЗЕР
// ============================================================================

#[nif]
fn create_eq<'a>(env: Env<'a>, config_json: String, sample_rate: f32, preamp_gain: f32) -> NifResult<Binary<'a>> {
    let eq_bands: Vec<EQBand> = serde_json::from_str(&config_json)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("config_error: {}", e))))?;
    
    let format = AudioFormat {
        sample_rate: SampleRate::Custom(sample_rate as u32),
        channels: 1,
        bit_depth: 32,
        floating_point: true,
        channel_layout: ChannelLayout::Mono,
        little_endian: true,
        planar: false,
    };
    
    let eq = ParametricEQ::<BUFFER_SIZE>::new(eq_bands, format, preamp_gain);
    let data = encode_effect(&eq)?;
    to_binary(env, &data)
}

#[nif]
fn eq_get_response(eq_data: Binary, frequencies: Vec<f32>) -> NifResult<Vec<f32>> {
    if frequencies.is_empty() {
        return Ok(Vec::new());
    }
    
    let eq: ParametricEQ<BUFFER_SIZE> = decode_effect(eq_data.as_slice())?;
    Ok(eq.get_frequency_response(&frequencies))
}

// ============================================================================
// PITCH SHIFT
// ============================================================================

#[nif]
fn create_pitch_shift<'a>(env: Env<'a>, config_json: String, sample_rate: f32) -> NifResult<Binary<'a>> {
    let config: PitchShiftConfig = serde_json::from_str(&config_json)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("config_error: {}", e))))?;
    
    let pitch_shift = PitchShift::<BUFFER_SIZE>::new(config, stereo_format(sample_rate));
    let data = encode_effect(&pitch_shift)?;
    to_binary(env, &data)
}

#[nif]
fn process_pitch_shift<'a>(env: Env<'a>, ps_data: Binary<'a>, audio_data: Binary<'a>) -> NifResult<Binary<'a>> {
    let mut ps: PitchShift<BUFFER_SIZE> = decode_effect(ps_data.as_slice())?;
    let audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        return f32_to_binary(env, &[]);
    }
    
    let format = ps.format().clone();
    let mut buffer = AudioBuffer::<BUFFER_SIZE>::from_interleaved(&audio_f32, format)
        .ok_or(Error::RaiseAtom("buffer_error"))?;
    
    ps.process(&mut buffer)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("process_error: {}", e))))?;
    
    f32_to_binary(env, &buffer.to_interleaved())
}

// ============================================================================
// EFFECT CHAIN
// ============================================================================

#[nif]
fn create_effect_chain<'a>(
    env: Env<'a>,
    config_json: String,
    sample_rate: u32,
    channels: u8,
) -> NifResult<Binary<'a>> {
    let effect_configs: Vec<EffectConfig<BUFFER_SIZE>> = serde_json::from_str(&config_json)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("config_parse_error: {}", e))))?;

    let channel_layout = match channels {
        1 => ChannelLayout::Mono,
        2 => ChannelLayout::Stereo,
        3 => ChannelLayout::Quad,
        4 => ChannelLayout::Surround50,
        5 => ChannelLayout::Surround51,
        6 => ChannelLayout::Surround61,
        7 => ChannelLayout::Surround71,
        _ => ChannelLayout::Custom(format!("{}-channel", channels)),
    };

    let format = AudioFormat {
        sample_rate: SampleRate::Custom(sample_rate),
        channels,
        bit_depth: 32,
        floating_point: true,
        channel_layout,
        little_endian: true,
        planar: false,
    };

    let chain = EffectChain::<BUFFER_SIZE>::new(effect_configs, format)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("chain_create_error: {}", e))))?;

    let chain_data = encode_effect(&chain)?;
    to_binary(env, &chain_data)
}

#[nif]
fn apply_effect_chain<'a>(env: Env<'a>, chain_data: Binary<'a>, audio_data: Binary<'a>) -> NifResult<Binary<'a>> {
    let mut chain: EffectChain<BUFFER_SIZE> = decode_effect(chain_data.as_slice())?;
    let audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        return f32_to_binary(env, &[]);
    }
    
    let format = chain.format().clone();
    let mut buffer = AudioBuffer::from_slice(&audio_f32, format)
        .ok_or(Error::RaiseAtom("buffer_error"))?;
    
    chain.process(&mut buffer)
        .map_err(|e| Error::RaiseTerm(Box::new(format!("processing_error: {}", e))))?;
    
    f32_to_binary(env, &buffer.to_interleaved())
}

// ============================================================================
// DSP UTILITIES
// ============================================================================

#[nif]
fn normalize_audio<'a>(env: Env<'a>, audio_data: Binary<'a>, target_peak: f32) -> NifResult<Binary<'a>> {
    let mut audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        return f32_to_binary(env, &[]);
    }
    
    dsp_utils::normalize_peak(&mut audio_f32, target_peak);
    f32_to_binary(env, &audio_f32)
}

#[nif]
fn calculate_rms(audio_data: Binary) -> NifResult<f32> {
    let audio_f32 = binary_to_f32(&audio_data);
    Ok(dsp_utils::calculate_rms(&audio_f32))
}

#[nif]
fn calculate_peak(audio_data: Binary) -> NifResult<f32> {
    let audio_f32 = binary_to_f32(&audio_data);
    Ok(dsp_utils::calculate_peak(&audio_f32))
}

#[nif]
fn remove_dc_offset<'a>(env: Env<'a>, audio_data: Binary<'a>, sample_rate: f32) -> NifResult<Binary<'a>> {
    let mut audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        return f32_to_binary(env, &[]);
    }
    
    dsp_utils::remove_dc_offset_filter(&mut audio_f32, sample_rate);
    f32_to_binary(env, &audio_f32)
}

#[nif]
fn generate_sine<'a>(
    env: Env<'a>,
    frequency: f32,
    sample_rate: f32,
    duration: f32,
    amplitude: f32,
) -> NifResult<Binary<'a>> {
    let signal = dsp_utils::generate_sine_signal(frequency, sample_rate, duration, amplitude);
    f32_to_binary(env, &signal)
}

#[nif]
fn generate_white_noise<'a>(
    env: Env<'a>,
    duration: f32,
    sample_rate: f32,
    amplitude: f32,
) -> NifResult<Binary<'a>> {
    let samples = (duration * sample_rate) as usize;
    let signal = dsp_utils::generate_white_noise(samples, amplitude);
    f32_to_binary(env, &signal)
}

#[nif]
fn generate_pink_noise<'a>(
    env: Env<'a>,
    duration: f32,
    sample_rate: f32,
    amplitude: f32,
) -> NifResult<Binary<'a>> {
    let samples = (duration * sample_rate) as usize;
    let signal = dsp_utils::generate_pink_noise(samples, amplitude);
    f32_to_binary(env, &signal)
}

#[nif]
fn apply_fade_in<'a>(env: Env<'a>, audio_data: Binary<'a>, fade_samples: usize) -> NifResult<Binary<'a>> {
    let mut audio_f32 = binary_to_f32(&audio_data);
    dsp_utils::apply_fade_in(&mut audio_f32, fade_samples);
    f32_to_binary(env, &audio_f32)
}

#[nif]
fn apply_fade_out<'a>(env: Env<'a>, audio_data: Binary<'a>, fade_samples: usize) -> NifResult<Binary<'a>> {
    let mut audio_f32 = binary_to_f32(&audio_data);
    dsp_utils::apply_fade_out_effect(&mut audio_f32, fade_samples);
    f32_to_binary(env, &audio_f32)
}

#[nif]
fn crossfade<'a>(
    env: Env<'a>,
    audio1: Binary<'a>,
    audio2: Binary<'a>,
    fade_samples: usize,
) -> NifResult<Binary<'a>> {
    let audio1_f32 = binary_to_f32(&audio1);
    let audio2_f32 = binary_to_f32(&audio2);
    let result = dsp_utils::crossfade(&audio1_f32, &audio2_f32, fade_samples);
    f32_to_binary(env, &result)
}

#[nif]
fn db_to_linear(db: f32) -> NifResult<f32> {
    Ok(dsp_utils::db_to_linear(db))
}

#[nif]
fn linear_to_db(linear: f32) -> NifResult<f32> {
    Ok(dsp_utils::linear_to_db(linear))
}

#[nif]
fn midi_to_frequency(note: u8) -> NifResult<f32> {
    Ok(dsp_utils::midi_to_frequency(note))
}

#[nif]
fn frequency_to_midi(freq: f32) -> NifResult<u8> {
    Ok(dsp_utils::frequency_to_midi(freq))
}

// ============================================================================
// AUDIO ANALYSIS
// ============================================================================

#[nif]
fn analyze_spectrum(audio_data: Binary, sample_rate: f32, window_size: usize) -> NifResult<String> {
    let audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        let empty_result = serde_json::json!({
            "spectrum": Vec::<f32>::new(),
            "centroid_hz": 0.0,
            "flatness": 0.0,
            "rolloff_hz": 0.0,
            "frames": 0
        });
        return Ok(empty_result.to_string());
    }
    
    let analyzer = SpectralAnalyzer::<1024>::new(window_size, window_size / 2);
    let spectra = analyzer.analyze(&audio_f32);
    
    if spectra.is_empty() {
        let empty_result = serde_json::json!({
            "spectrum": vec![0.0; window_size / 2 + 1],
            "centroid_hz": 0.0,
            "flatness": 0.0,
            "rolloff_hz": 0.0,
            "frames": 0
        });
        return Ok(empty_result.to_string());
    }
    
    let mut avg_spectrum = vec![0.0; window_size / 2 + 1];
    for spectrum in &spectra {
        for (i, &mag) in spectrum.iter().enumerate() {
            if i < avg_spectrum.len() {
                avg_spectrum[i] += mag;
            }
        }
    }
    
    for mag in &mut avg_spectrum {
        *mag /= spectra.len() as f32;
    }
    
    let result = serde_json::json!({
        "spectrum": avg_spectrum,
        "centroid_hz": dsp_utils::spectral_centroid(&avg_spectrum, sample_rate),
        "flatness": dsp_utils::spectral_flatness(&avg_spectrum),
        "rolloff_hz": dsp_utils::spectral_rolloff(&avg_spectrum, sample_rate, 0.85),
        "frames": spectra.len()
    });
    
    Ok(result.to_string())
}

#[nif]
fn detect_pitch(audio_data: Binary, sample_rate: f32, min_freq: f32, max_freq: f32) -> NifResult<Option<f32>> {
    let audio_f32 = binary_to_f32(&audio_data);
    
    if audio_f32.is_empty() {
        return Ok(None);
    }
    
    Ok(dsp_utils::yin_pitch_detection(&audio_f32, sample_rate, min_freq, max_freq))
}

rustler::init!("Elixir.MusicCore.AudioEffects.Native.DSP");
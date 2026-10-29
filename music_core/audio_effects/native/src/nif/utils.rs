pub use crate::audio::{AudioFormat, SampleRate, ChannelLayout};
pub use crate::nif::cache::{ProcessorCache, PROCESSOR_CACHE};
pub use bincode::{decode_from_slice, encode_to_vec, Decode, Encode};
pub use rustler::{Binary, Env, Error, NifResult, OwnedBinary};

pub fn binary_to_f32(bin: &Binary) -> Vec<f32> {
    let slice = bin.as_slice();
    let mut result = Vec::with_capacity(slice.len() / 4);
    
    for chunk in slice.chunks(4) {
        if chunk.len() == 4 {
            result.push(f32::from_le_bytes([chunk[0], chunk[1], chunk[2], chunk[3]]));
        }
    }
    result
}

pub fn f32_to_binary<'a>(env: Env<'a>, data: &[f32]) -> NifResult<Binary<'a>> {
    if data.is_empty() {
        let bin = OwnedBinary::new(0).ok_or(Error::RaiseAtom("alloc_failed"))?;
        return Ok(bin.release(env));
    }
    
    let byte_len = data.len() * 4;
    let mut bin = OwnedBinary::new(byte_len).ok_or(Error::RaiseAtom("alloc_failed"))?;
    
    unsafe {
        std::ptr::copy_nonoverlapping(
            data.as_ptr() as *const u8,
            bin.as_mut_ptr(),
            byte_len,
        );
    }
    
    Ok(bin.release(env))
}

pub fn stereo_format(sample_rate: f32) -> AudioFormat {
    AudioFormat {
        sample_rate: SampleRate::Custom(sample_rate as u32),
        channels: 2,
        bit_depth: 32,
        floating_point: true,
        channel_layout: ChannelLayout::Stereo,
        little_endian: true,
        planar: false,
    }
}

pub fn get_cache() -> Result<std::sync::MutexGuard<'static, ProcessorCache<1024>>, Error> {
    PROCESSOR_CACHE.lock().map_err(|_| Error::RaiseAtom("cache_lock_poisoned"))
}

pub fn encode_effect<T: serde::Serialize + Encode>(effect: &T) -> NifResult<Vec<u8>> {
    encode_to_vec(effect, bincode::config::standard())
        .map_err(|e| Error::RaiseTerm(Box::new(format!("encode_error: {}", e))))
}

pub fn decode_effect<T: serde::de::DeserializeOwned + Decode<()>>(data: &[u8]) -> NifResult<T> {
    decode_from_slice(data, bincode::config::standard())
        .map_err(|e| Error::RaiseTerm(Box::new(format!("decode_error: {}", e))))
        .map(|(val, _)| val)
}

pub fn to_binary<'a>(env: Env<'a>, data: &[u8]) -> NifResult<Binary<'a>> {
    let mut bin = OwnedBinary::new(data.len()).ok_or(Error::RaiseAtom("alloc_failed"))?;
    bin.as_mut_slice().copy_from_slice(data);
    Ok(bin.release(env))
}
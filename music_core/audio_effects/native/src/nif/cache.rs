//! Elixir NIF (Native Implemented Function) interface
//! Connects Rust audio processing with Elixir code

use crate::audio::{AudioProcessor, SampleRate, AudioFormat, ChannelLayout};
use crate::effects::reverb::{Reverb, ReverbConfig};
use crate::dsp::compressor::CompressorMetrics;
use bincode::{decode_from_slice, encode_to_vec};
use rustler::{Binary, Env, Error, NifResult, OwnedBinary};
use std::collections::HashMap;
use std::sync::{Arc, Mutex};
use std::sync::LazyLock;

// Elixir atoms
rustler::atoms! {
    ok,
    error,
    invalid_parameters,
    buffer_too_small,
    stream_closed
}

// ============================================================================
// ГЛОБАЛЬНЫЙ КЭШ ПРОЦЕССОРОВ
// ============================================================================

pub struct ProcessorCache<const N: usize> {
    processors: HashMap<u64, Arc<Mutex<AudioProcessor<N>>>>,
    next_id: u64,
}

impl<const N: usize> Default for ProcessorCache<N> {
    fn default() -> Self {
        Self::new()
    }
}

impl<const N: usize> ProcessorCache<N> {
    pub fn new() -> Self {
        Self {
            processors: HashMap::new(),
            next_id: 0,
        }
    }

    pub fn add(&mut self, processor: AudioProcessor<N>) -> u64 {
        self.next_id += 1;
        let id = self.next_id;
        self.processors.insert(id, Arc::new(Mutex::new(processor)));
        id
    }

    pub fn get(&self, id: u64) -> Option<Arc<Mutex<AudioProcessor<N>>>> {
        self.processors.get(&id).cloned()
    }

    pub fn remove(&mut self, id: u64) -> bool {
        self.processors.remove(&id).is_some()
    }
    
    pub fn clear(&mut self) {
        self.processors.clear();
        self.next_id = 0;
    }
}

pub static PROCESSOR_CACHE: LazyLock<Mutex<ProcessorCache<1024>>> = LazyLock::new(|| Mutex::new(ProcessorCache::new()));
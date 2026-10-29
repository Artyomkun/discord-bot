// backend.rs — FFI + RAII для libdsp

use std::ffi::c_float;

// ============================================================================
// C FFI
// ============================================================================

extern "C" {
    fn dsp_gpu_init();
    
    fn cuda_available() -> i32;
    fn rock_available() -> i32;
    fn zluda_available() -> i32;
    
    fn cuda_distortion(input: *const c_float, n: i32, drive: c_float, threshold: c_float, gain: c_float) -> *mut c_float;
    fn rock_distortion(input: *const c_float, n: i32, drive: c_float, threshold: c_float, gain: c_float) -> *mut c_float;
    fn zluda_distortion(input: *const c_float, n: i32, drive: c_float, threshold: c_float, gain: c_float) -> *mut c_float;
    fn cpu_distortion(input: *const c_float, n: i32, drive: c_float, threshold: c_float, gain: c_float) -> *mut c_float;
    
    fn cuda_lpf(input: *const c_float, n: i32, cutoff: c_float, sample_rate: c_float) -> *mut c_float;
    fn rock_lpf(input: *const c_float, n: i32, cutoff: c_float, sample_rate: c_float) -> *mut c_float;
    fn cpu_lpf(input: *const c_float, n: i32, cutoff: c_float, sample_rate: c_float) -> *mut c_float;
    
    fn cuda_reverb(input: *const c_float, n: i32, ir: *const c_float, ir_len: i32, wet: c_float, dry: c_float) -> *mut c_float;
    fn rock_reverb(input: *const c_float, n: i32, ir: *const c_float, ir_len: i32, wet: c_float, dry: c_float) -> *mut c_float;
    fn cpu_reverb(input: *const c_float, n: i32, ir: *const c_float, ir_len: i32, wet: c_float, dry: c_float) -> *mut c_float;
    
    fn cuda_chorus(input: *const c_float, n: i32, rate: c_float, depth: c_float, wet: c_float, dry: c_float, sample_rate: c_float) -> *mut c_float;
    fn rock_chorus(input: *const c_float, n: i32, rate: c_float, depth: c_float, wet: c_float, dry: c_float, sample_rate: c_float) -> *mut c_float;
    fn cpu_chorus(input: *const c_float, n: i32, rate: c_float, depth: c_float, wet: c_float, dry: c_float, sample_rate: c_float) -> *mut c_float;
    
    fn dsp_free_buffer(ptr: *mut c_float);
}

// ============================================================================
// RAII C-Array
// ============================================================================

pub struct CArray {
    ptr: *mut f32,
    len: usize,
}

impl CArray {
    pub unsafe fn new(ptr: *mut f32, len: usize) -> Self {
        Self { ptr, len }
    }
    
    pub fn as_slice(&self) -> &[f32] {
        unsafe { std::slice::from_raw_parts(self.ptr, self.len) }
    }
    
    pub fn to_vec(mut self) -> Vec<f32> {
        let v = self.as_slice().to_vec();
        self.ptr = std::ptr::null_mut();
        v
    }
}

impl Drop for CArray {
    fn drop(&mut self) {
        if !self.ptr.is_null() {
            unsafe { dsp_free_buffer(self.ptr); }
        }
    }
}

// ============================================================================
// GPU Backend
// ============================================================================

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum GpuBackend {
    Cpu,
    Cuda,
    Rock,
    Zluda,
}

pub struct DspBackend {
    pub backend: GpuBackend,
}

impl DspBackend {
    pub fn new() -> Self {
        let backend = unsafe {
            dsp_gpu_init();
            if cuda_available() == 1 { GpuBackend::Cuda }
            else if rock_available() == 1 { GpuBackend::Rock }
            else if zluda_available() == 1 { GpuBackend::Zluda }
            else { GpuBackend::Cpu }
        };
        Self { backend }
    }
    
    pub fn process_distortion(&self, input: &[f32], drive: f32, threshold: f32, gain: f32) -> CArray {
        let n = input.len();
        let ptr = unsafe {
            match self.backend {
                GpuBackend::Cuda  => cuda_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                GpuBackend::Rock  => rock_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                GpuBackend::Zluda => zluda_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                _                 => cpu_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
            }
        };
        unsafe { CArray::new(ptr, n) }
    }
    
    pub fn process_lpf(&self, input: &[f32], cutoff: f32, sample_rate: f32) -> CArray {
        let n = input.len();
        let ptr = unsafe {
            match self.backend {
                GpuBackend::Cuda => cuda_lpf(input.as_ptr(), n as i32, cutoff, sample_rate),
                GpuBackend::Rock => rock_lpf(input.as_ptr(), n as i32, cutoff, sample_rate),
                _                => cpu_lpf(input.as_ptr(), n as i32, cutoff, sample_rate),
            }
        };
        unsafe { CArray::new(ptr, n) }
    }
    
    pub fn process_reverb(&self, input: &[f32], ir: &[f32], wet: f32, dry: f32) -> CArray {
        let n = input.len();
        let ptr = unsafe {
            match self.backend {
                GpuBackend::Cuda => cuda_reverb(input.as_ptr(), n as i32, ir.as_ptr(), ir.len() as i32, wet, dry),
                GpuBackend::Rock => rock_reverb(input.as_ptr(), n as i32, ir.as_ptr(), ir.len() as i32, wet, dry),
                _                => cpu_reverb(input.as_ptr(), n as i32, ir.as_ptr(), ir.len() as i32, wet, dry),
            }
        };
        unsafe { CArray::new(ptr, n) }
    }
    
    pub fn process_chorus(&self, input: &[f32], rate: f32, depth: f32, wet: f32, dry: f32, sample_rate: f32) -> CArray {
        let n = input.len();
        let ptr = unsafe {
            match self.backend {
                GpuBackend::Cuda => cuda_chorus(input.as_ptr(), n as i32, rate, depth, wet, dry, sample_rate),
                GpuBackend::Rock => rock_chorus(input.as_ptr(), n as i32, rate, depth, wet, dry, sample_rate),
                _                => cpu_chorus(input.as_ptr(), n as i32, rate, depth, wet, dry, sample_rate),
            }
        };
        unsafe { CArray::new(ptr, n) }
    }
}
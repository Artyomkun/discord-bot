// frontend.rs — Rust-интерфейс для Elixir NIF + GPU-диспетчер

use crate::c_bindings::*;

pub enum GpuBackend {
    Cpu,
    Cuda,
    Rock,
    Zluda,
}

pub struct DspFrontend {
    backend: GpuBackend,
}

impl DspFrontend {
    pub fn new() -> Self {
        // Авто-детект при инициализации
        let backend = unsafe {
            dsp_gpu_init();
            if cuda_available() == 1 { GpuBackend::Cuda }
            else if rock_available() == 1 { GpuBackend::Rock }
            else if zluda_available() == 1 { GpuBackend::Zluda }
            else { GpuBackend::Cpu }
        };
        Self { backend }
    }
    
    pub fn process_distortion(&self, input: &[f32], drive: f32, threshold: f32, gain: f32) -> Vec<f32> {
        let n = input.len();
        if n == 0 { return vec![]; }
        
        let result = unsafe {
            let ptr = match self.backend {
                GpuBackend::Cuda => cuda_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                GpuBackend::Rock => rock_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                GpuBackend::Zluda => zluda_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
                _ => cpu_distortion(input.as_ptr(), n as i32, drive, threshold, gain),
            };
            if ptr.is_null() {
                return vec![0.0; n];
            }
            Vec::from_raw_parts(ptr as *mut f32, n, n)
        };
        result
    }
}
#include "../../common/include/dsp_config.h"
#include "../../common/include/dsp_errors.h"
#include "../../common/include/dsp_logging.h"
#include "../include/dsp_cuda.cuh"
#include <cuda_runtime.h>
#include <stdlib.h>
#include <math.h>

#ifdef CUDA_SUPPORT
    // ============================================================================
    // CUDA KERNELS
    // ============================================================================

    __global__ void distortion_kernel(const float *input, float *output, int n, float drive, float threshold, float gain) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx >= n) return;

        float driven = input[idx] * drive;
        float sign = (driven > 0.0f) ? 1.0f : -1.0f;
        float abs_input = fabsf(driven);

        if (abs_input < threshold) {
            output[idx] = driven * gain;
        } else {
            float overshoot = abs_input - threshold;
            float range = 1.0f - threshold;
            if (range < 0.001f) range = 0.001f;
            float clipped = threshold + range * tanhf(overshoot / range);
            output[idx] = sign * clipped * gain;
        }
    }

    __global__ void lpf_kernel(const float *input, float *output, int n, float b0, float a1, float *prev_out){
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx >= n) return;

        float out = b0 * input[idx] + a1 * prev_out[idx];
        output[idx] = out;
        prev_out[idx] = out;
    }

    __global__ void reverb_kernel(const float *input, float *output, int n, const float *ir, int ir_len, float wet, float dry) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx >= n) return;

        float sum = 0.0f;
        int start = (idx - ir_len + 1 > 0) ? idx - ir_len + 1 : 0;
        for (int j = start; j <= idx; j++) {
            sum += input[j] * ir[idx - j];
        }
        output[idx] = input[idx] * dry + sum * wet;
    }

    __global__ void chorus_kernel(const float *input, float *output, int n, float rate, float depth, float phase_offset, float wet, float dry, float sample_rate) {
        int idx = blockIdx.x * blockDim.x + threadIdx.x;
        if (idx >= n) return;

        float phase = phase_offset + (float)idx / sample_rate * rate;
        phase = fmodf(phase, 1.0f);
        float mod = sinf(phase * 2.0f * M_PI) * depth;
        int delay_samples = (int)(DSP_CHORUS_BASE_DELAY * sample_rate + mod * sample_rate * 0.01f);
        float delayed = (idx >= delay_samples) ? input[idx - delay_samples] : 0.0f;
        output[idx] = input[idx] * dry + delayed * wet;
    }

    // ============================================================================
    // PUBLIC GPU FUNCTIONS
    // ============================================================================

    cudaError_t process_distortion_gpu(const float *d_input, float *d_output, int n, float drive, float threshold, float gain) {
        int block_size = DSP_CUDA_DEFAULT_BLOCK_SIZE;
        int grid_size = (n + block_size - 1) / block_size;
        distortion_kernel<<<grid_size, block_size>>>(d_input, d_output, n, drive, threshold, gain);
        return cudaGetLastError();
    }

    cudaError_t process_lpf_gpu(const float *d_input, float *d_output, int n, float cutoff_freq, float sample_rate) {
        float rc = 1.0f / (cutoff_freq * 2.0f * M_PI);
        float dt = 1.0f / sample_rate;
        float alpha = dt / (rc + dt);
        float b0 = alpha;
        float a1 = 1.0f - alpha;

        float *d_prev_out;
        cudaError_t err = cudaMalloc(&d_prev_out, n * sizeof(float));
        if (err != cudaSuccess) return err;
        err = cudaMemset(d_prev_out, 0, n * sizeof(float));
        if (err != cudaSuccess) {
            cudaFree(d_prev_out);
            return err;
        }

        int block_size = DSP_CUDA_DEFAULT_BLOCK_SIZE;
        int grid_size = (n + block_size - 1) / block_size;
        lpf_kernel<<<grid_size, block_size>>>(d_input, d_output, n, b0, a1, d_prev_out);

        cudaFree(d_prev_out);
        return cudaGetLastError();
    }

    cudaError_t process_reverb_gpu(const float *d_input, float *d_output, int n, const float *d_ir, int ir_len, float wet, float dry) {
        int block_size = DSP_CUDA_DEFAULT_BLOCK_SIZE;
        int grid_size = (n + block_size - 1) / block_size;
        reverb_kernel<<<grid_size, block_size>>>(d_input, d_output, n, d_ir, ir_len, wet, dry);
        return cudaGetLastError();
    }

    cudaError_t process_chorus_gpu(const float *d_input, float *d_output, int n, float sample_rate, float rate, float depth, float wet, float dry) {
        int block_size = DSP_CUDA_DEFAULT_BLOCK_SIZE;
        int grid_size = (n + block_size - 1) / block_size;
        chorus_kernel<<<grid_size, block_size>>>(d_input, d_output, n, rate, depth, 0.0f, wet, dry, sample_rate);
        return cudaGetLastError();
    }

    // ============================================================================
    // BATCH GPU FUNCTIONS (with memory management)
    // ============================================================================

    dsp_error_t distortion_process_batch_gpu(const float *input, int n, float drive, float threshold, float gain, float **output) {
        if (input == NULL || output == NULL || n <= 0) {
            DSP_LOG_ERROR("Invalid parameters for distortion_process_batch_gpu");
            return DSP_ERROR_INVALID_PARAM;
        }

        int device_count;
        cudaError_t cuda_err = cudaGetDeviceCount(&device_count);
        if (cuda_err != cudaSuccess || device_count == 0) {
            DSP_LOG_WARN("CUDA not available, falling back to CPU: %s", cudaGetErrorString(cuda_err));
            return distortion_process_batch_cpu(input, n, drive, threshold, gain, output);
        }

        *output = (float *)malloc(n * sizeof(float));
        if (*output == NULL) {
            DSP_LOG_ERROR("Failed to allocate output memory");
            return DSP_ERROR_MEMORY;
        }

        // Allocate device memory
        float *d_input, *d_output;
        cuda_err = cudaMalloc(&d_input, n * sizeof(float));
        if (cuda_err != cudaSuccess) {
            DSP_LOG_ERROR("Failed to allocate device input: %s", cudaGetErrorString(cuda_err));
            free(*output);
            return DSP_ERROR_CUDA;
        }

        cuda_err = cudaMalloc(&d_output, n * sizeof(float));
        if (cuda_err != cudaSuccess) {
            DSP_LOG_ERROR("Failed to allocate device output: %s", cudaGetErrorString(cuda_err));
            cudaFree(d_input);
            free(*output);
            return DSP_ERROR_CUDA;
        }

        // Copy input to device
        cuda_err = cudaMemcpy(d_input, input, n * sizeof(float), cudaMemcpyHostToDevice);
        if (cuda_err != cudaSuccess) {
            DSP_LOG_ERROR("Failed to copy input to device: %s", cudaGetErrorString(cuda_err));
            cudaFree(d_input);
            cudaFree(d_output);
            free(*output);
            return DSP_ERROR_CUDA;
        }

        // Launch kernel
        cuda_err = process_distortion_gpu(d_input, d_output, n, drive, threshold, gain);
        if (cuda_err != cudaSuccess) {
            DSP_LOG_ERROR("CUDA kernel error: %s", cudaGetErrorString(cuda_err));
            cudaFree(d_input);
            cudaFree(d_output);
            free(*output);
            return DSP_ERROR_CUDA;
        }

        // Copy result back
        cuda_err = cudaMemcpy(*output, d_output, n * sizeof(float), cudaMemcpyDeviceToHost);
        if (cuda_err != cudaSuccess) {
            DSP_LOG_ERROR("Failed to copy result from device: %s", cudaGetErrorString(cuda_err));
            cudaFree(d_input);
            cudaFree(d_output);
            free(*output);
            return DSP_ERROR_CUDA;
        }

        cudaFree(d_input);
        cudaFree(d_output);

        DSP_LOG_DEBUG("GPU distortion processing completed for %d samples", n);
        return DSP_SUCCESS;
    }

    dsp_error_t lpf_process_batch_gpu(const float *input, int n, float cutoff_freq, float sample_rate, float **output) {
        // LPF is recursive - not efficient on GPU
        DSP_LOG_WARN("LPF not efficient on GPU, using CPU fallback");
        return lpf_process_batch_cpu(input, n, cutoff_freq, sample_rate, output);
    }

    dsp_error_t reverb_process_batch_gpu(const float *input, int n, const float *ir, int ir_len, float wet, float dry, float **output) {
        DSP_LOG_INFO("Reverb GPU processing with convolution (O(n * ir_len))");
        // For production, consider FFT-based convolution for longer IR
        
        if (input == NULL || output == NULL || n <= 0 || ir == NULL || ir_len <= 0) {
            DSP_LOG_ERROR("Invalid parameters for reverb_process_batch_gpu");
            return DSP_ERROR_INVALID_PARAM;
        }

        int device_count;
        cudaError_t cuda_err = cudaGetDeviceCount(&device_count);
        if (cuda_err != cudaSuccess || device_count == 0) {
            DSP_LOG_WARN("CUDA not available, falling back to CPU");
            return reverb_process_batch_cpu(input, n, ir, ir_len, wet, dry, output);
        }

        *output = (float *)malloc(n * sizeof(float));
        if (*output == NULL) {
            DSP_LOG_ERROR("Failed to allocate output memory");
            return DSP_ERROR_MEMORY;
        }

        // Allocate device memory
        float *d_input, *d_output, *d_ir;
        cuda_err = cudaMalloc(&d_input, n * sizeof(float));
        if (cuda_err != cudaSuccess) goto cleanup;
        cuda_err = cudaMalloc(&d_output, n * sizeof(float));
        if (cuda_err != cudaSuccess) goto cleanup;
        cuda_err = cudaMalloc(&d_ir, ir_len * sizeof(float));
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = cudaMemcpy(d_input, input, n * sizeof(float), cudaMemcpyHostToDevice);
        if (cuda_err != cudaSuccess) goto cleanup;
        cuda_err = cudaMemcpy(d_ir, ir, ir_len * sizeof(float), cudaMemcpyHostToDevice);
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = process_reverb_gpu(d_input, d_output, n, d_ir, ir_len, wet, dry);
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = cudaMemcpy(*output, d_output, n * sizeof(float), cudaMemcpyDeviceToHost);
        if (cuda_err != cudaSuccess) goto cleanup;

        cudaFree(d_input);
        cudaFree(d_output);
        cudaFree(d_ir);
        return DSP_SUCCESS;

        cleanup:
            if (d_input) cudaFree(d_input);
            if (d_output) cudaFree(d_output);
            if (d_ir) cudaFree(d_ir);
            free(*output);
            DSP_LOG_ERROR("CUDA error in reverb: %s", cudaGetErrorString(cuda_err));
            return DSP_ERROR_CUDA;
    }

    dsp_error_t chorus_process_batch_gpu(const float *input, int n, float sample_rate, float rate, float depth, float wet, float dry, float **output) {
        if (input == NULL || output == NULL || n <= 0) {
            DSP_LOG_ERROR("Invalid parameters for chorus_process_batch_gpu");
            return DSP_ERROR_INVALID_PARAM;
        }

        int device_count;
        cudaError_t cuda_err = cudaGetDeviceCount(&device_count);
        if (cuda_err != cudaSuccess || device_count == 0) {
            DSP_LOG_WARN("CUDA not available, falling back to CPU");
            return chorus_process_batch_cpu(input, n, sample_rate, rate, depth, wet, dry, output);
        }

        *output = (float *)malloc(n * sizeof(float));
        if (*output == NULL) {
            DSP_LOG_ERROR("Failed to allocate output memory");
            return DSP_ERROR_MEMORY;
        }

        float *d_input, *d_output;
        cuda_err = cudaMalloc(&d_input, n * sizeof(float));
        if (cuda_err != cudaSuccess) goto cleanup;
        cuda_err = cudaMalloc(&d_output, n * sizeof(float));
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = cudaMemcpy(d_input, input, n * sizeof(float), cudaMemcpyHostToDevice);
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = process_chorus_gpu(d_input, d_output, n, sample_rate, rate, depth, wet, dry);
        if (cuda_err != cudaSuccess) goto cleanup;

        cuda_err = cudaMemcpy(*output, d_output, n * sizeof(float), cudaMemcpyDeviceToHost);
        if (cuda_err != cudaSuccess) goto cleanup;

        cudaFree(d_input);
        cudaFree(d_output);
        return DSP_SUCCESS;

        cleanup:
            if (d_input) cudaFree(d_input);
            if (d_output) cudaFree(d_output);
            free(*output);
            DSP_LOG_ERROR("CUDA error in chorus: %s", cudaGetErrorString(cuda_err));
            return DSP_ERROR_CUDA;
    }
#endif // CUDA_SUPPORT
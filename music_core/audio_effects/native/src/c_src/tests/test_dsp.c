#include "../include/dsp.h"
#include "../common/include/dsp_config.h"
#include "../common/include/dsp_logging.h"
#include <assert.h>
#include <stdio.h>
#include <math.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifndef M_PI
    #define M_PI 3.14159265358979323846
#endif

// ============================================================================
// UTILITY FUNCTIONS
// ============================================================================

static int float_eq(float a, float b, float epsilon) {
    return fabs(a - b) < epsilon;
}

static void generate_sine(float *buffer, int n, float freq, float sample_rate) {
    for (int i = 0; i < n; i++) {
        buffer[i] = sinf(2.0f * M_PI * freq * i / sample_rate);
    }
}

// ============================================================================
// DELAY TESTS
// ============================================================================

void test_delay() {
    printf("\n=== Testing Delay ===\n");
    
    DelayBuffer delay;
    delay_init(&delay, 100, 0.5, 0.3, 0.7);
    assert(delay.buffer != NULL);
    assert(delay.size == 100);
    assert(delay.write_pos == 0);
    assert(float_eq(delay.feedback, 0.5f, 0.001f));
    assert(float_eq(delay.wet, 0.3f, 0.001f));
    assert(float_eq(delay.dry, 0.7f, 0.001f));

    // Test first sample (buffer empty)
    float input = 1.0f;
    float output = delay_process(&delay, input);
    assert(float_eq(output, 0.7f, 0.001f)); // dry only

    // Fill buffer
    for (int i = 0; i < 100; i++) {
        output = delay_process(&delay, 0.0f);
    }
    
    // Now should have feedback
    output = delay_process(&delay, 0.0f);
    assert(fabs(output) < 0.01f);
    
    // Test with zero size (should handle gracefully)
    DelayBuffer delay2;
    delay_init(&delay2, 0, 0.5, 0.3, 0.7);
    // delay2.buffer should be NULL due to size=0
    
    delay_free(&delay);
    delay_free(&delay2);
    
    printf("✓ Delay test passed\n");
}

// ============================================================================
// LOW-PASS FILTER TESTS
// ============================================================================

void test_lpf() {
    printf("\n=== Testing Low-Pass Filter ===\n");
    
    LowPassFilter filter;
    lpf_init(&filter, 1000.0f, 44100.0f);
    assert(float_eq(filter.b0, 0.001f, 0.0001f));
    assert(float_eq(filter.a1, 0.999f, 0.0001f));
    assert(filter.prev_out == 0.0f);

    // Test step response
    float step = lpf_process(&filter, 1.0f);
    assert(step > 0.0f && step < 1.0f);

    // Stabilization
    for (int i = 0; i < 100; i++) {
        step = lpf_process(&filter, 1.0f);
    }
    assert(float_eq(step, 1.0f, 0.01f));

    // Test reset
    lpf_reset(&filter);
    assert(filter.prev_out == 0.0f);
    
    // Test with invalid parameters (should not crash)
    lpf_init(NULL, 1000.0f, 44100.0f);
    lpf_process(NULL, 1.0f);
    lpf_reset(NULL);
    
    printf("✓ Low-Pass Filter test passed\n");
}

// ============================================================================
// DISTORTION TESTS
// ============================================================================

void test_distortion() {
    printf("\n=== Testing Distortion ===\n");
    
    Distortion dist;
    distortion_init(&dist, 2.0f, 0.8f, 0.5f);
    assert(float_eq(dist.drive, 2.0f, 0.001f));
    assert(float_eq(dist.threshold, 0.8f, 0.001f));
    assert(float_eq(dist.gain, 0.5f, 0.001f));

    // Test no clipping (small input)
    float output = distortion_process(&dist, 0.1f);
    assert(float_eq(output, 0.1f, 0.01f));

    // Test with clipping
    output = distortion_process(&dist, 1.0f);
    assert(output <= 0.5f);
    assert(output >= 0.0f);
    
    // Test negative input
    output = distortion_process(&dist, -1.0f);
    assert(output <= 0.0f);
    assert(output >= -0.5f);
    
    // Test with invalid parameters
    distortion_init(NULL, 2.0f, 0.8f, 0.5f);
    output = distortion_process(NULL, 1.0f);
    assert(float_eq(output, 1.0f, 0.001f)); // pass-through
    
    printf("✓ Distortion test passed\n");
}

// ============================================================================
// REVERB TESTS
// ============================================================================

void test_reverb() {
    printf("\n=== Testing Reverb ===\n");
    
    Reverb rev;
    reverb_init(&rev, 44100.0f, 0.5f, 0.3f, 0.7f);
    
    // Check comb buffers are initialized
    assert(rev.comb1.buffer != NULL);
    assert(rev.comb2.buffer != NULL);
    assert(rev.comb3.buffer != NULL);
    assert(rev.comb4.buffer != NULL);
    assert(float_eq(rev.wet, 0.3f, 0.001f));
    assert(float_eq(rev.dry, 0.7f, 0.001f));

    float input = 1.0f;
    float output = reverb_process(&rev, input);
    assert(output > 0.0f);
    assert(output <= 1.0f);
    
    // Test with silence
    output = reverb_process(&rev, 0.0f);
    assert(fabs(output) < 0.01f);

    reverb_free(&rev);
    
    // Test double free (should not crash)
    reverb_free(&rev);
    
    printf("✓ Reverb test passed\n");
}

// ============================================================================
// CHORUS TESTS
// ============================================================================

void test_chorus() {
    printf("\n=== Testing Chorus ===\n");
    
    Chorus chor;
    chorus_init(&chor, 44100.0f, 0.5f, 10.0f, 0.3f, 0.7f);
    
    assert(chor.delay1.buffer != NULL);
    assert(chor.delay2.buffer != NULL);
    assert(float_eq(chor.rate, 0.5f, 0.001f));
    assert(float_eq(chor.depth, 10.0f, 0.001f));
    assert(float_eq(chor.wet, 0.3f, 0.001f));
    assert(float_eq(chor.dry, 0.7f, 0.001f));

    float input = 1.0f;
    float output = chorus_process(&chor, input);
    assert(output > 0.0f);
    assert(output <= 1.0f);

    chorus_free(&chor);
    
    printf("✓ Chorus test passed\n");
}

// ============================================================================
// BATCH PROCESSING TESTS
// ============================================================================

void test_batch_processing() {
    printf("\n=== Testing Batch Processing ===\n");
    
    const int n = 1000;
    float *input = (float *)malloc(n * sizeof(float));
    assert(input != NULL);
    
    generate_sine(input, n, 440.0f, 44100.0f);
    
    // Test distortion batch
    float *output = distortion_process_batch_cpu(input, n, 2.0f, 0.8f, 0.5f);
    assert(output != NULL);
    assert(float_eq(output[0], input[0], 0.1f));
    free(output);
    
    // Test LPF batch
    output = lpf_process_batch_cpu(input, n, 1000.0f, 44100.0f);
    assert(output != NULL);
    free(output);
    
    // Test reverb batch
    float *ir = (float *)malloc(100 * sizeof(float));
    for (int i = 0; i < 100; i++) {
        ir[i] = expf(-i * 0.1f);
    }
    output = reverb_process_batch_cpu(input, n, ir, 100, 0.3f, 0.7f);
    assert(output != NULL);
    free(output);
    free(ir);
    
    // Test chorus batch
    output = chorus_process_batch_cpu(input, n, 44100.0f, 0.5f, 10.0f, 0.3f, 0.7f);
    assert(output != NULL);
    free(output);
    
    free(input);
    printf("✓ Batch processing test passed\n");
}

// ============================================================================
// PERFORMANCE BENCHMARK
// ============================================================================

void benchmark_effects() {
    printf("\n=== Performance Benchmark ===\n");
    
    const int num_samples = 100000;
    float *input = (float *)malloc(num_samples * sizeof(float));
    if (!input) {
        printf("Failed to allocate memory for benchmark\n");
        return;
    }

    generate_sine(input, num_samples, 440.0f, 44100.0f);

    clock_t start, end;
    
    // Benchmark single-sample distortion
    Distortion dist;
    distortion_init(&dist, 2.0f, 0.8f, 0.5f);
    start = clock();
    for (int i = 0; i < num_samples; i++) {
        volatile float out = distortion_process(&dist, input[i]);
        (void)out;
    }
    end = clock();
    printf("  Distortion (per sample): %.2f ms for %d samples\n",
           1000.0 * (end - start) / CLOCKS_PER_SEC, num_samples);

    // Benchmark batch distortion
    float *output;
    start = clock();
    output = distortion_process_batch_cpu(input, num_samples, 2.0f, 0.8f, 0.5f);
    end = clock();
    if (output) {
        printf("  Distortion (batch): %.2f ms for %d samples\n",
               1000.0 * (end - start) / CLOCKS_PER_SEC, num_samples);
        free(output);
    }
    
    // Benchmark LPF
    start = clock();
    output = lpf_process_batch_cpu(input, num_samples, 1000.0f, 44100.0f);
    end = clock();
    if (output) {
        printf("  LPF (batch): %.2f ms for %d samples\n",
               1000.0 * (end - start) / CLOCKS_PER_SEC, num_samples);
        free(output);
    }

    free(input);
    printf("✓ Benchmark completed\n");
}

// ============================================================================
// EDGE CASES TESTS
// ============================================================================

void test_edge_cases() {
    printf("\n=== Testing Edge Cases ===\n");
    
    // Test NULL pointers (should not crash)
    delay_init(NULL, 100, 0.5f, 0.3f, 0.7f);
    delay_free(NULL);
    delay_process(NULL, 1.0f);
    
    lpf_init(NULL, 1000.0f, 44100.0f);
    lpf_process(NULL, 1.0f);
    lpf_reset(NULL);
    
    distortion_init(NULL, 2.0f, 0.8f, 0.5f);
    distortion_process(NULL, 1.0f);
    
    reverb_init(NULL, 44100.0f, 0.5f, 0.3f, 0.7f);
    reverb_free(NULL);
    reverb_process(NULL, 1.0f);
    
    chorus_init(NULL, 44100.0f, 0.5f, 10.0f, 0.3f, 0.7f);
    chorus_free(NULL);
    chorus_process(NULL, 1.0f);
    
    // Test zero sample rate
    Reverb rev;
    reverb_init(&rev, 0.0f, 0.5f, 0.3f, 0.7f);
    
    printf("✓ Edge cases test passed\n");
}

// ============================================================================
// MAIN
// ============================================================================

int main() {
    printf("========================================\n");
    printf("     DSP Library Test Suite\n");
    printf("========================================\n");
    
    // Run all tests
    test_delay();
    test_lpf();
    test_distortion();
    test_reverb();
    test_chorus();
    test_batch_processing();
    test_edge_cases();
    benchmark_effects();
    
    printf("\n========================================\n");
    printf("     All tests passed!\n");
    printf("========================================\n");
    
    return 0;
}
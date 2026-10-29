#include "../include/dsp.h"
#include "../common/include/dsp_config.h"
#include <assert.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Fuzzing test for input robustness
void fuzz_test_effects() {
    srand(time(NULL));

    const int num_tests = 1000;
    const int max_samples = 1000;

    for (int test = 0; test < num_tests; test++) {
        int n = rand() % max_samples + 1;
        float *input = (float *)malloc(n * sizeof(float));
        if (!input) continue;

        // Generate random input
        for (int i = 0; i < n; i++) {
            input[i] = ((float)rand() / RAND_MAX - 0.5f) * 4.0f; // Random values -2 to 2
        }

        // Test distortion batch
        float *output = distortion_process_batch_cpu(input, n, 2.0f, 0.8f, 0.5f);
        if (output != NULL) {
            free(output);
        }

        // Test LPF batch
        output = lpf_process_batch_cpu(input, n, 1000.0f, 44100.0f);
        if (output != NULL) {
            free(output);
        }

        // Test reverb batch
        float *ir = (float *)malloc(n * sizeof(float));
        if (ir) {
            for (int i = 0; i < n; i++) ir[i] = expf(-i / 100.0f); // Simple decay IR
            output = reverb_process_batch_cpu(input, n, ir, n, 0.3f, 0.7f);
            if (output != NULL) {
                free(output);
            }
            free(ir);
        }

        // Test chorus batch
        output = chorus_process_batch_cpu(input, n, 44100.0f, 0.5f, 10.0f, 0.3f, 0.7f);
        if (output != NULL) {
            free(output);
        }

        free(input);
    }
    printf("Fuzzing tests passed\n");
}

// Property-based test: output should be bounded
void property_test_bounded_output() {
    const int n = 1000;
    float *input = (float *)malloc(n * sizeof(float));
    assert(input != NULL);

    // Extreme input values
    for (int i = 0; i < n; i++) {
        input[i] = (i % 2 == 0) ? 100.0f : -100.0f; // Alternating extreme values
    }

    float *output = distortion_process_batch_cpu(input, n, 5.0f, 0.5f, 0.1f);
    assert(output != NULL);

    // Check output is bounded
    for (int i = 0; i < n; i++) {
        assert(output[i] >= -1.1f && output[i] <= 1.1f); // Allow some tolerance
    }

    free(output);
    free(input);
    printf("Property-based bounded output test passed\n");
}

// Memory leak test
void memory_leak_test() {
    // This is a simple check - in real scenario use valgrind or similar
    for (int i = 0; i < 100; i++) {
        DelayBuffer delay;
        delay_init(&delay, 1000, 0.5, 0.3, 0.7);

        for (int j = 0; j < 1000; j++) {
            float out = delay_process(&delay, 1.0f);
            (void)out; // suppress unused variable warning
        }

        delay_free(&delay);
    }
    printf("Memory leak test simulation passed\n");
}

// Performance regression test
void performance_regression_test() {
    const int n = 100000;
    float *input = (float *)malloc(n * sizeof(float));
    assert(input != NULL);

    for (int i = 0; i < n; i++) {
        input[i] = sinf(2 * M_PI * 440 * i / 44100.0);
    }

    clock_t start = clock();
    float *output = distortion_process_batch_cpu(input, n, 2.0f, 0.8f, 0.5f);
    clock_t end = clock();

    assert(output != NULL);

    double time_taken = (double)(end - start) / CLOCKS_PER_SEC * 1000; // ms
    printf("Performance test: %.2f ms for %d samples\n", time_taken, n);

    // Assert reasonable performance (adjust threshold as needed)
    assert(time_taken < 500.0); // Should complete in less than 500ms

    free(output);
    free(input);
    printf("Performance regression test passed\n");
}

// Integration test: chain effects
void integration_test_chain_effects() {
    const int n = 1000;
    float *input = (float *)malloc(n * sizeof(float));
    assert(input != NULL);

    for (int i = 0; i < n; i++) {
        input[i] = sinf(2 * M_PI * i / n);
    }

    // Chain: Distortion -> LPF -> Reverb
    float *temp1 = distortion_process_batch_cpu(input, n, 2.0f, 0.8f, 0.5f);
    assert(temp1 != NULL);
    float *temp2 = lpf_process_batch_cpu(temp1, n, 2000.0f, 44100.0f);
    assert(temp2 != NULL);

    float *ir = (float *)malloc(n * sizeof(float));
    for (int i = 0; i < n; i++) ir[i] = expf(-i / 50.0f);
    float *output = reverb_process_batch_cpu(temp2, n, ir, n, 0.2f, 0.8f);
    assert(output != NULL);

    // Verify output is valid
    for (int i = 0; i < n; i++) {
        assert(!isnan(output[i]) && !isinf(output[i]));
    }

    free(input);
    free(temp1);
    free(temp2);
    free(output);
    free(ir);
    printf("Integration chain effects test passed\n");
}

int main() {
    printf("Running extended tests...\n");

    fuzz_test_effects();
    property_test_bounded_output();
    memory_leak_test();
    performance_regression_test();
    integration_test_chain_effects();

    printf("All extended tests passed!\n");
    return 0;
}
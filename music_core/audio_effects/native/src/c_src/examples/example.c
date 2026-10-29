#include "../include/dsp.h"
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// Пример использования C DSP библиотеки

#define SAMPLE_RATE 44100
#define NUM_SAMPLES 1000

int main() {
    // Создаем тестовый сигнал (синусоида)
    float *input = (float *)malloc(NUM_SAMPLES * sizeof(float));
    float *output = (float *)malloc(NUM_SAMPLES * sizeof(float));

    for (int i = 0; i < NUM_SAMPLES; i++) {
        float t = (float)i / SAMPLE_RATE;
        input[i] = 0.5 * sinf(2.0 * M_PI * 440.0 * t); // 440Hz синусоида
    }

    // Пример использования delay
    DelayBuffer delay;
    delay_init(&delay, SAMPLE_RATE / 2, 0.3, 0.2, 0.8); // 500ms delay

    printf("Применяем delay эффект...\n");
    for (int i = 0; i < NUM_SAMPLES; i++) {
        output[i] = delay_process(&delay, input[i]);
    }

    delay_free(&delay);

    // Пример использования distortion
    Distortion dist;
    distortion_init(&dist, 1.5, 0.7, 0.8);

    printf("Применяем distortion эффект...\n");
    for (int i = 0; i < NUM_SAMPLES; i++) {
        output[i] = distortion_process(&dist, output[i]);
    }

    // Пример использования reverb
    Reverb rev;
    reverb_init(&rev, SAMPLE_RATE, 0.4, 0.3, 0.7);

    printf("Применяем reverb эффект...\n");
    for (int i = 0; i < NUM_SAMPLES; i++) {
        output[i] = reverb_process(&rev, output[i]);
    }

    reverb_free(&rev);

    // Сохраняем результат (простой вывод первых 10 семплов)
    printf("Первые 10 выходных семплов:\n");
    for (int i = 0; i < 10; i++) {
        printf("%.4f\n", output[i]);
    }

    free(input);
    free(output);

    printf("Пример завершен.\n");
    return 0;
}
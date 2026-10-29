#ifndef DSP_ZLUDA_H
#define DSP_ZLUDA_H

int zluda_available(void);
float* zluda_distortion(float* input, int n, float drive, float threshold, float gain);
float* zluda_lpf(float* input, int n, float cutoff, float sample_rate);
float* zluda_reverb(float* input, int n, float* ir, int ir_len, float wet, float dry);
float* zluda_chorus(float* input, int n, float rate, float depth, float wet, float dry, float sample_rate);

#endif
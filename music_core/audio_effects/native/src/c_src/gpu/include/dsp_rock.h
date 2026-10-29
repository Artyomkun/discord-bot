#ifndef DSP_ROCK_H
#define DSP_ROCK_H

int rock_available(void);
float* rock_distortion(float* input, int n, float drive, float threshold, float gain);
float* rock_lpf(float* input, int n, float cutoff, float sample_rate);
float* rock_reverb(float* input, int n, float* ir, int ir_len, float wet, float dry);
float* rock_chorus(float* input, int n, float rate, float depth, float wet, float dry, float sample_rate);

#endif
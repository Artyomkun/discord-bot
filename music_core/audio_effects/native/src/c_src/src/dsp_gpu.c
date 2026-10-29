#include "dsp.h"
#include "dsp_rock.h"
#include "dsp_zluda.h"

static enum { BACKEND_NONE, BACKEND_CUDA, BACKEND_ROCK, BACKEND_ZLUDA } backend = BACKEND_NONE;

void dsp_gpu_init(void) {
    if (cuda_available()) backend = BACKEND_CUDA;
    else if (rock_available()) backend = BACKEND_ROCK;
    else if (zluda_available()) backend = BACKEND_ZLUDA;
}

float* process_distortion(float* input, int n, float drive, float threshold, float gain) {
    switch(backend) {
        case BACKEND_CUDA:  return cuda_distortion(input, n, drive, threshold, gain);
        case BACKEND_ROCK:  return rock_distortion(input, n, drive, threshold, gain);
        case BACKEND_ZLUDA: return zluda_distortion(input, n, drive, threshold, gain);
        default:            return cpu_distortion(input, n, drive, threshold, gain);
    }
}
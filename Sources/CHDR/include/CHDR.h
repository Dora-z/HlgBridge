#ifndef HLGBRIDGE_CHDR_H
#define HLGBRIDGE_CHDR_H
#include <stddef.h>
#include <stdint.h>
int hlg_encode(const uint16_t *rgba_half, unsigned width, unsigned height,
               const uint8_t *jpeg, size_t jpeg_size, float peak_nits,
               uint8_t **output, size_t *output_size, char *error, size_t error_size);
void hlg_free(void *buffer);
int hlg_verify(const uint8_t *jpeg, size_t size, unsigned *width, unsigned *height,
               float *max_boost, char *error, size_t error_size);
#endif

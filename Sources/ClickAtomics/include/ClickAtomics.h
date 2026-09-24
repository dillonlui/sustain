#ifndef SUSTAIN_CLICK_ATOMICS_H
#define SUSTAIN_CLICK_ATOMICS_H

#include <stdint.h>

void *sustain_atomic_create(int64_t initial);
void sustain_atomic_destroy(void *value);
int64_t sustain_atomic_load(void *value);
void sustain_atomic_store(void *value, int64_t next);
int64_t sustain_atomic_exchange(void *value, int64_t next);
int64_t sustain_atomic_add(void *value, int64_t amount);

#endif

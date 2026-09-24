#include "ClickAtomics.h"
#include <stdatomic.h>
#include <stdlib.h>

typedef struct {
    _Atomic int64_t value;
} SustainAtomicInt;

void *sustain_atomic_create(int64_t initial) {
    SustainAtomicInt *result = malloc(sizeof(SustainAtomicInt));
    if (result != NULL) atomic_init(&result->value, initial);
    return result;
}

void sustain_atomic_destroy(void *value) { free(value); }

int64_t sustain_atomic_load(void *value) {
    return atomic_load_explicit(&((SustainAtomicInt *)value)->value, memory_order_seq_cst);
}

void sustain_atomic_store(void *value, int64_t next) {
    atomic_store_explicit(&((SustainAtomicInt *)value)->value, next, memory_order_seq_cst);
}

int64_t sustain_atomic_exchange(void *value, int64_t next) {
    return atomic_exchange_explicit(&((SustainAtomicInt *)value)->value, next, memory_order_seq_cst);
}

int64_t sustain_atomic_add(void *value, int64_t amount) {
    return atomic_fetch_add_explicit(&((SustainAtomicInt *)value)->value, amount, memory_order_seq_cst);
}

/* lf_map.c — open-addressing hash map from byte strings to indexes (FNV-1a, linear probing). */
#include "lf_pbx.h"

#include <stdlib.h>
#include <string.h>

#define LF_MAP_MIN_CAPACITY 16u
#define FNV_OFFSET 1469598103934665603ULL
#define FNV_PRIME 1099511628211ULL

static uint64_t hash_bytes(const uint8_t *key, size_t length) {
    uint64_t hash = FNV_OFFSET;
    for (size_t i = 0; i < length; i++) {
        hash ^= key[i];
        hash *= FNV_PRIME;
    }
    return hash;
}

static size_t capacity_for(size_t expected) {
    size_t capacity = LF_MAP_MIN_CAPACITY;
    while (capacity / 2 < expected) {
        if (capacity > SIZE_MAX / 4) {
            return 0;
        }
        capacity *= 2;
    }
    return capacity;
}

int lf_map_init(lf_span_map *map, size_t expected) {
    map->count = 0;
    map->capacity = capacity_for(expected);
    map->slots = map->capacity ? calloc(map->capacity, sizeof *map->slots) : NULL;
    if (map->slots == NULL) {
        map->capacity = 0;
        return 0;
    }
    return 1;
}

static lf_map_slot *find_slot(lf_map_slot *slots, size_t capacity, const uint8_t *key, size_t length, uint64_t hash) {
    size_t index = (size_t)hash & (capacity - 1);
    for (;;) {
        lf_map_slot *slot = &slots[index];
        if (!slot->used ||
            (slot->hash == hash && slot->length == length && memcmp(slot->key, key, length) == 0)) {
            return slot;
        }
        index = (index + 1) & (capacity - 1);
    }
}

static int grow(lf_span_map *map) {
    if (map->capacity > SIZE_MAX / 2 / sizeof *map->slots) {
        return 0;
    }
    const size_t capacity = map->capacity * 2;
    lf_map_slot *slots = calloc(capacity, sizeof *slots);
    if (slots == NULL) {
        return 0;
    }
    for (size_t i = 0; i < map->capacity; i++) {
        if (map->slots[i].used) {
            *find_slot(slots, capacity, map->slots[i].key, map->slots[i].length, map->slots[i].hash) = map->slots[i];
        }
    }
    free(map->slots);
    map->slots = slots;
    map->capacity = capacity;
    return 1;
}

int lf_map_put(lf_span_map *map, const uint8_t *key, size_t length, size_t value) {
    if (map->slots == NULL) {
        return LF_MAP_NO_MEMORY;
    }
    if ((map->count + 1) * 2 > map->capacity && !grow(map)) {
        return LF_MAP_NO_MEMORY;
    }
    const uint64_t hash = hash_bytes(key, length);
    lf_map_slot *slot = find_slot(map->slots, map->capacity, key, length, hash);
    if (slot->used) {
        return LF_MAP_EXISTS;
    }
    slot->key = key;
    slot->length = length;
    slot->hash = hash;
    slot->value = value;
    slot->used = 1;
    map->count++;
    return LF_MAP_ADDED;
}

int lf_map_get(const lf_span_map *map, const uint8_t *key, size_t length, size_t *value) {
    if (map->slots == NULL) {
        return 0;
    }
    const lf_map_slot *slot = find_slot(map->slots, map->capacity, key, length, hash_bytes(key, length));
    if (!slot->used) {
        return 0;
    }
    if (value != NULL) {
        *value = slot->value;
    }
    return 1;
}

size_t *lf_map_find(lf_span_map *map, const uint8_t *key, size_t length) {
    if (map->slots == NULL) {
        return NULL;
    }
    lf_map_slot *slot = find_slot(map->slots, map->capacity, key, length, hash_bytes(key, length));
    return slot->used ? &slot->value : NULL;
}

void lf_map_free(lf_span_map *map) {
    free(map->slots);
    map->slots = NULL;
    map->capacity = 0;
    map->count = 0;
}

"use strict";

/* eslint-disable no-bitwise -- integer mixing is the point of this file */

/** mulberry32: small, fast, good enough for picking letters; returns [0, 1). */
export function mulberry32(seed) {
  let a = seed >>> 0;
  return () => {
    a = a + 0x6d2b79f5 >>> 0;
    let t = a;
    t = Math.imul(t ^ t >>> 15, t | 1);
    t ^= t + Math.imul(t ^ t >>> 7, t | 61);
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

/** Folds integers into one 32-bit seed so (seed, revision, cell) each move every bit. */
export function hash(...parts) {
  let h = 0x811c9dc5;
  for (const part of parts) {
    h ^= part | 0;
    h = Math.imul(h, 0x9e3779b1);
    h ^= h >>> 15;
  }
  return h >>> 0;
}
export function pick(rng, items) {
  const item = items[Math.floor(rng() * items.length)];
  if (item === undefined) throw new Error('pick from an empty list');
  return item;
}

/** Fisher–Yates permutation of 0..n-1. */
export function permutation(rng, n) {
  const order = Array.from({
    length: n
  }, (_, i) => i);
  for (let i = n - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    const a = order[i];
    order[i] = order[j];
    order[j] = a;
  }
  return order;
}
//# sourceMappingURL=random.js.map
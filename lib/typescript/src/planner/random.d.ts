export type Rng = () => number;
/** mulberry32: small, fast, good enough for picking letters; returns [0, 1). */
export declare function mulberry32(seed: number): Rng;
/** Folds integers into one 32-bit seed so (seed, revision, cell) each move every bit. */
export declare function hash(...parts: number[]): number;
export declare function pick<T>(rng: Rng, items: readonly T[]): T;
/** Fisher–Yates permutation of 0..n-1. */
export declare function permutation(rng: Rng, n: number): number[];
//# sourceMappingURL=random.d.ts.map
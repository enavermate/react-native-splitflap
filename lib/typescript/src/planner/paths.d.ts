import { type Scripts } from './alphabets.js';
import { type Rng } from './random.js';
import type { Easing, SplitflapTransition } from './types.js';
export type CellPath = {
    path: string[];
    dir: 1 | -1;
};
export type PathContext = {
    scripts: Scripts;
    rng: Rng;
};
export declare function cellPath(transition: SplitflapTransition, from: string, to: string, ctx: PathContext): CellPath;
export declare function durationFor(transition: SplitflapTransition, duration: number): number;
export declare function easingFor(transition: SplitflapTransition): Easing;
export declare const SCRAMBLE_STEP_MS = 55;
//# sourceMappingURL=paths.d.ts.map
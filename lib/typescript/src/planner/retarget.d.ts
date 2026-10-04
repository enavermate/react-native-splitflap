import type { BoardCell, CellPlan } from './types.js';
export type Origin = {
    from: string;
    resume?: CellPlan['resume'];
};
/** Where a new plan for this cell starts: the glyph on screen, plus the pair/fraction to continue from if it is moving. */
export declare function originAt(bc: BoardCell | undefined, now: number): Origin;
//# sourceMappingURL=retarget.d.ts.map
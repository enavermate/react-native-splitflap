import type { Board, Plan, TransitionInput } from './types.js';
export declare const DEFAULT_DURATION_MS = 650;
export declare const DEFAULT_STAGGER_MS = 40;
export declare function createBoard(): Board;
export declare function planTransition(board: Board, input: TransitionInput): {
    plan: Plan;
    board: Board;
};
//# sourceMappingURL=plan.d.ts.map
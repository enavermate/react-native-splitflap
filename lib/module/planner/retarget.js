"use strict";

import { glyphAt, positionAt } from "./timeline.js";
const roundFraction = f => Math.round(f * 1000) / 1000;

/** Where a new plan for this cell starts: the glyph on screen, plus the pair/fraction to continue from if it is moving. */
export function originAt(bc, now) {
  if (!bc) return {
    from: ''
  };
  const from = glyphAt(bc, now);
  const pos = positionAt(bc, now);
  return pos.moving ? {
    from,
    resume: {
      k: pos.k,
      f: roundFraction(pos.f)
    }
  } : {
    from
  };
}
//# sourceMappingURL=retarget.js.map
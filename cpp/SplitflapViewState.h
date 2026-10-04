#pragma once

#include <react/renderer/graphics/Float.h>

#include <vector>

#ifdef ANDROID
#include <folly/dynamic.h>
#endif

namespace facebook::react {

/**
 * What the shadow node measured, handed to the platform view so it places glyphs exactly where
 * Yoga sized them. Widths are per glyph of the `text` prop, in points, letter spacing included.
 */
class SplitflapViewState final {
 public:
  std::vector<Float> cellWidths{};
  Float lineHeight{0};
  Float ascent{0};
  /** fontSize after the font-scaling multiplier, so the view builds the same UIFont Yoga measured. */
  Float fontSizeResolved{0};
  /**
   * How many glyphs of `text` fit before a trailing "…" when the frame is narrower than the text,
   * or -1 when all of it fits — the tail truncation <Text numberOfLines={1}> applies, so an
   * animation lands on exactly what the Text it hands over to shows.
   */
  int visibleCount{-1};
  /**
   * `uniform` and `tiered`: the width every glyph is centred in — the widest cell the board's
   * alphabets can need; 0 for the other modes, which draw a glyph from its cell's left edge.
   */
  Float centreWidth{0};

  SplitflapViewState() = default;
  SplitflapViewState(
      std::vector<Float> cellWidths,
      Float lineHeight,
      Float ascent,
      Float fontSizeResolved,
      int visibleCount = -1)
      : cellWidths(std::move(cellWidths)),
        lineHeight(lineHeight),
        ascent(ascent),
        fontSizeResolved(fontSizeResolved),
        visibleCount(visibleCount) {}

#ifdef ANDROID
  SplitflapViewState(const SplitflapViewState& previousState, folly::dynamic data);
  folly::dynamic getDynamic() const;
#endif
};

} // namespace facebook::react

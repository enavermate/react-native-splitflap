#include "SplitflapViewState.h"

namespace facebook::react {

#ifdef ANDROID
SplitflapViewState::SplitflapViewState(const SplitflapViewState& previousState, folly::dynamic data)
    : cellWidths(previousState.cellWidths),
      lineHeight(previousState.lineHeight),
      ascent(previousState.ascent),
      fontSizeResolved(previousState.fontSizeResolved),
      visibleCount(previousState.visibleCount),
      centreWidth(previousState.centreWidth) {
  (void)data;
}

folly::dynamic SplitflapViewState::getDynamic() const {
  folly::dynamic widths = folly::dynamic::array();
  for (const auto width : cellWidths) {
    widths.push_back(width);
  }
  return folly::dynamic::object("cellWidths", std::move(widths))("lineHeight", lineHeight)("ascent", ascent)(
      "fontSizeResolved", fontSizeResolved)("visibleCount", visibleCount)("centreWidth", centreWidth);
}
#endif

} // namespace facebook::react

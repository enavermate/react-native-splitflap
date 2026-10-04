#pragma once

#include "SplitflapViewState.h"

#include <react/renderer/attributedstring/TextAttributes.h>
#include <react/renderer/components/SplitflapViewSpec/EventEmitters.h>
#include <react/renderer/components/SplitflapViewSpec/Props.h>
#include <react/renderer/components/view/ConcreteViewShadowNode.h>
#include <react/renderer/core/LayoutContext.h>
#include <react/renderer/textlayoutmanager/TextLayoutManager.h>

#include <memory>
#include <string>
#include <vector>

namespace facebook::react {

extern const char SplitflapViewComponentName[];

/** Splits UTF-8 into code points, the same cells `Array.from(text)` gives the planner. */
std::vector<std::string> splitflapGlyphs(const std::string& utf8);

/**
 * The reason the library is a Fabric component: Yoga asks this node for its size, and the size
 * is the sum of the glyphs measured one by one (cells are never kerned against each other),
 * through the same TextLayoutManager RN's <Text> uses, so the board sits on the text grid.
 */
class SplitflapViewShadowNode final : public ConcreteViewShadowNode<
                                          SplitflapViewComponentName,
                                          SplitflapViewProps,
                                          SplitflapViewEventEmitter,
                                          SplitflapViewState> {
 public:
  using ConcreteViewShadowNode::ConcreteViewShadowNode;

  static ShadowNodeTraits BaseTraits() {
    auto traits = ConcreteViewShadowNode::BaseTraits();
    traits.set(ShadowNodeTraits::Trait::LeafYogaNode);
    traits.set(ShadowNodeTraits::Trait::MeasurableYogaNode);
    return traits;
  }

  void setTextLayoutManager(std::shared_ptr<const TextLayoutManager> textLayoutManager);

  void layout(LayoutContext layoutContext) override;

  Size measureContent(const LayoutContext& layoutContext, const LayoutConstraints& layoutConstraints)
      const override;

 private:
  TextAttributes textAttributes(const LayoutContext& layoutContext) const;
  SplitflapViewState measureGlyphs(const LayoutContext& layoutContext) const;
  Float measureGlyph(const std::string& glyph, const LayoutContext& layoutContext) const;

  std::shared_ptr<const TextLayoutManager> textLayoutManager_;
};

} // namespace facebook::react

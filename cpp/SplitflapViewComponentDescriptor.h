#pragma once

#include "SplitflapViewShadowNode.h"

#include <react/renderer/core/ConcreteComponentDescriptor.h>
#include <react/renderer/textlayoutmanager/TextLayoutManager.h>
#include <react/utils/ContextContainer.h>

namespace facebook::react {

/**
 * Mirrors BaseParagraphComponentDescriptor: every node borrows the surface's shared
 * TextLayoutManager (registered under the same key RN's <Text> uses) and measures itself.
 */
class SplitflapViewComponentDescriptor final : public ConcreteComponentDescriptor<SplitflapViewShadowNode> {
 public:
  explicit SplitflapViewComponentDescriptor(const ComponentDescriptorParameters& parameters)
      : ConcreteComponentDescriptor<SplitflapViewShadowNode>(parameters),
        textLayoutManager_(getManagerByName<TextLayoutManager>(contextContainer_, "TextLayoutManager")) {}

 protected:
  void adopt(ShadowNode& shadowNode) const override {
    ConcreteComponentDescriptor<SplitflapViewShadowNode>::adopt(shadowNode);
    auto& splitflapShadowNode = static_cast<SplitflapViewShadowNode&>(shadowNode);
    splitflapShadowNode.setTextLayoutManager(textLayoutManager_);
    splitflapShadowNode.enableMeasurement();
  }

 private:
  const std::shared_ptr<const TextLayoutManager> textLayoutManager_;
};

} // namespace facebook::react

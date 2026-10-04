#include "SplitflapViewShadowNode.h"

#include <react/renderer/attributedstring/AttributedString.h>
#include <react/renderer/attributedstring/AttributedStringBox.h>
#include <react/renderer/attributedstring/ParagraphAttributes.h>
#include <react/renderer/core/LayoutConstraints.h>
#include <react/renderer/textlayoutmanager/TextLayoutContext.h>

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <limits>
#include <mutex>
#include <string>
#include <unordered_map>
#include <optional>

namespace facebook::react {

extern const char SplitflapViewComponentName[] = "SplitflapView";

namespace {

constexpr Float kDefaultFontSize = 14;
constexpr const char* kEllipsis = "\u2026";

// The fontVariant names a <Text> accepts, as React Native's own conversion reads them.
std::optional<FontVariant> fontVariantFromStrings(const std::vector<std::string>& values) {
  int bits = 0;
  for (const auto& value : values) {
    if (value == "small-caps") {
      bits |= static_cast<int>(FontVariant::SmallCaps);
    } else if (value == "oldstyle-nums") {
      bits |= static_cast<int>(FontVariant::OldstyleNums);
    } else if (value == "lining-nums") {
      bits |= static_cast<int>(FontVariant::LiningNums);
    } else if (value == "tabular-nums") {
      bits |= static_cast<int>(FontVariant::TabularNums);
    } else if (value == "proportional-nums") {
      bits |= static_cast<int>(FontVariant::ProportionalNums);
    }
  }
  return bits == 0 ? std::nullopt : std::optional<FontVariant>(static_cast<FontVariant>(bits));
}

std::optional<FontWeight> fontWeightFromString(const std::string& value) {
  if (value.empty() || value == "normal") {
    return std::nullopt;
  }
  if (value == "bold") {
    return FontWeight::Bold;
  }
  if (value == "ultralight") {
    return FontWeight::UltraLight;
  }
  if (value == "thin") {
    return FontWeight::Thin;
  }
  if (value == "light") {
    return FontWeight::Light;
  }
  if (value == "medium") {
    return FontWeight::Medium;
  }
  if (value == "semibold") {
    return FontWeight::Semibold;
  }
  if (value == "heavy") {
    return FontWeight::Heavy;
  }
  if (value == "black") {
    return FontWeight::Black;
  }
  const auto numeric = std::atoi(value.c_str());
  if (numeric >= 100 && numeric <= 900) {
    return static_cast<FontWeight>((numeric / 100) * 100);
  }
  return std::nullopt;
}

std::optional<FontStyle> fontStyleFromString(const std::string& value) {
  if (value == "italic") {
    return FontStyle::Italic;
  }
  if (value == "oblique") {
    return FontStyle::Oblique;
  }
  return std::nullopt;
}

/** RN's own rule (RCTAttributedTextUtils): scaling is on unless switched off, capped by the max. */
Float effectiveFontSizeMultiplier(const SplitflapViewProps& props, const LayoutContext& layoutContext) {
  if (!props.allowFontScaling) {
    return 1;
  }
  const auto multiplier = std::isnan(layoutContext.fontSizeMultiplier) ? 1 : layoutContext.fontSizeMultiplier;
  return props.maxFontSizeMultiplier >= 1 ? std::min(props.maxFontSizeMultiplier, multiplier) : multiplier;
}

AttributedString attributedGlyph(const std::string& glyph, const TextAttributes& attributes) {
  auto fragment = AttributedString::Fragment{};
  fragment.string = glyph;
  fragment.textAttributes = attributes;
  auto attributedString = AttributedString{};
  attributedString.setBaseTextAttributes(attributes);
  attributedString.appendFragment(std::move(fragment));
  return attributedString;
}

// The cells JS split `text` into (planner splitGlyphs: a flag or an emoji family is one cell);
// split by code point only when the prop is absent.
std::vector<std::string> cellGlyphs(const SplitflapViewProps& props) {
  return props.glyphs.empty() ? splitflapGlyphs(props.text) : props.glyphs;
}

} // namespace

std::vector<std::string> splitflapGlyphs(const std::string& utf8) {
  std::vector<std::string> glyphs;
  size_t i = 0;
  while (i < utf8.size()) {
    const auto lead = static_cast<unsigned char>(utf8[i]);
    size_t length = 1;
    if (lead >= 0xF0) {
      length = 4;
    } else if (lead >= 0xE0) {
      length = 3;
    } else if (lead >= 0xC0) {
      length = 2;
    }
    length = std::min(length, utf8.size() - i);
    glyphs.push_back(utf8.substr(i, length));
    i += length;
  }
  return glyphs;
}

void SplitflapViewShadowNode::setTextLayoutManager(std::shared_ptr<const TextLayoutManager> textLayoutManager) {
  ensureUnsealed();
  textLayoutManager_ = std::move(textLayoutManager);
}

TextAttributes SplitflapViewShadowNode::textAttributes(const LayoutContext& layoutContext) const {
  const auto& props = getConcreteProps();
  auto attributes = TextAttributes::defaultTextAttributes();
  attributes.fontFamily = props.fontFamily;
  attributes.fontSize = props.fontSize > 0 ? props.fontSize : kDefaultFontSize;
  attributes.fontWeight = fontWeightFromString(props.fontWeight);
  attributes.fontStyle = fontStyleFromString(props.fontStyle);
  attributes.fontVariant = fontVariantFromStrings(props.fontVariant);
  attributes.foregroundColor = props.color;
  attributes.letterSpacing = props.letterSpacing;
  if (props.lineHeight > 0) {
    attributes.lineHeight = props.lineHeight;
  }
  attributes.allowFontScaling = props.allowFontScaling;
  attributes.fontSizeMultiplier = layoutContext.fontSizeMultiplier;
  if (props.maxFontSizeMultiplier >= 1) {
    attributes.maxFontSizeMultiplier = props.maxFontSizeMultiplier;
  }
  return attributes;
}

namespace {

struct WidthTier {
  Float limit;
  Float width;
};

// Narrow, regular and wide, read off the alphabet's own widths against its median: any script and
// font sorts itself — "i l j t f r" narrow and "m w" wide in a Latin sans, "ж ш щ ю ы ф" wide in
// Cyrillic — with no list of letters to keep. `single` is `uniform`: one tier, the widest glyph.
std::vector<WidthTier> widthTiers(std::vector<Float> alphabet, bool single) {
  if (alphabet.empty()) {
    return {};
  }
  std::sort(alphabet.begin(), alphabet.end());
  const auto infinity = std::numeric_limits<Float>::infinity();
  if (single) {
    return {{infinity, std::ceil(alphabet.back())}};
  }
  const auto median = alphabet[alphabet.size() / 2];
  const auto narrowLimit = median * 0.75f;
  const auto wideLimit = median * 1.25f;
  auto narrow = Float{0};
  auto regular = Float{0};
  auto wide = Float{0};
  for (const auto width : alphabet) {
    if (width <= narrowLimit) {
      narrow = std::max(narrow, width);
    } else if (width < wideLimit) {
      regular = std::max(regular, width);
    } else {
      wide = std::max(wide, width);
    }
  }
  std::vector<WidthTier> tiers;
  if (narrow > 0) {
    tiers.push_back({narrowLimit, std::ceil(narrow)});
  }
  if (regular > 0) {
    tiers.push_back({wideLimit, std::ceil(regular)});
  }
  if (wide > 0) {
    tiers.push_back({infinity, std::ceil(wide)});
  }
  return tiers;
}

// A glyph outside the alphabets (a sign, an accented capital) still never gets a cell narrower
// than itself.
Float tierWidthOf(const std::vector<WidthTier>& tiers, Float width) {
  for (const auto& tier : tiers) {
    if (width <= tier.limit) {
      return std::max(tier.width, std::ceil(width));
    }
  }
  return std::ceil(width);
}

// The alphabets of one font are the same for every board that shows them, and measuring thirty-odd
// glyphs on every text change cost the JS thread 2–6 fps at sixty boards on an iPhone. Measured
// once per alphabet set, font and scale.
std::mutex gAlphabetMutex;
std::unordered_map<std::string, std::vector<Float>> gAlphabetWidths;
constexpr size_t kAlphabetCacheLimit = 256;

} // namespace

SplitflapViewState SplitflapViewShadowNode::measureGlyphs(const LayoutContext& layoutContext) const {
  const auto& props = getConcreteProps();
  const auto attributes = textAttributes(layoutContext);
  const auto fontSizeResolved = attributes.fontSize * effectiveFontSizeMultiplier(props, layoutContext);

  if (textLayoutManager_ == nullptr) {
    return SplitflapViewState{{}, 0, 0, fontSizeResolved};
  }

  auto paragraphAttributes = ParagraphAttributes{};
  paragraphAttributes.maximumNumberOfLines = 1;
  const auto textLayoutContext = TextLayoutContext{
      .pointScaleFactor = layoutContext.pointScaleFactor,
      .surfaceId = getSurfaceId(),
  };
  const auto unconstrained = LayoutConstraints{
      .minimumSize = {0, 0},
      .maximumSize = {std::numeric_limits<Float>::infinity(), std::numeric_limits<Float>::infinity()},
  };

  auto measure = [&](const std::string& glyph) {
    return textLayoutManager_
        ->measure(AttributedStringBox{attributedGlyph(glyph, attributes)}, paragraphAttributes, textLayoutContext, unconstrained)
        .size;
  };

  std::vector<Float> widths;
  auto centreWidth = Float{0};
  const auto uniform = props.cellWidth == SplitflapViewCellWidth::Uniform;
  if (uniform || props.cellWidth == SplitflapViewCellWidth::Tiered) {
    const auto key = props.widthGlyphs + '\0' + std::to_string(std::hash<TextAttributes>{}(attributes)) + '\0' +
        std::to_string(layoutContext.pointScaleFactor);
    std::vector<Float> alphabet;
    {
      std::lock_guard<std::mutex> lock(gAlphabetMutex);
      const auto cached = gAlphabetWidths.find(key);
      if (cached != gAlphabetWidths.end()) {
        alphabet = cached->second;
      }
    }
    if (alphabet.empty()) {
      for (const auto& glyph : splitflapGlyphs(props.widthGlyphs)) {
        alphabet.push_back(measure(glyph).width);
      }
      std::lock_guard<std::mutex> lock(gAlphabetMutex);
      if (gAlphabetWidths.size() >= kAlphabetCacheLimit) {
        gAlphabetWidths.clear();
      }
      gAlphabetWidths.emplace(key, alphabet);
    }
    const auto glyphs = cellGlyphs(props);
    std::vector<Float> own;
    for (const auto& glyph : glyphs) {
      own.push_back(measure(glyph).width);
    }
    if (uniform) {
      // The text's own glyphs count too: one outside every alphabet must still fit.
      alphabet.insert(alphabet.end(), own.begin(), own.end());
    }
    const auto tiers = widthTiers(alphabet, uniform);
    for (const auto width : own) {
      widths.push_back(tierWidthOf(tiers, width));
    }
    for (const auto& tier : tiers) {
      centreWidth = std::max(centreWidth, tier.width);
    }
    for (const auto width : widths) {
      centreWidth = std::max(centreWidth, width);
    }
  } else {
#ifdef ANDROID
  // Android's measure returns the layout's width in whole pixels, rounded up. Measured one by one,
  // every glyph gained up to a pixel, and "laburo" came out 1.5 dp wider than the <Text> it hands
  // over to. So a glyph's cell is placed where the whole line puts it: its start is the prefix
  // ending with it minus its own width, which counts the kerning with the glyph before it (the
  // "o" of "laburo" sits 3 px left of where "labur" alone ends), and the last cell ends where the
  // whole line does, so the widths sum to exactly what the <Text> measures.
  const auto glyphs = cellGlyphs(props);
  std::vector<Float> starts;
  std::string prefix;
  for (const auto& glyph : glyphs) {
    prefix += glyph;
    starts.push_back(starts.empty() ? 0 : std::max(starts.back(), measure(prefix).width - measure(glyph).width));
  }
  const auto lineWidth = glyphs.empty() ? Float{0} : measure(prefix).width;
  for (size_t i = 0; i < starts.size(); i++) {
    const auto end = i + 1 < starts.size() ? starts[i + 1] : lineWidth;
    widths.push_back(std::max(Float{0}, end - starts[i]));
  }
#else
  for (const auto& glyph : cellGlyphs(props)) {
    widths.push_back(measure(glyph).width);
  }
#endif
  }

  // A reference glyph keeps the line height stable across texts and defined for an empty one.
  const auto reference = attributedGlyph("H", attributes);
  const auto lineHeight = measure("H").height;
  auto ascent = Float{0};
  const auto lines = textLayoutManager_->measureLines(
      AttributedStringBox{reference}, paragraphAttributes, Size{unconstrained.maximumSize.width, lineHeight});
  if (!lines.empty()) {
    ascent = lines.front().ascender;
  }

  auto state = SplitflapViewState{std::move(widths), lineHeight, ascent, fontSizeResolved};
  state.centreWidth = centreWidth;
  return state;
}

Size SplitflapViewShadowNode::measureContent(
    const LayoutContext& layoutContext,
    const LayoutConstraints& layoutConstraints) const {
  const auto measured = measureGlyphs(layoutContext);
  auto width = Float{0};
  for (const auto cellWidth : measured.cellWidths) {
    width += cellWidth;
  }
  return layoutConstraints.clamp(Size{width, measured.lineHeight});
}

Float SplitflapViewShadowNode::measureGlyph(const std::string& glyph, const LayoutContext& layoutContext) const {
  if (textLayoutManager_ == nullptr) {
    return 0;
  }
  auto paragraphAttributes = ParagraphAttributes{};
  paragraphAttributes.maximumNumberOfLines = 1;
  const auto textLayoutContext = TextLayoutContext{
      .pointScaleFactor = layoutContext.pointScaleFactor,
      .surfaceId = getSurfaceId(),
  };
  const auto unconstrained = LayoutConstraints{
      .minimumSize = {0, 0},
      .maximumSize = {std::numeric_limits<Float>::infinity(), std::numeric_limits<Float>::infinity()},
  };
  return textLayoutManager_
      ->measure(
          AttributedStringBox{attributedGlyph(glyph, textAttributes(layoutContext))},
          paragraphAttributes,
          textLayoutContext,
          unconstrained)
      .size.width;
}

void SplitflapViewShadowNode::layout(LayoutContext layoutContext) {
  ensureUnsealed();
  auto measured = measureGlyphs(layoutContext);

  // The frame is narrower than the text when a flex parent shrank it: keep the glyphs that fit
  // with a trailing "…", as the platform's one-line text truncates (UIKit drops trailing spaces).
  const auto available = getLayoutMetrics().getContentFrame().size.width;
  auto total = Float{0};
  for (const auto width : measured.cellWidths) {
    total += width;
  }
  if (available > 0 && total > available + 0.5f) {
    const auto ellipsis = measureGlyph(kEllipsis, layoutContext);
    const auto glyphs = cellGlyphs(getConcreteProps());
    int fit = 0;
    auto used = Float{0};
    while (fit < static_cast<int>(measured.cellWidths.size()) &&
           used + measured.cellWidths[fit] + ellipsis <= available + 0.5f) {
      used += measured.cellWidths[fit];
      fit++;
    }
#ifndef ANDROID
    while (fit > 0 && fit - 1 < static_cast<int>(glyphs.size()) && glyphs[fit - 1] == " ") {
      fit--;
    }
#endif
    // Android's TextView keeps a trailing space before the "…" ("la …"); dropping it there moved
    // the ellipsis 14 px left of the <Text>'s at 22 sp.
    measured.visibleCount = fit;
  }

  const auto& current = getStateData();
  if (current.cellWidths != measured.cellWidths || current.lineHeight != measured.lineHeight ||
      current.ascent != measured.ascent || current.fontSizeResolved != measured.fontSizeResolved ||
      current.centreWidth != measured.centreWidth ||
      current.visibleCount != measured.visibleCount) {
    setStateData(std::move(measured));
  }
  ConcreteViewShadowNode::layout(layoutContext);
}

} // namespace facebook::react

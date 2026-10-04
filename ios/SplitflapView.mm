#import "SplitflapView.h"

#import "SplitflapGlyphAtlas.h"
#import "SplitflapPlan.h"
#import "SplitflapViewComponentDescriptor.h"

#import <React/RCTConversions.h>
#import <react/renderer/components/SplitflapViewSpec/EventEmitters.h>
#import <react/renderer/components/SplitflapViewSpec/Props.h>
#import <react/renderer/textlayoutmanager/RCTFontUtils.h>

#import "RCTFabricComponentsPlugins.h"

#import <cmath>
#import <string>
#import <vector>

using namespace facebook::react;

// Fade of the drum mask at the top and bottom of a cell, from the approved prototype.
static const CGFloat kSplitflapMaskFade = 0.16;
// A mask never resizes with its cell, so it is simply wider than any cell can be.
static const CGFloat kSplitflapMaskWidth = 4096;
// A uniform or tiered cell shifts its bounds' origin to centre its glyph, by at most half the
// widest cell; the mask starts well left of that, so the shift never uncovers an edge.
static const CGFloat kSplitflapMaskOrigin = -kSplitflapMaskWidth / 2;
// A cell's width settles a little after its glyph, like the prototype (window 1.15·t).
static const double kSplitflapWidthWindow = 1.15;
static const double kSplitflapSampleHz = 120;
static const NSUInteger kSplitflapMaxSamples = 2000;
// Two keyframes this close together are one instantaneous jump (a glyph swap between layers).
static const double kSplitflapKeyTimeEpsilon = 1e-6;
static const CGFloat kSplitflapDefaultFontSize = 14;
static NSString *const kSplitflapEllipsis = @"…";

// Prototype value: `perspective: 220px` on a flip cell.
static const CGFloat kSplitflapFlipPerspective = 220;
// The top flap folds toward the viewer (CSS rotateX(-180·s) in the prototype); flip once here if
// a device shows the flaps folding away.
static const double kSplitflapFlapFold = -1;
static const CGFloat kSplitflapScrambleDim = 0.55;
static const NSInteger kSplitflapScrambleMaxSteps = 2000;

typedef NS_ENUM(NSInteger, SplitflapRenderer) {
  SplitflapRendererDrum,
  SplitflapRendererScramble,
  SplitflapRendererFlip,
};

/** The fontVariant names a <Text> accepts; `tabular-nums` gives every digit one width. */
static RCTFontVariant SplitflapFontVariant(const std::vector<std::string> &values)
{
  NSInteger bits = 0;
  for (const auto &value : values) {
    if (value == "small-caps") {
      bits |= RCTFontVariantSmallCaps;
    } else if (value == "oldstyle-nums") {
      bits |= RCTFontVariantOldstyleNums;
    } else if (value == "lining-nums") {
      bits |= RCTFontVariantLiningNums;
    } else if (value == "tabular-nums") {
      bits |= RCTFontVariantTabularNums;
    } else if (value == "proportional-nums") {
      bits |= RCTFontVariantProportionalNums;
    }
  }
  return bits == 0 ? RCTFontVariantUndefined : (RCTFontVariant)bits;
}

static SplitflapRenderer SplitflapRendererFor(NSString *transition)
{
  if ([transition isEqualToString:@"scramble"]) {
    return SplitflapRendererScramble;
  }
  if ([transition isEqualToString:@"flip"]) {
    return SplitflapRendererFlip;
  }
  return SplitflapRendererDrum;
}

/**
 * The cells JS split the text into (planner splitGlyphs: a flag or an emoji family is one cell);
 * by code point only when the prop is absent.
 */
static NSArray<NSString *> *SplitflapCodePoints(NSString *text);
static NSArray<NSString *> *SplitflapCellsOfProps(const facebook::react::SplitflapViewProps &props, NSString *text)
{
  if (props.glyphs.empty()) {
    return SplitflapCodePoints(text);
  }
  NSMutableArray<NSString *> *cells = [NSMutableArray arrayWithCapacity:props.glyphs.size()];
  for (const auto &glyph : props.glyphs) {
    [cells addObject:@(glyph.c_str())];
  }
  return cells;
}

static NSArray<NSString *> *SplitflapCodePoints(NSString *text)
{
  // A fallback for a text without its `glyphs` prop, and the splitter of the alphabets.
  NSMutableArray<NSString *> *glyphs = [NSMutableArray new];
  NSUInteger i = 0;
  const NSUInteger length = text.length;
  while (i < length) {
    const unichar c = [text characterAtIndex:i];
    const NSUInteger units = (CFStringIsSurrogateHighCharacter(c) && i + 1 < length) ? 2 : 1;
    [glyphs addObject:[text substringWithRange:NSMakeRange(i, units)]];
    i += units;
  }
  return glyphs;
}


static UIFontWeight SplitflapFontWeight(const std::string &value)
{
  if (value.empty() || value == "normal") {
    return NAN;
  }
  int weight = 400;
  if (value == "bold") {
    weight = 700;
  } else if (value == "ultralight") {
    weight = 100;
  } else if (value == "thin") {
    weight = 200;
  } else if (value == "light") {
    weight = 300;
  } else if (value == "medium") {
    weight = 500;
  } else if (value == "semibold") {
    weight = 600;
  } else if (value == "heavy") {
    weight = 800;
  } else if (value == "black") {
    weight = 900;
  } else {
    const int numeric = std::atoi(value.c_str());
    if (numeric >= 100 && numeric <= 900) {
      weight = (numeric / 100) * 100;
    }
  }
  switch (weight) {
    case 100:
      return UIFontWeightUltraLight;
    case 200:
      return UIFontWeightThin;
    case 300:
      return UIFontWeightLight;
    case 500:
      return UIFontWeightMedium;
    case 600:
      return UIFontWeightSemibold;
    case 700:
      return UIFontWeightBold;
    case 800:
      return UIFontWeightHeavy;
    case 900:
      return UIFontWeightBlack;
    default:
      return UIFontWeightRegular;
  }
}

static NSDictionary<NSString *, id> *SplitflapNoActions(void)
{
  static NSDictionary *actions;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSNull *null = [NSNull null];
    actions = @{
      @"position" : null,
      @"bounds" : null,
      @"contents" : null,
      @"contentsRect" : null,
      @"contentsScale" : null,
      @"hidden" : null,
      @"sublayers" : null,
      @"onOrderIn" : null,
      @"onOrderOut" : null,
      @"mask" : null,
      @"opacity" : null,
      @"transform" : null,
      @"sublayerTransform" : null,
      @"backgroundColor" : null,
      @"anchorPoint" : null,
    };
  });
  return actions;
}

/** Glyph layers A and B alternate along a path: even glyphs on A, odd on B. */
static NSInteger SplitflapGlyphOfLayer(NSInteger segment, BOOL isLayerA)
{
  const BOOL even = segment % 2 == 0;
  if (isLayerA) {
    return even ? segment : segment + 1;
  }
  return even ? segment + 1 : segment;
}

/** Perspective for a cell's sublayers with the vanishing point at the cell's centre, as CSS does. */
static CATransform3D SplitflapPerspective(CGFloat distance, CGFloat width, CGFloat height)
{
  CATransform3D perspective = CATransform3DIdentity;
  perspective.m34 = -1 / distance;
  const CATransform3D toCentre = CATransform3DMakeTranslation(-width / 2, -height / 2, 0);
  const CATransform3D back = CATransform3DMakeTranslation(width / 2, height / 2, 0);
  return CATransform3DConcat(CATransform3DConcat(toCentre, perspective), back);
}

/** Angle about X of a presented transform whose rotation part is a pure X rotation. */
static double SplitflapRotationX(CATransform3D transform)
{
  return atan2(transform.m23, transform.m22);
}

static CGRect SplitflapTopHalf(CGRect rect)
{
  rect.size.height /= 2;
  return rect;
}

static CGRect SplitflapBottomHalf(CGRect rect)
{
  rect.origin.y += rect.size.height / 2;
  rect.size.height /= 2;
  return rect;
}

@interface SplitflapCell : NSObject
@property (nonatomic, strong) CALayer *container;
@property (nonatomic, strong) CAGradientLayer *mask;
@property (nonatomic, strong) CALayer *glyphA;
@property (nonatomic, strong) CALayer *glyphB;
/** Third and fourth glyph layers: the two flaps of a flip. */
@property (nonatomic, strong) CALayer *glyphC;
@property (nonatomic, strong) CALayer *glyphD;
/** Model width, where the cell settles once its plan is over. */
@property (nonatomic, assign) CGFloat width;
- (NSArray<CALayer *> *)glyphLayers;
- (void)removeAllAnimations;
@end

@implementation SplitflapCell
- (NSArray<CALayer *> *)glyphLayers
{
  return @[ self.glyphA, self.glyphB, self.glyphC, self.glyphD ];
}
- (void)removeAllAnimations
{
  [self.container removeAllAnimations];
  for (CALayer *layer in self.glyphLayers) {
    [layer removeAllAnimations];
  }
}
@end

/** Keyframes for one glyph layer over one plan window, in normalized time. */
struct SplitflapLayerTrack {
  NSMutableArray<NSNumber *> *keyTimesY = [NSMutableArray new];
  NSMutableArray<NSNumber *> *valuesY = [NSMutableArray new];
  NSMutableArray<NSNumber *> *keyTimesRect = [NSMutableArray new];
  NSMutableArray<NSValue *> *valuesRect = [NSMutableArray new];
  CGFloat finalY = 0;
  CGRect finalRect = CGRectZero;
};

/**
 * One keyframe animation of any property over a plan window, in milliseconds. Key times are kept
 * strictly increasing: a value added at a time already used lands an epsilon later, which Core
 * Animation plays as an instantaneous jump. A discrete track owns the extra trailing key time
 * CA wants for that mode.
 */
struct SplitflapTrack {
  NSMutableArray<NSNumber *> *times = [NSMutableArray new];
  NSMutableArray *values = [NSMutableArray new];
  double window;
  BOOL discrete;

  SplitflapTrack(double window, BOOL discrete) : window(window), discrete(discrete) {}

  void add(double ms, id value)
  {
    double t = window > 0 ? MIN(1, MAX(0, ms / window)) : 0;
    const double ceiling = discrete ? 1 - kSplitflapKeyTimeEpsilon : 1;
    t = MIN(t, ceiling);
    if (times.count > 0) {
      const double last = times.lastObject.doubleValue;
      if (t <= last) {
        t = last + kSplitflapKeyTimeEpsilon;
      }
      if (t > ceiling) {
        values[values.count - 1] = value;
        return;
      }
    }
    [times addObject:@(t)];
    [values addObject:value];
  }

  id last() const
  {
    return values.lastObject;
  }

  void addTo(CALayer *layer, NSString *keyPath, CFTimeInterval beginTime, BOOL loop)
  {
    if (values.count == 0) {
      return;
    }
    NSMutableArray<NSNumber *> *keyTimes = [times mutableCopy];
    if (discrete) {
      [keyTimes addObject:@1];
    } else if (keyTimes.lastObject.doubleValue < 1) {
      [keyTimes addObject:@1];
      [values addObject:values.lastObject];
    }
    CAKeyframeAnimation *animation = [CAKeyframeAnimation animationWithKeyPath:keyPath];
    animation.keyTimes = keyTimes;
    animation.values = values;
    animation.calculationMode = discrete ? kCAAnimationDiscrete : kCAAnimationLinear;
    animation.duration = window / 1000;
    animation.beginTime = beginTime;
    animation.fillMode = kCAFillModeBackwards;
    animation.repeatCount = loop ? HUGE_VALF : 0;
    [layer addAnimation:animation forKey:[@"splitflap." stringByAppendingString:keyPath]];
  }
};

/** What an interrupted cell showed at the moment the new plan arrived, per renderer. */
struct SplitflapPresented {
  CGFloat width = 0;
  BOOL hasWidth = NO;
  // drum: y of each glyph currently on a layer
  NSMutableDictionary<NSString *, NSNumber *> *glyphYs = [NSMutableDictionary new];
  // flip: which flap is mid-fold, showing which glyph, at which angle
  NSString *topGlyph = nil;
  double topAngle = NAN;
  NSString *bottomGlyph = nil;
  double bottomAngle = NAN;
  // scramble: the cell was flickering
  BOOL dimmed = NO;
};

@implementation SplitflapView {
  SplitflapViewShadowNode::ConcreteState::Shared _nodeState;
  NSMutableArray<SplitflapCell *> *_cells;
  UIFont *_font;
  UIColor *_color;
  CGFloat _letterSpacing;
  CGFloat _lineHeight;
  SplitflapGlyphAtlas *_atlas;
  BOOL _fontDirty;
  BOOL _planDirty;
  // How the frame moved in this mount transaction: its left edge shifted by `_frameShift` while it
  // took the new text's width, the parent placing it at `_frameAnchor` (0 at the start, ½ centred,
  // 1 at the end). The next plan carries the old word from where it stood to the new place.
  BOOL _frameMoved;
  CGFloat _frameShift;
  CGFloat _frameAnchor;
  BOOL _stateDirty;
  NSUInteger _generation;
  BOOL _inFlight;
  NSString *_inFlightText;
  SplitflapRenderer _inFlightRenderer;
  /** Transition of the last plan read; the settled look of `flip` (tiles) outlives its plan. */
  NSString *_styleTransition;
  NSArray<NSString *> *_textGlyphs;
}

+ (ComponentDescriptorProvider)componentDescriptorProvider
{
  return concreteComponentDescriptorProvider<SplitflapViewComponentDescriptor>();
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if (self = [super initWithFrame:frame]) {
    static const auto defaultProps = std::make_shared<const SplitflapViewProps>();
    _props = defaultProps;
    _cells = [NSMutableArray new];
    _styleTransition = @"roll";
    self.layer.actions = SplitflapNoActions();
    // A leaving word can be wider than the new frame for a moment, and a word in flight is drawn
    // where the old one stood, not where the frame has already moved: both spill past the frame
    // until the cells settle into it. Each cell still clips its own glyphs.
    self.clipsToBounds = NO;
  }
  return self;
}

#pragma mark - Fabric lifecycle

- (void)updateProps:(const Props::Shared &)props oldProps:(const Props::Shared &)oldProps
{
  const auto &oldViewProps = *std::static_pointer_cast<const SplitflapViewProps>(_props);
  const auto &newViewProps = *std::static_pointer_cast<const SplitflapViewProps>(props);

  if (oldViewProps.fontFamily != newViewProps.fontFamily || oldViewProps.fontSize != newViewProps.fontSize ||
      oldViewProps.fontWeight != newViewProps.fontWeight || oldViewProps.fontStyle != newViewProps.fontStyle ||
      oldViewProps.color != newViewProps.color || oldViewProps.letterSpacing != newViewProps.letterSpacing ||
      oldViewProps.lineHeight != newViewProps.lineHeight ||
      oldViewProps.allowFontScaling != newViewProps.allowFontScaling ||
      oldViewProps.maxFontSizeMultiplier != newViewProps.maxFontSizeMultiplier ||
      oldViewProps.surfaceColor != newViewProps.surfaceColor) {
    _fontDirty = YES;
  }
  if (oldViewProps.plan != newViewProps.plan || oldViewProps.text != newViewProps.text) {
    _planDirty = YES;
  }

  [super updateProps:props oldProps:oldProps];
}

- (void)updateState:(const State::Shared &)state oldState:(const State::Shared &)oldState
{
  _nodeState = std::static_pointer_cast<const SplitflapViewShadowNode::ConcreteState>(state);
  _stateDirty = YES;
}

- (void)updateLayoutMetrics:(const LayoutMetrics &)layoutMetrics
           oldLayoutMetrics:(const LayoutMetrics &)oldLayoutMetrics
{
  [super updateLayoutMetrics:layoutMetrics oldLayoutMetrics:oldLayoutMetrics];
  // A new text resizes the frame at once, and a parent that centres it (or aligns it to the end)
  // moves its left edge with it: drawn from the new edge, the old word would hop sideways before a
  // single cell turned. The anchor is read off the move itself, so any alignment is kept.
  const CGRect before = RCTCGRectFromRect(oldLayoutMetrics.frame);
  const CGRect after = RCTCGRectFromRect(layoutMetrics.frame);
  const CGFloat grown = after.size.width - before.size.width;
  const CGFloat shift = before.origin.x - after.origin.x;
  _frameMoved = NO;
  if (before.size.width > 0 && fabs(grown) > 0.5 && fabs(shift) > 0.01) {
    const CGFloat anchor = shift / grown;
    if (anchor > -0.05 && anchor < 1.05) {
      _frameMoved = YES;
      _frameShift = shift;
      _frameAnchor = MIN(1, MAX(0, anchor));
    }
  }
}

- (void)finalizeUpdates:(RNComponentViewUpdateMask)updateMask
{
  [super finalizeUpdates:updateMask];

  if (_fontDirty || _stateDirty || _font == nil) {
    [self resolveFont];
  }
  const auto &props = *std::static_pointer_cast<const SplitflapViewProps>(_props);
  NSString *text = @(props.text.c_str());
  _textGlyphs = SplitflapCellsOfProps(props, text);
  if (_planDirty) {
    SplitflapPlan *plan = [SplitflapPlan planWithJSON:@(props.plan.c_str())];
    if (plan != nil) {
      _styleTransition = plan.transition;
    }
    if (plan == nil || plan.version > 1 || plan.cells.count < _textGlyphs.count) {
      [self showTextInstantly:text];
    } else {
      [self playPlan:plan text:text];
    }
  } else if (_fontDirty || _stateDirty) {
    [self showTextInstantly:text];
  }
  _fontDirty = NO;
  _planDirty = NO;
  _stateDirty = NO;
  _frameMoved = NO;
}

- (void)prepareForRecycle
{
  [super prepareForRecycle];
  _generation++;
  _inFlight = NO;
  _inFlightText = nil;
  for (SplitflapCell *cell in _cells) {
    [cell removeAllAnimations];
    [cell.container removeFromSuperlayer];
  }
  [_cells removeAllObjects];
  _nodeState = nullptr;
  _textGlyphs = nil;
  _atlas = nil;
  _font = nil;
  _styleTransition = @"roll";
  _fontDirty = NO;
  _planDirty = NO;
  _stateDirty = NO;
  static const auto defaultProps = std::make_shared<const SplitflapViewProps>();
  _props = defaultProps;
}

#pragma mark - Font

- (void)resolveFont
{
  const auto &props = *std::static_pointer_cast<const SplitflapViewProps>(_props);
  RCTFontProperties fontProperties;
  fontProperties.family = props.fontFamily.empty() ? nil : @(props.fontFamily.c_str());
  CGFloat size = _nodeState ? _nodeState->getData().fontSizeResolved : 0;
  if (size <= 0) {
    size = props.fontSize > 0 ? props.fontSize : kSplitflapDefaultFontSize;
  }
  fontProperties.size = size;
  fontProperties.weight = SplitflapFontWeight(props.fontWeight);
  fontProperties.style = props.fontStyle == "italic" ? RCTFontStyleItalic
      : props.fontStyle == "oblique"                 ? RCTFontStyleOblique
                                                     : RCTFontStyleUndefined;
  fontProperties.variant = SplitflapFontVariant(props.fontVariant);
  fontProperties.sizeMultiplier = 1;
  _font = RCTFontWithFontProperties(fontProperties);
  _color = RCTUIColorFromSharedColor(props.color) ?: [UIColor blackColor];
  _letterSpacing = std::isnan(props.letterSpacing) ? 0 : props.letterSpacing;
  const CGFloat stateLineHeight = _nodeState ? _nodeState->getData().lineHeight : 0;
  _lineHeight = stateLineHeight > 0 ? stateLineHeight : ceil(_font.lineHeight);
  _atlas = nil;
}

- (SplitflapGlyphAtlas *)atlasForGlyphs:(NSSet<NSString *> *)glyphs
{
  const CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
  _atlas = [SplitflapGlyphAtlas atlasWithFont:_font
                                        color:_color
                                letterSpacing:_letterSpacing
                                   lineHeight:_lineHeight
                                        scale:scale
                                  centreWidth:[self centreWidth]
                                       glyphs:glyphs];
  return _atlas;
}

/** The cells of `text`: the props' split when it is the current text, else code points. */
- (NSArray<NSString *> *)cellsOfText:(NSString *)text
{
  if (_textGlyphs != nil && [[_textGlyphs componentsJoinedByString:@""] isEqualToString:text]) {
    return _textGlyphs;
  }
  return SplitflapCodePoints(text);
}

/** `uniform` and `tiered`: the width the atlas centres every glyph in; 0 for the other modes. */
- (CGFloat)centreWidth
{
  return _nodeState ? _nodeState->getData().centreWidth : 0;
}

/**
 * A cell `width` wide. The atlas draws each glyph centred in `centreWidth`; the bounds' origin
 * shifts that span so its middle is the cell's middle, whatever width the cell has right now.
 */
- (CGRect)cellBoundsWithWidth:(CGFloat)width height:(CGFloat)height
{
  const CGFloat centre = [self centreWidth];
  return CGRectMake(centre > 0 ? (centre - width) / 2 : 0, 0, width, height);
}

/** The colour under the board: what a flap paints so the half it covers never shows through. */
- (UIColor *)surfaceColor
{
  const auto &props = *std::static_pointer_cast<const SplitflapViewProps>(_props);
  UIColor *color = RCTUIColorFromSharedColor(props.surfaceColor);
  if (color != nil) {
    return color;
  }
  CGFloat r = 0, g = 0, b = 0, alpha = 0;
  if (self.backgroundColor != nil && [self.backgroundColor getRed:&r green:&g blue:&b alpha:&alpha] && alpha >= 1) {
    return self.backgroundColor;
  }
  return [UIColor.systemBackgroundColor resolvedColorWithTraitCollection:self.traitCollection];
}

/**
 * Yoga's width for this cell when it is a glyph of the measured `text`; a loading word or a
 * glyph that is leaving falls back to the atlas advance, which the same font produced.
 */
- (CGFloat)settledWidthOfGlyph:(NSString *)glyph atIndex:(NSUInteger)index
{
  if (glyph.length == 0) {
    return 0;
  }
  if (_nodeState && index < _textGlyphs.count && [_textGlyphs[index] isEqualToString:glyph]) {
    const auto &widths = _nodeState->getData().cellWidths;
    if (index < widths.size()) {
      return widths[index];
    }
  }
  return [_atlas advanceForGlyph:glyph];
}

/**
 * How many glyphs of the current text fit before the ellipsis, or -1 when all of it fits. Only
 * trusted when the state was measured for this very text.
 */
- (NSInteger)visibleGlyphCount
{
  if (!_nodeState) {
    return -1;
  }
  const auto &data = _nodeState->getData();
  if (data.visibleCount < 0 || data.cellWidths.size() != _textGlyphs.count ||
      (NSUInteger)data.visibleCount >= _textGlyphs.count) {
    return -1;
  }
  return data.visibleCount;
}

#pragma mark - Cells

- (SplitflapCell *)makeCell
{
  SplitflapCell *cell = [SplitflapCell new];
  cell.container = [CALayer layer];
  cell.container.anchorPoint = CGPointZero;
  cell.container.masksToBounds = YES;
  cell.container.actions = SplitflapNoActions();

  // Each drum cell keeps its own fade: one mask over the whole board measured 3–4 fps slower on
  // roll and reel at sixty boards on an iPhone — any moving cell then redraws every cell under
  // it.
  cell.mask = [CAGradientLayer layer];
  cell.mask.anchorPoint = CGPointZero;
  cell.mask.startPoint = CGPointMake(0.5, 0);
  cell.mask.endPoint = CGPointMake(0.5, 1);
  cell.mask.colors = @[
    (__bridge id)[UIColor clearColor].CGColor,
    (__bridge id)[UIColor blackColor].CGColor,
    (__bridge id)[UIColor blackColor].CGColor,
    (__bridge id)[UIColor clearColor].CGColor,
  ];
  cell.mask.locations = @[ @0, @(kSplitflapMaskFade), @(1 - kSplitflapMaskFade), @1 ];
  cell.mask.actions = SplitflapNoActions();
  cell.container.mask = cell.mask;

  cell.glyphA = [CALayer layer];
  cell.glyphB = [CALayer layer];
  cell.glyphC = [CALayer layer];
  cell.glyphD = [CALayer layer];
  for (CALayer *glyphLayer in cell.glyphLayers) {
    glyphLayer.anchorPoint = CGPointZero;
    glyphLayer.actions = SplitflapNoActions();
    [cell.container addSublayer:glyphLayer];
  }
  cell.glyphC.hidden = YES;
  cell.glyphD.hidden = YES;

  [self.layer addSublayer:cell.container];
  return cell;
}

- (void)ensureCellCount:(NSUInteger)count
{
  while (_cells.count < count) {
    [_cells addObject:[self makeCell]];
  }
  while (_cells.count > count) {
    SplitflapCell *cell = _cells.lastObject;
    [cell removeAllAnimations];
    [cell.container removeFromSuperlayer];
    [_cells removeLastObject];
  }
}

/** The drum look of a cell: masked, flat, two full-tile glyph layers. Every renderer starts here. */
- (void)applyAtlas:(SplitflapGlyphAtlas *)atlas toCell:(SplitflapCell *)cell
{
  const CGFloat height = atlas.tileHeight;
  cell.mask.frame = CGRectMake(kSplitflapMaskOrigin, 0, kSplitflapMaskWidth, height);
  cell.container.mask = cell.mask;
  cell.container.sublayerTransform = CATransform3DIdentity;
  for (CALayer *glyphLayer in cell.glyphLayers) {
    glyphLayer.contents = (__bridge id)atlas.image;
    glyphLayer.contentsScale = atlas.scale;
    glyphLayer.contentsGravity = kCAGravityResize;
    glyphLayer.anchorPoint = CGPointZero;
    glyphLayer.bounds = CGRectMake(0, 0, atlas.tileWidth, height);
    glyphLayer.position = CGPointMake(-atlas.padding, glyphLayer.position.y);
    glyphLayer.transform = CATransform3DIdentity;
    glyphLayer.opacity = 1;
    glyphLayer.backgroundColor = nil;
    glyphLayer.doubleSided = YES;
    glyphLayer.hidden = NO;
  }
  cell.glyphC.hidden = YES;
  cell.glyphD.hidden = YES;
}

/**
 * The split-flap look: two static halves (A top, B bottom), two flaps hinged on the middle line
 * (C top, D bottom), perspective from the cell centre, no drum mask (it would fade the flaps).
 */
- (void)configureFlipCell:(SplitflapCell *)cell
                    atlas:(SplitflapGlyphAtlas *)atlas
                    width:(CGFloat)width
                  surface:(UIColor *)surface
{
  const CGFloat height = atlas.tileHeight;
  const CGFloat half = height / 2;
  const CGFloat centreX = -atlas.padding + atlas.tileWidth / 2;
  cell.container.mask = nil;
  cell.container.sublayerTransform = SplitflapPerspective(kSplitflapFlipPerspective, width, height);
  // The halves take the surface colour, so the half a flap covers never shows through and no
  // card is drawn: a tinted card read as a highlighted block of text.
  CGColorRef paint = surface.CGColor;
  for (CALayer *glyphLayer in cell.glyphLayers) {
    glyphLayer.bounds = CGRectMake(0, 0, atlas.tileWidth, half);
    glyphLayer.backgroundColor = paint;
    glyphLayer.hidden = NO;
  }
  cell.glyphA.position = CGPointMake(-atlas.padding, 0);
  cell.glyphB.position = CGPointMake(-atlas.padding, half);
  cell.glyphC.anchorPoint = CGPointMake(0.5, 1);
  cell.glyphC.position = CGPointMake(centreX, half);
  cell.glyphC.doubleSided = NO;
  cell.glyphC.opacity = 0;
  cell.glyphD.anchorPoint = CGPointMake(0.5, 0);
  cell.glyphD.position = CGPointMake(centreX, half);
  cell.glyphD.doubleSided = NO;
  cell.glyphD.opacity = 0;
}

/** A cell at rest on `glyph`, in the drum look or, for a flip board, on its two halves. */
- (void)settleCell:(SplitflapCell *)cell onGlyph:(NSString *)glyph atlas:(SplitflapGlyphAtlas *)atlas flip:(BOOL)flip
{
  const CGRect rect = [atlas contentsRectForGlyph:glyph];
  if (flip) {
    cell.glyphA.contentsRect = SplitflapTopHalf(rect);
    cell.glyphB.contentsRect = SplitflapBottomHalf(rect);
    return;
  }
  cell.glyphA.contentsRect = rect;
  cell.glyphA.position = CGPointMake(-atlas.padding, 0);
  cell.glyphB.contentsRect = [atlas contentsRectForGlyph:@""];
  cell.glyphB.position = CGPointMake(-atlas.padding, -atlas.tileHeight);
}

- (void)emitTransitionStart:(NSString *)text
{
  if (!_eventEmitter) {
    return;
  }
  std::static_pointer_cast<const SplitflapViewEventEmitter>(_eventEmitter)
      ->onTransitionStart({.text = std::string(text.UTF8String ?: "")});
}

- (void)emitTransitionEnd:(NSString *)text interrupted:(BOOL)interrupted
{
  if (!_eventEmitter) {
    return;
  }
  std::static_pointer_cast<const SplitflapViewEventEmitter>(_eventEmitter)
      ->onTransitionEnd({.text = std::string(text.UTF8String ?: ""), .interrupted = static_cast<bool>(interrupted)});
}

- (BOOL)reduceMotion
{
  const auto &props = *std::static_pointer_cast<const SplitflapViewProps>(_props);
  switch (props.reduceMotion) {
    case SplitflapViewReduceMotion::Always:
      return YES;
    case SplitflapViewReduceMotion::Never:
      return NO;
    case SplitflapViewReduceMotion::System:
      return UIAccessibilityIsReduceMotionEnabled();
  }
  return NO;
}

- (void)finishInstantly:(NSString *)text
{
  const NSUInteger generation = ++_generation;
  _inFlight = NO;
  _inFlightText = nil;
  __weak SplitflapView *weakSelf = self;
  dispatch_async(dispatch_get_main_queue(), ^{
    SplitflapView *strongSelf = weakSelf;
    if (strongSelf != nil && strongSelf->_generation == generation) {
      [strongSelf emitTransitionEnd:text interrupted:NO];
    }
  });
}

- (void)interruptIfInFlight
{
  if (!_inFlight) {
    return;
  }
  NSString *text = _inFlightText;
  _inFlight = NO;
  _inFlightText = nil;
  [self emitTransitionEnd:text interrupted:YES];
}

/** The final text with no motion: an unreadable plan, Reduce Motion, or a font change. */
- (void)showTextInstantly:(NSString *)text
{
  [self interruptIfInFlight];
  NSArray<NSString *> *glyphs = [self cellsOfText:text];
  const NSInteger visible = [self visibleGlyphCount];
  if (visible >= 0) {
    glyphs = [[glyphs subarrayWithRange:NSMakeRange(0, visible)] arrayByAddingObject:kSplitflapEllipsis];
  }
  SplitflapGlyphAtlas *atlas = [self atlasForGlyphs:[NSSet setWithArray:glyphs]];
  const BOOL flip = SplitflapRendererFor(_styleTransition) == SplitflapRendererFlip;
  UIColor *surface = flip ? [self surfaceColor] : nil;

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self ensureCellCount:glyphs.count];
  CGFloat x = 0;
  for (NSUInteger i = 0; i < glyphs.count; i++) {
    SplitflapCell *cell = _cells[i];
    [cell removeAllAnimations];
    [self applyAtlas:atlas toCell:cell];
    const CGFloat width = [self settledWidthOfGlyph:glyphs[i] atIndex:i];
    cell.width = width;
    cell.container.bounds = [self cellBoundsWithWidth:width height:atlas.tileHeight];
    cell.container.position = CGPointMake(x, 0);
    if (flip) {
      [self configureFlipCell:cell atlas:atlas width:width surface:surface];
    }
    [self settleCell:cell onGlyph:glyphs[i] atlas:atlas flip:flip];
    x += width;
  }
  [CATransaction commit];
  [self finishInstantly:text];
}

#pragma mark - Drum

- (SplitflapLayerTrack)trackForCell:(SplitflapCellPlan *)cellPlan
                           isLayerA:(BOOL)isLayerA
                             window:(double)window
                             height:(CGFloat)height
                              atlas:(SplitflapGlyphAtlas *)atlas
                       resumeOffset:(CGFloat)resumeOffset
{
  SplitflapLayerTrack track;
  const NSInteger steps = cellPlan.land;
  const double delay = cellPlan.delayMs;
  const double duration = cellPlan.durationMs;
  const NSInteger dir = cellPlan.dir;
  NSArray<NSString *> *path = cellPlan.path;

  auto glyphAt = [&](NSInteger index) -> NSString * {
    return index >= 0 && index < (NSInteger)path.count ? path[index] : @"";
  };
  auto yOf = [&](NSInteger glyphIndex, double s) -> CGFloat { return dir * (glyphIndex - s) * height; };

  const NSInteger firstGlyph = SplitflapGlyphOfLayer(0, isLayerA);
  const CGFloat startY = yOf(firstGlyph, 0) + resumeOffset;
  [track.keyTimesY addObject:@0];
  [track.valuesY addObject:@(startY)];
  [track.keyTimesY addObject:@(delay / window)];
  [track.valuesY addObject:@(startY)];
  [track.keyTimesRect addObject:@0];
  [track.valuesRect addObject:[NSValue valueWithCGRect:[atlas contentsRectForGlyph:glyphAt(firstGlyph)]]];

  CGFloat lastY = startY;
  double lastTime = delay;
  for (NSInteger k = 0; k < steps; k++) {
    const double from = delay + duration * SplitflapEaseInverse(cellPlan.easing, (double)k / steps);
    const double to = delay + duration * SplitflapEaseInverse(cellPlan.easing, (double)(k + 1) / steps);
    const NSInteger glyph = SplitflapGlyphOfLayer(k, isLayerA);
    if (k > 0 && glyph != SplitflapGlyphOfLayer(k - 1, isLayerA)) {
      [track.keyTimesY addObject:@(MIN(1, from / window + kSplitflapKeyTimeEpsilon))];
      [track.valuesY addObject:@(yOf(glyph, k))];
      [track.keyTimesRect addObject:@(from / window)];
      [track.valuesRect addObject:[NSValue valueWithCGRect:[atlas contentsRectForGlyph:glyphAt(glyph)]]];
    }
    const NSInteger samples = (NSInteger)MIN(60, MAX(3, ceil((to - from) / 8)));
    for (NSInteger q = 1; q <= samples; q++) {
      const double t = from + (to - from) * q / samples;
      const double s = steps * SplitflapEase(cellPlan.easing, (t - delay) / duration);
      const CGFloat blend = k == 0 ? resumeOffset * (1 - MIN(1, s)) : 0;
      lastY = yOf(glyph, s) + blend;
      lastTime = t;
      [track.keyTimesY addObject:@(MIN(1, t / window))];
      [track.valuesY addObject:@(lastY)];
    }
  }
  if (lastTime < window) {
    [track.keyTimesY addObject:@1];
    [track.valuesY addObject:@(lastY)];
  }
  [track.keyTimesRect addObject:@1];

  track.finalY = lastY;
  track.finalRect = [track.valuesRect.lastObject CGRectValue];
  return track;
}

- (void)addTrack:(const SplitflapLayerTrack &)track
         toLayer:(CALayer *)layer
          window:(double)window
       beginTime:(CFTimeInterval)beginTime
            loop:(BOOL)loop
{
  CAKeyframeAnimation *y = [CAKeyframeAnimation animationWithKeyPath:@"position.y"];
  y.keyTimes = track.keyTimesY;
  y.values = track.valuesY;
  y.calculationMode = kCAAnimationLinear;
  y.duration = window / 1000;
  y.beginTime = beginTime;
  y.fillMode = kCAFillModeBackwards;
  y.repeatCount = loop ? HUGE_VALF : 0;
  [layer addAnimation:y forKey:@"splitflap.y"];

  if (track.valuesRect.count > 1) {
    CAKeyframeAnimation *rect = [CAKeyframeAnimation animationWithKeyPath:@"contentsRect"];
    rect.keyTimes = track.keyTimesRect;
    rect.values = track.valuesRect;
    rect.calculationMode = kCAAnimationDiscrete;
    rect.duration = window / 1000;
    rect.beginTime = beginTime;
    rect.fillMode = kCAFillModeBackwards;
    rect.repeatCount = loop ? HUGE_VALF : 0;
    [layer addAnimation:rect forKey:@"splitflap.rect"];
  }

  layer.position = CGPointMake(layer.position.x, track.finalY);
  layer.contentsRect = track.finalRect;
}

- (void)playDrumCell:(SplitflapCellPlan *)cellPlan
                cell:(SplitflapCell *)cell
               atlas:(SplitflapGlyphAtlas *)atlas
              window:(double)window
           beginTime:(CFTimeInterval)beginTime
                loop:(BOOL)loop
           presented:(const SplitflapPresented &)presented
{
  const CGFloat height = atlas.tileHeight;
  // An interrupted cell keeps rolling from where its visible glyph is, not from a jump to 0.
  CGFloat resumeOffset = 0;
  NSNumber *presentedY = presented.glyphYs[cellPlan.path[0]];
  if (presentedY != nil && fabs(presentedY.doubleValue) < height) {
    resumeOffset = presentedY.doubleValue;
  }

  const SplitflapLayerTrack trackA = [self trackForCell:cellPlan
                                               isLayerA:YES
                                                 window:window
                                                 height:height
                                                  atlas:atlas
                                           resumeOffset:resumeOffset];
  const SplitflapLayerTrack trackB = [self trackForCell:cellPlan
                                               isLayerA:NO
                                                 window:window
                                                 height:height
                                                  atlas:atlas
                                           resumeOffset:resumeOffset];
  [self addTrack:trackA toLayer:cell.glyphA window:window beginTime:beginTime loop:loop];
  [self addTrack:trackB toLayer:cell.glyphB window:window beginTime:beginTime loop:loop];
}

#pragma mark - Scramble

/**
 * One glyph layer flickers through letters of the target's script every stepMs, dimmed, and locks
 * on the landing glyph at delay + duration. The letters come from a small LCG seeded by the cell
 * index, so a replan shows the same flicker. An empty target fades out instead.
 */
- (void)playScrambleCell:(SplitflapCellPlan *)cellPlan
                    cell:(SplitflapCell *)cell
                   index:(NSUInteger)index
                   atlas:(SplitflapGlyphAtlas *)atlas
                  window:(double)window
               beginTime:(CFTimeInterval)beginTime
                    loop:(BOOL)loop
               presented:(const SplitflapPresented &)presented
{
  cell.container.mask = nil;
  NSString *from = cellPlan.path[0];
  NSString *to = cellPlan.path[cellPlan.land];
  const double delay = cellPlan.delayMs;
  const double lock = delay + cellPlan.durationMs;
  auto rectOf = [&](NSString *glyph) -> NSValue * {
    return [NSValue valueWithCGRect:[atlas contentsRectForGlyph:glyph]];
  };

  SplitflapTrack rect(window, YES);
  if (to.length == 0) {
    SplitflapTrack opacity(window, NO);
    rect.add(0, rectOf(from));
    opacity.add(0, @1);
    opacity.add(delay, @1);
    opacity.add(lock, @0);
    rect.add(lock, rectOf(@""));
    rect.addTo(cell.glyphA, @"contentsRect", beginTime, loop);
    opacity.addTo(cell.glyphA, @"opacity", beginTime, loop);
  } else {
    SplitflapTrack opacity(window, YES);
    NSArray<NSString *> *letters = cellPlan.letters.count > 0 ? cellPlan.letters : @[ to ];
    const double start = presented.dimmed ? 0 : delay;
    if (start > 0) {
      rect.add(0, rectOf(from));
      opacity.add(0, @1);
    }
    opacity.add(start, @(kSplitflapScrambleDim));
    uint32_t state = 0x9E3779B9u ^ (uint32_t)(index + 1) * 0x85EBCA6Bu;
    NSInteger count = 0;
    for (double t = start; t < lock && count < kSplitflapScrambleMaxSteps; t += cellPlan.stepMs, count++) {
      state = state * 1664525u + 1013904223u;
      rect.add(t, rectOf(letters[(state >> 8) % letters.count]));
    }
    rect.add(lock, rectOf(to));
    opacity.add(lock, @1);
    rect.addTo(cell.glyphA, @"contentsRect", beginTime, loop);
    opacity.addTo(cell.glyphA, @"opacity", beginTime, loop);
  }
  [self settleCell:cell onGlyph:to atlas:atlas flip:NO];
}

#pragma mark - Flip

/**
 * Per step of the path: A shows the NEXT glyph's top half, B the CURRENT glyph's bottom half; the
 * top flap C (current, top half) folds 0 → 90° about the hinge in the first half of the step,
 * then the bottom flap D (next, bottom half) drops 90° → 0 in the second half. A flap caught
 * mid-fold by an interruption continues from its presented angle.
 */
- (void)playFlipCell:(SplitflapCellPlan *)cellPlan
                cell:(SplitflapCell *)cell
               atlas:(SplitflapGlyphAtlas *)atlas
              window:(double)window
           beginTime:(CFTimeInterval)beginTime
                loop:(BOOL)loop
           presented:(const SplitflapPresented &)presented
{
  const NSInteger steps = cellPlan.land;
  const double delay = cellPlan.delayMs;
  const double duration = cellPlan.durationMs;
  NSArray<NSString *> *path = cellPlan.path;
  auto glyphAt = [&](NSInteger i) -> NSString * { return i >= 0 && i < (NSInteger)path.count ? path[i] : @""; };
  auto top = [&](NSInteger i) -> NSValue * {
    return [NSValue valueWithCGRect:SplitflapTopHalf([atlas contentsRectForGlyph:glyphAt(i)])];
  };
  auto bottom = [&](NSInteger i) -> NSValue * {
    return [NSValue valueWithCGRect:SplitflapBottomHalf([atlas contentsRectForGlyph:glyphAt(i)])];
  };
  const double folded = kSplitflapFlapFold * M_PI_2;
  const double raised = -kSplitflapFlapFold * M_PI_2;

  const BOOL resumeTop = !std::isnan(presented.topAngle) && [presented.topGlyph isEqualToString:path[0]] &&
      presented.topAngle * kSplitflapFlapFold > 0 && fabs(presented.topAngle) < M_PI_2;
  const BOOL resumeBottom = !resumeTop && !std::isnan(presented.bottomAngle) &&
      [presented.bottomGlyph isEqualToString:path[0]] && presented.bottomAngle * kSplitflapFlapFold < 0 &&
      fabs(presented.bottomAngle) < M_PI_2;

  SplitflapTrack aRect(window, YES), bRect(window, YES), cRect(window, YES), dRect(window, YES);
  SplitflapTrack cOpacity(window, YES), dOpacity(window, YES);
  SplitflapTrack cAngle(window, NO), dAngle(window, NO);

  aRect.add(0, top(resumeTop ? 1 : 0));
  bRect.add(0, bottom(0));
  cRect.add(0, top(0));
  cOpacity.add(0, @(resumeTop ? 1 : 0));
  cAngle.add(0, @(resumeTop ? presented.topAngle : 0));
  dRect.add(0, bottom(0));
  dOpacity.add(0, @(resumeBottom ? 1 : 0));
  dAngle.add(0, @(resumeBottom ? presented.bottomAngle : raised));

  for (NSInteger k = 0; k < steps; k++) {
    const double from = delay + duration * SplitflapEaseInverse(cellPlan.easing, (double)k / steps);
    const double to = delay + duration * SplitflapEaseInverse(cellPlan.easing, (double)(k + 1) / steps);
    const double mid = (from + to) / 2;

    aRect.add(from, top(k + 1));
    bRect.add(from, bottom(k));

    cRect.add(from, top(k));
    cOpacity.add(from, @1);
    cAngle.add(from, @(k == 0 && resumeTop ? presented.topAngle : 0));
    cAngle.add(mid, @(folded));
    cOpacity.add(mid, @0);
    cAngle.add(mid, @0);

    if (k == 0 && resumeBottom) {
      // The previous plan's bottom flap lands while this plan's top flap already falls.
      dRect.add(from, bottom(0));
      dOpacity.add(from, @1);
      dAngle.add(from, @(presented.bottomAngle));
      dAngle.add(mid, @0);
      dRect.add(mid, bottom(1));
      dAngle.add(mid, @(raised));
    } else {
      dRect.add(from, bottom(k + 1));
      dOpacity.add(from, @0);
      dAngle.add(from, @(raised));
      dOpacity.add(mid, @1);
      dAngle.add(mid, @(raised));
    }
    dAngle.add(to, @0);
    dOpacity.add(to, @0);
  }
  bRect.add(delay + duration, bottom(steps));

  aRect.addTo(cell.glyphA, @"contentsRect", beginTime, loop);
  bRect.addTo(cell.glyphB, @"contentsRect", beginTime, loop);
  cRect.addTo(cell.glyphC, @"contentsRect", beginTime, loop);
  cOpacity.addTo(cell.glyphC, @"opacity", beginTime, loop);
  cAngle.addTo(cell.glyphC, @"transform.rotation.x", beginTime, loop);
  dRect.addTo(cell.glyphD, @"contentsRect", beginTime, loop);
  dOpacity.addTo(cell.glyphD, @"opacity", beginTime, loop);
  dAngle.addTo(cell.glyphD, @"transform.rotation.x", beginTime, loop);

  [self settleCell:cell onGlyph:glyphAt(steps) atlas:atlas flip:YES];
  cell.glyphC.contentsRect = [cRect.last() CGRectValue];
  cell.glyphD.contentsRect = [dRect.last() CGRectValue];
}

#pragma mark - Plan

- (std::vector<SplitflapPresented>)capturePresentedForRenderer:(SplitflapRenderer)renderer
{
  std::vector<SplitflapPresented> presented(_cells.count);
  const BOOL sameRenderer = _inFlightRenderer == renderer;
  for (NSUInteger i = 0; i < _cells.count; i++) {
    SplitflapCell *cell = _cells[i];
    SplitflapPresented &state = presented[i];
    CALayer *container = cell.container.presentationLayer ?: cell.container;
    state.width = container.bounds.size.width;
    state.hasWidth = YES;
    if (!sameRenderer) {
      continue;
    }
    switch (renderer) {
      case SplitflapRendererDrum:
        for (CALayer *glyphLayer in @[ cell.glyphA, cell.glyphB ]) {
          CALayer *layer = glyphLayer.presentationLayer ?: glyphLayer;
          NSString *glyph = [_atlas glyphForContentsRect:layer.contentsRect];
          if (glyph != nil && state.glyphYs[glyph] == nil) {
            state.glyphYs[glyph] = @(layer.position.y);
          }
        }
        break;
      case SplitflapRendererFlip: {
        CALayer *top = cell.glyphC.presentationLayer ?: cell.glyphC;
        if (top.opacity > 0.5) {
          state.topGlyph = [_atlas glyphForContentsRect:top.contentsRect];
          state.topAngle = SplitflapRotationX(top.transform);
        }
        CALayer *bottom = cell.glyphD.presentationLayer ?: cell.glyphD;
        if (bottom.opacity > 0.5) {
          state.bottomGlyph = [_atlas glyphForContentsRect:bottom.contentsRect];
          state.bottomAngle = SplitflapRotationX(bottom.transform);
        }
        break;
      }
      case SplitflapRendererScramble: {
        CALayer *layer = cell.glyphA.presentationLayer ?: cell.glyphA;
        state.dimmed = layer.opacity < 1;
        break;
      }
    }
  }
  return presented;
}

- (void)playPlan:(SplitflapPlan *)plan text:(NSString *)text
{
  const SplitflapRenderer renderer = SplitflapRendererFor(plan.transition);
  const BOOL flip = renderer == SplitflapRendererFlip;
  std::vector<SplitflapPresented> presented;
  if (_inFlight && _atlas != nil) {
    presented = [self capturePresentedForRenderer:renderer];
  }
  [self interruptIfInFlight];
  _generation++;

  const NSInteger visible = [self visibleGlyphCount];
  if (visible >= 0) {
    plan = [plan planTruncatedTo:visible + 1 endingWith:kSplitflapEllipsis];
  }

  NSMutableSet<NSString *> *glyphSet = [NSMutableSet setWithArray:[self cellsOfText:text]];
  for (SplitflapCellPlan *cellPlan in plan.cells) {
    [glyphSet addObjectsFromArray:cellPlan.path];
    if (renderer == SplitflapRendererScramble && cellPlan.to.length > 0 && cellPlan.land > 0) {
      [glyphSet addObjectsFromArray:cellPlan.letters];
    }
  }
  SplitflapGlyphAtlas *atlas = [self atlasForGlyphs:glyphSet];
  const CGFloat height = atlas.tileHeight;
  const NSUInteger count = plan.cells.count;
  UIColor *surface = flip ? [self surfaceColor] : nil;

  double window = [self reduceMotion] ? 0 : plan.totalMs;
  if (window > 0) {
    for (SplitflapCellPlan *cellPlan in plan.cells) {
      window = MAX(window, cellPlan.delayMs + cellPlan.durationMs * kSplitflapWidthWindow);
    }
  }

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self ensureCellCount:count];

  std::vector<CGFloat> startWidths(count);
  std::vector<CGFloat> targetWidths(count);
  for (NSUInteger i = 0; i < count; i++) {
    SplitflapCellPlan *cellPlan = plan.cells[i];
    const BOOL hasPresented = i < presented.size() && presented[i].hasWidth;
    startWidths[i] = hasPresented ? presented[i].width : _cells[i].width;
    targetWidths[i] = [self settledWidthOfGlyph:cellPlan.path[cellPlan.land] atIndex:i];
  }
  // `stable` and `uniform`: the widest glyph on each cell's way, held while the glyphs turn. A
  // scramble cell's way is the letters it flickers through, which the plan does not list.
  // `tiered` holds only the wider of its two ends: a roll through «m» would otherwise widen a
  // narrow cell on every turn, and the cell clips what passes.
  const auto cellWidthMode = std::static_pointer_cast<const SplitflapViewProps>(_props)->cellWidth;
  const BOOL tiered = cellWidthMode == SplitflapViewCellWidth::Tiered;
  const BOOL stable = cellWidthMode == SplitflapViewCellWidth::Stable ||
      cellWidthMode == SplitflapViewCellWidth::Uniform || tiered;
  std::vector<CGFloat> holdWidths(count);
  if (stable) {
    for (NSUInteger i = 0; i < count; i++) {
      SplitflapCellPlan *cellPlan = plan.cells[i];
      CGFloat widest = MAX(startWidths[i], targetWidths[i]);
      if (tiered) {
        holdWidths[i] = widest;
        continue;
      }
      for (NSString *glyph in cellPlan.path) {
        widest = MAX(widest, [atlas advanceForGlyph:glyph]);
      }
      if (renderer == SplitflapRendererScramble && cellPlan.to.length > 0 && cellPlan.land > 0) {
        for (NSString *glyph in cellPlan.letters) {
          widest = MAX(widest, [atlas advanceForGlyph:glyph]);
        }
      }
      holdWidths[i] = widest;
    }
  }
  auto widthAt = [&](NSUInteger i, double t) -> CGFloat {
    SplitflapCellPlan *cellPlan = plan.cells[i];
    if (stable) {
      // Opens to the hold width in the first sixth of the turn, holds while the glyphs move, and
      // narrows to the landed glyph in the tail after they stop.
      const double start = cellPlan.delayMs;
      const double open = cellPlan.durationMs / 6;
      const double land = start + cellPlan.durationMs;
      const double close = land + cellPlan.durationMs * (kSplitflapWidthWindow - 1);
      if (t <= start || cellPlan.durationMs <= 0) {
        return t <= start ? startWidths[i] : targetWidths[i];
      }
      if (t < start + open) {
        const double p = SplitflapEase(SplitflapEasingInOut, (t - start) / open);
        return startWidths[i] + (holdWidths[i] - startWidths[i]) * p;
      }
      if (t < land) {
        return holdWidths[i];
      }
      if (t >= close) {
        return targetWidths[i];
      }
      const double p = SplitflapEase(SplitflapEasingInOut, (t - land) / (close - land));
      return holdWidths[i] + (targetWidths[i] - holdWidths[i]) * p;
    }
    const double span = cellPlan.durationMs * kSplitflapWidthWindow;
    if (t < cellPlan.delayMs) {
      return startWidths[i];
    }
    if (span <= 0 || t >= cellPlan.delayMs + span) {
      return targetWidths[i];
    }
    const double p = SplitflapEase(SplitflapEasingInOut, (t - cellPlan.delayMs) / span);
    return startWidths[i] + (targetWidths[i] - startWidths[i]) * p;
  };

  if (window > 0) {
    const NSUInteger generation = _generation;
    __weak SplitflapView *weakSelf = self;
    [CATransaction setCompletionBlock:^{
      SplitflapView *strongSelf = weakSelf;
      if (strongSelf == nil || strongSelf->_generation != generation) {
        return;
      }
      strongSelf->_inFlight = NO;
      strongSelf->_inFlightText = nil;
      [strongSelf emitTransitionEnd:text interrupted:NO];
    }];
  }

  const CFTimeInterval beginTime = CACurrentMediaTime();
  const NSUInteger sampleCount =
      MIN(kSplitflapMaxSamples, (NSUInteger)MAX(2.0, ceil(window / 1000 * kSplitflapSampleHz) + 1));
  BOOL anyWidthChanges = NO;
  CGFloat finalX = 0;
  // Where the word's left edge is drawn at `t`, against the new frame: where the old word stood,
  // moving to 0 as the content takes the new width, around the parent's anchor (_frameAnchor).
  const BOOL carried = _frameMoved && window > 0;
  auto contentAt = [&](double t) {
    CGFloat sum = 0;
    for (NSUInteger j = 0; j < count; j++) {
      sum += widthAt(j, t);
    }
    return sum;
  };
  const CGFloat startContent = carried ? contentAt(0) : 0;
  const CGFloat shift = _frameShift;
  const CGFloat anchor = _frameAnchor;
  auto offsetAt = [&](double t) -> CGFloat {
    return carried ? shift - anchor * (contentAt(t) - startContent) : 0;
  };
  SplitflapPresented nothingPresented;

  for (NSUInteger i = 0; i < count; i++) {
    SplitflapCellPlan *cellPlan = plan.cells[i];
    SplitflapCell *cell = _cells[i];
    [cell removeAllAnimations];
    [self applyAtlas:atlas toCell:cell];

    const BOOL widthChanges = startWidths[i] != targetWidths[i] || (stable && holdWidths[i] != targetWidths[i]);
    if (window > 0 && (widthChanges || anyWidthChanges || carried)) {
      NSMutableArray<NSNumber *> *keyTimes = [NSMutableArray arrayWithCapacity:sampleCount];
      NSMutableArray<NSValue *> *bounds = [NSMutableArray arrayWithCapacity:sampleCount];
      NSMutableArray<NSNumber *> *xs = [NSMutableArray arrayWithCapacity:sampleCount];
      for (NSUInteger q = 0; q < sampleCount; q++) {
        const double t = window * q / (sampleCount - 1);
        CGFloat x = offsetAt(t);
        for (NSUInteger j = 0; j < i; j++) {
          x += widthAt(j, t);
        }
        [keyTimes addObject:@((double)q / (sampleCount - 1))];
        [bounds addObject:[NSValue valueWithCGRect:[self cellBoundsWithWidth:widthAt(i, t) height:height]]];
        [xs addObject:@(x)];
      }
      if (widthChanges) {
        CAKeyframeAnimation *boundsAnimation = [CAKeyframeAnimation animationWithKeyPath:@"bounds"];
        boundsAnimation.keyTimes = keyTimes;
        boundsAnimation.values = bounds;
        boundsAnimation.calculationMode = kCAAnimationLinear;
        boundsAnimation.duration = window / 1000;
        boundsAnimation.beginTime = beginTime;
        boundsAnimation.fillMode = kCAFillModeBackwards;
        boundsAnimation.repeatCount = plan.loop ? HUGE_VALF : 0;
        [cell.container addAnimation:boundsAnimation forKey:@"splitflap.bounds"];
      }
      if (anyWidthChanges || carried) {
        CAKeyframeAnimation *xAnimation = [CAKeyframeAnimation animationWithKeyPath:@"position.x"];
        xAnimation.keyTimes = keyTimes;
        xAnimation.values = xs;
        xAnimation.calculationMode = kCAAnimationLinear;
        xAnimation.duration = window / 1000;
        xAnimation.beginTime = beginTime;
        xAnimation.fillMode = kCAFillModeBackwards;
        xAnimation.repeatCount = plan.loop ? HUGE_VALF : 0;
        [cell.container addAnimation:xAnimation forKey:@"splitflap.x"];
      }
    }
    anyWidthChanges = anyWidthChanges || widthChanges;
    cell.width = targetWidths[i];
    cell.container.bounds = [self cellBoundsWithWidth:targetWidths[i] height:height];
    cell.container.position = CGPointMake(finalX, 0);
    finalX += targetWidths[i];

    if (flip) {
      [self configureFlipCell:cell atlas:atlas width:targetWidths[i] surface:surface];
    }

    const NSInteger steps = cellPlan.land;
    if (window == 0 || steps == 0 || cellPlan.durationMs <= 0) {
      [self settleCell:cell onGlyph:cellPlan.path[steps] atlas:atlas flip:flip];
      continue;
    }

    const SplitflapPresented &cellPresented = i < presented.size() ? presented[i] : nothingPresented;
    switch (renderer) {
      case SplitflapRendererScramble:
        [self playScrambleCell:cellPlan
                          cell:cell
                         index:i
                         atlas:atlas
                        window:window
                     beginTime:beginTime
                          loop:plan.loop
                     presented:cellPresented];
        break;
      case SplitflapRendererFlip:
        [self playFlipCell:cellPlan
                      cell:cell
                     atlas:atlas
                    window:window
                 beginTime:beginTime
                      loop:plan.loop
                 presented:cellPresented];
        break;
      case SplitflapRendererDrum:
        [self playDrumCell:cellPlan
                      cell:cell
                     atlas:atlas
                    window:window
                 beginTime:beginTime
                      loop:plan.loop
                 presented:cellPresented];
        break;
    }
  }

  [CATransaction commit];

  if (window > 0) {
    _inFlight = YES;
    _inFlightText = text;
    _inFlightRenderer = renderer;
    [self emitTransitionStart:text];
  } else {
    [self finishInstantly:text];
  }
}

@end

Class<RCTComponentViewProtocol> SplitflapViewCls(void)
{
  return SplitflapView.class;
}

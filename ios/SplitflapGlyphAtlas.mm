#import "SplitflapGlyphAtlas.h"

static const NSUInteger kSplitflapAtlasBudgetBytes = 8 * 1024 * 1024;
static const CGFloat kSplitflapAtlasMaxRowWidth = 2048;

@interface SplitflapGlyphAtlas ()
@property (nonatomic, readonly) NSString *cacheKey;
@property (nonatomic, readonly) NSUInteger bytes;
@property (nonatomic, readonly) NSSet<NSString *> *glyphs;
@end

@implementation SplitflapGlyphAtlas {
  NSDictionary<NSString *, NSValue *> *_rects;
  NSDictionary<NSString *, NSNumber *> *_advances;
  NSDictionary<NSValue *, NSString *> *_glyphsByRect;
}

static NSMutableDictionary<NSString *, SplitflapGlyphAtlas *> *gAtlases;
static NSMutableArray<NSString *> *gAtlasOrder;

+ (void)initialize
{
  if (self != [SplitflapGlyphAtlas class]) {
    return;
  }
  gAtlases = [NSMutableDictionary new];
  gAtlasOrder = [NSMutableArray new];
  [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification
                                                    object:nil
                                                     queue:[NSOperationQueue mainQueue]
                                                usingBlock:^(NSNotification *__unused note) {
                                                  [SplitflapGlyphAtlas clearCache];
                                                }];
}

+ (void)clearCache
{
  [gAtlases removeAllObjects];
  [gAtlasOrder removeAllObjects];
}

static NSString *SplitflapColorKey(UIColor *color)
{
  CGFloat r = 0, g = 0, b = 0, a = 1;
  [color getRed:&r green:&g blue:&b alpha:&a];
  return [NSString stringWithFormat:@"%.3f,%.3f,%.3f,%.3f", r, g, b, a];
}

+ (instancetype)atlasWithFont:(UIFont *)font
                        color:(UIColor *)color
                letterSpacing:(CGFloat)letterSpacing
                   lineHeight:(CGFloat)lineHeight
                        scale:(CGFloat)scale
                  centreWidth:(CGFloat)centreWidth
                       glyphs:(NSSet<NSString *> *)glyphs
{
  // The descriptor's attributes carry the font features (tabular digits): the same font name with
  // and without them draws different advances, so they belong in the key.
  NSString *key = [NSString stringWithFormat:@"%@|%lu|%.2f|%@|%.2f|%.2f|%.1f|%.2f",
                                             font.fontName,
                                             (unsigned long)font.fontDescriptor.fontAttributes.description.hash,
                                             font.pointSize,
                                             SplitflapColorKey(color),
                                             letterSpacing,
                                             lineHeight,
                                             scale,
                                             centreWidth];
  SplitflapGlyphAtlas *cached = gAtlases[key];
  NSMutableSet<NSString *> *wanted = [glyphs mutableCopy];
  [wanted addObject:@""];
  if (cached != nil) {
    [gAtlasOrder removeObject:key];
    [gAtlasOrder addObject:key];
    if ([wanted isSubsetOfSet:cached.glyphs]) {
      return cached;
    }
    [wanted unionSet:cached.glyphs];
  }

  SplitflapGlyphAtlas *atlas = [[SplitflapGlyphAtlas alloc] initWithFont:font
                                                                   color:color
                                                           letterSpacing:letterSpacing
                                                              lineHeight:lineHeight
                                                                   scale:scale
                                                             centreWidth:centreWidth
                                                                  glyphs:wanted
                                                                     key:key];
  [gAtlasOrder removeObject:key];
  [gAtlasOrder addObject:key];
  gAtlases[key] = atlas;
  [self evictToBudget];
  return atlas;
}

+ (void)evictToBudget
{
  NSUInteger total = 0;
  for (SplitflapGlyphAtlas *atlas in gAtlases.allValues) {
    total += atlas.bytes;
  }
  while (total > kSplitflapAtlasBudgetBytes && gAtlasOrder.count > 1) {
    NSString *oldest = gAtlasOrder.firstObject;
    total -= gAtlases[oldest].bytes;
    [gAtlases removeObjectForKey:oldest];
    [gAtlasOrder removeObjectAtIndex:0];
  }
}

- (instancetype)initWithFont:(UIFont *)font
                       color:(UIColor *)color
               letterSpacing:(CGFloat)letterSpacing
                  lineHeight:(CGFloat)lineHeight
                       scale:(CGFloat)scale
                 centreWidth:(CGFloat)centreWidth
                      glyphs:(NSSet<NSString *> *)glyphs
                         key:(NSString *)key
{
  if (!(self = [super init])) {
    return nil;
  }
  _cacheKey = key;
  _scale = scale;
  _glyphs = [glyphs copy];
  _padding = ceil(font.pointSize * 0.25);
  _tileHeight = lineHeight > 0 ? lineHeight : ceil(font.lineHeight);

  NSDictionary<NSAttributedStringKey, id> *attributes = @{
    NSFontAttributeName : font,
    NSForegroundColorAttributeName : color,
    NSKernAttributeName : @(letterSpacing),
  };

  NSArray<NSString *> *ordered = [glyphs.allObjects sortedArrayUsingSelector:@selector(compare:)];
  NSMutableDictionary<NSString *, NSNumber *> *advances = [NSMutableDictionary new];
  CGFloat widest = 0;
  for (NSString *glyph in ordered) {
    CGFloat advance = glyph.length == 0 ? 0 : [glyph sizeWithAttributes:attributes].width;
    advances[glyph] = @(advance);
    widest = MAX(widest, advance);
  }
  // A uniform board centres every glyph in its cell: the tile's content is the cell width, and the
  // glyph is drawn in the middle of it, so the layers need no offset of their own.
  const CGFloat content = MAX(widest, centreWidth);
  _tileWidth = ceil(content) + 2 * _padding;

  NSUInteger perRow = MAX(1, (NSUInteger)floor(kSplitflapAtlasMaxRowWidth / _tileWidth));
  NSUInteger rows = (ordered.count + perRow - 1) / perRow;
  CGSize imageSize = CGSizeMake(_tileWidth * MIN(perRow, ordered.count), _tileHeight * rows);

  // RN centers a glyph inside a lineHeight taller than the font (RCTApplyBaselineOffset).
  CGFloat topOffset = _tileHeight > font.lineHeight ? (_tileHeight - font.lineHeight) / 2 : 0;

  NSMutableDictionary<NSString *, NSValue *> *rects = [NSMutableDictionary new];
  NSMutableDictionary<NSValue *, NSString *> *glyphsByRect = [NSMutableDictionary new];
  UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
  format.scale = scale;
  format.opaque = NO;
  UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:imageSize format:format];
  UIImage *image = [renderer imageWithActions:^(UIGraphicsImageRendererContext *__unused context) {
    NSUInteger index = 0;
    for (NSString *glyph in ordered) {
      CGFloat x = (index % perRow) * self->_tileWidth;
      CGFloat y = (index / perRow) * self->_tileHeight;
      if (glyph.length > 0) {
        const CGFloat inset = centreWidth > 0 ? (content - advances[glyph].doubleValue) / 2 : 0;
        [glyph drawAtPoint:CGPointMake(x + self->_padding + inset, y + topOffset) withAttributes:attributes];
      }
      CGRect rect = CGRectMake(x / imageSize.width,
                               y / imageSize.height,
                               self->_tileWidth / imageSize.width,
                               self->_tileHeight / imageSize.height);
      rects[glyph] = [NSValue valueWithCGRect:rect];
      glyphsByRect[[NSValue valueWithCGRect:rect]] = glyph;
      index++;
    }
  }];

  _image = CGImageRetain(image.CGImage);
  _rects = rects;
  _advances = advances;
  _glyphsByRect = glyphsByRect;
  _bytes = (NSUInteger)(imageSize.width * scale * imageSize.height * scale * 4);
  return self;
}

- (void)dealloc
{
  CGImageRelease(_image);
}

- (BOOL)hasGlyph:(NSString *)glyph
{
  return _rects[glyph] != nil;
}

- (CGRect)contentsRectForGlyph:(NSString *)glyph
{
  NSValue *rect = _rects[glyph] ?: _rects[@""];
  return rect.CGRectValue;
}

- (CGFloat)advanceForGlyph:(NSString *)glyph
{
  return _advances[glyph].doubleValue;
}

- (NSString *)glyphForContentsRect:(CGRect)rect
{
  NSString *exact = _glyphsByRect[[NSValue valueWithCGRect:rect]];
  if (exact != nil) {
    return exact;
  }
  // A presentation layer's rect comes back through float storage; match the tile it lies in.
  for (NSValue *key in _glyphsByRect) {
    CGRect tile = key.CGRectValue;
    if (fabs(CGRectGetMidX(tile) - CGRectGetMidX(rect)) < tile.size.width / 2 &&
        fabs(CGRectGetMidY(tile) - CGRectGetMidY(rect)) < tile.size.height / 2) {
      return _glyphsByRect[key];
    }
  }
  return nil;
}

@end

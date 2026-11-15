#import "PSOUI.h"

#import <CoreText/CoreText.h>

#include <cmath>
#include <cstdlib>

// ---- Fonts, colours, text ----------------------------------------------------------

static NSString* RegisteredFontName()
{
  static NSString* name = nil;
  static dispatch_once_t once;
  dispatch_once(&once, ^{
    NSURL* url = [NSBundle.mainBundle URLForResource:@"Baloo2-SemiBold" withExtension:@"ttf" subdirectory:@"fonts"];
    if (!url)
      return;
    CTFontManagerRegisterFontsForURL((__bridge CFURLRef)url, kCTFontManagerScopeProcess, nullptr);
    CFArrayRef descriptors = CTFontManagerCreateFontDescriptorsFromURL((__bridge CFURLRef)url);
    if (descriptors && CFArrayGetCount(descriptors) > 0)
    {
      CTFontDescriptorRef d = (CTFontDescriptorRef)CFArrayGetValueAtIndex(descriptors, 0);
      name = CFBridgingRelease(CTFontDescriptorCopyAttribute(d, kCTFontNameAttribute));
    }
    if (descriptors)
      CFRelease(descriptors);
  });
  return name;
}

UIFont* PSOFont(CGFloat size)
{
  NSString* name = RegisteredFontName();
  UIFont* font = name ? [UIFont fontWithName:name size:size] : nil;
  if (font)
    return font;
  UIFont* system = [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
  UIFontDescriptor* rounded = [system.fontDescriptor fontDescriptorWithDesign:UIFontDescriptorSystemDesignRounded];
  return rounded ? [UIFont fontWithDescriptor:rounded size:size] : system;
}

UIColor* PSOColor(int r, int g, int b, int a)
{
  return [UIColor colorWithRed:r / 255.0 green:g / 255.0 blue:b / 255.0 alpha:a / 255.0];
}

UIImage* PSOTextImage(NSString* text, UIFont* font, UIColor* top, UIColor* bottom, CGFloat shadow)
{
  if (text.length == 0)
    return nil;
  NSDictionary* attrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : UIColor.whiteColor};
  const CGSize textSize = [text sizeWithAttributes:attrs];
  const CGSize size = CGSizeMake(ceil(textSize.width + shadow + 2), ceil(textSize.height + shadow + 2));

  UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
  format.opaque = NO;

  // The text filled with the gradient: draw it, then paint the gradient "source in".
  UIImage* fill = [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
      imageWithActions:^(UIGraphicsImageRendererContext* rc) {
        [text drawAtPoint:CGPointZero withAttributes:attrs];
        CGContextRef ctx = rc.CGContext;
        CGContextSetBlendMode(ctx, kCGBlendModeSourceIn);
        NSArray* colors = @[ (id)top.CGColor, (id)bottom.CGColor ];
        CGGradientRef g = CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)colors, nullptr);
        const CGFloat y0 = textSize.height * 0.25, y1 = textSize.height * 0.8;
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, y0), CGPointMake(0, y1),
                                    kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(g);
      }];

  return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
      imageWithActions:^(UIGraphicsImageRendererContext* rc) {
        if (shadow > 0)
        {
          NSDictionary* sattrs = @{NSFontAttributeName : font, NSForegroundColorAttributeName : PSOColor(4, 8, 30, 110)};
          [text drawAtPoint:CGPointMake(shadow, shadow) withAttributes:sattrs];
          [text drawAtPoint:CGPointMake(shadow * 0.5, shadow * 0.5) withAttributes:sattrs];
        }
        [fill drawAtPoint:CGPointZero];
      }];
}

// ---- Background ----------------------------------------------------------------------

static void RadialGlow(CGContextRef ctx, CGPoint c, CGFloat r, UIColor* inner, UIColor* outer)
{
  NSArray* colors = @[ (id)inner.CGColor, (id)outer.CGColor ];
  CGGradientRef g = CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)colors, nullptr);
  CGContextDrawRadialGradient(ctx, g, c, 0, c, r, 0);
  CGGradientRelease(g);
}

static UIImage* GeneratedBackground(CGSize size)
{
  const CGFloat w = size.width, h = size.height;
  UIGraphicsImageRendererFormat* format = [UIGraphicsImageRendererFormat preferredFormat];
  format.opaque = YES;
  return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format]
      imageWithActions:^(UIGraphicsImageRendererContext* rc) {
        CGContextRef ctx = rc.CGContext;

        // Deep space, bluer toward the bottom right.
        NSArray* sky = @[ (id)PSOColor(6, 9, 30, 255).CGColor, (id)PSOColor(14, 26, 74, 255).CGColor,
                          (id)PSOColor(28, 56, 120, 255).CGColor ];
        const CGFloat skyStops[] = {0, 0.55, 1};
        CGGradientRef g = CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)sky, skyStops);
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, 0), CGPointMake(w, h), 0);
        CGGradientRelease(g);

        // Nebula haze.
        RadialGlow(ctx, CGPointMake(w * 0.30, h * 0.20), h * 0.9, PSOColor(70, 40, 140, 70), PSOColor(70, 40, 140, 0));
        RadialGlow(ctx, CGPointMake(w * 0.62, h * 0.35), h * 0.7, PSOColor(30, 120, 170, 60), PSOColor(30, 120, 170, 0));

        // Stars (fixed seed: the same sky every time).
        srand48(1337);
        for (int i = 0; i < 260; ++i)
        {
          const CGFloat x = drand48() * w, y = drand48() * h;
          const CGFloat r = 0.3 + pow(drand48(), 3) * 1.6;
          const CGFloat a = 0.25 + drand48() * 0.7;
          CGContextSetFillColorWithColor(ctx, [UIColor colorWithRed:0.85 green:0.9 blue:1 alpha:a].CGColor);
          CGContextFillEllipseInRect(ctx, CGRectMake(x - r, y - r, 2 * r, 2 * r));
          if (r > 1.3)
            RadialGlow(ctx, CGPointMake(x, y), r * 5, PSOColor(180, 210, 255, 60), PSOColor(180, 210, 255, 0));
        }

        // A distant sun, upper right.
        RadialGlow(ctx, CGPointMake(w * 0.93, h * 0.08), h * 0.55, PSOColor(255, 220, 160, 110),
                   PSOColor(255, 200, 120, 0));
        RadialGlow(ctx, CGPointMake(w * 0.93, h * 0.08), h * 0.06, PSOColor(255, 250, 235, 255),
                   PSOColor(255, 240, 200, 0));

        // A planet rising from the lower right, lit from the sun.
        const CGPoint pc = CGPointMake(w * 0.80, h * 1.18);
        const CGFloat pr = h * 0.82;
        RadialGlow(ctx, pc, pr * 1.16, PSOColor(90, 190, 255, 90), PSOColor(90, 190, 255, 0));  // atmosphere
        CGContextSaveGState(ctx);
        CGContextAddEllipseInRect(ctx, CGRectMake(pc.x - pr, pc.y - pr, 2 * pr, 2 * pr));
        CGContextClip(ctx);
        NSArray* land = @[ (id)PSOColor(92, 178, 170, 255).CGColor, (id)PSOColor(36, 96, 110, 255).CGColor,
                           (id)PSOColor(8, 22, 40, 255).CGColor ];
        const CGFloat landStops[] = {0, 0.45, 1};
        g = CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)land, landStops);
        const CGPoint lit = CGPointMake(pc.x + pr * 0.35, pc.y - pr * 0.75);
        CGContextDrawRadialGradient(ctx, g, lit, 0, pc, pr * 1.05, kCGGradientDrawsAfterEndLocation);
        CGGradientRelease(g);
        // Cloud bands.
        srand48(7);
        for (int i = 0; i < 14; ++i)
        {
          const CGFloat y = pc.y - pr * (0.2 + drand48() * 0.8);
          const CGFloat bw = pr * (0.6 + drand48() * 0.9), bh = pr * (0.02 + drand48() * 0.04);
          const CGFloat x = pc.x - bw / 2 + (drand48() - 0.5) * pr * 0.8;
          CGContextSetFillColorWithColor(ctx, [UIColor colorWithWhite:1 alpha:0.05 + drand48() * 0.08].CGColor);
          CGContextFillEllipseInRect(ctx, CGRectMake(x, y, bw, bh));
        }
        CGContextRestoreGState(ctx);
        // Thin bright rim on the lit edge.
        CGContextSetStrokeColorWithColor(ctx, PSOColor(170, 230, 255, 120).CGColor);
        CGContextSetLineWidth(ctx, 1.5);
        CGContextStrokeEllipseInRect(ctx, CGRectMake(pc.x - pr, pc.y - pr, 2 * pr, 2 * pr));

        // Darken the left side, where the menu text sits.
        NSArray* shade = @[ (id)PSOColor(6, 10, 34, 150).CGColor, (id)PSOColor(6, 10, 34, 0).CGColor ];
        g = CGGradientCreateWithColors(nullptr, (__bridge CFArrayRef)shade, nullptr);
        CGContextDrawLinearGradient(ctx, g, CGPointMake(0, 0), CGPointMake(w * 0.6, 0), 0);
        CGGradientRelease(g);
      }];
}

UIImage* PSOBackgroundImage(CGSize size)
{
  NSString* docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  for (NSString* name in @[ @"background.png", @"background.jpg", @"background.jpeg", @"background.heic" ])
  {
    UIImage* image = [UIImage imageWithContentsOfFile:[docs stringByAppendingPathComponent:name]];
    if (image)
      return image;
  }
  static UIImage* cached = nil;
  static CGSize cachedSize;
  if (!cached || !CGSizeEqualToSize(cachedSize, size))
  {
    cached = GeneratedBackground(size);
    cachedSize = size;
  }
  return cached;
}

// ---- Menu items ----------------------------------------------------------------------

@interface PSOMenuItem ()
- (BOOL)isEnabled;
@end

@interface PSOPageViewController ()
- (BOOL)startScreen;
@end

@implementation PSOMenuItem
+ (instancetype)action:(NSString*)title help:(NSString*)help run:(void (^)(void))run
{
  PSOMenuItem* item = [PSOMenuItem new];
  item.title = title;
  item.help = help;
  item.activate = run;
  return item;
}

+ (instancetype)choice:(NSString*)title
                  help:(NSString*)help
                 value:(NSString* (^)(void))value
                adjust:(void (^)(NSInteger delta))adjust
{
  PSOMenuItem* item = [PSOMenuItem new];
  item.title = title;
  item.help = help;
  item.value = value;
  item.adjust = adjust;
  return item;
}

- (BOOL)isEnabled
{
  return !self.enabled || self.enabled();
}
@end

// ---- Controller routing ----------------------------------------------------------------

@implementation PSOPad

static NSPointerArray* s_targets;
static void (^s_gameHandler)(GCExtendedGamepad*);
static void (^s_menuHandler)(void);
static NSInteger s_prevX, s_prevY;
static BOOL s_prevA, s_prevB, s_prevMenu;

+ (void)initialize
{
  if (self != PSOPad.class)
    return;
  s_targets = [NSPointerArray weakObjectsPointerArray];
  NSNotificationCenter* center = NSNotificationCenter.defaultCenter;
  [center addObserver:self selector:@selector(connectAll) name:GCControllerDidConnectNotification object:nil];
  [self connectAll];
}

+ (void)connectAll
{
  for (GCController* c in GCController.controllers)
  {
    if (!c.extendedGamepad)
      continue;
    c.extendedGamepad.valueChangedHandler = ^(GCExtendedGamepad* pad, GCControllerElement*) {
      [PSOPad handlePad:pad];
    };
  }
}

+ (BOOL)controllerConnected
{
  for (GCController* c in GCController.controllers)
    if (c.extendedGamepad)
      return YES;
  return NO;
}

+ (id<PSOPadTarget>)topTarget
{
  [s_targets compact];
  for (NSInteger i = (NSInteger)s_targets.count - 1; i >= 0; --i)
  {
    id t = (__bridge id)[s_targets pointerAtIndex:i];
    if (t)
      return t;
  }
  return nil;
}

+ (void)handlePad:(GCExtendedGamepad*)pad
{
  const float sx = pad.leftThumbstick.xAxis.value, sy = pad.leftThumbstick.yAxis.value;
  const NSInteger x = pad.dpad.left.isPressed || sx < -0.5 ? -1 : pad.dpad.right.isPressed || sx > 0.5 ? 1 : 0;
  // Down is +1 (screen order).
  const NSInteger y = pad.dpad.up.isPressed || sy > 0.5 ? -1 : pad.dpad.down.isPressed || sy < -0.5 ? 1 : 0;
  const BOOL a = pad.buttonA.isPressed, b = pad.buttonB.isPressed;
  const BOOL menu = pad.buttonOptions.isPressed || pad.buttonHome.isPressed;

  id<PSOPadTarget> target = [self topTarget];
  if (target)
  {
    if (x != s_prevX && x != 0)
      [target padMoveX:x y:0];
    if (y != s_prevY && y != 0)
      [target padMoveX:0 y:y];
    if (a && !s_prevA)
      [target padConfirm];
    else if (b && !s_prevB)
      [target padBack];
  }
  else
  {
    if (menu && !s_prevMenu && s_menuHandler)
      s_menuHandler();
    else if (s_gameHandler)
      s_gameHandler(pad);
  }
  s_prevX = x;
  s_prevY = y;
  s_prevA = a;
  s_prevB = b;
  s_prevMenu = menu;
}

+ (void)pushTarget:(id<PSOPadTarget>)target
{
  [self removeTarget:target];
  [s_targets addPointer:(__bridge void*)target];
}

+ (void)removeTarget:(id<PSOPadTarget>)target
{
  for (NSInteger i = (NSInteger)s_targets.count - 1; i >= 0; --i)
    if ([s_targets pointerAtIndex:i] == (__bridge void*)target)
      [s_targets removePointerAtIndex:i];
}

+ (void (^)(GCExtendedGamepad*))gameHandler
{
  return s_gameHandler;
}
+ (void)setGameHandler:(void (^)(GCExtendedGamepad*))handler
{
  s_gameHandler = [handler copy];
}
+ (void (^)(void))menuHandler
{
  return s_menuHandler;
}
+ (void)setMenuHandler:(void (^)(void))handler
{
  s_menuHandler = [handler copy];
}
@end

// ---- Menu list --------------------------------------------------------------------------

// One row: the highlight band, the title and (for choices) the value.
@interface PSOMenuRow : UIView
@property(nonatomic, strong) PSOMenuItem* item;
@property(nonatomic) BOOL hot;
@property(nonatomic) CGFloat fontSize, leftInset, valueColumn;
@property(nonatomic, readonly) CGRect valueFrame;
- (void)render;
@end

@implementation PSOMenuRow
{
  CALayer* _band;
  CAGradientLayer* _dark;
  CAGradientLayer* _glow;
  CAGradientLayer* _feather;
  UIImageView* _title;
  UIImageView* _value;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    _band = [CALayer layer];
    _dark = [CAGradientLayer layer];
    _glow = [CAGradientLayer layer];
    _dark.startPoint = _glow.startPoint = CGPointMake(0, 0.5);
    _dark.endPoint = _glow.endPoint = CGPointMake(1, 0.5);
    [_band addSublayer:_dark];
    [_band addSublayer:_glow];
    _feather = [CAGradientLayer layer];
    _feather.colors = @[ (id)UIColor.clearColor.CGColor, (id)UIColor.blackColor.CGColor,
                         (id)UIColor.blackColor.CGColor, (id)UIColor.clearColor.CGColor ];
    _feather.locations = @[ @0, @0.22, @0.78, @1 ];
    _band.mask = _feather;
    [self.layer addSublayer:_band];
    _title = [UIImageView new];
    _value = [UIImageView new];
    [self addSubview:_title];
    [self addSubview:_value];
  }
  return self;
}

- (void)render
{
  const BOOL enabled = [self.item isEnabled];
  UIFont* font = PSOFont(self.fontSize);
  const BOOL hot = self.hot && enabled;
  UIColor* top = !enabled ? PSOColor(170, 175, 200, 140) : hot ? PSOColor(255, 214, 64, 255) : PSOColor(250, 250, 255, 255);
  UIColor* bottom = hot ? PSOColor(255, 160, 50, 255) : top;
  const CGFloat shadow = enabled ? MAX(1, self.fontSize * 0.06) : 0;
  _title.image = PSOTextImage(self.item.title, font, top, bottom, shadow);
  const CGFloat h = self.bounds.size.height;
  const CGSize ts = _title.image.size;
  _title.frame = CGRectMake(self.leftInset, (h - ts.height) / 2, ts.width, ts.height);

  CGFloat textEnd = CGRectGetMaxX(_title.frame);
  if (self.item.value)
  {
    NSString* v = self.item.value();
    NSString* shown = hot ? [NSString stringWithFormat:@"‹ %@ ›", v] : [NSString stringWithFormat:@"  %@", v];
    UIColor* vc = enabled ? PSOColor(246, 232, 176, 255) : PSOColor(170, 175, 200, 140);
    _value.image = PSOTextImage(shown, font, vc, vc, shadow);
    const CGSize vs = _value.image.size;
    const CGFloat x = self.valueColumn > 0 ? self.leftInset + self.valueColumn
                                           : CGRectGetMaxX(_title.frame) + self.fontSize * 0.6;
    _value.frame = CGRectMake(x, (h - vs.height) / 2, vs.width, vs.height);
    _value.hidden = NO;
    textEnd = CGRectGetMaxX(_value.frame);
  }
  else
  {
    _value.image = nil;
    _value.hidden = YES;
  }

  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  _band.hidden = !hot;
  if (hot)
  {
    const CGFloat x2 = textEnd + self.fontSize * 3.5;
    const CGFloat x1 = self.leftInset + (textEnd - self.leftInset) * 0.75;
    _band.frame = CGRectMake(0, 0, x2, h);
    _dark.frame = _glow.frame = _feather.frame = _band.bounds;
    const NSNumber* split = @(x1 / x2);
    _dark.colors = @[ (id)PSOColor(6, 10, 34, 150).CGColor, (id)PSOColor(6, 10, 34, 150).CGColor,
                      (id)PSOColor(6, 10, 34, 0).CGColor ];
    _glow.colors = @[ (id)PSOColor(255, 190, 80, 34).CGColor, (id)PSOColor(255, 190, 80, 34).CGColor,
                      (id)PSOColor(255, 190, 80, 0).CGColor ];
    _dark.locations = _glow.locations = @[ @0, split, @1 ];
  }
  [CATransaction commit];
}

- (CGRect)valueFrame
{
  return _value.hidden ? CGRectNull : _value.frame;
}
@end

@implementation PSOMenuView
{
  NSMutableArray<PSOMenuRow*>* _rows;
  NSInteger _touchRow;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    _rows = [NSMutableArray array];
    _fontSize = 26;
    _touchRow = -1;
  }
  return self;
}

- (CGFloat)rowHeight
{
  return round(self.fontSize * 1.5);
}

- (CGFloat)contentHeight
{
  return self.rowHeight * self.items.count;
}

- (void)setItems:(NSArray<PSOMenuItem*>*)items
{
  _items = [items copy];
  [self reload];
}

- (void)reload
{
  for (PSOMenuRow* row in _rows)
    [row removeFromSuperview];
  [_rows removeAllObjects];
  for (PSOMenuItem* item in self.items)
  {
    PSOMenuRow* row = [PSOMenuRow new];
    row.item = item;
    [self addSubview:row];
    [_rows addObject:row];
  }
  if (_selectedIndex >= (NSInteger)self.items.count)
    _selectedIndex = 0;
  if (self.items.count && ![self.items[_selectedIndex] isEnabled])
    [self moveSelection:1];
  [self setNeedsLayout];
  [self layoutIfNeeded];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  const CGFloat rh = self.rowHeight;
  // The value column clears the longest title that has a value.
  CGFloat column = self.valueColumn;
  if (column > 0)
  {
    UIFont* font = PSOFont(self.fontSize);
    for (PSOMenuItem* item in self.items)
      if (item.value)
        column = MAX(column, [item.title sizeWithAttributes:@{NSFontAttributeName : font}].width + self.fontSize * 0.5);
  }
  for (NSUInteger i = 0; i < _rows.count; ++i)
  {
    PSOMenuRow* row = _rows[i];
    row.frame = CGRectMake(0, i * rh, self.bounds.size.width, rh);
    row.fontSize = self.fontSize;
    row.leftInset = self.leftInset;
    row.valueColumn = column;
    row.hot = (NSInteger)i == _selectedIndex;
    [row render];
  }
}

- (void)refreshValues
{
  for (NSUInteger i = 0; i < _rows.count; ++i)
  {
    _rows[i].hot = (NSInteger)i == _selectedIndex;
    [_rows[i] render];
  }
}

- (void)setSelectedIndex:(NSInteger)index
{
  if (index < 0 || index >= (NSInteger)self.items.count)
    return;
  _selectedIndex = index;
  [self refreshValues];
  if (self.selectionChanged)
    self.selectionChanged(self.items[index]);
  // Keep it on screen inside a scroll view.
  if ([self.superview isKindOfClass:UIScrollView.class] && index < (NSInteger)_rows.count)
  {
    const CGRect r = [self convertRect:_rows[index].frame toView:self.superview];
    [(UIScrollView*)self.superview scrollRectToVisible:CGRectInset(r, 0, -self.rowHeight * 0.5) animated:YES];
  }
}

- (void)moveSelection:(NSInteger)delta
{
  const NSInteger n = (NSInteger)self.items.count;
  if (n == 0)
    return;
  NSInteger i = _selectedIndex;
  for (NSInteger tries = 0; tries < n; ++tries)
  {
    i = (i + delta + n) % n;
    if ([self.items[i] isEnabled])
    {
      self.selectedIndex = i;
      return;
    }
  }
}

- (void)adjustSelection:(NSInteger)delta
{
  if (_selectedIndex >= (NSInteger)self.items.count)
    return;
  PSOMenuItem* item = self.items[_selectedIndex];
  if (![item isEnabled] || !item.adjust)
    return;
  item.adjust(delta);
  [self refreshValues];
  if (self.selectionChanged)
    self.selectionChanged(item);
}

- (void)activateSelection
{
  if (_selectedIndex >= (NSInteger)self.items.count)
    return;
  PSOMenuItem* item = self.items[_selectedIndex];
  if (![item isEnabled])
    return;
  if (item.activate)
    item.activate();
  else if (item.adjust)
    [self adjustSelection:1];
  [self refreshValues];
}

- (NSInteger)rowAt:(CGPoint)p
{
  const NSInteger i = (NSInteger)floor(p.y / self.rowHeight);
  return i >= 0 && i < (NSInteger)self.items.count ? i : -1;
}

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  const NSInteger i = [self rowAt:[touches.anyObject locationInView:self]];
  _touchRow = i;
  if (i >= 0 && [self.items[i] isEnabled])
    self.selectedIndex = i;
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  const CGPoint p = [touches.anyObject locationInView:self];
  const NSInteger i = [self rowAt:p];
  const NSInteger began = _touchRow;
  _touchRow = -1;
  if (i < 0 || i != began || ![self.items[i] isEnabled])
    return;
  PSOMenuItem* item = self.items[i];
  if (item.adjust && !item.activate)
  {
    // Tapping the value: left half steps back, right half forward.
    const CGRect vf = _rows[i].valueFrame;
    if (!CGRectIsNull(vf) && p.x >= CGRectGetMinX(vf) - self.fontSize)
      [self adjustSelection:p.x < CGRectGetMidX(vf) ? -1 : 1];
    else
      [self adjustSelection:1];
    return;
  }
  [self activateSelection];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  _touchRow = -1;
}
@end

// ---- A menu page ---------------------------------------------------------------------------

@implementation PSOPageViewController
{
  UIImageView* _background;
  UIView* _dim;
  UIImageView* _title;
  UIImageView* _subtitleView;
  UIScrollView* _scroll;
  PSOMenuView* _menu;
  UILabel* _help;
  UILabel* _status;
  UILabel* _footer;
  UILabel* _corner;
  CGSize _laidOutSize;
}

- (instancetype)init
{
  if ((self = [super init]))
  {
    self.modalPresentationStyle = UIModalPresentationOverFullScreen;
    self.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
  }
  return self;
}

- (void)loadView
{
  UIView* root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  root.backgroundColor = UIColor.clearColor;

  _background = [[UIImageView alloc] initWithFrame:root.bounds];
  _background.contentMode = UIViewContentModeScaleAspectFill;
  _background.clipsToBounds = YES;
  [root addSubview:_background];
  _dim = [[UIView alloc] initWithFrame:root.bounds];
  [root addSubview:_dim];

  _title = [UIImageView new];
  _subtitleView = [UIImageView new];
  [root addSubview:_title];
  [root addSubview:_subtitleView];

  _scroll = [UIScrollView new];
  _scroll.showsVerticalScrollIndicator = NO;
  _scroll.delaysContentTouches = NO;
  _scroll.alwaysBounceVertical = NO;
  [root addSubview:_scroll];
  _menu = [PSOMenuView new];
  [_scroll addSubview:_menu];
  __weak PSOPageViewController* weakSelf = self;
  _menu.selectionChanged = ^(PSOMenuItem* item) {
    PSOPageViewController* s = weakSelf;
    if (s)
      s->_help.text = item.help;
  };

  auto label = [&](UIColor* color) {
    UILabel* l = [UILabel new];
    l.textColor = color;
    l.numberOfLines = 0;
    [root addSubview:l];
    return l;
  };
  _help = label(PSOColor(210, 214, 232, 230));
  _status = label(PSOColor(120, 220, 120, 255));
  _footer = label(PSOColor(170, 185, 230, 255));
  _corner = label(PSOColor(250, 250, 255, 255));
  _corner.textAlignment = NSTextAlignmentRight;

  self.view = root;
}

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

- (UILabel*)statusLabel
{
  [self loadViewIfNeeded];
  return _status;
}
- (UILabel*)footerLabel
{
  [self loadViewIfNeeded];
  return _footer;
}
- (UILabel*)cornerLabel
{
  [self loadViewIfNeeded];
  return _corner;
}
- (PSOMenuView*)menu
{
  [self loadViewIfNeeded];
  return _menu;
}

- (BOOL)startScreen
{
  return !self.smallItems && !self.overGame;
}

- (void)setItems:(NSArray<PSOMenuItem*>*)items
{
  _items = [items copy];
  if (self.isViewLoaded)
  {
    _menu.items = items;
    [self.view setNeedsLayout];
  }
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  _menu.items = self.items;
}

- (void)viewWillAppear:(BOOL)animated
{
  [super viewWillAppear:animated];
  [self refresh];
}

- (void)viewDidAppear:(BOOL)animated
{
  [super viewDidAppear:animated];
  [PSOPad pushTarget:self];
}

- (void)viewWillDisappear:(BOOL)animated
{
  [super viewWillDisappear:animated];
  [PSOPad removeTarget:self];
}

- (void)refresh
{
  [_menu refreshValues];
  if (_menu.selectedIndex < (NSInteger)self.items.count)
    _help.text = self.items[_menu.selectedIndex].help;
  _laidOutSize = CGSizeZero;
  [self.view setNeedsLayout];
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  const CGRect bounds = self.view.bounds;
  if (CGSizeEqualToSize(_laidOutSize, bounds.size) && _title.image)
    return;
  _laidOutSize = bounds.size;

  const UIEdgeInsets safe = self.view.safeAreaInsets;
  const CGFloat w = bounds.size.width, h = bounds.size.height;
  const CGFloat s = h / 720.0;  // the LAS launcher's 1280x720 design, scaled
  const CGFloat left = MAX(safe.left, 16) + 70 * s;

  _background.frame = bounds;
  _dim.frame = bounds;
  if (self.overGame)
  {
    _background.hidden = YES;
    _dim.backgroundColor = PSOColor(4, 6, 20, 175);
  }
  else
  {
    _background.hidden = NO;
    _background.image = PSOBackgroundImage(bounds.size);
    _dim.backgroundColor = [self startScreen] ? UIColor.clearColor : PSOColor(4, 6, 20, 120);
  }

  const BOOL start = [self startScreen];
  const CGFloat titleSize = start ? MAX(34, 84 * s) : MAX(26, 58 * s);
  _title.image = PSOTextImage(self.pageTitle, PSOFont(titleSize), PSOColor(255, 232, 120, 255),
                              PSOColor(255, 138, 48, 255), MAX(2, 3 * s));
  const CGFloat titleY = start ? h * 0.16 : MAX(safe.top, 10) + 34 * s;
  _title.frame = CGRectMake(left - 2, titleY, _title.image.size.width, _title.image.size.height);
  CGFloat y = CGRectGetMaxY(_title.frame);
  if (self.subtitle.length)
  {
    _subtitleView.image = PSOTextImage(self.subtitle, PSOFont(MAX(16, 34 * s)), PSOColor(200, 220, 255, 255),
                                   PSOColor(140, 170, 240, 255), MAX(1, 2 * s));
    _subtitleView.frame = CGRectMake(left, y - 10 * s, _subtitleView.image.size.width, _subtitleView.image.size.height);
    y = CGRectGetMaxY(_subtitleView.frame);
  }
  else
    _subtitleView.image = nil;

  _menu.fontSize = self.smallItems ? MAX(18, 34 * s) : MAX(22, 46 * s);
  _menu.leftInset = left;
  _menu.valueColumn = self.valueColumn > 0 ? self.valueColumn * _menu.fontSize : 0;

  UIFont* small = PSOFont(MAX(12, 22 * s));
  for (UILabel* l in @[ _help, _status, _footer, _corner ])
    l.font = small;
  const CGFloat bottom = h - MAX(safe.bottom, 8) - 24 * s;
  const CGFloat lineH = small.lineHeight;
  _footer.frame = CGRectMake(left, bottom - lineH, w * 0.6, lineH);
  _corner.frame = CGRectMake(w * 0.4, bottom - lineH, w * 0.6 - MAX(safe.right, 16) - 40 * s, lineH);
  CGFloat statusH = _status.text.length ? lineH : 0;
  _status.frame = CGRectMake(left, CGRectGetMinY(_footer.frame) - statusH - 4 * s, w * 0.6, statusH);
  const CGFloat helpH = start ? 0 : lineH * 2.2;
  _help.hidden = start;
  _help.frame = CGRectMake(left, CGRectGetMinY(_status.frame) - helpH - 6 * s, w - left * 2, helpH);

  const CGFloat menuTop = start ? h * 0.47 : y + 20 * s;
  const CGFloat menuBottom = (start ? CGRectGetMinY(_status.frame) : CGRectGetMinY(_help.frame)) - 10 * s;
  _scroll.frame = CGRectMake(0, menuTop, w, MAX(_menu.fontSize * 1.5, menuBottom - menuTop));
  _menu.frame = CGRectMake(0, 0, w, _menu.contentHeight);
  _scroll.contentSize = _menu.frame.size;
  [_menu setNeedsLayout];
  [_menu layoutIfNeeded];
  _help.text = _menu.selectedIndex < (NSInteger)self.items.count ? self.items[_menu.selectedIndex].help : nil;
}

- (void)showPage:(UIViewController*)page
{
  [self presentViewController:page animated:YES completion:^{
    // Hide this page while another is on top (they're translucent over the game).
    self.view.alpha = 0;
  }];
}

- (void)goBack
{
  if (self.onBack)
  {
    self.onBack();
    return;
  }
  UIViewController* parent = self.presentingViewController;
  parent.view.alpha = 1;
  if ([parent isKindOfClass:PSOPageViewController.class])
    [(PSOPageViewController*)parent refresh];
  [PSOPad removeTarget:self];
  [self dismissViewControllerAnimated:YES completion:nil];
}

// PSOPadTarget
- (void)padMoveX:(NSInteger)dx y:(NSInteger)dy
{
  if (dy)
    [_menu moveSelection:dy];
  if (dx)
    [_menu adjustSelection:dx];
}
- (void)padConfirm
{
  [_menu activateSelection];
}
- (void)padBack
{
  [self goBack];
}
@end

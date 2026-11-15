#import "TouchControls.h"

#import "PSOHost.h"
#import "Settings.h"

#include <cmath>
#include <vector>

namespace
{
enum class Kind
{
  Button,
  Stick,
  Dpad,
};

struct Control
{
  Kind kind;
  PSOInput input;    // the button's input (Button only)
  NSString* ident;   // key in the saved layout
  NSString* label;
  CGPoint center;
  CGFloat radius;
  CGFloat alpha = 1;  // per-control opacity (times the global one)
  bool hidden = false;  // removed in the layout editor
  CAShapeLayer* base = nil;
  CAShapeLayer* knob = nil;  // Stick only
  CATextLayer* text = nil;
};
// The game's action palette (bottom right): its three slots, in the game's
// 640x480 layout at HUD size 100%, measured from the game. The border colors
// match the GameCube buttons: green A, red B, grey X. Above them sits the chat
// icon (Y) and below them the R mark (switches the palette).
struct PaletteSlot
{
  PSOInput input;
  CGFloat x, y, radius;
};
constexpr PaletteSlot kPaletteSlots[] = {
    {PSOInputA, 546, 391, 27},
    {PSOInputB, 501, 417, 27},
    {PSOInputX, 591, 368, 27},
    {PSOInputY, 517, 370, 22},
    {PSOInputR, 575, 426, 18},
};
}  // namespace

@implementation PSOTouchControls
{
  std::vector<Control> _controls;
  // Which control each active touch is driving.
  NSMapTable<UITouch*, NSNumber*>* _touchControl;
  CGFloat _opacity;
  int _selected;
  CGPoint _dragOffset;
  BOOL _rLatched;
  PSOStickMode _stickMode;
  BOOL _stickHeld;
  // A drag on empty space in the right half turns the camera (the C-stick).
  __weak UITouch* _cameraTouch;
  CGPoint _cameraStart;
  BOOL _cameraSwipe;
  // Touches on the game's action palette, and the button each one holds.
  NSMapTable<UITouch*, NSNumber*>* _paletteTouch;
  BOOL _tapPalette;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    self.multipleTouchEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    _touchControl = [NSMapTable weakToStrongObjectsMapTable];
    _paletteTouch = [NSMapTable weakToStrongObjectsMapTable];
    _selected = -1;

    auto add = [&](Kind kind, PSOInput input, NSString* ident, NSString* label) {
      Control c{kind, input, ident, label, CGPointZero, 0};
      _controls.push_back(c);
    };
    add(Kind::Stick, PSOInputStickX, @"stick", @"");
    add(Kind::Dpad, PSOInputDpadUp, @"dpad", @"✚");
    add(Kind::Button, PSOInputA, @"A", @"A");
    add(Kind::Button, PSOInputB, @"B", @"B");
    add(Kind::Button, PSOInputX, @"X", @"X");
    add(Kind::Button, PSOInputY, @"Y", @"Y");
    add(Kind::Button, PSOInputL, @"L", @"L");
    add(Kind::Button, PSOInputR, @"R", @"R");
    add(Kind::Button, PSOInputZ, @"Z", @"Z");
    add(Kind::Button, PSOInputStart, @"START", @"START");

    for (Control& c : _controls)
    {
      c.base = [CAShapeLayer layer];
      c.base.fillColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
      c.base.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
      c.base.lineWidth = 2;
      [self.layer addSublayer:c.base];
      if (c.kind == Kind::Stick)
      {
        c.knob = [CAShapeLayer layer];
        c.knob.fillColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        [self.layer addSublayer:c.knob];
      }
      c.text = [CATextLayer layer];
      c.text.string = c.label;
      c.text.alignmentMode = kCAAlignmentCenter;
      c.text.foregroundColor = UIColor.whiteColor.CGColor;
      c.text.contentsScale = UIScreen.mainScreen.scale;
      [self.layer addSublayer:c.text];
    }
    [NSNotificationCenter.defaultCenter addObserver:self
                                           selector:@selector(settingsChanged)
                                               name:PSOSettingsDidChangeNotification
                                             object:nil];
    _opacity = PSOSettings.touchOpacity;
    _stickMode = PSOSettings.stickMode;
    _tapPalette = PSOSettings.tapPalette;
    _cameraSwipe = PSOSettings.cameraSwipe;
  }
  return self;
}

- (void)dealloc
{
  [NSNotificationCenter.defaultCenter removeObserver:self];
}

- (void)settingsChanged
{
  _opacity = PSOSettings.touchOpacity;
  _stickMode = PSOSettings.stickMode;
  _tapPalette = PSOSettings.tapPalette;
  _cameraSwipe = PSOSettings.cameraSwipe;
  [self setNeedsLayout];
}

- (void)setRLatched:(BOOL)latched
{
  _rLatched = latched;
  for (Control& c : _controls)
    if (c.kind == Kind::Button && c.input == PSOInputR)
      [self setPressed:c pressed:NO];
}

// ---- Layout ------------------------------------------------------------------

- (CGRect)safeRect
{
  return UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
}

- (CGFloat)unit
{
  return MIN(self.bounds.size.height / 8.0, 56.0);
}

// Where each control goes before the user's changes.
- (void)defaultPlacement:(Control&)c
{
  const CGRect safe = [self safeRect];
  const CGFloat u = [self unit];
  const CGFloat left = CGRectGetMinX(safe) + u * 0.4;
  const CGFloat right = CGRectGetMaxX(safe) - u * 0.4;
  const CGFloat top = CGRectGetMinY(safe);
  const CGFloat bottom = CGRectGetMaxY(safe);
  const CGPoint face = CGPointMake(right - 2.2 * u, bottom - 2.5 * u);

  switch (c.kind)
  {
  case Kind::Stick: c.center = CGPointMake(left + 1.8 * u, bottom - 2.0 * u); c.radius = 1.5 * u; break;
  case Kind::Dpad: c.center = CGPointMake(left + 1.8 * u, bottom - 5.4 * u); c.radius = 1.1 * u; break;
  case Kind::Button:
    switch (c.input)
    {
    case PSOInputA: c.center = face; c.radius = 0.75 * u; break;
    case PSOInputB: c.center = CGPointMake(face.x - 1.45 * u, face.y + 0.85 * u); c.radius = 0.5 * u; break;
    case PSOInputX: c.center = CGPointMake(face.x + 1.4 * u, face.y - 0.45 * u); c.radius = 0.55 * u; break;
    case PSOInputY: c.center = CGPointMake(face.x - 0.35 * u, face.y - 1.45 * u); c.radius = 0.55 * u; break;
    case PSOInputL: c.center = CGPointMake(left + 1.2 * u, top + 0.9 * u); c.radius = 0.6 * u; break;
    case PSOInputR: c.center = CGPointMake(right - 1.2 * u, top + 0.9 * u); c.radius = 0.6 * u; break;
    case PSOInputZ: c.center = CGPointMake(right - 2.7 * u, top + 0.9 * u); c.radius = 0.5 * u; break;
    case PSOInputStart: c.center = CGPointMake(CGRectGetMidX(safe), bottom - 0.6 * u); c.radius = 0.45 * u; break;
    default: break;
    }
    break;
  }
  c.alpha = 1;
  c.hidden = false;
}

- (void)placeControl:(Control&)c
{
  [self defaultPlacement:c];
  NSDictionary* o = PSOSettings.touchLayout[c.ident];
  if (![o isKindOfClass:NSDictionary.class])
    return;
  const CGRect safe = [self safeRect];
  if (o[@"x"] && o[@"y"])
  {
    c.center = CGPointMake(CGRectGetMinX(safe) + [o[@"x"] doubleValue] * safe.size.width,
                           CGRectGetMinY(safe) + [o[@"y"] doubleValue] * safe.size.height);
  }
  if (o[@"scale"])
    c.radius *= MAX(0.5, MIN(2.0, [o[@"scale"] doubleValue]));
  if (o[@"opacity"])
    c.alpha = MAX(0.0, MIN(1.0, [o[@"opacity"] doubleValue]));
  c.hidden = [o[@"hidden"] boolValue];
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  for (Control& c : _controls)
  {
    if (c.kind == Kind::Stick && _stickHeld)
      continue;  // a floating stick stays under the thumb
    [self placeControl:c];
    [self drawControl:c];
  }
  [CATransaction commit];
}

- (void)drawControl:(Control&)c
{
  const CGRect box = CGRectMake(c.center.x - c.radius, c.center.y - c.radius, 2 * c.radius, 2 * c.radius);
  c.base.path = (c.kind == Kind::Dpad) ? [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:c.radius * 0.3].CGPath
                                       : [UIBezierPath bezierPathWithOvalInRect:box].CGPath;
  if (c.knob)
    [self placeKnob:c offset:CGPointZero];
  const CGFloat font = (c.input == PSOInputStart && c.kind == Kind::Button) ? c.radius * 0.5 : c.radius * 0.8;
  c.text.fontSize = font;
  c.text.frame = CGRectMake(c.center.x - c.radius, c.center.y - font * 0.6, 2 * c.radius, font * 1.3);
  [self setPressed:c pressed:NO];
}

- (void)placeKnob:(Control&)c offset:(CGPoint)offset
{
  const CGFloat r = c.radius * 0.45;
  const CGRect box = CGRectMake(c.center.x + offset.x - r, c.center.y + offset.y - r, 2 * r, 2 * r);
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  c.knob.path = [UIBezierPath bezierPathWithOvalInRect:box].CGPath;
  [CATransaction commit];
}

- (void)setPressed:(Control&)c pressed:(BOOL)pressed
{
  const BOOL selected = self.editing && &c == (_selected >= 0 ? &_controls[_selected] : nullptr);
  const BOOL latched = _rLatched && c.kind == Kind::Button && c.input == PSOInputR;
  CGFloat idle = _opacity * c.alpha;
  if (self.editing)
    idle = c.hidden ? 0.15 : MAX(idle, 0.25);  // never invisible while editing
  else if (c.hidden)
    idle = 0;
  else if (c.kind == Kind::Stick && _stickMode != PSOStickAlways && !_stickHeld)
    idle = 0;  // only drawn while held
  const CGFloat lit = MIN(1.0, MAX(idle * 2.0, idle + 0.3));
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  c.base.opacity = (pressed || latched) ? lit : idle;
  if (c.knob)
    c.knob.opacity = pressed ? lit : idle;
  c.text.opacity = MIN(1.0, ((pressed || latched) ? lit : idle) * 2.0);
  UIColor* gold = [UIColor colorWithRed:1 green:0.8 blue:0.3 alpha:1];
  c.base.strokeColor = (selected || latched) ? gold.CGColor : [UIColor colorWithWhite:1 alpha:0.8].CGColor;
  c.base.fillColor = latched ? [gold colorWithAlphaComponent:0.45].CGColor
                             : [UIColor colorWithWhite:1 alpha:0.25].CGColor;
  c.base.lineWidth = selected ? 3 : 2;
  c.base.lineDashPattern = c.hidden ? @[ @6, @5 ] : nil;
  [CATransaction commit];
}

- (int)controlAt:(CGPoint)p
{
  int best = -1;
  CGFloat best_d = CGFLOAT_MAX;
  for (size_t i = 0; i < _controls.size(); ++i)
  {
    const Control& c = _controls[i];
    if (c.hidden && !self.editing)
      continue;
    // Generous hit areas: sticks grab anything nearby.
    const CGFloat reach = self.editing ? MAX(c.radius, 22) : c.radius * (c.kind == Kind::Button ? 1.25 : 1.6);
    const CGFloat d = std::hypot(p.x - c.center.x, p.y - c.center.y);
    if (d <= reach && d / reach < best_d)
    {
      best = static_cast<int>(i);
      best_d = d / reach;
    }
  }
  if (!self.editing && _stickMode == PSOStickFloating && !_stickHeld && p.x < CGRectGetMidX(self.bounds))
  {
    // The stick appears under the thumb, unless another control was hit.
    const BOOL onOther = best >= 0 && _controls[best].kind != Kind::Stick &&
                         std::hypot(p.x - _controls[best].center.x, p.y - _controls[best].center.y) <=
                             _controls[best].radius * 1.25;
    if (!onOther)
      for (size_t i = 0; i < _controls.size(); ++i)
        if (_controls[i].kind == Kind::Stick && !_controls[i].hidden)
          return static_cast<int>(i);
  }
  return best;
}

// ---- Playing -------------------------------------------------------------------

- (void)didMoveToWindow
{
  [super didMoveToWindow];
  if (self.window && !self.editing)
  {
    __weak PSOTouchControls* weakSelf = self;
    PSOSetRLatchHandler(^(bool latched) {
      [weakSelf setRLatched:latched];
    });
  }
}

- (void)updateStick:(Control&)c touch:(UITouch*)touch
{
  const CGPoint p = [touch locationInView:self];
  CGFloat dx = (p.x - c.center.x) / c.radius;
  CGFloat dy = (p.y - c.center.y) / c.radius;
  const CGFloat len = std::hypot(dx, dy);
  if (len > 1.0)
  {
    dx /= len;
    dy /= len;
  }
  PSOSetInput(PSOInputStickX, dx);
  PSOSetInput(PSOInputStickY, -dy);  // screen y grows downward; stick up is positive
  [self placeKnob:c offset:CGPointMake(dx * c.radius, dy * c.radius)];
}

- (void)updateDpad:(Control&)c touch:(UITouch*)touch
{
  const CGPoint p = [touch locationInView:self];
  const CGFloat dx = p.x - c.center.x;
  const CGFloat dy = p.y - c.center.y;
  const CGFloat dead = c.radius * 0.25;
  const BOOL up = dy < -dead && std::fabs(dy) > std::fabs(dx) * 0.5;
  const BOOL down = dy > dead && std::fabs(dy) > std::fabs(dx) * 0.5;
  const BOOL leftDir = dx < -dead && std::fabs(dx) > std::fabs(dy) * 0.5;
  const BOOL rightDir = dx > dead && std::fabs(dx) > std::fabs(dy) * 0.5;
  PSOSetInput(PSOInputDpadUp, up ? 1 : 0);
  PSOSetInput(PSOInputDpadDown, down ? 1 : 0);
  PSOSetInput(PSOInputDpadLeft, leftDir ? 1 : 0);
  PSOSetInput(PSOInputDpadRight, rightDir ? 1 : 0);
}

- (void)releaseControl:(Control&)c
{
  switch (c.kind)
  {
  case Kind::Button: PSOClearInput(c.input); break;
  case Kind::Stick:
    PSOClearInput(PSOInputStickX);
    PSOClearInput(PSOInputStickY);
    _stickHeld = NO;
    [self placeControl:c];
    [self drawControl:c];
    break;
  case Kind::Dpad:
    PSOClearInput(PSOInputDpadUp);
    PSOClearInput(PSOInputDpadDown);
    PSOClearInput(PSOInputDpadLeft);
    PSOClearInput(PSOInputDpadRight);
    break;
  }
  [self setPressed:c pressed:NO];
}

// ---- Action palette ------------------------------------------------------------
//
// Where the game's picture is and how wide its 2D layout is (as in
// ApplySettingsNow and the widescreen mod): the 640x480 layout spans the middle
// 1/W of the picture, and the HUD's right side is moved out to the picture's
// edge and sized about the bottom-right corner.

- (CGRect)pictureRect:(CGFloat*)widen
{
  const CGRect b = self.bounds;
  CGFloat aspect = 4.0 / 3.0;
  *widen = 1;
  switch (PSOSettings.displayMode)
  {
  case PSODisplayStretch: return b;
  case PSODisplayOriginal: break;
  case PSODisplayWidescreen: aspect = 16.0 / 9.0; break;
  case PSODisplayFill: aspect = b.size.width / MAX(1.0, b.size.height); break;
  }
  *widen = MAX(1.0, aspect / (4.0 / 3.0));
  CGSize size = b.size;
  if (size.width / size.height > aspect)
    size.width = size.height * aspect;
  else
    size.height = size.width / aspect;
  return CGRectMake(CGRectGetMidX(b) - size.width / 2, CGRectGetMidY(b) - size.height / 2, size.width, size.height);
}

// The palette button under p, or -1.
- (int)paletteButtonAt:(CGPoint)p
{
  CGFloat w;
  const CGRect pic = [self pictureRect:&w];
  const CGFloat k = MAX(25, MIN(200, PSOSettings.hudScale)) / 100.0;
  const CGFloat unitX = pic.size.width / (640.0 * w);  // view points per game pixel
  const CGFloat unitY = pic.size.height / 480.0;
  int best = -1;
  CGFloat best_d = CGFLOAT_MAX;
  for (const PaletteSlot& slot : kPaletteSlots)
  {
    const CGFloat gx = 640 + k * (slot.x - 640) + (w - 1) * 320;
    const CGFloat gy = 480 + k * (slot.y - 480);
    const CGFloat vx = CGRectGetMinX(pic) + (gx - 320 * (1 - w)) * unitX;
    const CGFloat vy = CGRectGetMinY(pic) + gy * unitY;
    // Distance in slot radii, so the nearest slot wins where the touch areas overlap.
    const CGFloat d = std::hypot((p.x - vx) / unitX, (p.y - vy) / unitY) / k / slot.radius;
    if (d <= 1.15 && d < best_d)
    {
      best = slot.input;
      best_d = d;
    }
  }
  return best;
}

- (void)releasePalette
{
  for (UITouch* touch in _paletteTouch.keyEnumerator.allObjects)
    PSOClearInput((PSOInput)[_paletteTouch objectForKey:touch].intValue);
  [_paletteTouch removeAllObjects];
}

// ---- Camera ----------------------------------------------------------------------

- (void)updateCamera:(UITouch*)touch
{
  // Full turn speed once the finger is 1.5 units from where it went down.
  const CGFloat dx = ([touch locationInView:self].x - _cameraStart.x) / ([self unit] * 1.5);
  PSOSetInput(PSOInputCStickX, MAX(-1.0, MIN(1.0, dx)));
}

- (void)releaseCamera
{
  _cameraTouch = nil;
  PSOClearInput(PSOInputCStickX);
}

- (void)releaseAll
{
  [self releaseCamera];
  [self releasePalette];
  for (UITouch* touch in _touchControl.keyEnumerator.allObjects)
  {
    NSNumber* index = [_touchControl objectForKey:touch];
    if (index && !self.editing)
      [self releaseControl:_controls[index.intValue]];
  }
  [_touchControl removeAllObjects];
}

// ---- Editing --------------------------------------------------------------------

- (void)setEditing:(BOOL)editing
{
  [self releaseAll];
  _editing = editing;
  _selected = -1;
  [self setNeedsLayout];
}

- (void)selectControl:(int)index
{
  _selected = index;
  for (Control& c : _controls)
    [self setPressed:c pressed:NO];
  if (self.selectionChanged)
    self.selectionChanged();
}

- (NSString*)selectedName
{
  if (_selected < 0)
    return nil;
  const Control& c = _controls[_selected];
  switch (c.kind)
  {
  case Kind::Stick: return @"Stick";
  case Kind::Dpad: return @"D-pad";
  case Kind::Button: return c.input == PSOInputStart ? @"Start" : c.ident;
  }
  return nil;
}

- (NSMutableDictionary*)overrideFor:(const Control&)c layout:(NSMutableDictionary*)layout
{
  NSMutableDictionary* o = [layout[c.ident] mutableCopy] ?: [NSMutableDictionary dictionary];
  layout[c.ident] = o;
  return o;
}

- (void)saveSelected:(void (^)(NSMutableDictionary* o))change
{
  if (_selected < 0)
    return;
  NSMutableDictionary* layout = [PSOSettings.touchLayout mutableCopy];
  NSMutableDictionary* o = [self overrideFor:_controls[_selected] layout:layout];
  change(o);
  PSOSettings.touchLayout = layout;  // posts the change; layout follows
}

- (CGFloat)selectedScale
{
  if (_selected < 0)
    return 1;
  NSNumber* v = PSOSettings.touchLayout[_controls[_selected].ident][@"scale"];
  return v ? v.doubleValue : 1;
}

- (void)setSelectedScale:(CGFloat)scale
{
  [self saveSelected:^(NSMutableDictionary* o) {
    o[@"scale"] = @(MAX(0.5, MIN(2.0, scale)));
  }];
}

- (CGFloat)selectedOpacity
{
  return _selected < 0 ? 1 : _controls[_selected].alpha;
}

- (void)setSelectedOpacity:(CGFloat)opacity
{
  [self saveSelected:^(NSMutableDictionary* o) {
    o[@"opacity"] = @(MAX(0.0, MIN(1.0, opacity)));
  }];
}

- (BOOL)selectedHidden
{
  return _selected >= 0 && _controls[_selected].hidden;
}

- (void)setSelectedHidden:(BOOL)hidden
{
  [self saveSelected:^(NSMutableDictionary* o) {
    if (hidden)
      o[@"hidden"] = @YES;
    else
      [o removeObjectForKey:@"hidden"];
  }];
  if (self.selectionChanged)
    self.selectionChanged();
}

- (void)resetSelected
{
  if (_selected < 0)
    return;
  NSMutableDictionary* layout = [PSOSettings.touchLayout mutableCopy];
  [layout removeObjectForKey:_controls[_selected].ident];
  PSOSettings.touchLayout = layout;
  if (self.selectionChanged)
    self.selectionChanged();
}

- (void)resetAll
{
  PSOSettings.touchLayout = @{};
  if (self.selectionChanged)
    self.selectionChanged();
}

- (void)moveSelectedTo:(CGPoint)p
{
  Control& c = _controls[_selected];
  const CGRect b = self.bounds;
  c.center = CGPointMake(MAX(CGRectGetMinX(b) + c.radius * 0.5, MIN(CGRectGetMaxX(b) - c.radius * 0.5, p.x)),
                         MAX(CGRectGetMinY(b) + c.radius * 0.5, MIN(CGRectGetMaxY(b) - c.radius * 0.5, p.y)));
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  [self drawControl:c];
  [CATransaction commit];
}

- (void)saveSelectedPosition
{
  const CGRect safe = [self safeRect];
  const CGPoint p = _controls[_selected].center;
  [self saveSelected:^(NSMutableDictionary* o) {
    o[@"x"] = @((p.x - CGRectGetMinX(safe)) / safe.size.width);
    o[@"y"] = @((p.y - CGRectGetMinY(safe)) / safe.size.height);
  }];
}

// ---- Touches ---------------------------------------------------------------------

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  if (self.editing)
  {
    UITouch* touch = touches.anyObject;
    const CGPoint p = [touch locationInView:self];
    const int index = [self controlAt:p];
    [self selectControl:index];
    if (index >= 0)
    {
      _dragOffset = CGPointMake(_controls[index].center.x - p.x, _controls[index].center.y - p.y);
      [_touchControl setObject:@(index) forKey:touch];
    }
    return;
  }
  for (UITouch* touch in touches)
  {
    const CGPoint p = [touch locationInView:self];
    const int index = [self controlAt:p];
    if (index < 0)
    {
      const int button = _tapPalette ? [self paletteButtonAt:p] : -1;
      if (button >= 0)
      {
        [_paletteTouch setObject:@(button) forKey:touch];
        PSOSetInput((PSOInput)button, 1);
      }
      else if (_cameraSwipe && !_cameraTouch && p.x >= CGRectGetMidX(self.bounds))
      {
        _cameraTouch = touch;
        _cameraStart = p;
      }
      continue;
    }
    Control& c = _controls[index];
    if (c.kind == Kind::Stick)
    {
      if (_stickHeld)
        continue;  // one thumb on the stick at a time
      _stickHeld = YES;
      if (_stickMode == PSOStickFloating)
      {
        c.center = [touch locationInView:self];
        [self drawControl:c];
      }
    }
    [_touchControl setObject:@(index) forKey:touch];
    [self setPressed:c pressed:YES];
    switch (c.kind)
    {
    case Kind::Button: PSOSetInput(c.input, 1); break;
    case Kind::Stick: [self updateStick:c touch:touch]; break;
    case Kind::Dpad: [self updateDpad:c touch:touch]; break;
    }
  }
}

- (void)touchesMoved:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches)
  {
    if (touch == _cameraTouch)
    {
      [self updateCamera:touch];
      continue;
    }
    NSNumber* index = [_touchControl objectForKey:touch];
    if (!index)
      continue;
    if (self.editing)
    {
      const CGPoint p = [touch locationInView:self];
      [self moveSelectedTo:CGPointMake(p.x + _dragOffset.x, p.y + _dragOffset.y)];
      continue;
    }
    Control& c = _controls[index.intValue];
    if (c.kind == Kind::Stick)
      [self updateStick:c touch:touch];
    else if (c.kind == Kind::Dpad)
      [self updateDpad:c touch:touch];
  }
}

- (void)endTouches:(NSSet<UITouch*>*)touches
{
  for (UITouch* touch in touches)
  {
    if (touch == _cameraTouch)
      [self releaseCamera];
    if (NSNumber* button = [_paletteTouch objectForKey:touch])
    {
      [_paletteTouch removeObjectForKey:touch];
      PSOClearInput((PSOInput)button.intValue);
    }
    NSNumber* index = [_touchControl objectForKey:touch];
    if (!index)
      continue;
    [_touchControl removeObjectForKey:touch];
    if (self.editing)
    {
      if (_selected == index.intValue)
        [self saveSelectedPosition];
      continue;
    }
    [self releaseControl:_controls[index.intValue]];
  }
}

- (void)touchesEnded:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self endTouches:touches];
}

- (void)touchesCancelled:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  [self endTouches:touches];
}

@end

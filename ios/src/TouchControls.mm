#import "TouchControls.h"

#import "PSOHost.h"

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
  PSOInput input;  // the button's input (Button only)
  NSString* label;
  CGPoint center;
  CGFloat radius;
  CAShapeLayer* base = nil;
  CAShapeLayer* knob = nil;  // Stick only
  CATextLayer* text = nil;
};

constexpr CGFloat kIdleAlpha = 0.35;
constexpr CGFloat kPressedAlpha = 0.7;
}  // namespace

@implementation PSOTouchControls
{
  std::vector<Control> _controls;
  // Which control each active touch is driving.
  NSMapTable<UITouch*, NSNumber*>* _touchControl;
}

- (instancetype)initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame]))
  {
    self.multipleTouchEnabled = YES;
    self.backgroundColor = UIColor.clearColor;
    _touchControl = [NSMapTable weakToStrongObjectsMapTable];

    auto add = [&](Kind kind, PSOInput input, NSString* label) {
      Control c{kind, input, label, CGPointZero, 0};
      _controls.push_back(c);
    };
    add(Kind::Stick, PSOInputStickX, @"");
    add(Kind::Dpad, PSOInputDpadUp, @"+");
    add(Kind::Button, PSOInputA, @"A");
    add(Kind::Button, PSOInputB, @"B");
    add(Kind::Button, PSOInputX, @"X");
    add(Kind::Button, PSOInputY, @"Y");
    add(Kind::Button, PSOInputL, @"L");
    add(Kind::Button, PSOInputR, @"R");
    add(Kind::Button, PSOInputZ, @"Z");
    add(Kind::Button, PSOInputStart, @"START");

    for (Control& c : _controls)
    {
      c.base = [CAShapeLayer layer];
      c.base.fillColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
      c.base.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.8].CGColor;
      c.base.lineWidth = 2;
      c.base.opacity = kIdleAlpha;
      [self.layer addSublayer:c.base];
      if (c.kind == Kind::Stick)
      {
        c.knob = [CAShapeLayer layer];
        c.knob.fillColor = [UIColor colorWithWhite:1.0 alpha:0.6].CGColor;
        c.knob.opacity = kIdleAlpha;
        [self.layer addSublayer:c.knob];
      }
      c.text = [CATextLayer layer];
      c.text.string = c.label;
      c.text.alignmentMode = kCAAlignmentCenter;
      c.text.foregroundColor = UIColor.whiteColor.CGColor;
      c.text.contentsScale = UIScreen.mainScreen.scale;
      c.text.opacity = 0.8;
      [self.layer addSublayer:c.text];
    }
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  const CGRect safe = UIEdgeInsetsInsetRect(self.bounds, self.safeAreaInsets);
  const CGFloat h = self.bounds.size.height;
  const CGFloat u = MIN(h / 8.0, 56.0);
  const CGFloat left = CGRectGetMinX(safe) + u * 0.4;
  const CGFloat right = CGRectGetMaxX(safe) - u * 0.4;
  const CGFloat bottom = CGRectGetMaxY(safe);
  const CGPoint face = CGPointMake(right - 2.2 * u, bottom - 2.5 * u);

  for (Control& c : _controls)
  {
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
      case PSOInputL: c.center = CGPointMake(left + 1.2 * u, CGRectGetMinY(safe) + 0.9 * u); c.radius = 0.6 * u; break;
      case PSOInputR: c.center = CGPointMake(right - 1.2 * u, CGRectGetMinY(safe) + 0.9 * u); c.radius = 0.6 * u; break;
      case PSOInputZ: c.center = CGPointMake(right - 2.7 * u, CGRectGetMinY(safe) + 0.9 * u); c.radius = 0.5 * u; break;
      case PSOInputStart: c.center = CGPointMake(CGRectGetMidX(safe), CGRectGetMinY(safe) + 0.6 * u); c.radius = 0.45 * u; break;
      default: break;
      }
      break;
    }

    const CGRect box = CGRectMake(c.center.x - c.radius, c.center.y - c.radius, 2 * c.radius, 2 * c.radius);
    c.base.path = (c.kind == Kind::Dpad)
                      ? [UIBezierPath bezierPathWithRoundedRect:box cornerRadius:c.radius * 0.3].CGPath
                      : [UIBezierPath bezierPathWithOvalInRect:box].CGPath;
    if (c.knob)
      [self placeKnob:c offset:CGPointZero];
    const CGFloat font = (c.input == PSOInputStart) ? c.radius * 0.5 : c.radius * 0.8;
    c.text.fontSize = font;
    c.text.frame = CGRectMake(c.center.x - c.radius, c.center.y - font * 0.6, 2 * c.radius, font * 1.3);
  }
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

- (int)controlAt:(CGPoint)p
{
  int best = -1;
  CGFloat best_d = CGFLOAT_MAX;
  for (size_t i = 0; i < _controls.size(); ++i)
  {
    const Control& c = _controls[i];
    // Generous hit areas: sticks grab anything nearby.
    const CGFloat reach = c.radius * (c.kind == Kind::Button ? 1.25 : 1.6);
    const CGFloat d = std::hypot(p.x - c.center.x, p.y - c.center.y);
    if (d <= reach && d / reach < best_d)
    {
      best = static_cast<int>(i);
      best_d = d / reach;
    }
  }
  return best;
}

- (void)setPressed:(Control&)c pressed:(BOOL)pressed
{
  [CATransaction begin];
  [CATransaction setDisableActions:YES];
  c.base.opacity = pressed ? kPressedAlpha : kIdleAlpha;
  if (c.knob)
    c.knob.opacity = pressed ? kPressedAlpha : kIdleAlpha;
  [CATransaction commit];
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
    [self placeKnob:c offset:CGPointZero];
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

- (void)touchesBegan:(NSSet<UITouch*>*)touches withEvent:(UIEvent*)event
{
  for (UITouch* touch in touches)
  {
    const int index = [self controlAt:[touch locationInView:self]];
    if (index < 0)
      continue;
    [_touchControl setObject:@(index) forKey:touch];
    Control& c = _controls[index];
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
    NSNumber* index = [_touchControl objectForKey:touch];
    if (!index)
      continue;
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
    NSNumber* index = [_touchControl objectForKey:touch];
    if (!index)
      continue;
    [_touchControl removeObjectForKey:touch];
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

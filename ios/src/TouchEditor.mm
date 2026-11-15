#import "TouchEditor.h"

#import "PSOUI.h"
#import "Settings.h"
#import "TouchControls.h"

@interface PSOTouchEditorViewController () <PSOPadTarget>
@end

@implementation PSOTouchEditorViewController
{
  UIImageView* _background;
  PSOTouchControls* _controls;
  UIView* _panel;
  UILabel* _title;
  UILabel* _sizeLabel;
  UILabel* _opacityLabel;
  UILabel* _allLabel;
  UISlider* _size;
  UISlider* _opacity;
  UISlider* _all;
  UIButton* _reset;
  CGPoint _panelCenter;  // fraction of the view; (0,0) = not moved yet
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

- (BOOL)prefersStatusBarHidden { return YES; }
- (BOOL)prefersHomeIndicatorAutoHidden { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations { return UIInterfaceOrientationMaskLandscape; }

static UILabel* MakeLabel(CGFloat size, UIColor* color)
{
  UILabel* l = [UILabel new];
  l.font = PSOFont(size);
  l.textColor = color;
  return l;
}

- (UIButton*)button:(NSString*)title action:(SEL)action
{
  UIButton* b = [UIButton buttonWithType:UIButtonTypeSystem];
  [b setTitle:title forState:UIControlStateNormal];
  b.titleLabel.font = PSOFont(17);
  [b setTitleColor:PSOColor(255, 214, 64, 255) forState:UIControlStateNormal];
  [b setTitleColor:PSOColor(170, 175, 200, 140) forState:UIControlStateDisabled];
  b.backgroundColor = PSOColor(255, 255, 255, 20);
  b.layer.cornerRadius = 8;
  [b addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
  [_panel addSubview:b];
  return b;
}

- (UISlider*)slider:(float)min max:(float)max action:(SEL)action
{
  UISlider* s = [UISlider new];
  s.minimumValue = min;
  s.maximumValue = max;
  s.minimumTrackTintColor = PSOColor(255, 190, 80, 255);
  [s addTarget:self action:action forControlEvents:UIControlEventValueChanged];
  [_panel addSubview:s];
  return s;
}

- (void)loadView
{
  UIView* root = [[UIView alloc] initWithFrame:UIScreen.mainScreen.bounds];
  root.backgroundColor = self.overGame ? PSOColor(4, 6, 20, 90) : UIColor.blackColor;

  _background = [[UIImageView alloc] initWithFrame:root.bounds];
  _background.contentMode = UIViewContentModeScaleAspectFill;
  _background.alpha = 0.55;
  _background.hidden = self.overGame;
  [root addSubview:_background];

  _controls = [[PSOTouchControls alloc] initWithFrame:root.bounds];
  _controls.editing = YES;
  __weak PSOTouchEditorViewController* weakSelf = self;
  _controls.selectionChanged = ^{
    [weakSelf updatePanel];
  };
  [root addSubview:_controls];

  _panel = [UIView new];
  _panel.backgroundColor = PSOColor(10, 16, 40, 235);
  _panel.layer.cornerRadius = 14;
  _panel.layer.borderColor = PSOColor(255, 255, 255, 40).CGColor;
  _panel.layer.borderWidth = 1;
  [root addSubview:_panel];
  [_panel addGestureRecognizer:[[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(dragPanel:)]];

  _title = MakeLabel(18, PSOColor(255, 214, 64, 255));
  _title.adjustsFontSizeToFitWidth = YES;
  [_panel addSubview:_title];
  _sizeLabel = MakeLabel(15, PSOColor(230, 232, 245, 255));
  _opacityLabel = MakeLabel(15, PSOColor(230, 232, 245, 255));
  _allLabel = MakeLabel(15, PSOColor(230, 232, 245, 255));
  for (UILabel* l in @[ _sizeLabel, _opacityLabel, _allLabel ])
    [_panel addSubview:l];
  _size = [self slider:0.5 max:2.0 action:@selector(sizeChanged)];
  _opacity = [self slider:0 max:1 action:@selector(opacityChanged)];
  _all = [self slider:0.1 max:1 action:@selector(allChanged)];
  _reset = [self button:@"Reset this" action:@selector(resetSelected)];
  [self button:@"Reset all" action:@selector(resetAll)];
  [self button:@"Done" action:@selector(done)];

  self.view = root;
  [self updatePanel];
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

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  const CGRect b = self.view.bounds;
  if (!self.overGame && !_background.image)
    _background.image = PSOBackgroundImage(b.size);
  _background.frame = b;
  _controls.frame = b;

  const CGFloat pw = MIN(400, b.size.width - 40), ph = 236;
  _panel.bounds = CGRectMake(0, 0, pw, ph);
  if (CGPointEqualToPoint(_panelCenter, CGPointZero))
    _panel.center = CGPointMake(CGRectGetMidX(b), CGRectGetMidY(b) - 10);
  else
    _panel.center = CGPointMake(_panelCenter.x * b.size.width, _panelCenter.y * b.size.height);

  const CGFloat m = 14, lw = 118;
  _title.frame = CGRectMake(m, 8, pw - 2 * m, 28);
  CGFloat y = 42;
  for (NSArray* pair in @[ @[ _sizeLabel, _size ], @[ _opacityLabel, _opacity ], @[ _allLabel, _all ] ])
  {
    [pair[0] setFrame:CGRectMake(m, y, lw, 34)];
    [pair[1] setFrame:CGRectMake(m + lw, y, pw - 2 * m - lw, 34)];
    y += 40;
  }
  NSArray<UIButton*>* buttons = [_panel.subviews
      filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(id v, NSDictionary*) {
        return [v isKindOfClass:UIButton.class];
      }]];
  const CGFloat gap = 10, bw = (pw - 2 * m - gap * (buttons.count - 1)) / buttons.count;
  for (NSUInteger i = 0; i < buttons.count; ++i)
    buttons[i].frame = CGRectMake(m + i * (bw + gap), ph - 14 - 40, bw, 40);
}

- (void)dragPanel:(UIPanGestureRecognizer*)pan
{
  const CGPoint t = [pan translationInView:self.view];
  _panel.center = CGPointMake(_panel.center.x + t.x, _panel.center.y + t.y);
  [pan setTranslation:CGPointZero inView:self.view];
  const CGSize s = self.view.bounds.size;
  _panelCenter = CGPointMake(_panel.center.x / s.width, _panel.center.y / s.height);
}

- (void)updatePanel
{
  NSString* name = _controls.selectedName;
  const BOOL has = name != nil;
  _title.text = has ? [NSString stringWithFormat:@"%@ selected — drag to move", name]
                    : @"Drag a control to move it, or tap one to resize it";
  _size.enabled = _opacity.enabled = _reset.enabled = has;
  _size.alpha = _opacity.alpha = _sizeLabel.alpha = _opacityLabel.alpha = has ? 1 : 0.4;
  _size.value = _controls.selectedScale;
  _opacity.value = _controls.selectedOpacity;
  _all.value = PSOSettings.touchOpacity;
  [self updateLabels];
}

- (void)updateLabels
{
  _sizeLabel.text = [NSString stringWithFormat:@"Size %d%%", (int)lround(_size.value * 100)];
  _opacityLabel.text = [NSString stringWithFormat:@"Opacity %d%%", (int)lround(_opacity.value * 100)];
  _allLabel.text = [NSString stringWithFormat:@"All %d%%", (int)lround(_all.value * 100)];
}

- (void)sizeChanged
{
  _controls.selectedScale = _size.value;
  [self updateLabels];
}

- (void)opacityChanged
{
  _controls.selectedOpacity = _opacity.value;
  [self updateLabels];
}

- (void)allChanged
{
  PSOSettings.touchOpacity = _all.value;
  [self updateLabels];
}

- (void)resetSelected
{
  [_controls resetSelected];
}

- (void)resetAll
{
  UIAlertController* alert =
      [UIAlertController alertControllerWithTitle:@"Reset all controls?"
                                          message:@"Every control goes back to its original place, size and opacity."
                                   preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
  [alert addAction:[UIAlertAction actionWithTitle:@"Reset"
                                            style:UIAlertActionStyleDestructive
                                          handler:^(UIAlertAction*) {
                                            [self->_controls resetAll];
                                            PSOSettings.touchOpacity = 0.45;
                                            [self updatePanel];
                                          }]];
  [self presentViewController:alert animated:YES completion:nil];
}

- (void)done
{
  [PSOPad removeTarget:self];
  void (^onDone)(void) = self.onDone;
  [self dismissViewControllerAnimated:YES completion:onDone];
}

// PSOPadTarget: B or A finishes.
- (void)padMoveX:(NSInteger)dx y:(NSInteger)dy {}
- (void)padConfirm { [self done]; }
- (void)padBack { [self done]; }
@end

# Desktop Optimization Guide

This guide explains how to use the desktop-optimized widgets and utilities in the Cultioo Business App.

## Overview

The Cultioo Business App now includes comprehensive desktop optimization for macOS, Windows, and Linux platforms. The app automatically adapts its UI to provide a native desktop experience while maintaining consistency across all platforms.

## Key Features

### 1. Adaptive Sizing
- **Buttons**: 40px height on desktop vs 48px on mobile
- **Text Fields**: 44px height on desktop vs 56px on mobile
- **Padding**: 12px on desktop vs 16px on mobile
- **Border Radius**: 12px on desktop vs 16px on mobile
- **Font Size**: 14px on desktop vs 16px on mobile
- **Icon Size**: 18px on desktop vs 24px on mobile

### 2. Responsive Spacing
- Automatic spacing adjustment based on platform
- Consistent visual hierarchy across all screen sizes
- Optimized for readability on desktop displays

### 3. Desktop-Specific Interactions
- Hover effects with smooth transitions
- Click cursor changes for interactive elements
- Faster animation durations on desktop (100ms vs 150ms)
- Optimized press/hover scale effects

### 4. Visual Polish
- Flatter design with reduced shadows on desktop
- Optimized elevation (0.5 on desktop vs 2 on mobile)
- Refined divider thickness (0.5px on desktop vs 1px on mobile)
- Professional color handling for light/dark modes

## Usage

### Using DesktopOptimizedWidgets

```dart
import 'package:cultioo_business/shared/widgets/trade_republic_widgets.dart';

// Get adaptive button height
final buttonHeight = DesktopOptimizedWidgets.getButtonHeight();

// Get adaptive padding
final padding = DesktopOptimizedWidgets.getPadding();

// Check if running on desktop
if (DesktopOptimizedWidgets.isDesktopPlatform) {
  // Desktop-specific code
}

// Get adaptive text style
final textStyle = DesktopOptimizedWidgets.getDesktopTextStyle(
  color: Colors.black,
  fontSize: 14,
  fontWeight: FontWeight.w600,
);

// Get adaptive box decoration
final decoration = DesktopOptimizedWidgets.getDesktopBoxDecoration(
  backgroundColor: Colors.white,
  borderRadius: 12,
  showShadow: true,
);
```

### Using DesktopOptimizedContainer

```dart
DesktopOptimizedContainer(
  backgroundColor: Colors.white,
  borderRadius: 12,
  padding: DesktopOptimizedWidgets.getDesktopContentPadding(),
  child: Text('Desktop-optimized content'),
)
```

### Using DesktopOptimizedDivider

```dart
DesktopOptimizedDivider(
  color: Colors.grey[300],
  thickness: DesktopOptimizedWidgets.getDividerThickness(),
)
```

### Using DesktopOptimizedSpacing

```dart
// Horizontal spacing
DesktopOptimizedSpacing.horizontal()

// Vertical spacing
DesktopOptimizedSpacing.vertical()

// Custom spacing
DesktopOptimizedSpacing(width: 20, height: 10)
```

## Adaptive Button Heights

The `TradeRepublicButton` widget now automatically uses desktop-optimized heights:

```dart
// Automatically uses 40px on desktop, 44px on mobile
TradeRepublicButton(
  label: 'Click me',
  onPressed: () {},
)
```

## Platform Detection

The app uses the following logic to detect desktop platforms:

```dart
bool isDesktop = !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.macOS ||
     defaultTargetPlatform == TargetPlatform.windows ||
     defaultTargetPlatform == TargetPlatform.linux);
```

## Color Handling

Desktop-optimized color utilities:

```dart
// Hover color
final hoverColor = DesktopOptimizedWidgets.getHoverColor(baseColor, isLight);

// Pressed color
final pressedColor = DesktopOptimizedWidgets.getPressedColor(baseColor, isLight);

// Disabled color
final disabledColor = DesktopOptimizedWidgets.getDisabledColor(baseColor);
```

## Animation Durations

Desktop animations are faster for better responsiveness:

```dart
// Desktop: 100ms, Mobile: 150ms
final duration = DesktopOptimizedWidgets.getAnimationDuration();
```

## Scale Effects

Optimized scale effects for desktop interactions:

```dart
// Hover scale: 0.98 on desktop, 0.97 on mobile
final hoverScale = DesktopOptimizedWidgets.getHoverScale();

// Pressed scale: 0.95 on desktop, 0.97 on mobile
final pressedScale = DesktopOptimizedWidgets.getPressedScale();
```

## Best Practices

1. **Always use adaptive sizing**: Use `DesktopOptimizedWidgets` methods instead of hardcoded values
2. **Respect platform conventions**: Desktop apps should feel native to their platform
3. **Test on all platforms**: Verify the UI looks good on macOS, Windows, and Linux
4. **Use consistent spacing**: Maintain visual hierarchy with adaptive spacing
5. **Optimize for readability**: Ensure text is readable on desktop displays
6. **Handle hover states**: Implement proper hover effects for desktop users
7. **Respect cursor changes**: Use appropriate cursors for interactive elements

## Migration Guide

To migrate existing widgets to use desktop optimization:

1. Replace hardcoded sizes with `DesktopOptimizedWidgets` methods
2. Use `DesktopOptimizedContainer` for card-like elements
3. Use `DesktopOptimizedDivider` for separators
4. Use `DesktopOptimizedSpacing` for consistent spacing
5. Update text styles to use `getDesktopTextStyle()` and similar methods
6. Test thoroughly on all platforms

## Examples

### Example 1: Desktop-Optimized Card

```dart
DesktopOptimizedContainer(
  backgroundColor: Colors.white,
  borderRadius: DesktopOptimizedWidgets.getBorderRadius(),
  padding: DesktopOptimizedWidgets.getDesktopCardPadding(),
  child: Column(
    children: [
      Text(
        'Card Title',
        style: DesktopOptimizedWidgets.getDesktopHeadingStyle(
          color: Colors.black,
        ),
      ),
      DesktopOptimizedSpacing.vertical(),
      Text(
        'Card content goes here',
        style: DesktopOptimizedWidgets.getDesktopTextStyle(
          color: Colors.grey[700],
        ),
      ),
    ],
  ),
)
```

### Example 2: Desktop-Optimized Button

```dart
TradeRepublicButton(
  label: 'Submit',
  onPressed: () {},
  height: DesktopOptimizedWidgets.getButtonHeight(),
  padding: DesktopOptimizedWidgets.getDesktopButtonPadding(),
)
```

### Example 3: Desktop-Optimized List

```dart
ListView(
  children: [
    for (int i = 0; i < items.length; i++) ...[
      SizedBox(
        height: DesktopOptimizedWidgets.getListTileHeight(),
        child: ListTile(
          title: Text(items[i]),
        ),
      ),
      if (i < items.length - 1)
        DesktopOptimizedDivider(),
    ],
  ],
)
```

## Support

For questions or issues with desktop optimization, please refer to:
- `cultioo_desktop_layout.dart` - Desktop layout constants
- `desktop_optimized_widgets.dart` - Desktop widget utilities
- `trade_republic_widgets.dart` - Central widget exports

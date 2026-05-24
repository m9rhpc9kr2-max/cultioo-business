# Desktop Quick Start Guide

Schnelle Anleitung zur Konvertierung von Pages auf Desktop.

## 3-Schritt Konvertierung

### Schritt 1: Import hinzufügen

```dart
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';
```

### Schritt 2: Scaffold ersetzen

**Vorher:**
```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    appBar: AppBar(title: Text('My Page')),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [...]),
      ),
    ),
  );
}
```

**Nachher:**
```dart
@override
Widget build(BuildContext context) {
  return DesktopAppWrapper.buildScaffold(
    context: context,
    appBar: DesktopAppWrapper.buildAppBar(
      context: context,
      title: 'My Page',
    ),
    body: SingleChildScrollView(
      child: Padding(
        padding: DesktopAppWrapper.getPagePadding(),
        child: Column(children: [...]),
      ),
    ),
  );
}
```

### Schritt 3: Text Styles aktualisieren

**Vorher:**
```dart
Text(
  'Title',
  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
)
```

**Nachher:**
```dart
Text(
  'Title',
  style: DesktopOptimizedWidgets.getDesktopHeadingStyle(
    color: Colors.black,
    fontSize: 24,
  ),
)
```

## Häufige Replacements

### Padding
```dart
// Vorher
padding: const EdgeInsets.all(16)
padding: const EdgeInsets.symmetric(horizontal: 20)
padding: const EdgeInsets.fromLTRB(20, 16, 20, 16)

// Nachher
padding: DesktopAppWrapper.getPagePadding()
padding: EdgeInsets.symmetric(horizontal: DesktopAppWrapper.getHorizontalPadding())
padding: EdgeInsets.symmetric(
  horizontal: DesktopAppWrapper.getHorizontalPadding(),
  vertical: DesktopAppWrapper.getVerticalPadding(),
)
```

### Font Sizes
```dart
// Vorher
fontSize: 16
fontSize: 18
fontSize: 20

// Nachher
fontSize: DesktopOptimizedWidgets.getFontSize()
fontSize: DesktopOptimizedWidgets.getFontSize() + 2
fontSize: DesktopOptimizedWidgets.getFontSize() + 4
```

### Spacing
```dart
// Vorher
SizedBox(height: 12)
SizedBox(height: 16)
SizedBox(height: 24)

// Nachher
SizedBox(height: DesktopOptimizedWidgets.getSpacing())
SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 1.5)
SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3)
```

### Border Radius
```dart
// Vorher
borderRadius: BorderRadius.circular(16)
borderRadius: BorderRadius.circular(20)

// Nachher
borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius())
borderRadius: BorderRadius.circular(DesktopOptimizedWidgets.getBorderRadius() + 4)
```

## Checkliste für jede Page

- [ ] Imports hinzufügen
- [ ] Scaffold durch DesktopAppWrapper.buildScaffold ersetzen
- [ ] AppBar durch DesktopAppWrapper.buildAppBar ersetzen
- [ ] Alle Padding-Werte durch adaptive Werte ersetzen
- [ ] Alle Font-Größen durch adaptive Werte ersetzen
- [ ] Alle Spacing-Werte durch adaptive Werte ersetzen
- [ ] Alle Border-Radius-Werte durch adaptive Werte ersetzen
- [ ] Auf Desktop testen (macOS, Windows, Linux)
- [ ] Auf Mobile testen (iOS, Android)
- [ ] Commit und Push

## Beispiel: Vollständige Konvertierung

### Vorher
```dart
import 'package:flutter/material.dart';

class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('My Page'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Page Title',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 16),
              Text(
                'Page description',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text('Content'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

### Nachher
```dart
import 'package:flutter/material.dart';
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

class MyPage extends StatefulWidget {
  @override
  State<MyPage> createState() => _MyPageState();
}

class _MyPageState extends State<MyPage> {
  @override
  Widget build(BuildContext context) {
    return DesktopAppWrapper.buildScaffold(
      context: context,
      appBar: DesktopAppWrapper.buildAppBar(
        context: context,
        title: 'My Page',
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: DesktopAppWrapper.getPagePadding(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Page Title',
                style: DesktopOptimizedWidgets.getDesktopHeadingStyle(
                  color: Colors.black,
                  fontSize: 24,
                ),
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
              Text(
                'Page description',
                style: DesktopOptimizedWidgets.getDesktopTextStyle(
                  color: Colors.grey,
                  fontSize: DesktopOptimizedWidgets.getFontSize(),
                ),
              ),
              SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 3),
              DesktopAppWrapper.buildCard(
                context: context,
                child: Text('Content'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

## Tipps & Tricks

1. **Verwende Multiplier für Spacing**
   ```dart
   SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2)
   ```

2. **Verwende Addieren für Font Sizes**
   ```dart
   fontSize: DesktopOptimizedWidgets.getFontSize() + 4
   ```

3. **Nutze buildCard für Container**
   ```dart
   DesktopAppWrapper.buildCard(context: context, child: content)
   ```

4. **Nutze buildListItem für Listen**
   ```dart
   DesktopAppWrapper.buildListItem(
     context: context,
     title: 'Item',
     onTap: () {},
   )
   ```

5. **Nutze buildButton für Buttons**
   ```dart
   DesktopAppWrapper.buildButton(
     context: context,
     label: 'Click me',
     onPressed: () {},
   )
   ```

## Häufige Fehler

❌ **Hardcoded Werte**
```dart
padding: const EdgeInsets.all(16)
fontSize: 24
height: 48
```

✅ **Adaptive Werte**
```dart
padding: DesktopAppWrapper.getPagePadding()
fontSize: DesktopOptimizedWidgets.getFontSize() + 4
height: DesktopOptimizedWidgets.getButtonHeight()
```

❌ **Vergessene Imports**
```dart
// Keine Imports!
```

✅ **Vollständige Imports**
```dart
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';
```

❌ **Keine Wrapping**
```dart
body: MyContent()
```

✅ **Mit Wrapping**
```dart
body: DesktopAppWrapper.wrapPage(MyContent())
```

## Nächste Schritte

1. Wähle eine Page aus
2. Folge der 3-Schritt Anleitung
3. Teste auf Desktop
4. Teste auf Mobile
5. Commit und Push
6. Wiederhole für nächste Page

## Support

- Siehe `DESKTOP_CONVERSION_GUIDE.md` für detaillierte Anleitung
- Siehe `desktop_app_wrapper.dart` für alle verfügbaren Methoden
- Siehe `desktop_optimized_widgets.dart` für alle Größen und Stile

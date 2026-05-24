# Desktop App Conversion Guide

Dieses Dokument erklärt, wie die gesamte App auf Desktop optimiert wird.

## Übersicht

Die App wird auf drei Ebenen optimiert:

1. **Global Level** - `DesktopAppWrapper` für alle Pages
2. **Page Level** - `DesktopPageMixin` für Business Pages
3. **Widget Level** - `DesktopOptimizedWidgets` für einzelne Komponenten

## Schritt-für-Schritt Anleitung

### 1. Global Level - DesktopAppWrapper verwenden

Alle Pages sollten `DesktopAppWrapper` verwenden:

```dart
import 'package:cultioo_business/shared/widgets/desktop_app_wrapper.dart';

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
            children: [
              // Page content
            ],
          ),
        ),
      ),
    );
  }
}
```

### 2. Business Pages - DesktopPageMixin verwenden

Für Business Module Pages zusätzlich `DesktopPageMixin` verwenden:

```dart
import '../widgets/desktop_page_mixin.dart';

class MyBusinessPage extends StatefulWidget {
  @override
  State<MyBusinessPage> createState() => _MyBusinessPageState();
}

class _MyBusinessPageState extends State<MyBusinessPage> with DesktopPageMixin {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: buildResponsiveLayout(
        context,
        child: Column(
          children: [
            buildPageHeader(context, title: 'My Page'),
            SizedBox(height: getSpacing() * 2),
            buildCard(context, child: content),
          ],
        ),
      ),
    );
  }
}
```

### 3. Widget Level - DesktopOptimizedWidgets verwenden

Für einzelne Widgets:

```dart
import 'package:cultioo_business/shared/widgets/desktop_optimized_widgets.dart';

// Adaptive Größen
final buttonHeight = DesktopOptimizedWidgets.getButtonHeight();
final padding = DesktopOptimizedWidgets.getPadding();
final fontSize = DesktopOptimizedWidgets.getFontSize();

// Adaptive Stile
final textStyle = DesktopOptimizedWidgets.getDesktopTextStyle(
  color: Colors.black,
  fontSize: 14,
);

// Adaptive Container
final decoration = DesktopOptimizedWidgets.getDesktopBoxDecoration(
  backgroundColor: Colors.white,
  borderRadius: 12,
);
```

## Wichtige Größen auf Desktop

### Buttons
- Höhe: 40px (statt 48px auf Mobile)
- Padding: 12px horizontal (statt 16px)

### Text Fields
- Höhe: 44px (statt 56px auf Mobile)
- Padding: 12px (statt 16px)

### Text Sizes
- Page Title: 24px
- Section Title: 16px
- Body Text: 14px (statt 16px)
- Label Text: 13px (statt 15px)

### Spacing
- Standard Spacing: 8px (statt 12px)
- Standard Padding: 12px (statt 16px)
- Border Radius: 12px (statt 16px)

### Icons
- Icon Size: 18px (statt 24px)

## Pages zum Konvertieren

### Auth Pages
- [ ] login_page.dart
- [ ] register_page.dart
- [ ] signup_page.dart
- [ ] two_factor_page.dart
- [ ] business_info_page.dart
- [ ] driver_info_page.dart
- [ ] driver_signup_page.dart

### Business Pages
- [ ] business_home_page.dart
- [ ] products_page.dart
- [ ] orders_page.dart
- [ ] messenger_page.dart
- [ ] chat_view_page.dart
- [ ] business_account_page.dart

### Delvioo Pages
- [ ] delvioo_home_page.dart
- [ ] delvioo_orders_page.dart
- [ ] delvioo_messages_page.dart
- [ ] delvioo_account_page.dart
- [ ] delvioo_maps_page.dart

### Shared Pages
- [ ] my_account_page.dart
- [ ] onboarding_page.dart

## Conversion Patterns

### Pattern 1: Simple Page with Header

```dart
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
              // Content
            ],
          ),
        ),
      ),
    );
  }
}
```

### Pattern 2: Page with Form

```dart
class MyFormPage extends StatefulWidget {
  @override
  State<MyFormPage> createState() => _MyFormPageState();
}

class _MyFormPageState extends State<MyFormPage> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DesktopAppWrapper.buildScaffold(
      context: context,
      appBar: DesktopAppWrapper.buildAppBar(
        context: context,
        title: 'Form Page',
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: DesktopAppWrapper.getPagePadding(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DesktopAppWrapper.buildTextField(
                    context: context,
                    label: 'Email',
                    controller: _controller,
                    hint: 'Enter your email',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  SizedBox(height: DesktopOptimizedWidgets.getSpacing() * 2),
                  DesktopAppWrapper.buildButton(
                    context: context,
                    label: 'Submit',
                    onPressed: () {},
                    width: double.infinity,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

### Pattern 3: Page with List

```dart
class MyListPage extends StatefulWidget {
  @override
  State<MyListPage> createState() => _MyListPageState();
}

class _MyListPageState extends State<MyListPage> {
  final List<String> items = ['Item 1', 'Item 2', 'Item 3'];

  @override
  Widget build(BuildContext context) {
    return DesktopAppWrapper.buildScaffold(
      context: context,
      appBar: DesktopAppWrapper.buildAppBar(
        context: context,
        title: 'List Page',
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: DesktopAppWrapper.getPagePadding(),
          child: DesktopAppWrapper.buildCard(
            context: context,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: items.length,
              separatorBuilder: (context, index) => Divider(
                thickness: DesktopOptimizedWidgets.getDividerThickness(),
              ),
              itemBuilder: (context, index) {
                return DesktopAppWrapper.buildListItem(
                  context: context,
                  title: items[index],
                  onTap: () {},
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
```

## Best Practices

1. **Immer DesktopAppWrapper verwenden** - für konsistente Styling
2. **Adaptive Größen verwenden** - nicht hardcoded
3. **Max-Width constraints** - für breite Screens
4. **Responsive padding** - basierend auf Platform
5. **Testen auf Desktop** - macOS, Windows, Linux
6. **Konsistente Abstände** - verwende getSpacing()
7. **Konsistente Schriftgrößen** - verwende getDesktopTextStyle()

## Häufige Fehler

❌ **Falsch:**
```dart
Text('Title', style: TextStyle(fontSize: 24))
```

✅ **Richtig:**
```dart
Text('Title', style: DesktopOptimizedWidgets.getDesktopHeadingStyle(
  color: Colors.black,
  fontSize: 24,
))
```

❌ **Falsch:**
```dart
Padding(padding: const EdgeInsets.all(16), child: child)
```

✅ **Richtig:**
```dart
Padding(padding: DesktopAppWrapper.getPagePadding(), child: child)
```

❌ **Falsch:**
```dart
SizedBox(height: 48) // Button height
```

✅ **Richtig:**
```dart
SizedBox(height: DesktopOptimizedWidgets.getButtonHeight())
```

## Exports aktualisieren

Stelle sicher, dass alle neuen Widgets in `trade_republic_widgets.dart` exportiert werden:

```dart
export 'desktop_app_wrapper.dart';
export 'desktop_optimized_widgets.dart';
export 'desktop_page_mixin.dart';
```

## Testing

Nach jeder Konvertierung testen:

1. **Desktop (macOS)** - Größen und Abstände prüfen
2. **Desktop (Windows)** - Rendering prüfen
3. **Desktop (Linux)** - Kompatibilität prüfen
4. **Mobile** - Sicherstellen, dass Mobile nicht beeinflusst wird

## Support

Für Fragen oder Probleme:
- Siehe `DESKTOP_OPTIMIZATION.md` für Widget-Details
- Siehe `DESKTOP_PAGE_MIGRATION.md` für Page-Details
- Siehe `desktop_app_wrapper.dart` für globale Utilities

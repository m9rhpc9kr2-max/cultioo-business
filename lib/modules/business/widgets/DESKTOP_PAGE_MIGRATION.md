# Desktop Page Migration Guide

This guide explains how to migrate all business pages to use desktop-optimized layouts and styling.

## Overview

The `DesktopPageMixin` provides a comprehensive set of utilities for creating desktop-optimized pages. All business pages should be updated to use these utilities for consistent styling across the application.

## Quick Start

### 1. Add the Mixin to Your Page

```dart
import '../widgets/desktop_page_mixin.dart';

class MyBusinessPage extends StatefulWidget {
  const MyBusinessPage({super.key});

  @override
  State<MyBusinessPage> createState() => _MyBusinessPageState();
}

class _MyBusinessPageState extends State<MyBusinessPage> with DesktopPageMixin {
  @override
  Widget build(BuildContext context) {
    // Use mixin methods for desktop-optimized styling
  }
}
```

### 2. Use Desktop-Optimized Text Styles

Replace hardcoded text styles with mixin methods:

```dart
// Before
Text(
  'Page Title',
  style: TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    color: Colors.black,
  ),
)

// After
Text(
  'Page Title',
  style: getPageTitleStyle(context),
)
```

### 3. Use Desktop-Optimized Padding

Replace hardcoded padding with adaptive values:

```dart
// Before
Padding(
  padding: const EdgeInsets.all(20),
  child: child,
)

// After
Padding(
  padding: EdgeInsets.all(getPadding()),
  child: child,
)
```

## Available Methods

### Text Styles

- `getPageTitleStyle(context)` - Large page titles (24px)
- `getSectionTitleStyle(context)` - Section headers (16px)
- `getBodyTextStyle(context)` - Body text (14px on desktop)
- `getLabelTextStyle(context)` - Labels and captions (13px on desktop)

### Spacing & Sizing

- `getSpacing()` - Standard spacing (8px on desktop)
- `getPadding()` - Standard padding (12px on desktop)
- `getBorderRadius()` - Standard border radius (12px on desktop)

### Layout Builders

- `buildPageHeader()` - Page header with title and optional subtitle
- `buildSection()` - Section with title and content
- `buildCard()` - Desktop-optimized card
- `buildListItem()` - Desktop-optimized list item
- `buildGrid()` - Desktop-optimized grid
- `buildEmptyState()` - Empty state UI
- `buildLoadingState()` - Loading state UI
- `buildErrorState()` - Error state UI
- `buildResponsiveLayout()` - Responsive page wrapper

## Migration Examples

### Example 1: Simple Page Header

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: buildResponsiveLayout(
      context,
      child: Column(
        children: [
          buildPageHeader(
            context,
            title: 'My Products',
            subtitle: Text(
              'Manage your product listings',
              style: getBodyTextStyle(context),
            ),
            trailing: ElevatedButton(
              onPressed: () {},
              child: const Text('Add Product'),
            ),
          ),
          // Page content here
        ],
      ),
    ),
  );
}
```

### Example 2: Page with Sections

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: buildResponsiveLayout(
      context,
      child: Column(
        children: [
          buildPageHeader(
            context,
            title: 'Orders',
          ),
          SizedBox(height: getSpacing() * 2),
          buildSection(
            context,
            title: 'Recent Orders',
            child: buildCard(
              context,
              child: ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (var order in orders)
                    buildListItem(
                      context,
                      title: Text(
                        order.id,
                        style: getSectionTitleStyle(context),
                      ),
                      subtitle: Text(
                        order.date,
                        style: getLabelTextStyle(context),
                      ),
                      trailing: Text(
                        order.total,
                        style: getBodyTextStyle(context),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
```

### Example 3: Page with Grid

```dart
@override
Widget build(BuildContext context) {
  return Scaffold(
    body: buildResponsiveLayout(
      context,
      child: Column(
        children: [
          buildPageHeader(
            context,
            title: 'Products',
          ),
          SizedBox(height: getSpacing() * 2),
          buildGrid(
            context,
            crossAxisCount: 3,
            children: [
              for (var product in products)
                buildCard(
                  context,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Image.network(product.image),
                      SizedBox(height: getSpacing()),
                      Text(
                        product.name,
                        style: getSectionTitleStyle(context),
                      ),
                      Text(
                        product.price,
                        style: getBodyTextStyle(context),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    ),
  );
}
```

### Example 4: Page with States

```dart
@override
Widget build(BuildContext context) {
  if (isLoading) {
    return Scaffold(
      body: buildLoadingState(context),
    );
  }

  if (hasError) {
    return Scaffold(
      body: buildErrorState(
        context,
        message: 'Failed to load data',
        onRetry: _loadData,
      ),
    );
  }

  if (items.isEmpty) {
    return Scaffold(
      body: buildEmptyState(
        context,
        title: 'No Items',
        description: 'You haven\'t created any items yet.',
        icon: Icon(
          Icons.inbox_outlined,
          size: DesktopOptimizedWidgets.getIconSize() * 3,
          color: Colors.grey[400],
        ),
        action: ElevatedButton(
          onPressed: () {},
          child: const Text('Create Item'),
        ),
      ),
    );
  }

  return Scaffold(
    body: buildResponsiveLayout(
      context,
      child: Column(
        children: [
          buildPageHeader(context, title: 'Items'),
          // Content here
        ],
      ),
    ),
  );
}
```

## Font Sizes on Desktop

- Page Title: 24px
- Section Title: 16px
- Body Text: 14px
- Label Text: 13px

## Spacing on Desktop

- Standard Spacing: 8px
- Standard Padding: 12px
- Border Radius: 12px

## Best Practices

1. **Always use the mixin methods** - Don't hardcode values
2. **Use buildResponsiveLayout** - Wraps content with max-width and padding
3. **Use buildPageHeader** - Consistent page headers across all pages
4. **Use buildSection** - Consistent section styling
5. **Use buildCard** - Consistent card styling
6. **Use buildListItem** - Consistent list item styling
7. **Test on desktop** - Verify appearance on macOS, Windows, and Linux

## Pages to Migrate

- [ ] business_home_page.dart
- [ ] products_page.dart
- [ ] orders_page.dart
- [ ] messenger_page.dart
- [ ] chat_view_page.dart
- [ ] business_account_page.dart
- [ ] main_navigation.dart

## Migration Checklist

For each page:

1. Add `with DesktopPageMixin` to the State class
2. Replace hardcoded text styles with mixin methods
3. Replace hardcoded padding with mixin methods
4. Wrap content with `buildResponsiveLayout()`
5. Use `buildPageHeader()` for page titles
6. Use `buildSection()` for content sections
7. Use `buildCard()` for card containers
8. Use `buildListItem()` for list items
9. Test on desktop platforms
10. Commit changes

## Common Patterns

### Pattern 1: Page with Header and Content

```dart
buildResponsiveLayout(
  context,
  child: Column(
    children: [
      buildPageHeader(context, title: 'Title'),
      SizedBox(height: getSpacing() * 2),
      buildCard(context, child: content),
    ],
  ),
)
```

### Pattern 2: Page with Multiple Sections

```dart
buildResponsiveLayout(
  context,
  child: Column(
    children: [
      buildPageHeader(context, title: 'Title'),
      SizedBox(height: getSpacing() * 2),
      buildSection(context, title: 'Section 1', child: content1),
      SizedBox(height: getSpacing() * 2),
      buildSection(context, title: 'Section 2', child: content2),
    ],
  ),
)
```

### Pattern 3: Page with List

```dart
buildResponsiveLayout(
  context,
  child: Column(
    children: [
      buildPageHeader(context, title: 'Title'),
      SizedBox(height: getSpacing() * 2),
      buildCard(
        context,
        child: ListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (var item in items)
              buildListItem(
                context,
                title: Text(item.title, style: getSectionTitleStyle(context)),
                subtitle: Text(item.subtitle, style: getLabelTextStyle(context)),
              ),
          ],
        ),
      ),
    ],
  ),
)
```

## Support

For questions about desktop page migration, refer to:
- `desktop_page_mixin.dart` - Mixin implementation
- `desktop_optimized_widgets.dart` - Widget utilities
- Existing migrated pages for examples

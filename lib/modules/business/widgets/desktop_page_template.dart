import 'package:flutter/material.dart';
import '../../../shared/widgets/desktop_optimized_widgets.dart';
import 'desktop_page_mixin.dart';

/// Template for desktop-optimized business pages
/// Copy this template and customize for your specific page
class DesktopPageTemplate extends StatefulWidget {
  const DesktopPageTemplate({super.key});

  @override
  State<DesktopPageTemplate> createState() => _DesktopPageTemplateState();
}

class _DesktopPageTemplateState extends State<DesktopPageTemplate>
    with DesktopPageMixin {
  bool isLoading = false;
  bool hasError = false;
  String errorMessage = '';
  List<String> items = ['Item 1', 'Item 2', 'Item 3'];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => isLoading = true);
    try {
      // Simulate loading
      await Future.delayed(const Duration(seconds: 1));
      setState(() => isLoading = false);
    } catch (e) {
      setState(() {
        hasError = true;
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Handle loading state
    if (isLoading) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: buildLoadingState(context));
    }

    // Handle error state
    if (hasError) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: buildErrorState(
          context,
          message: errorMessage,
          onRetry: _loadData));
    }

    // Handle empty state
    if (items.isEmpty) {
      return Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: buildEmptyState(
          context,
          title: 'No Items',
          description: 'You haven\'t created any items yet.',
          icon: Icon(
            Icons.inbox_outlined,
            size: DesktopOptimizedWidgets.getIconSize() * 3,
            color: Colors.grey[400]),
          action: ElevatedButton(
            onPressed: () {},
            child: Text('Create Item'))));
    }

    // Main content
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: buildResponsiveLayout(
        context,
        maxWidth: 1200,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Page header
            buildPageHeader(
              context,
              title: 'Page Title',
              subtitle: Text(
                'Page description goes here',
                style: getBodyTextStyle(context)),
              trailing: ElevatedButton(
                onPressed: () {},
                child: Text('Action Button'))),
            SizedBox(height: getSpacing() * 2),

            // First section
            buildSection(
              context,
              title: 'Section 1',
              trailing: TextButton(
                onPressed: () {},
                child: Text('View All')),
              child: buildCard(
                context,
                child: ListView(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    for (int i = 0; i < items.length; i++) ...[
                      buildListItem(
                        context,
                        title: Text(
                          items[i],
                          style: getSectionTitleStyle(context)),
                        subtitle: Text(
                          'Item description',
                          style: getLabelTextStyle(context)),
                        leading: Icon(
                          Icons.check_circle,
                          color: Colors.green[400]),
                        trailing: Icon(
                          Icons.arrow_forward,
                          size: DesktopOptimizedWidgets.getIconSize(),
                          color: Colors.grey[400]),
                        showDivider: i < items.length - 1),
                    ],
                  ]))),
            SizedBox(height: getSpacing() * 2),

            // Second section with grid
            buildSection(
              context,
              title: 'Section 2 - Grid View',
              child: buildGrid(
                context,
                crossAxisCount: 3,
                childAspectRatio: 1.2,
                children: [
                  for (var item in items)
                    buildCard(
                      context,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item,
                                style: getSectionTitleStyle(context)),
                              SizedBox(height: getSpacing()),
                              Text(
                                'Grid item description',
                                style: getBodyTextStyle(context)),
                            ]),
                          Align(
                            alignment: Alignment.bottomRight,
                            child: ElevatedButton(
                              onPressed: () {},
                              child: Text('View'))),
                        ])),
                ])),
            SizedBox(height: getSpacing() * 2),

            // Third section with custom content
            buildSection(
              context,
              title: 'Section 3 - Custom Content',
              showDivider: true,
              child: buildCard(
                context,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Custom content goes here',
                      style: getBodyTextStyle(context)),
                    SizedBox(height: getSpacing()),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {},
                            child: Text('Button 1'))),
                        SizedBox(width: getSpacing()),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {},
                            child: Text('Button 2'))),
                      ]),
                  ]))),
            SizedBox(height: getPadding() * 2),
          ])));
  }
}

/// Example of a simple list page
class SimpleListPageExample extends StatefulWidget {
  const SimpleListPageExample({super.key});

  @override
  State<SimpleListPageExample> createState() => _SimpleListPageExampleState();
}

class _SimpleListPageExampleState extends State<SimpleListPageExample>
    with DesktopPageMixin {
  final List<Map<String, String>> items = [
    {'title': 'Item 1', 'subtitle': 'Description 1', 'value': '\$100'},
    {'title': 'Item 2', 'subtitle': 'Description 2', 'value': '\$200'},
    {'title': 'Item 3', 'subtitle': 'Description 3', 'value': '\$300'},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: buildResponsiveLayout(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildPageHeader(
              context,
              title: 'Simple List Example',
              subtitle: Text(
                'This is a simple list page example',
                style: getBodyTextStyle(context))),
            SizedBox(height: getSpacing() * 2),
            buildCard(
              context,
              child: ListView(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (int i = 0; i < items.length; i++)
                    buildListItem(
                      context,
                      title: Text(
                        items[i]['title']!,
                        style: getSectionTitleStyle(context)),
                      subtitle: Text(
                        items[i]['subtitle']!,
                        style: getLabelTextStyle(context)),
                      trailing: Text(
                        items[i]['value']!,
                        style: getBodyTextStyle(context)),
                      showDivider: i < items.length - 1),
                ])),
          ])));
  }
}

/// Example of a grid page
class GridPageExample extends StatefulWidget {
  const GridPageExample({super.key});

  @override
  State<GridPageExample> createState() => _GridPageExampleState();
}

class _GridPageExampleState extends State<GridPageExample>
    with DesktopPageMixin {
  final List<String> items = List.generate(12, (i) => 'Product ${i + 1}');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: buildResponsiveLayout(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            buildPageHeader(
              context,
              title: 'Grid Example',
              subtitle: Text(
                'This is a grid page example',
                style: getBodyTextStyle(context))),
            SizedBox(height: getSpacing() * 2),
            buildGrid(
              context,
              crossAxisCount: 4,
              childAspectRatio: 1.0,
              children: [
                for (var item in items)
                  buildCard(
                    context,
                    child: Center(
                      child: Text(
                        item,
                        style: getSectionTitleStyle(context),
                        textAlign: TextAlign.center))),
              ]),
          ])));
  }
}

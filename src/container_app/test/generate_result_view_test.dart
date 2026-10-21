import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:applix/widgets/generate_result_view.dart';

Widget _app({
  VoidCallback? onBuild,
  VoidCallback? onPreview,
  VoidCallback? onRegenerate,
}) =>
    MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: GenerateResultView(
          appName: 'Budget',
          preview: const Center(child: Text('LIVE PREVIEW')),
          code: '<html><body><button>one</button></body></html>',
          onBack: () {},
          onOpenPreview: onPreview ?? () {},
          onBuild: onBuild ?? () {},
          onRegenerate: onRegenerate ?? () {},
          onEditDetails: () {},
        ),
      ),
    );

void main() {
  testWidgets('Preview is the first tab and is visible by default', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.byKey(GenerateResultView.previewTabKey), findsOneWidget);
    expect(find.byKey(GenerateResultView.codeTabKey), findsOneWidget);
    expect(find.byKey(GenerateResultView.previewPaneKey), findsOneWidget);
    expect(find.text('LIVE PREVIEW'), findsOneWidget);
    expect(find.byKey(GenerateResultView.codePaneKey), findsNothing);
    expect(find.textContaining('<html>'), findsNothing);
  });

  testWidgets('Code is hidden until its tab is chosen', (tester) async {
    await tester.pumpWidget(_app());
    await tester.tap(find.byKey(GenerateResultView.codeTabKey));
    await tester.pumpAndSettle();
    expect(find.byKey(GenerateResultView.codePaneKey), findsOneWidget);
    expect(find.byKey(GenerateResultView.previewPaneKey), findsNothing);
    expect(find.textContaining('<html>'), findsOneWidget);
  });

  testWidgets('actions stay visible and outside the code pane', (tester) async {
    await tester.pumpWidget(_app());
    final actions = find.byKey(GenerateResultView.actionsKey);
    expect(actions, findsOneWidget);
    final screen = tester.getSize(find.byType(Scaffold));
    final bottom = tester.getBottomRight(actions).dy;
    expect(bottom, lessThanOrEqualTo(screen.height));
    expect(bottom, greaterThan(screen.height - 120));

    await tester.tap(find.byKey(GenerateResultView.codeTabKey));
    await tester.pumpAndSettle();
    expect(actions, findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(GenerateResultView.codePaneKey),
        matching: find.text('Build APK'),
      ),
      findsNothing,
    );
  });

  testWidgets('regenerate, preview and build are wired', (tester) async {
    var preview = 0, build = 0, regenerate = 0;
    await tester.pumpWidget(_app(
      onPreview: () => preview++,
      onBuild: () => build++,
      onRegenerate: () => regenerate++,
    ));
    await tester.tap(find.byKey(GenerateResultView.previewActionKey));
    await tester.tap(find.byKey(GenerateResultView.buildActionKey));
    await tester.tap(find.byKey(GenerateResultView.regenerateActionKey));
    expect(preview, 1);
    expect(build, 1);
    expect(regenerate, 1);
  });

  testWidgets('generating disables the action bar', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: GenerateResultView(
          appName: 'Budget',
          preview: const SizedBox(),
          code: '<html></html>',
          generating: true,
          onBack: () {},
          onOpenPreview: () {},
          onBuild: () {},
          onRegenerate: () {},
          onEditDetails: () {},
        ),
      ),
    ));
    expect(find.text('Generating...'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(
        find.byKey(GenerateResultView.buildActionKey));
    expect(button.onPressed, isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lattice_core/lattice_core.dart';
import 'package:lattice_editor/src/host/editor_host.dart';
import 'package:lattice_editor/src/panels/signing_wizard.dart';

class _EnvHost extends MemoryHost {
  _EnvHost(this.set, {this.existingPaths = const {}})
      : super(description: 'a test');

  final Set<String> set;
  final Set<String> existingPaths;

  @override
  Set<String> presentEnvironment(Iterable<String> names) =>
      names.where(set.contains).toSet();

  @override
  bool environmentPathExists(String name) => existingPaths.contains(name);
}

void main() {
  Future<void> pump(
    WidgetTester tester,
    EditorHost host,
    List<BuildTarget> targets,
  ) async {
    await tester.pumpWidget(MaterialApp(
      home: SigningWizard(host: host, targets: targets),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a project with only unsigned targets says so', (tester) async {
    await pump(tester, _EnvHost(const {}),
        const [BuildTarget.linux, BuildTarget.web]);

    expect(find.textContaining('are code-signed'), findsOneWidget);
    expect(find.text('ANDROID'), findsNothing);
  });

  testWidgets('missing credentials are listed by variable name',
      (tester) async {
    await pump(tester, _EnvHost(const {}), const [BuildTarget.android]);

    expect(find.text('ANDROID'), findsOneWidget);
    expect(find.text('not ready'), findsOneWidget);
    expect(find.text('LATTICE_ANDROID_KEYSTORE'), findsOneWidget);
    expect(find.text('not set'), findsNWidgets(4));
  });

  testWidgets('a keystore path that is gone reads differently from unset',
      (tester) async {
    final host = _EnvHost(
      const {
        'LATTICE_ANDROID_KEYSTORE',
        'LATTICE_ANDROID_KEY_ALIAS',
        'LATTICE_ANDROID_STORE_PASSWORD',
        'LATTICE_ANDROID_KEY_PASSWORD',
      },
      // Set, but the file is not there.
      existingPaths: const {},
    );
    await pump(tester, host, const [BuildTarget.android]);

    expect(find.text('set, but that file is not there'), findsOneWidget);
    expect(find.text('not ready'), findsOneWidget);
  });

  testWidgets('everything present reads as ready', (tester) async {
    final host = _EnvHost(
      const {
        'LATTICE_ANDROID_KEYSTORE',
        'LATTICE_ANDROID_KEY_ALIAS',
        'LATTICE_ANDROID_STORE_PASSWORD',
        'LATTICE_ANDROID_KEY_PASSWORD',
      },
      existingPaths: const {'LATTICE_ANDROID_KEYSTORE'},
    );
    await pump(tester, host, const [BuildTarget.android]);

    expect(find.text('ready'), findsOneWidget);
    expect(find.text('set'), findsNWidgets(4));
  });
}

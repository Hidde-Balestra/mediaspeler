import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mediaspeler/services/pip.dart';
import 'package:mediaspeler/widgets/dim_overlay.dart';

class _FakeEffects extends DimEffects {
  int dims = 0, restores = 0;
  @override
  Future<void> dim() async => dims++;
  @override
  Future<void> restore() async => restores++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('mediaspeler/pip');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  group('beeld-in-beeld', () {
    final calls = <MethodCall>[];

    setUp(() {
      calls.clear();
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return switch (call.method) {
          'isSupported' => true,
          'enter' => true,
          _ => null,
        };
      });
    });

    tearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      PipController.instance.setInPip(false);
    });

    test('vraagt Android om ondersteuning, automatisch PiP en direct PiP', () async {
      final pip = PipController.instance;
      expect(await pip.isSupported(), isTrue);
      await pip.setAuto(true);
      expect(await pip.enter(), isTrue);
      expect(calls.map((c) => '${c.method}:${c.arguments}'),
          ['isSupported:null', 'setAuto:true', 'enter:null']);
    });

    test('meldingen van Android over het kleine venster', () async {
      final pip = PipController.instance;
      var notified = 0;
      void listener() => notified++;
      pip.addListener(listener);
      await messenger.handlePlatformMessage('mediaspeler/pip',
          const StandardMethodCodec().encodeMethodCall(const MethodCall('changed', true)), (_) {});
      expect(pip.inPip, isTrue);
      pip.setInPip(true); // geen dubbele melding
      expect(notified, 1);
      pip.removeListener(listener);
    });

    test('zonder Android-kant (Windows, iOS): netjes "niet ondersteund"', () async {
      messenger.setMockMethodCallHandler(channel, null);
      final pip = PipController.instance;
      expect(await pip.isSupported(), isFalse);
      expect(await pip.enter(), isFalse);
      await pip.setAuto(true); // geen fout
    });

    test('fout van Android: ook "niet ondersteund"', () async {
      messenger.setMockMethodCallHandler(channel, (_) async => throw PlatformException(code: 'x'));
      expect(await PipController.instance.isSupported(), isFalse);
      expect(await PipController.instance.enter(), isFalse);
    });
  });

  group('scherm dimmen', () {
    testWidgets('dimt bij tonen, herstelt bij weghalen, tik = terug', (tester) async {
      final effects = _FakeEffects();
      var exited = false;
      await tester.pumpWidget(MaterialApp(
        home: DimOverlay(effects: effects, title: 'Video', onExit: () => exited = true),
      ));
      expect(effects.dims, 1);
      expect(find.text('Video'), findsOneWidget);
      expect(find.textContaining('tik om terug te gaan'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      expect(exited, isTrue);

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      expect(effects.restores, 1);
    });

    test('echte effecten zonder platform: geen fouten', () async {
      const effects = DimEffects();
      await effects.dim();
      await effects.restore();
    });
  });
}

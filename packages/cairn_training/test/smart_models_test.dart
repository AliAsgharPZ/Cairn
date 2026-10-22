import 'dart:io';

import 'package:cairn_training/cairn_training.dart';
import 'package:test/test.dart';

({List<T> train, List<T> heldOut}) _split<T>(List<T> all) {
  final train = <T>[], held = <T>[];
  for (var i = 0; i < all.length; i++) {
    (i % 5 == 4 ? held : train).add(all[i]);
  }
  return (train: train, heldOut: held);
}

void main() {
  group('language detector (real training on the bundled corpus)', () {
    test('held-out accuracy is high and loss falls', () {
      final parts = _split(langDetectCorpus);
      final clf = TextClassifier(labels: const ['fa', 'en']);
      final losses = clf.train(parts.train, epochs: 40);
      expect(losses.last, lessThan(losses.first),
          reason: 'training must actually learn (loss falls)');
      final acc = clf.accuracy(parts.heldOut);
      expect(acc, greaterThanOrEqualTo(0.9),
          reason: 'held-out language id accuracy was $acc');
    });

    test('obvious cases classify correctly after full training', () {
      final clf = TextClassifier(labels: const ['fa', 'en']);
      clf.train(langDetectCorpus, epochs: 40);
      expect(clf.predict('سلام خوبی؟ امروز چطوری؟').label, 'fa');
      expect(clf.predict('Hello, how are you today?').label, 'en');
      expect(clf.predict('لطفاً این فایل را پاک کن').label, 'fa');
      expect(clf.predict('Please delete this file').label, 'en');
    });
  });

  group('interpreter / intent classifier', () {
    test('held-out accuracy is solid; key intents classify', () {
      final parts = _split(intentCorpus);
      final clf = TextClassifier(
          labels: const ['question', 'task', 'chat', 'translate']);
      final losses = clf.train(parts.train, epochs: 60);
      expect(losses.last, lessThan(losses.first));
      final acc = clf.accuracy(parts.heldOut);
      expect(acc, greaterThanOrEqualTo(0.7),
          reason: 'held-out intent accuracy was $acc');
      final full = TextClassifier(
          labels: const ['question', 'task', 'chat', 'translate']);
      full.train(intentCorpus, epochs: 60);
      expect(full.predict('این فایل را پاک کن').label, 'task');
      expect(full.predict('پایتخت فرانسه کجاست؟').label, 'question');
      expect(full.predict('سلام خوبی؟').label, 'chat');
      expect(full.predict('این جمله را به انگلیسی ترجمه کن').label,
          'translate');
    });
  });

  group('classifier serialization', () {
    test('encode/decode preserves predictions', () {
      final clf = TextClassifier(labels: const ['fa', 'en']);
      clf.train(langDetectCorpus, epochs: 15);
      final restored = TextClassifier.decode(clf.encode());
      expect(restored.predict('سلام دنیا').label,
          clf.predict('سلام دنیا').label);
      expect(restored.predict('hello world').label, 'en');
    });
  });

  group('phrase translator', () {
    final translator = PhraseTranslator.bundled();

    test('exact training pairs translate both ways', () {
      expect(translator.translate('سلام خوبی؟', toEnglish: true).text,
          'hello how are you');
      expect(translator.translate('hello how are you', toEnglish: false).text,
          'سلام خوبی');
      expect(translator.translate('صبح بخیر', toEnglish: true).coverage, 1.0);
    });

    test('recombined words use the lexicon; unknowns pass through', () {
      final r = translator.translate('این کتاب جدید است', toEnglish: true);
      expect(r.text, contains('book'));
      expect(r.text, contains('new'));
      expect(r.coverage, greaterThan(0.5));
      final withUnknown =
          translator.translate('سلام xyzzy', toEnglish: true);
      expect(withUnknown.text, contains('xyzzy'));
      expect(withUnknown.coverage, lessThan(1.0));
    });

    test('serialization round-trip', () {
      final restored = PhraseTranslator.decode(translator.encode());
      expect(restored.translate('ممنون', toEnglish: true).text, 'thank you');
    });
  });

  group('smart model store', () {
    test('save/list/get/delete round-trip on disk', () async {
      final tmp = await Directory.systemTemp.createTemp('cairn_smart');
      addTearDown(() => tmp.delete(recursive: true));
      final store = SmartModelStore(tmp);
      final clf = TextClassifier(labels: const ['fa', 'en']);
      clf.train(langDetectCorpus, epochs: 5);
      await store.save(SmartModel(
        id: 'langdetect:test',
        name: 'Language detector',
        kind: SmartModelKind.langDetect,
        createdAtIso: '2026-10-22T00:00:00.000Z',
        metrics: const {'accuracy': 0.95, 'examples': 168},
        payloadJson: clf.toJson(),
      ));
      final listed = await store.list();
      expect(listed, hasLength(1));
      expect(listed.single.kind, SmartModelKind.langDetect);
      final loaded = await store.latestOfKind(SmartModelKind.langDetect);
      expect(loaded, isNotNull);
      expect(loaded!.asClassifier().predict('سلام').label, 'fa');
      await store.delete('langdetect:test');
      expect(await store.list(), isEmpty);
    });
  });
}

import 'dart:math';

import 'package:ble_spike/chat/chat.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'replay window accepts reorder, rejects duplicates and stale counters',
    () {
      var highest = -1;
      var mask = 0;

      var decision = evaluateReplayWindow(
        highestCounter: highest,
        seenMask: mask,
        counter: 5,
      );
      expect(decision.accepted, isTrue);
      highest = decision.nextHighestCounter;
      mask = decision.nextSeenMask;

      decision = evaluateReplayWindow(
        highestCounter: highest,
        seenMask: mask,
        counter: 3,
      );
      expect(decision.accepted, isTrue);
      highest = decision.nextHighestCounter;
      mask = decision.nextSeenMask;

      decision = evaluateReplayWindow(
        highestCounter: highest,
        seenMask: mask,
        counter: 3,
      );
      expect(decision.accepted, isFalse);
      expect(decision.isDuplicate, isTrue);
      expect(decision.isTooOld, isFalse);

      decision = evaluateReplayWindow(
        highestCounter: highest,
        seenMask: mask,
        counter: 100,
      );
      expect(decision.accepted, isTrue);
      highest = decision.nextHighestCounter;
      mask = decision.nextSeenMask;

      decision = evaluateReplayWindow(
        highestCounter: highest,
        seenMask: mask,
        counter: 10,
      );
      expect(decision.accepted, isFalse);
      expect(decision.isDuplicate, isFalse);
      expect(decision.isTooOld, isTrue);
    },
  );

  test('randomized stream matches a naive replay model', () {
    final random = Random(1337);
    for (var run = 0; run < 100; run++) {
      final stream = <int>[];
      for (var i = 0; i < 90; i++) {
        stream.add(i);
      }
      for (var i = 0; i < 45; i++) {
        stream.add(random.nextInt(90));
      }
      stream.shuffle(random);

      var highest = -1;
      var mask = 0;

      var naiveHighest = -1;
      final naiveAccepted = <int>{};

      for (final counter in stream) {
        final decision = evaluateReplayWindow(
          highestCounter: highest,
          seenMask: mask,
          counter: counter,
        );
        final naive = _naiveReplayDecision(
          highestCounter: naiveHighest,
          acceptedCounters: naiveAccepted,
          counter: counter,
        );

        expect(decision.accepted, naive.accepted);
        expect(decision.isTooOld, naive.isTooOld);
        expect(decision.isDuplicate, naive.isDuplicate);

        if (decision.accepted) {
          highest = decision.nextHighestCounter;
          mask = decision.nextSeenMask;
          if (counter > naiveHighest) {
            naiveHighest = counter;
          }
          naiveAccepted.add(counter);
        }
      }
    }
  });
}

_NaiveDecision _naiveReplayDecision({
  required int highestCounter,
  required Set<int> acceptedCounters,
  required int counter,
}) {
  if (highestCounter < 0) {
    return const _NaiveDecision(
      accepted: true,
      isDuplicate: false,
      isTooOld: false,
    );
  }
  if (counter > highestCounter) {
    return const _NaiveDecision(
      accepted: true,
      isDuplicate: false,
      isTooOld: false,
    );
  }
  final distance = highestCounter - counter;
  if (distance >= kChatReplayWindowSize) {
    return const _NaiveDecision(
      accepted: false,
      isDuplicate: false,
      isTooOld: true,
    );
  }
  if (acceptedCounters.contains(counter)) {
    return const _NaiveDecision(
      accepted: false,
      isDuplicate: true,
      isTooOld: false,
    );
  }
  return const _NaiveDecision(
    accepted: true,
    isDuplicate: false,
    isTooOld: false,
  );
}

class _NaiveDecision {
  const _NaiveDecision({
    required this.accepted,
    required this.isDuplicate,
    required this.isTooOld,
  });

  final bool accepted;
  final bool isDuplicate;
  final bool isTooOld;
}

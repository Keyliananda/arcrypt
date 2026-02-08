const int kChatReplayWindowSize = 64;
const int _kReplayWindowMask64 = 0xFFFFFFFFFFFFFFFF;

class ReplayWindowDecision {
  const ReplayWindowDecision({
    required this.accepted,
    required this.isDuplicate,
    required this.isTooOld,
    required this.nextHighestCounter,
    required this.nextSeenMask,
  });

  final bool accepted;
  final bool isDuplicate;
  final bool isTooOld;
  final int nextHighestCounter;
  final int nextSeenMask;
}

ReplayWindowDecision evaluateReplayWindow({
  required int highestCounter,
  required int seenMask,
  required int counter,
}) {
  if (highestCounter < 0) {
    return ReplayWindowDecision(
      accepted: true,
      isDuplicate: false,
      isTooOld: false,
      nextHighestCounter: counter,
      nextSeenMask: 1,
    );
  }

  if (counter > highestCounter) {
    final shift = counter - highestCounter;
    final nextMask = shift >= kChatReplayWindowSize
        ? 1
        : ((seenMask << shift) | 1) & _kReplayWindowMask64;
    return ReplayWindowDecision(
      accepted: true,
      isDuplicate: false,
      isTooOld: false,
      nextHighestCounter: counter,
      nextSeenMask: nextMask,
    );
  }

  final distance = highestCounter - counter;
  if (distance >= kChatReplayWindowSize) {
    return ReplayWindowDecision(
      accepted: false,
      isDuplicate: false,
      isTooOld: true,
      nextHighestCounter: highestCounter,
      nextSeenMask: seenMask,
    );
  }

  final bit = 1 << distance;
  if ((seenMask & bit) != 0) {
    return ReplayWindowDecision(
      accepted: false,
      isDuplicate: true,
      isTooOld: false,
      nextHighestCounter: highestCounter,
      nextSeenMask: seenMask,
    );
  }

  return ReplayWindowDecision(
    accepted: true,
    isDuplicate: false,
    isTooOld: false,
    nextHighestCounter: highestCounter,
    nextSeenMask: (seenMask | bit) & _kReplayWindowMask64,
  );
}

/// A D-pad left/right hold
/// accelerates the seek jump size the longer it's held, keyed off the
/// platform's own key-repeat count.
int seekIncrementForHold(int repeatCount) {
  if (repeatCount == 0) return 10000;
  if (repeatCount < 8) return 20000;
  if (repeatCount < 20) return 45000;
  return 90000;
}

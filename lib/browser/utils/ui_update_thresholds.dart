bool shouldUpdateWebProgress(int previousProgress, int nextProgress) {
  if (previousProgress == nextProgress) {
    return false;
  }

  return nextProgress <= 0 ||
      nextProgress >= 100 ||
      (previousProgress - nextProgress).abs() >= 5;
}

bool hasSignificantScrollChange(
  double previousScrollPosition,
  double nextScrollPosition,
) {
  return (previousScrollPosition - nextScrollPosition).abs() >= 24;
}

public enum Arithmetic {
  public static func add(_ lhs: Int, _ rhs: Int) -> Int {
    lhs + rhs
  }

  public static func clamp(_ value: Int, to range: ClosedRange<Int>) -> Int {
    min(max(value, range.lowerBound), range.upperBound)
  }
}

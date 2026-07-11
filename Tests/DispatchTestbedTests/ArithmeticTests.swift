import Testing
@testable import DispatchTestbed

@Suite("Arithmetic")
struct ArithmeticTests {
  @Test("adds two integers")
  func adds() {
    #expect(Arithmetic.add(2, 3) == 5)
  }
}

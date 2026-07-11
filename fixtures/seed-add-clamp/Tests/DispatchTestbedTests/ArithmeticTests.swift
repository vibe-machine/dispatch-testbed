import Testing
@testable import DispatchTestbed

@Suite("Arithmetic")
struct ArithmeticTests {
  @Test("adds two integers")
  func adds() {
    #expect(Arithmetic.add(2, 3) == 5)
  }

  @Test("clamps below, inside, and above a range")
  func clamps() {
    #expect(Arithmetic.clamp(-1, to: 0...10) == 0)
    #expect(Arithmetic.clamp(4, to: 0...10) == 4)
    #expect(Arithmetic.clamp(14, to: 0...10) == 10)
  }
}

import Testing
@testable import MTGSheetOptimizer

/// A translation with different placeholders would make String(format:) show wrong values or crash.
@Test func italianKeepsPlaceholders() {
    func placeholders(_ s: String) -> [Character] { zip(s, s.dropFirst()).filter { $0.0 == "%" }.map(\.1) }
    for (english, italian) in italianTranslations {
        #expect(placeholders(english) == placeholders(italian), "\(english)")
    }
}

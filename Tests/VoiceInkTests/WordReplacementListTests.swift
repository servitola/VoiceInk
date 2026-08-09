import AppKit
import SwiftData
import SwiftUI
import Testing

@testable import VoiceInk

@MainActor
struct WordReplacementSortingTests {
    private func items(_ pairs: [(String, String)]) -> [WordReplacement] {
        pairs.map { WordReplacement(originalText: $0.0, replacementText: $0.1) }
    }

    @Test func sortsByOriginalIgnoringCase() {
        let sorted = WordReplacementSorting.sorted(
            items([("banana", "1"), ("Apple", "2"), ("cherry", "3")]), by: .originalAsc)
        #expect(sorted.map(\.originalText) == ["Apple", "banana", "cherry"])
    }

    @Test func sortsByOriginalDescending() {
        let sorted = WordReplacementSorting.sorted(
            items([("banana", "1"), ("Apple", "2"), ("cherry", "3")]), by: .originalDesc)
        #expect(sorted.map(\.originalText) == ["cherry", "banana", "Apple"])
    }

    @Test func sortsByReplacement() {
        let sorted = WordReplacementSorting.sorted(
            items([("a", "zebra"), ("b", "Ant"), ("c", "moose")]), by: .replacementAsc)
        #expect(sorted.map(\.replacementText) == ["Ant", "moose", "zebra"])
    }

    @Test func sortsByReplacementDescending() {
        let sorted = WordReplacementSorting.sorted(
            items([("a", "zebra"), ("b", "Ant"), ("c", "moose")]), by: .replacementDesc)
        #expect(sorted.map(\.replacementText) == ["zebra", "moose", "Ant"])
    }

    @Test func sortsCyrillicAlphabetically() {
        let sorted = WordReplacementSorting.sorted(
            items([("яблоко", "1"), ("Арбуз", "2"), ("клод", "3")]), by: .originalAsc)
        #expect(sorted.map(\.originalText) == ["Арбуз", "клод", "яблоко"])
    }
}

@MainActor
struct WordReplacementListPerformanceTests {
    /// A dictionary with hundreds of entries used to re-sort the whole list dozens
    /// of times per layout pass — once per rendered row plus once per body pass —
    /// which froze the screen and made the input fields unusable. The list now
    /// sorts once, so a large dictionary must lay out well inside a second.
    @Test func largeDictionaryLaysOutQuickly() throws {
        let container = try ModelContainer(
            for: WordReplacement.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        for i in 0..<2000 {
            container.mainContext.insert(
                WordReplacement(originalText: "original-\(i)", replacementText: "replacement-\(i)"))
        }
        try container.mainContext.save()

        let started = CFAbsoluteTimeGetCurrent()
        let host = NSHostingView(
            rootView: ScrollView { WordReplacementView() }
                .frame(width: 700, height: 600)
                .modelContainer(container)
        )
        host.frame = NSRect(x: 0, y: 0, width: 700, height: 600)
        let window = NSWindow(
            contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = host
        window.orderFront(nil)
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let elapsed = CFAbsoluteTimeGetCurrent() - started

        #expect(elapsed < 1.0, "laying out 2000 replacements took \(Int(elapsed * 1000))ms")
    }
}

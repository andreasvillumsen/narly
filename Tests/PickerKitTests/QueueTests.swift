import Foundation
import Testing
@testable import PickerKit

@Suite struct QueueTests {
    @Test(arguments: ["https://example.com/a?q=a%2Fb#part", "http://localhost:8080/test", "https://example.com/"])
    func acceptsWebLinks(_ text: String) throws {
        let url = try #require(URL(string: text))
        #expect(LinkQueue.accepts(url))
    }

    @Test(arguments: ["file:///tmp/test", "file:///tmp/test.pdf", "file://remote/tmp/test.html", "mailto:a@example.com", "notion://page", "https:", "javascript:alert(1)"])
    func rejectsUnownedSchemesAndMissingHost(_ text: String) throws {
        #expect(!LinkQueue.accepts(try #require(URL(string: text))))
    }

    @Test(arguments: ["html", "htm", "shtml", "xhtml", "xht", "HTML"])
    func acceptsLocalWebDocuments(_ extensionName: String) throws {
        let url = try #require(URL(string: "file:///tmp/My%20page.\(extensionName)#chapter"))
        #expect(LinkQueue.accepts(url))
        #expect(PendingLink(url: url).displayName == "My page.\(extensionName)")
    }

    @Test func repeatedURLsRemainSeparateAndFIFO() throws {
        let url = try #require(URL(string: "https://example.com/?a=1%2F2&b=%E2%9C%93#fragment"))
        var queue = LinkQueue()
        queue.enqueue([url, url])
        let first = try #require(queue.pending.first)
        let second = try #require(queue.pending.last)
        #expect(first.id != second.id)
        let outOfOrder = queue.complete(second.id)
        #expect(!outOfOrder)
        let completedFirst = queue.complete(first.id)
        #expect(completedFirst)
        #expect(queue.pending.first?.url.absoluteString == url.absoluteString)
        let repeatedCompletion = queue.complete(first.id)
        #expect(!repeatedCompletion)
        let completedSecond = queue.complete(second.id)
        #expect(completedSecond)
        #expect(queue.pending.isEmpty)
    }

    @Test func dismissalAndRestorePreserveOrderWithoutOverwritingNewLinks() throws {
        let links = try (0..<10).map { try #require(URL(string: "https://example.com/\($0)")) }
        var queue = LinkQueue()
        queue.enqueue(links)
        queue.dismiss()
        queue.dismiss() // duplicate blur must not erase the saved queue
        #expect(queue.pending.isEmpty)
        #expect(queue.dismissed == links)
        let restored = queue.restore()
        #expect(restored)
        #expect(queue.pending.map(\.url) == links)
        let restoredAgain = queue.restore()
        #expect(!restoredAgain)
        #expect(queue.dismissed.isEmpty)
    }
}

@Suite struct PlacementTests {
    @Test(arguments: [
        CGPoint(x: -1800, y: 400), CGPoint(x: -20, y: 20),
        CGPoint(x: 3000, y: 1200), CGPoint(x: -5000, y: -2000)
    ])
    func clampedToNegativeOriginScreen(_ pointer: CGPoint) {
        let display = CGRect(x: -1920, y: -200, width: 1920, height: 1080)
        let frame = PickerPlacement.frame(pointer: pointer, size: CGSize(width: 340, height: 300), visibleFrame: display)
        #expect(display.contains(frame))
        #expect(frame.width == 340)
        #expect(frame.height == 300)
    }

    @Test func oversizedWindowFitsSmallDisplay() {
        let screen = CGRect(x: 200, y: 300, width: 200, height: 150)
        let frame = PickerPlacement.frame(pointer: .zero, size: CGSize(width: 340, height: 300), visibleFrame: screen)
        #expect(screen.contains(frame))
        #expect(frame.width > 0 && frame.height > 0)
    }

    @Test func disconnectedScreenFallsBackToNearestConnectedScreen() {
        let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900),
                       CGRect(x: -1920, y: 0, width: 1920, height: 1080)]
        #expect(PickerPlacement.screenIndex(pointer: CGPoint(x: -1000, y: 600), frames: screens) == 1)
        #expect(PickerPlacement.screenIndex(pointer: CGPoint(x: 3500, y: 600), frames: screens) == 0)
        #expect(PickerPlacement.screenIndex(pointer: .zero, frames: []) == nil)
    }
}

@Suite struct KeyboardTests {
    @Test func navigationAndLayoutAwareShortcuts() {
        #expect(PickerCommand.decode(keyCode: 48, characters: nil, command: false, shift: true, option: false, control: false) == .move(-1))
        #expect(PickerCommand.decode(keyCode: 125, characters: nil, command: false, shift: false, option: false, control: false) == .move(1))
        #expect(PickerCommand.decode(keyCode: 53, characters: nil, command: false, shift: false, option: false, control: false) == .dismiss)
        #expect(PickerCommand.decode(keyCode: 36, characters: nil, command: false, shift: false, option: false, control: false) == .choose)
        #expect(PickerCommand.decode(keyCode: 8, characters: "c", command: true, shift: false, option: false, control: false) == .copy)
        #expect(PickerCommand.decode(keyCode: 19, characters: "2", command: false, shift: false, option: false, control: false) == .chooseIndex(1))
        #expect(PickerCommand.decode(keyCode: 19, characters: "@", command: false, shift: false, option: true, control: false) == .chooseShortcut("@"))
        #expect(PickerCommand.decode(keyCode: 12, characters: "q", command: true, shift: false, option: false, control: false) == nil)
    }
}

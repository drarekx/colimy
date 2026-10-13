import AppKit
import SwiftUI

/// Follows `docker logs -f` (one container) or `docker compose logs -f` (a stack).
@MainActor
final class LogStream: ObservableObject {
    enum Source: Hashable {
        case container(Container)
        case stack(Stack)
    }

    private static let maxLines = 5000

    @Published private(set) var lines: [String] = []
    /// Changes when `lines` is replaced or trimmed rather than appended to.
    @Published private(set) var generation = 0
    @Published private(set) var isRunning = false
    @Published private(set) var error: String?

    private var task: Task<Void, Never>?
    private var pending: [String] = []
    private var flushScheduled = false
    private(set) var source: Source?

    func follow(_ source: Source) {
        stop()
        self.source = source
        lines = []
        generation += 1
        error = nil
        resume()
    }

    /// Starts following again (after the container restarted, for example).
    func resume() {
        guard let source, let host = DockerStore.shared.dockerHost, task == nil else { return }
        let tail = String(Settings.shared.logTail)
        let args: [String]
        switch source {
        case .container(let container):
            args = ["logs", "-f", "--tail", tail, container.id]
        case .stack(let stack):
            args = Docker.composeArguments(stack) + ["logs", "-f", "--tail", tail, "--no-color"]
        }
        isRunning = true
        task = Task { [weak self] in
            do {
                try await ToolProcess.run(.docker, args, environment: Docker.environment(host: host),
                                          includeErrors: true) { line in
                    let text = stripANSI(line)
                    Task { @MainActor in self?.enqueue(text) }
                }
            } catch {
                if case ToolError.cancelled = error {} else if !Task.isCancelled {
                    let message = error.localizedDescription
                    Task { @MainActor in self?.error = message }
                }
            }
            self?.task = nil
            self?.isRunning = false
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        isRunning = false
    }

    func clear() {
        lines = []
        pending = []
        generation += 1
    }

    var text: String { lines.joined(separator: "\n") }

    /// Lines arrive in bursts; publish them a few times a second.
    private func enqueue(_ line: String) {
        pending.append(line)
        guard !flushScheduled else { return }
        flushScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
    }

    private func flush() {
        flushScheduled = false
        guard !pending.isEmpty else { return }
        lines.append(contentsOf: pending)
        pending = []
        if lines.count > Self.maxLines {
            lines.removeFirst(lines.count - Self.maxLines + 500)
            generation += 1
        }
    }
}

/// Read-only, selectable log text. Appends incrementally and sticks to the bottom
/// unless the user scrolled up.
struct LogTextView: NSViewRepresentable {
    let lines: [String]
    let generation: Int
    var filter: String = ""

    final class Coordinator {
        var key = ""
        var renderedCount = 0
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        scroll.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        let text = scroll.documentView as! NSTextView
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 6, height: 8)
        text.font = .monospacedSystemFont(ofSize: 11.5, weight: .regular)
        text.textColor = NSColor(red: 0xD6 / 255, green: 0xD6 / 255, blue: 0xDA / 255, alpha: 1)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let text = scroll.documentView as? NSTextView, let storage = text.textStorage else { return }
        let coordinator = context.coordinator
        let key = "\(generation)|\(filter)"
        let atBottom = scroll.contentView.bounds.maxY >= text.bounds.maxY - 30
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11.5, weight: .regular),
            .foregroundColor: NSColor(red: 0xD6 / 255, green: 0xD6 / 255, blue: 0xDA / 255, alpha: 1),
        ]

        if key != coordinator.key || lines.count < coordinator.renderedCount {
            coordinator.key = key
            let body = matching(lines[...]).joined(separator: "\n")
            storage.setAttributedString(NSAttributedString(string: body, attributes: attributes))
            coordinator.renderedCount = lines.count
            text.scrollToEndOfDocument(nil)
            return
        }
        guard lines.count > coordinator.renderedCount else { return }
        let added = matching(lines[coordinator.renderedCount...])
        coordinator.renderedCount = lines.count
        guard !added.isEmpty else { return }
        let prefix = storage.length > 0 ? "\n" : ""
        storage.append(NSAttributedString(string: prefix + added.joined(separator: "\n"), attributes: attributes))
        if atBottom { text.scrollToEndOfDocument(nil) }
    }

    private func matching(_ slice: ArraySlice<String>) -> [String] {
        let query = filter.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return Array(slice) }
        return slice.filter { $0.localizedCaseInsensitiveContains(query) }
    }
}

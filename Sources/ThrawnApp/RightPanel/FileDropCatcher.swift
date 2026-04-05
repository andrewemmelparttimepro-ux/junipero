import SwiftUI
#if os(macOS)
import AppKit

struct FileDropCatcher: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let onDropURLs: ([URL]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> DropView {
        let view = DropView()
        view.onDropURLs = { urls in
            onDropURLs(urls)
        }
        view.onTargetChanged = { targeted in
            isTargeted = targeted
        }
        return view
    }

    func updateNSView(_ nsView: DropView, context: Context) {
        nsView.onDropURLs = { urls in
            onDropURLs(urls)
        }
        nsView.onTargetChanged = { targeted in
            isTargeted = targeted
        }
    }

    final class Coordinator: NSObject {
        let parent: FileDropCatcher
        init(parent: FileDropCatcher) {
            self.parent = parent
        }
    }
}

final class DropView: NSView {
    var onDropURLs: (([URL]) -> Void)?
    var onTargetChanged: ((Bool) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        onTargetChanged?(true)
        return .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        onTargetChanged?(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTargetChanged?(false)
        let pasteboard = sender.draggingPasteboard
        guard let files = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL], !files.isEmpty else {
            return false
        }
        onDropURLs?(files)
        return true
    }
}
#endif

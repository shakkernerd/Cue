import Dispatch
import Foundation

/// Calls `onChange` on `queue` after the file at a path is written in place, replaced (an editor's atomic save by
/// rename), deleted or created, once per burst of changes: events closer together than `debounce` produce one call.
///
/// It watches the file's directory for entries appearing, disappearing or being renamed over, and the file itself for
/// writes. After a replacement it watches the new file. A symbolic link in the path is followed when a watch opens, so
/// a config linked from elsewhere is watched at its target. While the directory does not exist it checks again every
/// `retryInterval` and reports a change once it appears.
///
/// Call `start` and `stop` on `queue`, the queue `onChange` runs on.
///
/// Events can arrive for changes that leave the file's contents as they were (another file in the directory, a
/// rewrite with the same bytes); the receiver compares what it reads with what it has.
public final class ConfigWatcher: @unchecked Sendable {
    // Every stored property below is read and written only on `queue`.
    private let filePath: String
    private let directoryPath: String
    private let queue: DispatchQueue
    private let debounce: Double
    private let retryInterval: Double
    private let onChange: @Sendable () -> Void

    private var running = false
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pendingChange: DispatchWorkItem?
    private var pendingRetry: DispatchWorkItem?

    public init(
        url: URL, queue: DispatchQueue, debounce: Double = 0.1, retryInterval: Double = 1,
        onChange: @escaping @Sendable () -> Void
    ) {
        filePath = url.path(percentEncoded: false)
        directoryPath = url.deletingLastPathComponent().path(percentEncoded: false)
        self.queue = queue
        self.debounce = debounce
        self.retryInterval = retryInterval
        self.onChange = onChange
    }

    /// Starts watching. Changes from now on are reported; the file's current contents are not.
    public func start() {
        dispatchPrecondition(condition: .onQueue(queue))
        guard !running else { return }
        running = true
        openWatches()
    }

    /// Stops watching and drops a change not reported yet.
    public func stop() {
        dispatchPrecondition(condition: .onQueue(queue))
        running = false
        pendingChange?.cancel()
        pendingChange = nil
        pendingRetry?.cancel()
        pendingRetry = nil
        closeFileWatch()
        directorySource?.cancel()
        directorySource = nil
    }

    // MARK: Watches

    /// Opens the directory watch and, when the file exists, the file watch. Returns whether the directory is watched.
    @discardableResult
    private func openWatches() -> Bool {
        if directorySource == nil {
            guard let source = Self.source(
                path: directoryPath, events: [.write, .delete, .rename], queue: queue,
                handler: { [weak self] in self?.directoryChanged() })
            else {
                scheduleRetry()
                return false
            }
            directorySource = source
        }
        if fileSource == nil {
            fileSource = Self.source(
                path: filePath, events: [.write, .extend, .delete, .rename], queue: queue,
                handler: { [weak self] in self?.fileChanged() })
        }
        return true
    }

    private func closeFileWatch() {
        fileSource?.cancel()
        fileSource = nil
    }

    private func directoryChanged() {
        guard running, let source = directorySource else { return }
        if !source.data.isDisjoint(with: [.delete, .rename]) {
            // The directory itself was removed or moved away: watch its path again, now or once it is back.
            source.cancel()
            directorySource = nil
        }
        // An entry was added, removed or renamed over: the file at the path may be a new one.
        closeFileWatch()
        openWatches()
        changed()
    }

    private func fileChanged() {
        guard running, let source = fileSource else { return }
        if !source.data.isDisjoint(with: [.delete, .rename]) {
            // Replaced or deleted: what is at the path now, if anything, is another file.
            closeFileWatch()
            openWatches()
        }
        changed()
    }

    private func scheduleRetry() {
        guard running, pendingRetry == nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self, running else { return }
            pendingRetry = nil
            if openWatches() { changed() }
        }
        pendingRetry = item
        queue.asyncAfter(deadline: .now() + retryInterval, execute: item)
    }

    /// Reports a change once no further change has arrived for `debounce`.
    private func changed() {
        pendingChange?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, running else { return }
            pendingChange = nil
            onChange()
        }
        pendingChange = item
        queue.asyncAfter(deadline: .now() + debounce, execute: item)
    }

    private static func source(
        path: String, events: DispatchSource.FileSystemEvent, queue: DispatchQueue,
        handler: @escaping @Sendable () -> Void
    ) -> DispatchSourceFileSystemObject? {
        let descriptor = open(path, O_EVTONLY)
        guard descriptor >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor, eventMask: events, queue: queue)
        source.setEventHandler(handler: handler)
        source.setCancelHandler { close(descriptor) }
        source.resume()
        return source
    }
}

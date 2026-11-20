import Foundation

/// The saved library on disk. The app and the command-line tool can both change it, so every
/// change re-reads the file under an exclusive lock, applies one change and writes it back.
public struct ProfileLibraryFile: Sendable {
    public struct Snapshot: Sendable {
        public var library: ProfileLibrary
        public var stamp: Stamp?
    }

    /// Identifies one version of the file. Atomic saves replace the file, which changes the inode.
    public struct Stamp: Equatable, Sendable {
        var inode: UInt64
        var size: Int64
        var seconds: Int
        var nanoseconds: Int
    }

    public let url: URL

    public init(url: URL) { self.url = url }

    public static var standard: Self {
        Self(url: URL.applicationSupportDirectory.appending(path: "Hostshift/profiles.json"))
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: url.path) }

    public func stamp() -> Stamp? {
        var info = stat()
        guard stat(url.path, &info) == 0 else { return nil }
        return Stamp(inode: info.st_ino, size: info.st_size,
                     seconds: info.st_mtimespec.tv_sec, nanoseconds: info.st_mtimespec.tv_nsec)
    }

    /// Reads the saved library, or nil before first launch has created it.
    public func load() throws -> Snapshot? {
        guard exists else { return nil }
        let stamp = stamp()
        return Snapshot(library: try ProfileLibrary.load(from: url), stamp: stamp)
    }

    /// Reads the saved library, creating it with `original` as the Original profile if it does not exist yet.
    public func loadOrCreate(original: String?) throws -> Snapshot? {
        if let snapshot = try load() { return snapshot }
        guard let original else { return nil }
        return try withLock {
            if let snapshot = try load() { return snapshot }
            let library = ProfileLibrary(original: original)
            try library.save(to: url)
            return Snapshot(library: library, stamp: stamp())
        }
    }

    /// Applies one change to the latest saved library. Nothing is written if the change throws.
    @discardableResult
    public func update(_ change: (inout ProfileLibrary) throws -> Void) throws -> Snapshot {
        try withLock {
            var library = try ProfileLibrary.load(from: url)
            try change(&library)
            try library.save(to: url)
            return Snapshot(library: library, stamp: stamp())
        }
    }

    private func withLock<T>(_ body: () throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path + ".lock", O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        defer { close(descriptor) }
        while flock(descriptor, LOCK_EX) != 0 {
            guard errno == EINTR else { throw Self.posixError() }
        }
        return try body()
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}

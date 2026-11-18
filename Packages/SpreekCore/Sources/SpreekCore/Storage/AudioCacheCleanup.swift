import Foundation

/// Settings › Storage clean-ups. Each returns the bytes it freed and leaves entries whose files
/// are in `protecting` (the clip that is playing) alone. Plain file system work: run it off the
/// main actor.
extension AudioCache {
    /// Removes the entries with these keys. `progress` gets (done, total) after each one.
    @discardableResult
    public func remove(
        keys: some Collection<String>, protecting: Set<URL> = [], progress: (@Sendable (Int, Int) -> Void)? = nil
    ) -> Int64 {
        let wanted = Set(keys)
        let files = entryFiles().filter { wanted.contains($0.key) }
        let protected = Set(protecting.map(\.standardizedPath))
        var freed: Int64 = 0
        for (index, urls) in files.values.enumerated() {
            freed += removeFiles(urls, protected: protected)
            progress?(index + 1, files.count)
        }
        return freed
    }

    /// Removes entries not used since `cutoff`.
    @discardableResult
    public func removeEntries(lastUsedBefore cutoff: Date, protecting: Set<URL> = []) -> Int64 {
        let stale = StorageScanner.entries(in: self).filter { $0.lastUsed < cutoff }.map(\.key)
        return remove(keys: stale, protecting: protecting)
    }

    /// Removes entries until the cache is at most `limit` bytes: least recently used first,
    /// entries in `favoriteKeys` only after every other one.
    @discardableResult
    public func trim(toBytes limit: Int64, favoriteKeys: Set<String> = [], protecting: Set<URL> = []) -> Int64 {
        let entries = StorageScanner.entries(in: self)
        var total = entries.reduce(0) { $0 + $1.totalBytes }
        guard total > limit else { return 0 }
        let files = entryFiles()
        let protected = Set(protecting.map(\.standardizedPath))
        let order = entries.sorted { a, b in
            let aFavorite = favoriteKeys.contains(a.key)
            let bFavorite = favoriteKeys.contains(b.key)
            if aFavorite != bFavorite { return !aFavorite }
            return a.lastUsed < b.lastUsed
        }
        var freed: Int64 = 0
        for entry in order where total > limit {
            let bytes = removeFiles(files[entry.key] ?? [], protected: protected)
            freed += bytes
            total -= bytes
        }
        return freed
    }

    /// Every file in the cache folder, grouped by entry key.
    func entryFiles() -> [String: [URL]] {
        var files: [String: [URL]] = [:]
        for url in StorageScanner.contents(of: root) {
            files[url.deletingPathExtension().lastPathComponent, default: []].append(url)
        }
        return files
    }

    /// Deletes one entry's files, unless one of them is protected.
    private func removeFiles(_ urls: [URL], protected: Set<String>) -> Int64 {
        guard !urls.contains(where: { protected.contains($0.standardizedPath) }) else { return 0 }
        var freed: Int64 = 0
        for url in urls {
            let size = StorageScanner.fileSize(url)
            if (try? FileManager.default.removeItem(at: url)) != nil { freed += size }
        }
        return freed
    }
}

extension StorageScanner {
    /// Just the cache entries.
    static func entries(in cache: AudioCache) -> [CacheEntryInfo] {
        StorageScanner(root: cache.root.deletingLastPathComponent()).scanEntries(cache: cache)
    }
}

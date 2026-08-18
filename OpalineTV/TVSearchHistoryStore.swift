import Foundation

final class TVSearchHistoryStore {
    private let defaults: UserDefaults
    private let key = "opalineTV.searchHistory"
    private let limit = 10

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var queries: [String] {
        defaults.stringArray(forKey: key) ?? []
    }

    func add(_ rawQuery: String) {
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        var updated = queries.filter {
            $0.localizedCaseInsensitiveCompare(query) != .orderedSame
        }
        updated.insert(query, at: 0)
        defaults.set(Array(updated.prefix(limit)), forKey: key)
    }

    func clear() {
        defaults.removeObject(forKey: key)
    }
}

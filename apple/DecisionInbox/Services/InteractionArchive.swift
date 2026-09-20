import Foundation

/// Small explicit user-owned records, separate from the regenerable feed
/// cache. Tests substitute UserDefaults so no signed-in data is touched.
@MainActor
enum InteractionArchive {
    private static func read<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
    private static func write<T: Encodable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
    static func saved() -> [Message] { read([Message].self, key: "interaction.saved.v1") ?? [] }
    static func save(_ messages: [Message]) { write(messages, key: "interaction.saved.v1") }
    static func runs() -> [String: UnsubscribeRun] { read([String: UnsubscribeRun].self, key: "interaction.runs.v1") ?? [:] }
    static func saveRuns(_ runs: [String: UnsubscribeRun]) { write(runs, key: "interaction.runs.v1") }
}

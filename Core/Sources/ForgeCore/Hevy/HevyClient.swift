import Foundation

/// Reads everything from Hevy's REST API. The key comes from the caller (the CLI reads HEVY_API_KEY).
public struct HevyClient: Sendable {
    let apiKey: String
    let session: URLSession
    let baseURL = URL(string: "https://api.hevyapp.com")!

    public init(apiKey: String, session: URLSession = .shared) {
        self.apiKey = apiKey
        self.session = session
    }

    public func fetchAllTemplates() async throws -> [HevyTemplate] { try await fetchAll(HevyTemplatesPage.self, "/v1/exercise_templates", pageSize: 100) }
    public func fetchAllRoutines() async throws -> [HevyRoutine] { try await fetchAll(HevyRoutinesPage.self, "/v1/routines", pageSize: 10) }
    public func fetchAllWorkouts() async throws -> [HevyWorkout] { try await fetchAll(HevyWorkoutsPage.self, "/v1/workouts", pageSize: 10) }

    func fetchAll<P: HevyPage>(_ type: P.Type, _ path: String, pageSize: Int) async throws -> [P.Item] {
        var items: [P.Item] = []
        var page = 1
        var pageCount = 1
        repeat {
            var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "page", value: "\(page)"), URLQueryItem(name: "pageSize", value: "\(pageSize)")]
            var request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "api-key")
            request.setValue("application/json", forHTTPHeaderField: "accept")
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                throw ForgeError.invalid(status == 401 ? "Hevy rejected the API key (401)" : "Hevy answered \(status) for \(path)")
            }
            let decoded = try HevyJSON.decoder.decode(P.self, from: data)
            items += decoded.items
            pageCount = decoded.pageCount
            page += 1
        } while page <= pageCount
        return items
    }
}

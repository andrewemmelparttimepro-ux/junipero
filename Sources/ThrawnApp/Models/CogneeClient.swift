import Foundation

// MARK: - Cognee Memory Client
//
// Provides explicit recall and store operations against the Cognee API (localhost:8000).
// Used as an on-demand tool instead of autoRecall, which blocks every chat request.

@MainActor
final class CogneeClient: ObservableObject {
    @Published var isRecalling = false
    @Published var lastRecallResults: [CogneeSearchResult] = []

    private let baseURL: String
    private let datasetName: String
    private let session: URLSession

    struct CogneeSearchResult: Codable, Identifiable {
        var id: String { text.prefix(40) + String(score) }
        var text: String
        var score: Double

        enum CodingKeys: String, CodingKey {
            case text = "content_text"
            case score = "score"
        }

        // Flexible decoding: Cognee response format can vary
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            // Try content_text first, fall back to other fields
            if let t = try? c.decode(String.self, forKey: .text) {
                text = t
            } else {
                // Try plain "text" key
                let alt = try decoder.container(keyedBy: AltKeys.self)
                text = (try? alt.decode(String.self, forKey: .text))
                    ?? (try? alt.decode(String.self, forKey: .content))
                    ?? ""
            }
            score = (try? c.decode(Double.self, forKey: .score)) ?? 0
        }

        init(text: String, score: Double) {
            self.text = text
            self.score = score
        }

        private enum AltKeys: String, CodingKey {
            case text, content
        }
    }

    init(baseURL: String = "http://localhost:8000", datasetName: String = "ndai") {
        self.baseURL = baseURL
        self.datasetName = datasetName
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    /// Check if Cognee is reachable and healthy
    func isHealthy() async -> Bool {
        guard let url = URL(string: "\(baseURL)/health") else { return false }
        do {
            let (data, response) = try await session.data(for: URLRequest(url: url))
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let status = json["status"] as? String {
                return status == "ready" || status == "healthy"
            }
            return true
        } catch {
            return false
        }
    }

    /// Search Cognee memory for relevant context. Returns formatted context string.
    func recall(query: String, maxResults: Int = 5) async -> String? {
        isRecalling = true
        defer { isRecalling = false }

        guard let url = URL(string: "\(baseURL)/api/v1/search") else { return nil }

        let body: [String: Any] = [
            "query": query,
            "search_type": "GRAPH_COMPLETION",
            "datasets": [datasetName],
            "top_k": maxResults
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                await ChatDiagnostics.shared.log("cognee-recall failed status=\((response as? HTTPURLResponse)?.statusCode ?? 0)")
                return nil
            }

            // Parse the response — Cognee returns an array of results
            let results = parseSearchResults(data)
            lastRecallResults = results

            if results.isEmpty {
                await ChatDiagnostics.shared.log("cognee-recall empty query=\(query.prefix(50))")
                return nil
            }

            // Format as context block
            let contextBlock = results.enumerated().map { idx, result in
                "[\(idx + 1)] \(result.text)"
            }.joined(separator: "\n\n")

            await ChatDiagnostics.shared.log("cognee-recall success results=\(results.count) query=\(query.prefix(50))")
            return contextBlock
        } catch {
            await ChatDiagnostics.shared.log("cognee-recall error=\(error.localizedDescription)")
            return nil
        }
    }

    /// Store a piece of knowledge in Cognee for future recall
    func store(text: String, source: String = "thrawn-console") async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/v1/add") else { return false }

        let body: [String: Any] = [
            "data": [
                ["text": text, "source": source, "dataset": datasetName]
            ]
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: body) else { return false }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            await ChatDiagnostics.shared.log("cognee-store success source=\(source)")
            return true
        } catch {
            await ChatDiagnostics.shared.log("cognee-store error=\(error.localizedDescription)")
            return false
        }
    }

    private func parseSearchResults(_ data: Data) -> [CogneeSearchResult] {
        // Try decoding as array of results
        if let results = try? JSONDecoder().decode([CogneeSearchResult].self, from: data) {
            return results.filter { !$0.text.isEmpty }
        }

        // Try as wrapper object with "results" key
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let resultsArray = json["results"] as? [[String: Any]] {
                return resultsArray.compactMap { item -> CogneeSearchResult? in
                    guard let text = item["content_text"] as? String ?? item["text"] as? String ?? item["content"] as? String,
                          !text.isEmpty else { return nil }
                    let score = item["score"] as? Double ?? 0
                    return CogneeSearchResult(text: text, score: score)
                }
            }
            // Single result
            if let text = json["content_text"] as? String ?? json["text"] as? String,
               !text.isEmpty {
                return [CogneeSearchResult(text: text, score: 1.0)]
            }
        }

        return []
    }
}

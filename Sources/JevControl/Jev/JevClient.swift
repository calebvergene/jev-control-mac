import Foundation

/// Talks to TypeSafe's System One endpoint.
///
/// One request per utterance carrying every question the executor could need,
/// evaluated in parallel server-side. Asking speculatively costs one round trip;
/// asking sequentially would cost one per branch.
actor JevClient {
    /// A noul above this reads as "yes".
    static let yesThreshold = 0.6

    /// Pinned rather than `jev-latest`: the confidence thresholds in `Brain`
    /// are calibrated against this model's behaviour.
    static let defaultModel = "jev-1.13.0"

    enum ClientError: LocalizedError {
        case missingKey
        case http(Int, String)
        case malformed(String)

        var errorDescription: String? {
            switch self {
            case .missingKey:
                return "No TypeSafe API key. Add one in Setup."
            case .http(let code, let body):
                if code == 401 || code == 403 {
                    return "TypeSafe rejected the API key (HTTP \(code))."
                }
                return "TypeSafe returned HTTP \(code): \(body)"
            case .malformed(let detail):
                return "Could not read the TypeSafe response: \(detail)"
            }
        }
    }

    struct Response {
        let answers: [String: JevAnswer]
        let latency: TimeInterval
    }

    private let session: URLSession
    private let endpoint = URL(string: "https://api.typesafe.ai/v1/systemone")!

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpMaximumConnectionsPerHost = 4
        session = URLSession(configuration: config)
    }

    /// Opens the TLS connection early so the first real command is not paying
    /// for the handshake.
    func warmUp() async {
        guard let key = Credentials.apiKey else { return }
        var request = URLRequest(url: URL(string: "https://api.typesafe.ai/v1/models")!)
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        _ = try? await session.data(for: request)
    }

    func evaluate(state: [String: JSONValue], questions: [String: JevQuestion]) async throws -> Response {
        guard let key = Credentials.apiKey, !key.isEmpty else { throw ClientError.missingKey }

        let payload = JSONValue.object([
            "state": .object(state),
            "model": .string(Credentials.model),
            "questions": .object(questions.mapValues(\.json)),
        ])

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)

        let started = Date()
        let (data, response) = try await session.data(for: request)
        let latency = Date().timeIntervalSince(started)

        guard let http = response as? HTTPURLResponse else {
            throw ClientError.malformed("no HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ClientError.http(http.statusCode, String(body.prefix(300)))
        }

        struct Envelope: Decodable { let answers: [String: JevAnswer] }
        do {
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            return Response(answers: envelope.answers, latency: latency)
        } catch {
            throw ClientError.malformed(error.localizedDescription)
        }
    }
}

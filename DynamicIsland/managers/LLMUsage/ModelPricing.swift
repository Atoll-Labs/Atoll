import Foundation

// USD per million tokens, matched by model-family substring. Public list prices verified 2026-07-03.
enum ModelPricing {
    private static let perMillion: [(match: String, input: Double, output: Double)] = [
        ("opus",     5.0, 25.0),
        ("sonnet",   3.0, 15.0),
        ("haiku",    1.0,  5.0),
        ("gpt-5",    1.25, 10.0),
    ]

    static func cost(model: String, inputTokens: Int, outputTokens: Int) -> Double? {
        guard inputTokens > 0 || outputTokens > 0 else { return 0.0 }
        let key = model.lowercased()
        guard let rate = perMillion.first(where: { key.contains($0.match) }) else { return nil }
        let inCost = Double(inputTokens) / 1_000_000 * rate.input
        let outCost = Double(outputTokens) / 1_000_000 * rate.output
        return inCost + outCost
    }
}

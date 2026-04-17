import Foundation

struct StateCopyPool {
    let captions: [String]
    let details: [String]
}

enum StateCopy {
    static let good = StateCopyPool(
        captions: [
            "feeling great!",
            "vibing",
            "top of the world",
            "claude is up, i am up",
            "no notes",
            "thriving",
            "everything is fine",
            "chillin hard",
            "all quiet",
            "claude is behaving",
        ],
        details: [
            "Claude is chilling. No complaints.",
            "All quiet on the Anthropic front.",
            "No rumblings, no incidents, pure vibes.",
            "Claude seems to be doing Claude things.",
            "Nothing is on fire for now.",
        ]
    )

    static let error = StateCopyPool(
        captions: [
            "Prickles has DIED",
            "RIP Prickles (again)",
            "Prickles is DOWN bad",
            "Prickles has fainted",
            "Prickles has left the chat",
            "It's joever",
            "Prickles saw God",
            "Prickles is KO'd",
            "Prickles is deceased",
            "Prickles.exe has stopped responding",
        ],
        details: [
            "Claude is having a real incident.",
            "Anthropic is aware and working on it.",
            "Something is on fire over at Anthropic.",
            "The official status page is screaming.",
            "The tower is down. Man down. Man down.",
        ]
    )

    static func pool(for state: PricklesState) -> StateCopyPool {
        switch state {
        case .good: return good
        case .error: return error
        }
    }

    /// Picks a deterministic caption+detail pair from the pool so that the widget
    /// stays visually stable between refreshes of the same state. Seeded by the
    /// state transition time so copy re-rolls on every state change.
    static func pick(for state: PricklesState, seed: Date?) -> (caption: String, detail: String) {
        let pool = pool(for: state)
        let seedValue = Int((seed ?? Date()).timeIntervalSince1970)
        var rng = SeededRNG(seed: UInt64(bitPattern: Int64(seedValue)))
        let caption = pool.captions.randomElement(using: &rng) ?? ""
        let detail = pool.details.randomElement(using: &rng) ?? ""
        return (caption, detail)
    }

    /// Non-seeded random pick, for the host app which should feel fresh per screen open.
    static func pickRandom(for state: PricklesState) -> (caption: String, detail: String) {
        let pool = pool(for: state)
        var rng = SystemRandomNumberGenerator()
        let caption = pool.captions.randomElement(using: &rng) ?? ""
        let detail = pool.details.randomElement(using: &rng) ?? ""
        return (caption, detail)
    }
}

struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xdead_beef_cafe : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

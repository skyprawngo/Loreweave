import Foundation

/// Pure three-version rule, shared by disk refresh and write preflight.
/// Filesystem events and modification dates are hints; complete content is the equality authority.
enum DocumentReconciliation {
    enum Decision: Equatable { case unchanged, adoptDisk, conflict }
    static func decide(base: String, draft: String, disk: String) -> Decision {
        if disk == base { return .unchanged }
        if draft == base || draft == disk { return .adoptDisk }
        return .conflict
    }
}

struct DocumentReadIdentity {
    let requestID: UUID
    let documentID: UUID
    let base: String?
    func matches(requestID: UUID?, documentID: UUID?, base: String?) -> Bool {
        self.requestID == requestID && self.documentID == documentID && self.base == base
    }
}

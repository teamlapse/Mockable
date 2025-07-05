import SwiftSyntax

extension AttributeListSyntax {
    func contains(_ name: String) -> Bool {
        trimmed.contains { element in
            guard case .attribute(let attribute) = element else {
                return false
            }

            return attribute.attributeName.as(IdentifierTypeSyntax.self)?.description == name
        }
    }

    func removingAttributes(_ names: Set<String>) -> AttributeListSyntax {
        let filtered = trimmed.filter { element in
            guard case .attribute(let attribute) = element else {
                return true
            }

            let attributeName = attribute.attributeName.as(IdentifierTypeSyntax.self)?.description
            return !names.contains(attributeName ?? "")
        }

        return AttributeListSyntax(filtered)
    }
}

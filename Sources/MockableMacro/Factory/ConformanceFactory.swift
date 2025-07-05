//
//  ConformanceFactory.swift
//  MockableMacro
//
//  Created by Kolos Foltanyi on 2024. 03. 23..
//

import SwiftSyntax

/// Factory to generate mock conformances of requirements.
///
/// Returns a member block item list that includes a mock implementation for every requirement.
enum ConformanceFactory: Factory {
    static func build(from requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            try inits(requirements)
            try functions(requirements)
            try variables(requirements)
        }
    }
}

// MARK: - Helpers

extension ConformanceFactory {
    private static func variables(_ requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            for variable in requirements.variables {
                MemberBlockItemSyntax(
                    decl: try variable.implement(with: requirements.modifiers)
                )
            }
        }
    }

    private static func functions(_ requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            for function in requirements.functions {
                MemberBlockItemSyntax(
                    decl: try function.implement(
                        with: {
                            var modifiers = requirements.modifiers
                            
                            // If the protocol has concurrent functions, all functions should be nonisolated
                            if requirements.hasConcurrentFunctions {
                                // Add nonisolated if not already present
                                if !modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) {
                                    modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
                                }
                            }
                            
                            // Individual function has @concurrent, make it nonisolated
                            if function.syntax.attributes.contains("concurrent") {
                                if !modifiers.contains(where: { $0.name.tokenKind == .keyword(.nonisolated) }) {
                                    modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
                                }
                            }
                            
                            // Remove nonisolated for @MainActor functions
                            if function.syntax.attributes.contains("MainActor") {
                                modifiers.remove(keyword: .nonisolated)
                            }

                            return modifiers
                        }()
                    )
                )
            }
        }
    }

    private static func inits(_ requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            for initializer in requirements.initializers {
                MemberBlockItemSyntax(
                    decl: try initializer.implement(with: requirements.modifiers)
                )
            }
        }
    }
}

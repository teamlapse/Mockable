//
//  BuilderFactory.swift
//  MockableMacro
//
//  Created by Kolos Foltanyi on 2024. 03. 23..
//

import SwiftSyntax

/// Factory to generate builder struct declarations.
///
/// Creates a member block item list that includes  `ReturnBuilder`,
/// `ActionBuilder` and `VerifyBuilder` struct declarations.
enum BuilderFactory: Factory {
    static func build(from requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            for builder in BuilderKind.allCases {
                try builderDeclaration(for: builder, requirements)
            }
        }
    }
}

// MARK: - Helpers

extension BuilderFactory {
    private static func builderDeclaration(
        for kind: BuilderKind,
        _ requirements: Requirements
    ) throws -> some DeclSyntaxProtocol {
        StructDeclSyntax(
            modifiers: requirements.modifiers,
            name: kind.name,
            inheritanceClause: InheritanceClauseSyntax(
                inheritedTypes: [
                    InheritedTypeSyntax(
                        type: MemberTypeSyntax(
                            baseType: IdentifierTypeSyntax(name: NS.Mockable),
                            name: NS.Builder
                        )
                    )
                ]
            ),
            memberBlock: MemberBlockSyntax(members: try members(kind, requirements))
        )
    }

    private static func members(_ kind: BuilderKind, _ requirements: Requirements) throws -> MemberBlockItemListSyntax {
        try MemberBlockItemListSyntax {
            mockerDeclaration(requirements)
            initializerDeclaration(kind, requirements)
            for variable in requirements.variables {
                MemberBlockItemSyntax(
                    decl: try variable.builder(
                        of: kind,
                        with: builderMemberModifiers(requirements),
                        using: requirements.syntax.mockType
                    )
                )
            }
            for function in requirements.functions {
                MemberBlockItemSyntax(
                    decl: try function.builder(
                        of: kind,
                        with: {
                            var modifiers = builderMemberModifiers(requirements)
                            if function.syntax.attributes.contains("MainActor") {
                                modifiers.remove(keyword: .nonisolated)
                            }

                            return modifiers
                        }(),
                        using: requirements.syntax.mockType
                    )
                )
            }
        }
    }
    
    private static func builderMemberModifiers(_ requirements: Requirements) -> DeclModifierListSyntax {
        // For actors, global actors, or concurrent functions, make all builder members nonisolated
        if requirements.isActor || requirements.hasConcurrentFunctions {
            return DeclModifierListSyntax {
                DeclModifierSyntax(name: .keyword(.nonisolated))
            }
        }
        
        // Check for global actor
        let hasGlobalActor = requirements.syntax.attributes.contains { attribute in
            guard case .attribute(let attr) = attribute else { return false }
            if let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) {
                let name = identifier.name.text
                return name == "MainActor" || name.hasSuffix("Actor")
            }
            return false
        }
        
        if hasGlobalActor {
            var modifiers = requirements.modifiers
            modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
            return modifiers
        }
        
        return requirements.modifiers
    }

    private static func mockerDeclaration(_ requirements: Requirements) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.private))],
            bindingSpecifier: .keyword(.let),
            bindingsBuilder: {
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: NS.mocker),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: NS.Mocker))
                )
            }
        )
    }

    private static func initializerDeclaration(
        _ kind: BuilderKind,
        _ requirements: Requirements
    ) -> InitializerDeclSyntax {
        InitializerDeclSyntax(
            modifiers: initModifiers(requirements),
            signature: initializerSignature(kind, requirements)
        ) {
            InfixOperatorExprSyntax(
                leftOperand: MemberAccessExprSyntax(
                    base: DeclReferenceExprSyntax(baseName: .keyword(.self)),
                    name: NS.mocker
                ),
                operator: AssignmentExprSyntax(),
                rightOperand: DeclReferenceExprSyntax(baseName: NS.mocker)
            )
        }
    }
    
    private static func initModifiers(_ requirements: Requirements) -> DeclModifierListSyntax {
        // Actors cannot have nonisolated synchronous initializers
        if requirements.isActor {
            return requirements.modifiers
        }
        
        // Add nonisolated for global actors or concurrent functions
        if requirements.hasConcurrentFunctions {
            return DeclModifierListSyntax {
                DeclModifierSyntax(name: .keyword(.nonisolated))
            }
        }
        
        // Check for global actor
        let hasGlobalActor = requirements.syntax.attributes.contains { attribute in
            guard case .attribute(let attr) = attribute else { return false }
            if let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) {
                let name = identifier.name.text
                return name == "MainActor" || name.hasSuffix("Actor")
            }
            return false
        }
        
        if hasGlobalActor {
            var modifiers = requirements.modifiers
            modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
            return modifiers
        }
        
        return requirements.modifiers
    }

    private static func initializerSignature(
        _ kind: BuilderKind,
        _ requirements: Requirements
    ) -> FunctionSignatureSyntax {
        FunctionSignatureSyntax(
            parameterClause: FunctionParameterClauseSyntax {
                FunctionParameterSyntax(
                    firstName: NS.mocker,
                    type: IdentifierTypeSyntax(name: NS.Mocker)
                )
            }
        )
    }
}

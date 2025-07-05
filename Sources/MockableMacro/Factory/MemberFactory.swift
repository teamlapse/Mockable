//
//  MemberFactory.swift
//  MockableMacro
//
//  Created by Kolos Foltanyi on 2024. 03. 23..
//

import SwiftSyntax

/// Factory to generate custom members.
///
/// Generates custom members (ex.: default init, reset function, etc...)
/// for the mock implementation.
enum MemberFactory: Factory {
    static func build(from requirements: Requirements) throws -> MemberBlockItemListSyntax {
        MemberBlockItemListSyntax {
            mockerAlias(requirements)
            mocker(requirements)
            clause(requirements, name: NS._given, type: NS.ReturnBuilder, message: Messages.givenMessage)
            clause(requirements, name: NS._when, type: NS.ActionBuilder, message: Messages.whenMessage)
            clause(requirements, name: NS._verify, type: NS.VerifyBuilder, message: Messages.verifyMessage)
            reset(requirements)
            defaultInit(requirements)
        }
    }
}

// MARK: - Helpers

extension MemberFactory {
    private static func defaultInit(_ requirements: Requirements) -> InitializerDeclSyntax {
        InitializerDeclSyntax(
            modifiers: {
                // Actors cannot have nonisolated synchronous initializers
                if requirements.isActor {
                    return requirements.modifiers
                }
                return memberModifiers(requirements)
            }(),
            signature: .init(parameterClause: defaultInitParameters),
            body: .init { CodeBlockItemSyntax(item: .expr(mockerAssignmentWithPolicy)) }
        )
    }

    private static func mockerAlias(_ requirements: Requirements) -> TypeAliasDeclSyntax {
        TypeAliasDeclSyntax(
            modifiers: requirements.modifiers.filter({ $0.name.tokenKind != .keyword(.nonisolated) }),
            name: NS.Mocker,
            initializer: TypeInitializerClauseSyntax(
                value: MemberTypeSyntax(
                    baseType: IdentifierTypeSyntax(name: NS.Mockable),
                    name: NS.Mocker,
                    genericArgumentClause: GenericArgumentClauseSyntax(
                        arguments: GenericArgumentListSyntax {
                            GenericArgumentSyntax(argument: requirements.syntax.mockType)
                        }
                    )
                )
            )
        )
    }

    private static func mocker(_ requirements: Requirements) -> VariableDeclSyntax {
        VariableDeclSyntax(
            modifiers: [DeclModifierSyntax(name: .keyword(.private))],
            bindingSpecifier: .keyword(.let)
        ) {
            PatternBindingSyntax(
                pattern: IdentifierPatternSyntax(identifier: NS.mocker),
                initializer: InitializerClauseSyntax(
                    value: FunctionCallExprSyntax(
                        calledExpression: DeclReferenceExprSyntax(baseName: NS.Mocker),
                        leftParen: .leftParenToken(),
                        arguments: [],
                        rightParen: .rightParenToken()
                    )
                )
            )
        }
    }

    private static func clause(
        _ requirements: Requirements,
        name: TokenSyntax,
        type: TokenSyntax,
        message: String
    ) -> VariableDeclSyntax {
        VariableDeclSyntax(
            attributes: unavailableAttribute(message: message),
            modifiers: memberModifiers(requirements),
            bindingSpecifier: .keyword(.var),
            bindings: PatternBindingListSyntax {
                PatternBindingSyntax(
                    pattern: IdentifierPatternSyntax(identifier: name),
                    typeAnnotation: TypeAnnotationSyntax(type: IdentifierTypeSyntax(name: type)),
                    accessorBlock: AccessorBlockSyntax(
                        accessors: .getter(builderInit)
                    )
                )
            }
        )
    }

    private static var builderInit: CodeBlockItemListSyntax {
        CodeBlockItemListSyntax {
            FunctionCallExprSyntax(
                calledExpression: MemberAccessExprSyntax(name: NS._init),
                leftParen: .leftParenToken(),
                arguments: [
                    LabeledExprSyntax(
                        label: NS.mocker,
                        colon: .colonToken(),
                        expression: DeclReferenceExprSyntax(baseName: NS.mocker)
                    )
                ],
                rightParen: .rightParenToken()
            )
        }
    }

    private static func reset(_ requirements: Requirements) -> FunctionDeclSyntax {
        FunctionDeclSyntax(
            modifiers: memberModifiers(requirements),
            name: NS.reset,
            signature: .init(
                parameterClause: FunctionParameterClauseSyntax(
                    parameters: [scopesParameter]
                )
            ),
            body: resetCall
        )
    }

    private static func memberModifiers(_ requirements: Requirements) -> DeclModifierListSyntax {
        // Check if the mock class will be actor-isolated
        // This happens when:
        // 1. The protocol inherits from Actor (isActor = true)
        // 2. The protocol has @MainActor or other global actor attributes
        // 3. The protocol has @concurrent functions (requires nonisolated for thread safety)
        
        if requirements.isActor || requirements.hasConcurrentFunctions {
            // For actor types or protocols with concurrent functions, add nonisolated
            return DeclModifierListSyntax {
                DeclModifierSyntax(name: .keyword(.nonisolated))
            }
        }
        
        // Check if the protocol has global actor attributes that will be copied to the mock
        let hasGlobalActor = requirements.syntax.attributes.contains { attribute in
            guard case .attribute(let attr) = attribute else { return false }
            if let identifier = attr.attributeName.as(IdentifierTypeSyntax.self) {
                let name = identifier.name.text
                // Common global actors end with "Actor"
                return name == "MainActor" || name.hasSuffix("Actor")
            }
            return false
        }
        
        if hasGlobalActor {
            // For globally-isolated types, add nonisolated
            // but preserve other modifiers like public/internal
            var modifiers = requirements.modifiers
            modifiers.append(DeclModifierSyntax(name: .keyword(.nonisolated)))
            return modifiers
        }
        
        // For regular protocols, just use the original modifiers
        return requirements.modifiers
    }

    private static var scopesParameter: FunctionParameterSyntax {
        FunctionParameterSyntax(
            firstName: .wildcardToken(),
            secondName: NS.scopes,
            type: IdentifierTypeSyntax(
                name: NS.Set,
                genericArgumentClause: GenericArgumentClauseSyntax(
                    arguments: GenericArgumentListSyntax {
                        GenericArgumentSyntax(
                            argument: MemberTypeSyntax(
                                baseType: IdentifierTypeSyntax(name: NS.Mockable),
                                name: NS.MockerScope
                            )
                        )
                    }
                )
            ),
            defaultValue: InitializerClauseSyntax(
                value: MemberAccessExprSyntax(name: NS.all)
            )
        )
    }

    private static var resetCall: CodeBlockSyntax {
        CodeBlockSyntax(
            statements: CodeBlockItemListSyntax {
                FunctionCallExprSyntax(
                    calledExpression: MemberAccessExprSyntax(
                        base: DeclReferenceExprSyntax(baseName: NS.mocker),
                        name: NS.reset
                    ),
                    leftParen: .leftParenToken(),
                    arguments: [
                        LabeledExprSyntax(
                            label: NS.scopes,
                            colon: .colonToken(),
                            expression: DeclReferenceExprSyntax(baseName: NS.scopes)
                        )
                    ],
                    rightParen: .rightParenToken()
                )
            }
        )
    }

    private static func unavailableAttribute(message: String) -> AttributeListSyntax {
        let arguments = AvailabilityArgumentListSyntax {
            AvailabilityArgumentSyntax(argument: .token(NS._star))
            AvailabilityArgumentSyntax(argument: .token(NS.deprecated))
            AvailabilityArgumentSyntax(argument: .availabilityLabeledArgument(
                AvailabilityLabeledArgumentSyntax(
                    label: NS.message,
                    value: .string(SimpleStringLiteralExprSyntax(
                        openingQuote: .stringQuoteToken(),
                        segments: SimpleStringLiteralSegmentListSyntax {
                            StringSegmentSyntax(content: .identifier(message))
                        },
                        closingQuote: .stringQuoteToken()
                    ))
                )
            ))
        }
        let attribute = AttributeSyntax(
            attributeName: IdentifierTypeSyntax(name: NS.available),
            leftParen: .leftParenToken(),
            arguments: .availability(arguments),
            rightParen: .rightParenToken(),
            trailingTrivia: .newline
        )
        return AttributeListSyntax { attribute }
    }

    private static var defaultInitParameters: FunctionParameterClauseSyntax {
        FunctionParameterClauseSyntax(
            parameters: FunctionParameterListSyntax {
                FunctionParameterSyntax(
                    firstName: NS.policy,
                    type: OptionalTypeSyntax(
                        wrappedType: MemberTypeSyntax(
                            baseType: IdentifierTypeSyntax(name: NS.Mockable),
                            name: NS.MockerPolicy
                        )
                    ),
                    defaultValue: InitializerClauseSyntax(
                        value: NilLiteralExprSyntax()
                    )
                )
            }
        )
    }

    private static var mockerAssignmentWithPolicy: ExprSyntax {
        let expression = IfExprSyntax(
            conditions: ConditionElementListSyntax {
                OptionalBindingConditionSyntax(
                    bindingSpecifier: .keyword(.let),
                    pattern: IdentifierPatternSyntax(
                        identifier: NS.policy
                    )
                )
            },
            body: CodeBlockSyntax(
                statements: CodeBlockItemListSyntax {
                    InfixOperatorExprSyntax(
                        leftOperand: MemberAccessExprSyntax(
                            base: DeclReferenceExprSyntax(baseName: NS.mocker),
                            declName: DeclReferenceExprSyntax(baseName: NS.policy)
                        ),
                        operator: AssignmentExprSyntax(),
                        rightOperand: DeclReferenceExprSyntax(baseName: NS.policy)
                    )
                }
            )
        )
        return ExprSyntax(expression)
    }
}

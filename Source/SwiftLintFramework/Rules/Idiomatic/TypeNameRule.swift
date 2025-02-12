import Foundation
import SourceKittenFramework

public struct TypeNameRule: ASTRule, ConfigurationProviderRule {
    public var configuration = NameConfiguration(minLengthWarning: 3,
                                                 minLengthError: 0,
                                                 maxLengthWarning: 40,
                                                 maxLengthError: 1000)

    public init() {}

    public static let description = RuleDescription(
        identifier: "type_name",
        name: "Type Name",
        description: "Type name should only contain alphanumeric characters, start with an " +
                     "uppercase character and span between 3 and 40 characters in length.",
        kind: .idiomatic,
        nonTriggeringExamples: TypeNameRuleExamples.nonTriggeringExamples,
        triggeringExamples: TypeNameRuleExamples.triggeringExamples
    )

    private let typeKinds = SwiftDeclarationKind.typeKinds

    public func validate(file: File) -> [StyleViolation] {
        return validateTypeAliasesAndAssociatedTypes(in: file) +
            validate(file: file, dictionary: file.structure.dictionary)
    }

    public func validate(file: File, kind: SwiftDeclarationKind,
                         dictionary: [String: SourceKitRepresentable]) -> [StyleViolation] {
        guard typeKinds.contains(kind),
            let name = dictionary.name,
            let offset = dictionary.nameOffset else {
                return []
        }

        return validate(name: name, dictionary: dictionary, file: file, offset: offset)
    }

    private func validateTypeAliasesAndAssociatedTypes(in file: File) -> [StyleViolation] {
        guard SwiftVersion.current < .fourDotOne else {
            return []
        }

        let rangesAndTokens = file.rangesAndTokens(matching: "(typealias|associatedtype)\\s+.+?\\b")
        return rangesAndTokens.flatMap { _, tokens -> [StyleViolation] in
            guard tokens.count == 2,
                let keywordToken = tokens.first,
                let nameToken = tokens.last,
                SyntaxKind(rawValue: keywordToken.type) == .keyword,
                SyntaxKind(rawValue: nameToken.type) == .identifier else {
                    return []
            }

            let contents = file.contents.bridge()
            guard let name = contents.substringWithByteRange(start: nameToken.offset,
                                                             length: nameToken.length) else {
                return []
            }

            return validate(name: name, file: file, offset: nameToken.offset)
        }
    }

    private func validate(name: String, dictionary: [String: SourceKitRepresentable] = [:], file: File,
                          offset: Int) -> [StyleViolation] {
        guard !configuration.excluded.contains(name) else {
            return []
        }

        let name = name
            .nameStrippingLeadingUnderscoreIfPrivate(dictionary)
            .nameStrippingTrailingSwiftUIPreviewProvider(dictionary)
        let allowedSymbols = configuration.allowedSymbols.union(.alphanumerics)
        if !allowedSymbols.isSuperset(of: CharacterSet(safeCharactersIn: name)) {
            return [StyleViolation(ruleDescription: type(of: self).description,
                                   severity: .error,
                                   location: Location(file: file, byteOffset: offset),
                                   reason: "Type name should only contain alphanumeric characters: '\(name)'")]
        } else if configuration.validatesStartWithLowercase &&
            !String(name[name.startIndex]).isUppercase() {
            return [StyleViolation(ruleDescription: type(of: self).description,
                                   severity: .error,
                                   location: Location(file: file, byteOffset: offset),
                                   reason: "Type name should start with an uppercase character: '\(name)'")]
        } else if let severity = severity(forLength: name.count) {
            return [StyleViolation(ruleDescription: type(of: self).description,
                                   severity: severity,
                                   location: Location(file: file, byteOffset: offset),
                                   reason: "Type name should be between \(configuration.minLengthThreshold) and " +
                "\(configuration.maxLengthThreshold) characters long: '\(name)'")]
        }

        return []
    }
}

private extension String {
    func nameStrippingTrailingSwiftUIPreviewProvider(_ dictionary: [String: SourceKitRepresentable]) -> String {
        guard dictionary.inheritedTypes.contains("PreviewProvider"),
            hasSuffix("_Previews"),
            let lastPreviewsIndex = lastIndex(of: "_Previews")
            else { return self }

        return substring(from: 0, length: lastPreviewsIndex)
    }
}

import Foundation

enum HTMLEscaping {
    static func text(_ value: String) -> String {
        var result = ""
        result.reserveCapacity(value.utf8.count)

        for character in value {
            switch character {
            case "&": result += "&amp;"
            case "<": result += "&lt;"
            case ">": result += "&gt;"
            case "\"": result += "&quot;"
            case "'": result += "&#39;"
            default: result.append(character)
            }
        }

        return result
    }

    static func attribute(_ value: String) -> String {
        text(value)
    }

    static func cssClassToken(_ value: String) -> String? {
        let scalars = value.lowercased().unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "+"
        }
        let token = String(String.UnicodeScalarView(scalars.prefix(48)))
        return token.isEmpty ? nil : token
    }
}

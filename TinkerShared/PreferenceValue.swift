//
//  PreferenceValue.swift
//  Tinker
//

import Foundation

/// How a setting's value is stored in its property list.
nonisolated enum ValueType: String, Decodable, Sendable {
    case bool
    case int
    case double
    case string
    /// A whole number stored as a string, which is how some system
    /// preferences are written (for example `NSRecentDocumentsLimit = "10"`).
    case intString
}

/// A scalar preference value.
nonisolated enum PreferenceValue: Hashable, Sendable {
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
}

nonisolated extension PreferenceValue: Decodable {
    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }
}

nonisolated extension PreferenceValue {
    /// Converts a value read from a property list. Returns `nil` for
    /// arrays, dictionaries, dates and data, which the catalog does not model.
    init?(propertyList: Any) {
        switch propertyList {
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if CFNumberIsFloatType(number) {
                self = .double(number.doubleValue)
            } else {
                self = .int(number.intValue)
            }
        case let string as String:
            self = .string(string)
        default:
            return nil
        }
    }

    var propertyList: CFPropertyList {
        switch self {
        case .bool(let value): NSNumber(value: value)
        case .int(let value): NSNumber(value: value)
        case .double(let value): NSNumber(value: value)
        case .string(let value): value as NSString
        }
    }

    var doubleValue: Double? {
        switch self {
        case .bool(let value): value ? 1 : 0
        case .int(let value): Double(value)
        case .double(let value): value
        case .string(let value): Double(value)
        }
    }

    private var intValue: Int? {
        switch self {
        case .bool(let value): value ? 1 : 0
        case .int(let value): value
        case .double(let value): Int(exactly: value.rounded())
        case .string(let value): Int(value)
        }
    }

    private var boolValue: Bool? {
        switch self {
        case .bool(let value): value
        case .int(let value): value != 0
        case .double(let value): value != 0
        case .string(let value):
            switch value.lowercased() {
            case "1", "true", "yes": true
            case "0", "false", "no": false
            default: nil
            }
        }
    }

    /// The same value expressed in `type`, so values that mean the same
    /// thing compare equal no matter who wrote them (`1`, `true`, `"1"`).
    /// Returns `nil` when the value cannot be read as that type.
    func coerced(to type: ValueType) -> PreferenceValue? {
        switch type {
        case .bool: boolValue.map(PreferenceValue.bool)
        case .int: intValue.map(PreferenceValue.int)
        case .double: doubleValue.map(PreferenceValue.double)
        case .intString: intValue.map { .string(String($0)) }
        case .string:
            switch self {
            case .bool(let value): .string(value ? "true" : "false")
            case .int(let value): .string(String(value))
            case .double(let value): .string(String(value))
            case .string: self
            }
        }
    }

    /// Text for showing a raw value to the user.
    var displayText: String {
        switch self {
        case .bool(let value): value ? "true" : "false"
        case .int(let value): String(value)
        case .double(let value): String(value)
        case .string(let value): value
        }
    }
}

//
//  URL+Extensions.swift
//  GIACKKit
//
//  This file is part of GIACK.
//
//  GIACK is free software: you can redistribute it and/or modify it under the terms
//  of the GNU General Public License as published by the Free Software Foundation,
//  either version 3 of the License, or (at your option) any later version.
//
//  GIACK is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY;
//  without even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.
//  See the GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License along with GIACK.
//  If not, see https://www.gnu.org/licenses/.
//

import Foundation

extension String {
    public var esc: String {
        let esc = ["\\", "\"", "'", " ", "(", ")", "[", "]", "{", "}", "&", "|",
                   ";", "<", ">", "`", "$", "!", "*", "?", "#", "~", "="]
        var str = self
        for char in esc {
            str = str.replacingOccurrences(of: char, with: "\\" + char)
        }
        return str
    }

    /// Environment variable names are restricted before shell generation so
    /// user-editable keys cannot inject additional shell syntax.
    public var isPortableEnvironmentVariableName: Bool {
        range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil
    }

    /// Splits a user-entered argument string using lightweight shell-style rules.
    ///
    /// Quotes group whitespace, backslashes escape the next character, and any
    /// unfinished quote is treated as literal input so the user can still see
    /// what will be passed through rather than silently losing characters.
    public static func shellSplit(_ raw: String) -> [String] {
        var arguments: [String] = []
        var current = ""
        var quote: Character?
        var iterator = raw.makeIterator()

        while let char = iterator.next() {
            if char == "\\" {
                if let next = iterator.next() {
                    current.append(next)
                } else {
                    current.append(char)
                }
                continue
            }

            if let activeQuote = quote {
                if char == activeQuote {
                    quote = nil
                } else {
                    current.append(char)
                }
                continue
            }

            switch char {
            case "\"", "'":
                quote = char
            case _ where char.isWhitespace:
                appendCompletedArgument(&arguments, current: &current)
            default:
                current.append(char)
            }
        }

        if let quote {
            current.insert(quote, at: current.startIndex)
        }
        appendCompletedArgument(&arguments, current: &current)
        return arguments
    }

    /// Escapes a shell command for embedding inside an AppleScript string.
    ///
    /// Several UI actions send shell commands to Terminal via `do script`.
    /// Those commands are already shell-escaped, but they still need a second
    /// escaping pass so quotes and backslashes do not break the surrounding
    /// AppleScript string literal.
    public var appleScriptEscaped: String {
        self
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func appendCompletedArgument(_ arguments: inout [String], current: inout String) {
        guard !current.isEmpty else { return }
        arguments.append(current)
        current.removeAll(keepingCapacity: true)
    }
}

extension URL {
    public var esc: String {
        path.esc
    }

    public func prettyPath() -> String {
        let displayName = Bundle.appDisplayName
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: Bundle.main.bundleIdentifier ?? Bundle.whiskyBundleIdentifier, with: displayName)
            .replacingOccurrences(of: "/Users/\(NSUserName())", with: "~")
        return prettyPath
    }

    // NOT to be used for logic only as UI decoration
    public func prettyPath(_ bottle: Bottle) -> String {
        var prettyPath = path(percentEncoded: false)
        prettyPath = prettyPath
            .replacingOccurrences(of: bottle.url.path(percentEncoded: false), with: "")
            .replacingOccurrences(of: "/drive_c/", with: "C:\\")
            .replacingOccurrences(of: "/", with: "\\")
        return prettyPath
    }

    // There is probably a better way to do this
    public func updateParentBottle(old: URL, new: URL) -> URL {
        let originalPath = path(percentEncoded: false)

        var oldBottlePath = old.path(percentEncoded: false)
        if oldBottlePath.last != "/" {
            oldBottlePath += "/"
        }

        var newBottlePath = new.path(percentEncoded: false)
        if newBottlePath.last != "/" {
            newBottlePath += "/"
        }

        let newPath = originalPath.replacingOccurrences(of: oldBottlePath,
                                                        with: newBottlePath)
        return URL(filePath: newPath)
    }
}

extension URL: @retroactive Identifiable {
    public var id: URL { self }
}

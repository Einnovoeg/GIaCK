//
//  ProgramShortcut.swift
//  GIACK
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
import AppKit
import QuickLookThumbnailing
import GIACKKit

class ProgramShortcut {
    public static func createShortcut(_ program: Program, app: URL, name: String) async {
        let contents = app.appending(path: "Contents")
        let macos = contents.appending(path: "MacOS")
        do {
            try FileManager.default.createDirectory(at: macos, withIntermediateDirectories: true)

            // Build a tiny launcher script inside the generated app bundle. The
            // script stays minimal so the shortcut remains easy to inspect.
            let script = """
            #!/bin/sh
            \(program.generateTerminalCommand())
            """
            let scriptUrl = macos.appending(path: "launch")
            try script.write(to: scriptUrl,
                             atomically: false,
                             encoding: .utf8)

            // The launcher only needs to be executable, not world-writable.
            try FileManager.default.setAttributes([.posixPermissions: 0o755],
                                                  ofItemAtPath: scriptUrl.path(percentEncoded: false))

            // Create Info.plist (set category for Game mode)
            let info = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleExecutable</key>
                <string>launch</string>
                <key>CFBundleSupportedPlatforms</key>
                <array>
                    <string>MacOSX</string>
                </array>
                <key>LSMinimumSystemVersion</key>
                <string>14.0</string>
                <key>LSApplicationCategoryType</key>
                <string>public.app-category.games</string>
            </dict>
            </plist>
            """
            try info.write(to: contents.appending(path: "Info")
                                       .appendingPathExtension("plist"),
                           atomically: false,
                           encoding: .utf8)

            // Render a consistent icon so shortcuts are visually grouped with the app.
            let request = QLThumbnailGenerator.Request(fileAt: program.url,
                                                       size: CGSize(width: 512, height: 512),
                                                       scale: 2.0,
                                                       representationTypes: .thumbnail)
            let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let iconImage = buildShortcutIcon(using: thumbnail?.nsImage)
            NSWorkspace.shared.setIcon(iconImage,
                                       forFile: app.path(percentEncoded: false),
                                       options: NSWorkspace.IconCreationOptions())
            NSWorkspace.shared.activateFileViewerSelecting([app])
        } catch {
            print(error)
        }
    }

    private static func buildShortcutIcon(using programIcon: NSImage?) -> NSImage {
        guard UserDefaults.standard.object(forKey: "wrapProgramShortcuts") as? Bool ?? true else {
            return programIcon ?? NSImage(named: "BrandMark") ?? NSImage()
        }

        let canvasSize = NSSize(width: 1024, height: 1024)
        let output = NSImage(size: canvasSize)

        output.lockFocus()
        defer { output.unlockFocus() }

        let fullRect = NSRect(origin: .zero, size: canvasSize)
        if let background = NSImage(named: "BrandMark") {
            background.draw(in: fullRect)
        } else {
            NSColor.windowBackgroundColor.setFill()
            fullRect.fill()
        }

        let cardRect = NSRect(x: 224, y: 208, width: 576, height: 576)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
        shadow.shadowBlurRadius = 36
        shadow.shadowOffset = NSSize(width: 0, height: -18)

        NSGraphicsContext.saveGraphicsState()
        shadow.set()
        let cardPath = NSBezierPath(roundedRect: cardRect, xRadius: 132, yRadius: 132)
        NSColor.white.withAlphaComponent(0.16).setFill()
        cardPath.fill()
        NSGraphicsContext.restoreGraphicsState()

        NSColor.white.withAlphaComponent(0.28).setStroke()
        cardPath.lineWidth = 5
        cardPath.stroke()

        let highlightRect = NSRect(x: cardRect.minX + 18, y: cardRect.maxY - 152, width: cardRect.width - 36, height: 110)
        let highlightPath = NSBezierPath(roundedRect: highlightRect, xRadius: 72, yRadius: 72)
        NSColor.white.withAlphaComponent(0.08).setFill()
        highlightPath.fill()

        if let programIcon {
            let iconInsetRect = cardRect.insetBy(dx: 74, dy: 74)
            let iconPath = NSBezierPath(roundedRect: iconInsetRect, xRadius: 84, yRadius: 84)
            iconPath.addClip()
            programIcon.draw(in: iconInsetRect, from: .zero, operation: .sourceOver, fraction: 1)
            NSColor.white.withAlphaComponent(0.12).setStroke()
            iconPath.lineWidth = 4
            iconPath.stroke()
        }

        let badgeRect = NSRect(x: 702, y: 724, width: 126, height: 126)
        let badgePath = NSBezierPath(roundedRect: badgeRect, xRadius: 42, yRadius: 42)
        NSColor.white.withAlphaComponent(0.12).setFill()
        badgePath.fill()
        NSColor.white.withAlphaComponent(0.22).setStroke()
        badgePath.lineWidth = 4
        badgePath.stroke()

        if let badge = NSImage(named: "BrandMark") {
            badge.draw(in: badgeRect.insetBy(dx: 14, dy: 14))
        }

        return output
    }
}

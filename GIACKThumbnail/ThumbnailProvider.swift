//
//  ThumbnailProvider.swift
//  GIACKThumbnail
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
import QuickLookThumbnailing
import AppKit
import GIACKKit

class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(for request: QLFileThumbnailRequest,
                                   _ handler: @escaping (QLThumbnailReply?, Error?) -> Void) {
        let thumbnailSize = CGSize(width: request.maximumSize.width,
                                   height: request.maximumSize.height)

        // % of thumbnail occupied by icon
        let iconScaleFactor = 0.9
        let giackIconScaleFactor = 0.4

        // AppKit coordinate system origin is in the bottom-left
        // Icon is centered
        let iconFrame = CGRect(x: (request.maximumSize.width - request.maximumSize.width * iconScaleFactor) / 2.0,
                               y: (request.maximumSize.height - request.maximumSize.height * iconScaleFactor) / 2.0,
                               width: request.maximumSize.width * iconScaleFactor,
                               height: request.maximumSize.height * iconScaleFactor)

        // GIACK icon is aligned bottom-right
        let giackIconFrame = CGRect(x: request.maximumSize.width - request.maximumSize.width * giackIconScaleFactor,
                                     y: 0,
                                     width: request.maximumSize.width * giackIconScaleFactor,
                                     height: request.maximumSize.height * giackIconScaleFactor)
        do {
            var image: NSImage?

            let peFile = try PEFile(url: request.fileURL)
            image = peFile.bestIcon()

            let reply: QLThumbnailReply = QLThumbnailReply.init(contextSize: thumbnailSize) { () -> Bool in
                if let image = image {
                    image.draw(in: iconFrame)
                    let giackIcon = NSImage(named: NSImage.Name("Icon"))
                    giackIcon?.draw(in: giackIconFrame, from: .zero, operation: .sourceOver, fraction: 1)
                    return true
                }

                // We didn't draw anything
                return false
            }

            handler(reply, nil)
        } catch {
            handler(nil, nil)
        }
    }
}

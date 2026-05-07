//
//  Card+Transferable.swift
//  BOBAPlaybook
//
//  Transferable conformance for SwiftUI drag-and-drop. Used on iPad
//  to drag cards from the Find / Decks pool / Collection grid into
//  the Decks editor (3-column NavigationSplitView per DESIGN.md
//  §6.6). Card is already Codable/Sendable so the implementation is
//  a CodableRepresentation backed by a private UTType.
//
//  iPhone compact width has no in-app drop target (the pool and
//  editor aren't visible at the same time), but `.draggable(_:)`
//  costs nothing when there's nowhere to drop — iOS just snaps the
//  preview back. The same payload is also reachable from external
//  apps that accept the bobaCard UTType.
//

import Foundation
import CoreTransferable
import UniformTypeIdentifiers

extension UTType {
    /// Custom UTType for in-app card drag-drop. The `exportedAs`
    /// identifier is namespaced under the bundle ID and intentionally
    /// not declared in Info.plist — we don't want third-party apps
    /// announcing they can receive BOBA cards. Internal use only.
    static let bobaCard = UTType(exportedAs: "com.bhwilkoff.bobaplaybook.card")
}

extension Card: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .bobaCard)
    }
}

//
//  CloudStorageBootstrap.swift
//  ExcalidrawZ
//

import Foundation

/// The third-party providers (OneDrive, Google Drive, Dropbox, Box, WebDAV)
/// were removed from this build; nothing is registered.
enum CloudStorageBootstrap {
    @MainActor
    static func registerConfiguredProviders() async {}
}

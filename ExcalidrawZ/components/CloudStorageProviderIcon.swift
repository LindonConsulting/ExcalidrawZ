//
//  CloudStorageProviderIcon.swift
//  ExcalidrawZ
//

import SwiftUI

struct CloudStorageProviderIcon: View {
    let providerID: CloudStorageProviderID
    let size: CGFloat
    var accountDisplayName: String? = nil

    var body: some View {
        Image(systemName: "externaldrive.fill")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

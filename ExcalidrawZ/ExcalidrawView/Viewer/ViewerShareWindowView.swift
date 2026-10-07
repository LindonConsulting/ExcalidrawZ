//
//  ViewerShareWindowView.swift
//  ExcalidrawZ
//
//  Small window for sharing the Viewer with browsers on the local network:
//  on/off switch, the link, a QR code and the connected-viewer count.
//

#if os(macOS)
import AppKit
import CoreImage.CIFilterBuiltins
import SwiftUI

struct ViewerShareWindowView: View {
    @ObservedObject private var controller = ViewerMirrorController.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Toggle(isOn: sharingBinding) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(.localizable(.viewerShareToggleTitle))
                    Text(.localizable(.viewerShareToggleHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Toggle(isOn: $controller.startsNetworkSharingAtLaunch) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(.localizable(.viewerShareAutoStartTitle))
                    Text(.localizable(.viewerShareAutoStartHelp))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = controller.networkSharingState {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if controller.isNetworkSharingEnabled {
                if let url = controller.networkShareURLs.first {
                    HStack(alignment: .top, spacing: 16) {
                        if let image = Self.qrCode(for: url) {
                            Image(nsImage: image)
                                .interpolation(.none)
                                .resizable()
                                .frame(width: 140, height: 140)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(controller.networkShareURLs, id: \.absoluteString) { url in
                                HStack(spacing: 6) {
                                    Text(url.absoluteString)
                                        .font(.callout.monospaced())
                                        .textSelection(.enabled)
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                    .help(Text(.localizable(.generalButtonCopy)))
                                }
                            }
                            Text(.localizable(.viewerShareConnectedCount(controller.networkClientCount)))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text(.localizable(.viewerShareNoNetwork))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(20)
        .frame(minWidth: 420, alignment: .topLeading)
    }

    private var sharingBinding: Binding<Bool> {
        Binding {
            controller.isNetworkSharingEnabled
        } set: { enabled in
            controller.setNetworkSharing(enabled)
        }
    }

    private static func qrCode(for url: URL) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(url.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 8, y: 8))
        let representation = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: representation.size)
        image.addRepresentation(representation)
        return image
    }
}
#endif

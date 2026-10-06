//
//  CoverageViews.swift
//  ExcalidrawZ
//

import SwiftUI
import TutorModels

extension CoverageStatus {
    var color: Color {
        switch self {
            case .notCovered: return Color.secondary.opacity(0.25)
            case .shown: return .blue
            case .right: return .green
            case .partial: return .orange
            case .wrong: return .red
        }
    }

    var title: String {
        switch self {
            case .notCovered: return "Not covered"
            case .shown: return "Shown"
            case .right: return "Right"
            case .partial: return "Partly"
            case .wrong: return "Wrong"
        }
    }
}

/// Stacked bar of coverage counts.
struct CoverageBar: View {
    let coverage: TutorKitContainer.CoverageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach([CoverageStatus.right, .partial, .wrong, .shown, .notCovered], id: \.self) { status in
                        let fraction = coverage.total == 0 ? 0 : CGFloat(coverage.count(status)) / CGFloat(coverage.total)
                        Rectangle().fill(status.color).frame(width: proxy.size.width * fraction)
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
            Text("\(coverage.total - coverage.count(.notCovered)) of \(coverage.total) spec points covered · \(coverage.count(.right)) right · \(coverage.count(.wrong)) wrong")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct StatusPill: View {
    let status: CoverageStatus
    var body: some View {
        Text(status.title)
            .font(.caption2)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(status.color.opacity(status == .notCovered ? 1 : 0.2), in: Capsule())
            .foregroundStyle(status == .notCovered ? Color.secondary : status.color)
    }
}

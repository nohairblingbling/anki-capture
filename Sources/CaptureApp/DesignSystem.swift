import SwiftUI

enum AppStyle {
    static let pagePadding: CGFloat = 32
    static let sectionGap: CGFloat = 24
    static let contentGap: CGFloat = 16
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
}

struct PageHeading: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 24, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct FieldCaption: View {
    let title: String
    var optional = false
    var body: some View {
        HStack(spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            if optional { Text("可选").font(.caption).foregroundStyle(.secondary) }
        }.accessibilityElement(children: .combine)
    }
}

struct StatusLabel: View {
    let title: String
    let symbol: String
    var color: Color = .secondary
    var body: some View {
        Label(title, systemImage: symbol)
            .font(.caption.weight(.medium)).foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}

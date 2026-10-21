import SwiftUI

enum AppStyle {
    static let pagePadding: CGFloat = 32
    static let sectionGap: CGFloat = 24
    static let contentGap: CGFloat = 16
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let canvas = Color(nsColor: .windowBackgroundColor)
}

struct PageHeading: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
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
    let title: LocalizedStringKey
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
        Label { Text(LocalizedStringKey(title)) } icon: { Image(systemName: symbol) }
            .font(.caption.weight(.medium)).foregroundStyle(color)
            .accessibilityElement(children: .combine)
    }
}

/// Keep the native disclosure state while making the title and empty row space actionable.
struct FullRowDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { configuration.isExpanded.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: configuration.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        .frame(width: 12).accessibilityHidden(true)
                    configuration.label
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(Text(LocalizedStringKey(configuration.isExpanded ? "已展开" : "已折叠")))
            if configuration.isExpanded {
                configuration.content.padding(.leading, 20)
            }
        }
    }
}

import SwiftUI

/// 56pt-tall filled primary button — the one action shape used everywhere.
struct BigButton: View {
    let title: LocalizedStringKey
    var systemImage: String?
    var color: Color = Theme.terracottaFill
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .font(.system(.headline, design: .rounded))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(minHeight: 56)
            .background(color, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

struct CategoryBadge: View {
    let category: ServiceCategory
    var size: CGFloat = 48

    var body: some View {
        Image(systemName: category.symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(Theme.terracotta)
            .frame(width: size, height: size)
            .background(Circle().fill(Theme.terracotta.opacity(0.14)))
            .accessibilityHidden(true)
    }
}

struct DemoBanner: View {
    var body: some View {
        Label {
            Text("Demo mode — changes are not saved")
                .font(.footnote.weight(.medium))
        } icon: {
            Image(systemName: "eye.fill")
        }
        .foregroundStyle(Theme.ink)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.yellow.opacity(0.25), in: Capsule())
    }
}

struct InlineMessage: View {
    enum Kind { case error, info }
    let kind: Kind
    let text: String

    var body: some View {
        Label {
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: kind == .error ? "exclamationmark.triangle.fill" : "envelope.fill")
        }
        .foregroundStyle(kind == .error ? Theme.danger : Theme.ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            (kind == .error ? Theme.danger.opacity(0.12) : Theme.terracotta.opacity(0.12)),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
    }
}

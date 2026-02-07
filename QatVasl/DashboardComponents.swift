import SwiftUI

private extension ConnectivityState {
    var accentColor: Color {
        switch self {
        case .offline:
            return .red
        case .domesticOnly:
            return .orange
        case .globalLimited:
            return .yellow
        case .vpnOK:
            return .green
        case .vpnOrProxyActive:
            return .blue
        case .openInternet:
            return .mint
        }
    }
}

struct GlassCard<Content: View>: View {
    let cornerRadius: CGFloat
    let tint: Color?
    @ViewBuilder var content: Content

    init(cornerRadius: CGFloat = 18, tint: Color? = nil, @ViewBuilder content: () -> Content) {
        self.cornerRadius = cornerRadius
        self.tint = tint
        self.content = content()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let glass = tint.map { Glass.regular.tint($0.opacity(0.12)) } ?? .regular

        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: shape)
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(.white.opacity(0.06), lineWidth: 0.8)
            )
            .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
    }
}

struct StatusPill: View {
    let state: ConnectivityState

    var body: some View {
        Label("\(state.statusEmoji) \(state.shortLabel)", systemImage: state.systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .glassEffect(.regular.tint(color.opacity(0.14)), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(.white.opacity(0.08), lineWidth: 0.8)
            )
    }

    private var color: Color {
        state.accentColor
    }
}

struct StateGlyph: View {
    let state: ConnectivityState

    var body: some View {
        ZStack {
            Circle()
                .fill(.clear)
                .frame(width: 56, height: 56)
                .glassEffect(.regular.tint(state.accentColor.opacity(0.10)), in: Circle())

            Image(systemName: state.systemImage)
                .font(.title3.weight(.bold))
                .foregroundStyle(state.accentColor)
        }
    }
}

struct ProbeMetricCard: View {
    let result: ProbeResult

    var body: some View {
        GlassCard(cornerRadius: 14, tint: result.ok ? .green : .orange) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: result.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(result.ok ? .green : .orange)
                    Text(result.name)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                }

                Text(result.summary)
                    .font(.callout.weight(.medium))

                Text(result.target)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

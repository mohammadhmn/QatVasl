import SwiftUI

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
        let glass = tint.map { Glass.regular.tint($0.opacity(0.10)) } ?? .regular

        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(glass, in: shape)
            .clipShape(shape)
            .overlay(
                shape
                    .strokeBorder(.white.opacity(0.05), lineWidth: 0.7)
            )
            .shadow(color: .black.opacity(0.14), radius: 10, y: 5)
    }
}

struct StatusPill: View {
    let state: ConnectivityState

    var body: some View {
        HStack(spacing: 7) {
            Circle()
                .fill(color)
                .frame(width: 9, height: 9)

            Text(state.shortLabel)
                .font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(color.opacity(0.12)), in: Capsule(style: .continuous))
        .overlay(
            Capsule(style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.7)
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

struct RouteChip: View {
    let indicator: RouteIndicator

    var body: some View {
        Label(indicator.kind.title, systemImage: indicator.kind.systemImage)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .glassEffect(.regular.tint(chipColor.opacity(indicator.isActive ? 0.14 : 0.04)), in: Capsule(style: .continuous))
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(indicator.isActive ? chipColor.opacity(0.42) : .white.opacity(0.08), lineWidth: 0.8)
            )
            .foregroundStyle(indicator.isActive ? chipColor : .secondary)
    }

    private var chipColor: Color {
        switch indicator.kind {
        case .direct:
            return .mint
        case .vpn:
            return .indigo
        case .proxy:
            return .cyan
        }
    }
}

struct ProbeMetricCard: View {
    let result: ProbeResult

    var body: some View {
        GlassCard(cornerRadius: 14, tint: result.ok ? .green : .orange) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 8) {
                    Image(systemName: result.systemImage)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(result.ok ? .green : .orange)
                    Text(result.name)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                }

                Text(result.summary)
                    .font(.callout.weight(.semibold))

                Text(result.target)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

import SwiftUI

/// Pick how cleanup shapes your words. One is active at a time; it applies from the next
/// dictation on, wherever it's started from.
struct TemplatesView: View {
    @State private var settings = Settings.shared

    private let columns = [GridItem(.adaptive(minimum: 250), spacing: DS.Space.roomy)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DS.Space.wide) {
                PageHeader(eyebrow: "Templates", title: "Shape how", italic: "your words land.")

                if !smartCleanupOn {
                    notice
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: DS.Space.roomy) {
                    ForEach(DictationTemplate.allCases) { template in
                        TemplateCard(
                            template: template,
                            isActive: settings.template == template,
                            isLimited: template.needsSmartCleanup && !smartCleanupOn
                        ) {
                            settings.template = template
                        }
                    }
                }
            }
            .padding(DS.Space.page)
            .padding(.top, DS.Space.snug)
        }
    }

    private var smartCleanupOn: Bool {
        settings.cleanupEnabled && settings.smartCleanup
    }

    /// Honest about the limit: without the on-device model, templates can only flip the
    /// rule pass's switches — they can't turn a sentence into a list.
    private var notice: some View {
        HStack(alignment: .top, spacing: DS.Space.base) {
            Image(systemName: "sparkles")
                .foregroundStyle(DS.Color.accentInk)
            VStack(alignment: .leading, spacing: DS.Space.tight) {
                Text("Templates do the most with Smart cleanup")
                    .font(DS.Font.bodyEmphasis)
                    .foregroundStyle(DS.Color.ink)
                Text("Without it, cleanup is rule-based: fillers, spacing and capitals. Tasks and Content need the on-device model to restructure what you said.")
                    .font(DS.Font.label)
                    .foregroundStyle(DS.Color.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            if FoundationModelFormatter.isAvailable {
                Button("Turn on") {
                    settings.cleanupEnabled = true
                    settings.smartCleanup = true
                }
                .buttonStyle(.pillPrimary)
            } else if let reason = FoundationModelFormatter.unavailableReason {
                Text(reason)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkTertiary)
                    .frame(maxWidth: 200, alignment: .trailing)
                    .multilineTextAlignment(.trailing)
            }
        }
        .padding(DS.Space.roomy)
        .background(DS.Color.selection.opacity(0.5), in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

private struct TemplateCard: View {
    let template: DictationTemplate
    let isActive: Bool
    let isLimited: Bool
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.base) {
            HStack(alignment: .top) {
                Image(systemName: template.symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isActive ? DS.Color.onAccent : DS.Color.ink)
                    .frame(width: DS.Size.iconTile, height: DS.Size.iconTile)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
                            .fill(isActive ? DS.Color.accent : DS.Color.sunken)
                    )
                Spacer()
                if isActive {
                    Chip(text: "Active", systemImage: "checkmark", tint: DS.Color.live, fill: DS.Color.liveSoft)
                } else if isLimited {
                    Chip(text: "Best with Smart cleanup", tint: DS.Color.warning, fill: DS.Color.warningSoft)
                }
            }

            Text(template.title)
                .font(DS.Font.title)
                .foregroundStyle(DS.Color.ink)
            Text(template.summary)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: DS.Space.snug) {
                Eyebrow(text: "You say")
                Text(template.example.said)
                    .font(DS.Font.label.italic())
                    .foregroundStyle(DS.Color.inkTertiary)
                Eyebrow(text: "You get")
                Text(template.example.result)
                    .font(DS.Font.label)
                    .fontDesign(template == .code ? .monospaced : .default)
                    .foregroundStyle(DS.Color.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DS.Space.base)
            .sunkenStyle()

            Spacer(minLength: 0)

            Button(isActive ? "In use" : "Use \(template.title)", action: onUse)
                .buttonStyle(PillButtonStyle(kind: isActive ? .secondary : .primary))
                .disabled(isActive)
        }
        .padding(DS.Space.roomy + DS.Space.tight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
                .strokeBorder(isActive ? DS.Color.accentInk.opacity(0.5) : .clear, lineWidth: DS.Border.strong)
        )
    }
}

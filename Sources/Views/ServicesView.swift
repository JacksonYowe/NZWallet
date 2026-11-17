// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

/// Services, grouped by topic like the Service NSW services list. Each row either
/// pushes an in-app mock screen or opens the official NZ Government website in-app
/// (see ServiceCatalog for which is which, and why).
struct ServicesView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var web: IdentifiedURL?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(ServiceCatalog.groups, id: \.title) { group in
                        GovPanel(title: settings.t(group.title)) {
                            ForEach(Array(group.items.enumerated()), id: \.element.id) { i, s in
                                row(s, divider: i < group.items.count - 1)
                            }
                        }
                    }
                    GovFootnote(text: settings.t("services.subtitle"))

                }
                .padding(16)
            }
            .background(Color.govPage)
            .govHeader(settings.t("services.title"))
            .serviceRoutes(web: $web)
        }
    }

    @ViewBuilder
    private func row(_ s: GovService, divider: Bool) -> some View {
        if s.isWeb {
            // Official government page → open in-app, flagged with a "Website" tag.
            Button { if let u = s.webURL { web = IdentifiedURL(url: u) } } label: {
                GovLinkRow(icon: s.icon, title: settings.t(s.id), tag: settings.t("services.website"),
                           chevron: true, tint: .nzAccent, showDivider: divider)
            }
            .buttonStyle(.plain)
        } else {
            // In-app mock screen.
            NavigationLink(value: s) {
                GovLinkRow(icon: s.icon, title: settings.t(s.id), tint: .nzAccent, showDivider: divider)
            }
            .buttonStyle(.plain)
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

// Government visual language aggregated from Service NSW and myVicRoads
// (see docs/DESIGN_LANGUAGE.md): flat and opaque, light grey page, white
// sections with hairline borders, one dark colour plus one accent, stacked rows.
extension Color {
    static let nzInk    = Color(red: 0.071, green: 0.102, blue: 0.129) // #121A21 titles, buttons
    static let nzAccent = Color(red: 0.0, green: 0.478, blue: 0.369)   // #007A5E pounamu accent
    static let nzSilver = Color(red: 0.72, green: 0.76, blue: 0.78)    // #B8C2C8 silver
    static let govPaper = Color(red: 0.945, green: 0.965, blue: 0.953) // #F1F6F3 licence card stock
    static let govInk   = Color(red: 0.133, green: 0.153, blue: 0.169) // #22272B body text
    static let govMuted = Color(red: 0.353, green: 0.392, blue: 0.439) // #5A6470 labels
    static let govPage  = Color(red: 0.949, green: 0.949, blue: 0.949) // #F2F2F2 page
    static let govLine  = Color(red: 0.871, green: 0.882, blue: 0.898) // #DEE1E5 borders
}

extension View {
    /// Opaque white header: Southern Cross mark, bold title, accent rule underneath.
    func govHeader(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.white, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    HStack(spacing: 8) {
                        NZMark(color: .nzInk, outline: .white, lineWidth: 0.5).frame(width: 30, height: 30)
                        Text(title).font(.gov(.headline, .heavy)).foregroundStyle(Color.nzInk)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                Rectangle().fill(Color.nzAccent).frame(height: 3)
            }
    }

    /// Opaque white tab bar with navy selection (no floating glass).
    func govTabBar() -> some View {
        self
            .toolbarBackground(Color.white, for: .tabBar)
            .toolbarBackground(.visible, for: .tabBar)
    }
}

/// Bold sentence-case heading above a white, flat, bordered section.
struct GovPanel<Content: View>: View {
    let title: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title)
                    .font(.gov(.title3, .bold))
                    .foregroundStyle(Color.nzInk)
                    .padding(.top, 6)
                    .accessibilityAddTraits(.isHeader)
            }
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
        }
    }
}

/// Label stacked above a bold value, as on both reference apps' detail screens.
struct GovRow: View {
    let label: String
    let value: String
    var valueColor: Color = .govInk
    var showDivider = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                Text(value)
                    .font(.gov(.body, .semibold))
                    .foregroundStyle(valueColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if showDivider { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 16) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Coloured left bar + icon + tinted background (in-page alert).
struct GovNotice: View {
    let text: String
    var icon = "info.circle.fill"
    var color: Color = .nzInk

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).foregroundStyle(color)
            Text(text).font(.gov(.footnote)).foregroundStyle(Color.govInk)
            Spacer(minLength: 0)
        }
        .padding(12)
        .padding(.leading, 4)
        .background(color.opacity(0.07))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: 4) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct GovButtonStyle: ButtonStyle {
    var prominent = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.gov(.headline))
            .padding(.vertical, 13)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .foregroundStyle(prominent ? Color.white : Color.nzInk)
            .background(prominent ? Color.nzInk : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.nzInk, lineWidth: prominent ? 0 : 2))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Dates as printed on NZ documents: dd/MM/yyyy.
enum CardDate {
    private static func formatter(_ pattern: String) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = pattern
        return f
    }
    static func format(_ d: Date) -> String { formatter("dd/MM/yyyy").string(from: d) }
    static func iso(_ s: String) -> String {
        guard let d = formatter("yyyy-MM-dd").date(from: s) else { return s }
        return format(d)
    }
}

/// Flat list row: icon, title, optional detail, trailing tag or chevron.
struct GovLinkRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var tag: String? = nil
    var chevron = true
    var tint: Color = .nzInk
    var showDivider = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.gov(.body, .semibold)).foregroundStyle(tint == .red ? Color.red : Color.govInk)
                    if let detail { Text(detail).font(.gov(.footnote)).foregroundStyle(Color.govMuted) }
                }
                Spacer(minLength: 8)
                if let tag {
                    Text(tag)
                        .font(.gov(.caption, .semibold)).foregroundStyle(Color.govMuted)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
                }
                if chevron {
                    Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.govMuted)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
            if showDivider { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 64) }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small muted note under a panel (replaces grouped-list footers).
struct GovFootnote: View {
    let text: String
    var body: some View {
        Text(text).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

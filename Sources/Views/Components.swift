// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI

extension CredentialType {
    var icon: String {
        switch self {
        case .nationalID: "person.text.rectangle.fill"
        case .driverLicence: "car.fill"
        case .healthInsurance: "cross.case.fill"
        case .degree: "graduationcap.fill"
        }
    }
}

extension VerificationOutcome {
    var titleKey: String {
        switch self {
        case .valid: "result.valid"
        case .validOffline: "result.validOffline"
        case .invalid: "result.invalid"
        case .expired: "result.expired"
        case .unverifiable: "result.unverifiable"
        }
    }
    var reasonKey: String? {
        switch self {
        case .invalid(let r), .unverifiable(let r): r
        case .expired: "reason.expired"
        default: nil
        }
    }
    var icon: String {
        switch self {
        case .valid: "checkmark.seal.fill"
        case .validOffline: "checkmark.icloud.fill"
        case .invalid: "xmark.octagon.fill"
        case .expired: "clock.badge.xmark.fill"
        case .unverifiable: "questionmark.diamond.fill"
        }
    }
    var color: Color {
        switch self {
        case .valid: .green
        case .validOffline: .orange
        case .invalid, .expired: .red
        case .unverifiable: .gray
        }
    }
}

/// Flat status stamp.
struct StatusPill: View {
    @EnvironmentObject private var settings: AppSettings
    let status: CredentialStatus

    var body: some View {
        let (text, icon, color): (String, String, Color) = switch status {
        case .valid: (settings.t("status.valid"), "checkmark.circle.fill", Color(red: 0.13, green: 0.55, blue: 0.27))
        case .expiringSoon(let d): (settings.t("status.expiresInDays", d), "exclamationmark.circle.fill", .orange)
        case .expired: (settings.t("status.expired"), "xmark.circle.fill", .red)
        }
        Label(text, systemImage: icon)
            .font(.gov(.caption, .bold))
            .textCase(.uppercase)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(color, in: RoundedRectangle(cornerRadius: 4))
            .foregroundStyle(.white)
    }
}

/// Proof-of-age chip: compares today's date to the date of birth and shows
/// whether the holder is over or under 18. Replaces the plain validity tick on
/// the licence card. The result is computed live, so it is always current.
struct AgePill: View {
    @EnvironmentObject private var settings: AppSettings
    let dateOfBirth: String   // yyyy-MM-dd

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let over18 = DemoLicenceData.age(dateOfBirth, now: context.date) >= 18
            let green = Color(red: 0.13, green: 0.55, blue: 0.27)
            let amber = Color(red: 0.78, green: 0.45, blue: 0.0)
            Label(settings.t(over18 ? "age.over18" : "age.under18"),
                  systemImage: over18 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.gov(.caption, .bold))
                .textCase(.uppercase)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(over18 ? green : amber, in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(.white)
                .accessibilityLabel(settings.t(over18 ? "age.over18" : "age.under18"))
        }
    }
}

struct PrototypeBanner: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(Color.orange).frame(width: 4)
            Label(settings.t("prototype.banner"), systemImage: "exclamationmark.triangle.fill")
                .font(.gov(.caption, .semibold))
                .foregroundStyle(Color(red: 0.6, green: 0.33, blue: 0.0))
                .padding(.vertical, 8)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .background(Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

struct LiveClock: View {
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            Text(ctx.date, format: .dateTime.hour().minute().second())
                .font(.gov(.caption, .semibold).monospacedDigit())
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import SafariServices

/// A government service tile.
///
/// Each service does one of two things when tapped:
/// - **In-app mock screen** — for anything that would involve a form, a payment,
///   or showing the citizen's own data. These are front-end only (no backend) and
///   clearly marked TEST. We build these because the real flow needs app UI.
/// - **Official website, opened in-app** — for content-only pages the NZ Government
///   already publishes (driver licence info, the Road Code, IRD, passports, …).
///   We don't rebuild government content; we open the authoritative page in an
///   in-app Safari view so the citizen always sees current, official information.
struct GovService: Identifiable, Hashable {
    let id: String          // localisation key, e.g. "service.renewLicence"
    let icon: String        // SF Symbol name
    let dest: Dest

    enum Dest: Hashable {
        // In-app mock screens (front-end only):
        case renew          // renew driver licence (form)
        case demerit        // demerit points (the holder's own balance)
        case bookTest       // book a driving test (form)
        case vehicles       // vehicles / rego (the holder's own list)
        case infringement   // pay an infringement fee (front-end only — no real payment)
        case address        // update address (form)
        // Content-only page hosted by the NZ Government, opened in-app:
        case web(String)
    }

    var isWeb: Bool { if case .web = dest { true } else { false } }
    var webURL: URL? { if case .web(let s) = dest { URL(string: s) } else { nil } }
}

/// The service catalogue, grouped by topic like the Service NSW services list.
///
/// URLs are official NZ Government section pages. They are deliberately section
/// roots (not deep links) so they stay valid; the in-app browser shows the real
/// address, so the citizen can see it is the genuine site.
enum ServiceCatalog {
    static let groups: [(title: String, items: [GovService])] = [
        ("services.group.driving", [
            GovService(id: "service.renewLicence", icon: "car.fill", dest: .renew),
            GovService(id: "service.points", icon: "gauge.with.dots.needle.33percent", dest: .demerit),
            GovService(id: "service.test", icon: "calendar.badge.clock", dest: .bookTest),
            GovService(id: "service.driverInfo", icon: "info.circle.fill", dest: .web("https://www.nzta.govt.nz/driver-licences/")),
            GovService(id: "service.roadCode", icon: "book.fill", dest: .web("https://www.nzta.govt.nz/roadcode/")),
        ]),
        ("services.group.vehicles", [
            GovService(id: "service.vehicles", icon: "car.2.fill", dest: .vehicles),
            GovService(id: "service.fines", icon: "creditcard.fill", dest: .infringement),
            GovService(id: "service.vehicleInfo", icon: "info.circle.fill", dest: .web("https://www.nzta.govt.nz/vehicles/")),
        ]),
        ("services.group.details", [
            GovService(id: "service.address", icon: "house.fill", dest: .address),
            GovService(id: "service.realme", icon: "person.badge.key.fill", dest: .web("https://www.realme.govt.nz/")),
        ]),
        // Broader government services beyond transport. These are mostly content and
        // transactions the relevant agency already hosts, so they open the official site.
        ("services.group.other", [
            GovService(id: "service.passports", icon: "airplane", dest: .web("https://www.passports.govt.nz/")),
            GovService(id: "service.bdm", icon: "doc.text.fill", dest: .web("https://www.govt.nz/browse/family-and-whanau/")),
            GovService(id: "service.ird", icon: "dollarsign.circle.fill", dest: .web("https://www.ird.govt.nz/")),
            GovService(id: "service.support", icon: "hand.raised.fill", dest: .web("https://www.workandincome.govt.nz/")),
            GovService(id: "service.health", icon: "cross.case.fill", dest: .web("https://www.health.govt.nz/")),
            GovService(id: "service.allServices", icon: "building.2.fill", dest: .web("https://www.govt.nz/")),
        ]),
    ]
}

/// Wraps a URL so it can drive a SwiftUI `.sheet(item:)`.
struct IdentifiedURL: Identifiable { let id = UUID(); let url: URL }

/// Opens a URL in an in-app Safari view (SFSafariViewController). The real address
/// bar and site chrome stay visible, so it is obvious the citizen is on the official
/// government website and not an app screen imitating one.
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        let config = SFSafariViewController.Configuration()
        let controller = SFSafariViewController(url: url, configuration: config)
        controller.preferredControlTintColor = UIColor(Color.nzAccent)
        controller.dismissButtonStyle = .close
        return controller
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}

/// Pushes the matching in-app mock screen for a service, and opens official
/// websites in an in-app Safari sheet. Applied by both the Services tab and the
/// Home favourites so they behave the same way.
extension View {
    func serviceRoutes(web: Binding<IdentifiedURL?>) -> some View {
        self
            .navigationDestination(for: GovService.self) { ServiceDetailView(service: $0) }
            .sheet(item: web) { SafariView(url: $0.url).ignoresSafeArea() }
    }
}

/// Dispatches to the right in-app mock screen. Web services never reach here —
/// they are opened as a sheet instead of being pushed.
struct ServiceDetailView: View {
    let service: GovService
    var body: some View {
        switch service.dest {
        case .renew: RenewLicenceView()
        case .demerit: DemeritPointsView()
        case .bookTest: BookTestView()
        case .vehicles: VehiclesView()
        case .infringement: InfringementView()
        case .address: UpdateAddressView()
        case .web: EmptyView()
        }
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import SwiftUI
import AVFoundation

// MARK: - Display helpers

/// Display order: photo and name first, as on the card.
enum MDLDisplayOrder {
    static let ids = ["portrait", "family_name", "given_name", "birth_date", "age_over_18", "age_over_21",
                      "document_number", "driving_privileges", "issue_date", "expiry_date", "resident_address",
                      "resident_city", "resident_country", "nationality", "issuing_country", "issuing_authority",
                      "un_distinguishing_sign", "card_version", "licence_classes", "endorsements", "organ_donor"]
    static func sorted(_ list: [String]) -> [String] {
        list.sorted { (ids.firstIndex(of: $0) ?? 99, $0) < (ids.firstIndex(of: $1) ?? 99, $1) }
    }
}

extension AppSettings {
    func elementName(_ id: String) -> String { t("el.\(id)") }

    func elementValue(_ id: String, _ v: CBOR) -> String? {
        if id == "portrait" { return nil }
        if case .tagged(let tag, _) = v, tag == 0 || tag == 1004, let d = v.displayDate { return d }
        if id.hasSuffix("_date"), let d = v.displayDate { return d }
        switch v.untagged {
        case .bool(let b): return t(b ? "common.yes" : "common.no")
        case .text(let s): return s
        case .unsigned, .negative: return v.int.map(String.init)
        case .array(let a) where id == "driving_privileges":
            return a.compactMap { p -> String? in
                guard let cat = p["vehicle_category_code"]?.text else { return nil }
                let local = p["codes"]?.array?.compactMap { $0["code"]?.text }.joined(separator: " ") ?? ""
                return local.isEmpty ? cat : "\(cat) (\(local))"
            }.joined(separator: ", ")
        case .array(let a) where a.isEmpty: return "—"
        case .array(let a): return a.compactMap { $0.text }.joined(separator: ", ")
        default: return "…"
        }
    }
}

// MARK: - Holder: share in person

@MainActor
final class ShareController: ObservableObject {
    enum Phase: Equatable { case waiting, connected, request(MDLItemsRequest), sent, declined, ended }

    @Published var phase: Phase = .waiting
    @Published var qr = ""
    @Published var remaining = 30
    @Published var bluetoothNoteKey: String?
    @Published var selection: [String: Set<String>] = [:]
    @Published var demoResult: MDLVerification?

    private var store: WalletStore?
    private var session: MDLHolderSession?
    private var ble: MDLGATTServer?
    private var demoReader: MDLReaderSession?
    private(set) var available: [String: [String]] = [:]

    func begin(_ store: WalletStore) {
        self.store = store
        newSession()
    }

    /// Fresh engagement: new ephemeral key and Bluetooth service ID, so an old QR is useless.
    func newSession() {
        stop()
        guard let store, let s = store.makeHolderSession() else { return }
        session = s
        available = s.availableElements
        qr = s.engagement.qrString
        remaining = 30
        phase = .waiting
        demoResult = nil
        s.onStateChange = { [weak self] st in Task { @MainActor in self?.update(st) } }
        ble = s.startBluetooth { [weak self] err in
            Task { @MainActor in
                self?.bluetoothNoteKey = switch err {
                case .poweredOff: "share.bleOff"
                case .unauthorized: "share.bleDenied"
                default: "share.bleUnavailable"
                }
            }
        }
    }

    func tick() {
        guard phase == .waiting else { return }
        remaining -= 1
        if remaining <= 0 { newSession() }
    }

    private func update(_ st: MDLHolderSession.State) {
        switch st {
        case .waiting: phase = .waiting
        case .connected: phase = .connected
        case .requested(let req):
            selection = req.elements.reduce(into: [:]) { acc, kv in
                acc[kv.key] = Set(kv.value.keys).intersection(available[kv.key] ?? [])
            }
            phase = .request(req)
        case .sent: phase = .sent
        case .declined: phase = .declined
        case .failed, .closed: if phase != .sent && phase != .declined { phase = .ended }
        }
    }

    func approve(reason: String) async {
        guard await Biometrics.confirm(reason: reason) else { return }
        session?.approve(selection)
        store?.logMDLShare(selection.values.flatMap { $0 }.sorted(), positive: true)
    }

    func decline() {
        if case .request(let req) = phase {
            store?.logMDLShare(req.elements.values.flatMap(\.keys).sorted(), positive: false)
        }
        session?.decline()
    }

    /// Same-phone demo: a reader on this phone, connected in memory instead of Bluetooth.
    func runDemo(_ scenario: Scenario) {
        guard phase == .waiting, let session,
              let reader = MDLReaderSession(qr: qr, request: scenario.mdlRequest, trustedIACAKeys: WalletStore.mdlTrustList) else { return }
        ble?.close(); ble = nil
        demoReader = reader
        let (h, r) = LoopbackTransport.pair()
        session.attach(h)
        reader.onStateChange = { [weak self] st in
            if case .done(let v) = st { Task { @MainActor in self?.demoResult = v } }
        }
        reader.start(r)
    }

    func stop() {
        session?.cancel()
        ble?.close()
        session = nil; ble = nil; demoReader = nil
    }
}

struct ShareLicenceView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var store: WalletStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var share = ShareController()
    @State private var savedBrightness: CGFloat?
    @State private var isCaptured = UIScreen.main.isCaptured
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    holderStrip
                    switch share.phase {
                    case .waiting: waiting
                    case .connected: status(icon: "antenna.radiowaves.left.and.right", key: "share.connecting", color: .nzInk, busy: true)
                    case .request(let req): consent(req)
                    case .sent: finished(icon: "checkmark.circle.fill", key: "share.sent", color: .green)
                    case .declined: finished(icon: "hand.raised.fill", key: "share.declined", color: .govMuted)
                    case .ended: finished(icon: "xmark.circle.fill", key: "share.failed", color: .govMuted)
                    }
                    Text(settings.t("share.standard"))
                        .font(.gov(.caption)).foregroundStyle(Color.govMuted)
                }
                .padding(16)
            }
            .background(Color.govPage)
            .govHeader(settings.t("share.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("common.done")) { dismiss() }.foregroundStyle(Color.nzInk)
                }
            }
            .onAppear {
                share.begin(store)
                savedBrightness = UIScreen.main.brightness
                UIScreen.main.brightness = 1.0
            }
            .onDisappear {
                share.stop()
                if let b = savedBrightness { UIScreen.main.brightness = b }
            }
            .onReceive(timer) { _ in share.tick() }
            .onReceive(NotificationCenter.default.publisher(for: UIScreen.capturedDidChangeNotification)) { _ in
                isCaptured = UIScreen.main.isCaptured
            }
            .sheet(item: Binding(get: { share.demoResult.map(IdentifiedResult.init) }, set: { if $0 == nil { share.demoResult = nil } })) { r in
                NavigationStack {
                    MDLResultView(result: r.value)
                        .govHeader(settings.t("reader.title"))
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button(settings.t("common.done")) { share.demoResult = nil }.foregroundStyle(Color.nzInk)
                            }
                        }
                }
            }
        }
    }

    private var holderStrip: some View {
        HStack(spacing: 12) {
            LicencePortrait().frame(width: 44, height: 58)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: store.holderName.uppercased(with: Locale(identifier: "en_NZ"))).font(.gov(.headline))
                Text(verbatim: "Số / No. \(store.credentials.first?.value("licenceNumber") ?? "")")
                    .font(.gov(.caption)).foregroundStyle(Color.govMuted)
            }
            Spacer()
            LiveClock()
        }
        .padding(12)
        .background(Color.govPaper)
        .overlay(alignment: .trailing) {
            HologramFoil(shape: NZMarkShape(), lineWidth: 1.6, strength: 0.7)
                .frame(width: 44, height: 38).padding(.trailing, 90)
        }
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
    }

    private var waiting: some View {
        VStack(spacing: 14) {
            Text(settings.t("share.instructions")).font(.gov(.headline)).multilineTextAlignment(.center)
            Group {
                if let img = QRCode.image(share.qr) {
                    Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                } else { ProgressView() }
            }
            .frame(width: 250, height: 250)
            .blur(radius: isCaptured ? 24 : 0)
            .overlay {
                if isCaptured {
                    Label(settings.t("qr.recording"), systemImage: "record.circle")
                        .font(.gov(.subheadline, .semibold)).foregroundStyle(.red).padding()
                }
            }
            .padding(12)
            .background(Color.white)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.govLine))
            .accessibilityLabel(settings.t("share.instructions"))

            ProgressView(value: Double(share.remaining), total: 30).tint(Color.nzInk).frame(width: 250)
            Text(settings.t("share.newCodeIn", share.remaining))
                .font(.gov(.footnote).monospacedDigit()).foregroundStyle(Color.govMuted)

            GovNotice(text: settings.t("share.howItWorks"), icon: "wifi.slash")
            if let key = share.bluetoothNoteKey {
                GovNotice(text: settings.t(key), icon: "exclamationmark.triangle.fill", color: .orange)
            }


        }
    }

    private func consent(_ req: MDLItemsRequest) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            GovPanel(title: settings.t("share.requestTitle")) {
                let rows = req.elements.sorted { $0.key < $1.key }.flatMap { ns, ids in
                    MDLDisplayOrder.sorted(Array(ids.keys)).map { (ns, $0, ids[$0] ?? false) }
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                    let (ns, id, retain) = row
                    let held = share.available[ns]?.contains(id) ?? false
                    VStack(spacing: 0) {
                        let on = share.selection[ns]?.contains(id) ?? false
                        Button {
                            if on { share.selection[ns]?.remove(id) } else { share.selection[ns, default: []].insert(id) }
                        } label: {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: on ? "checkmark.square.fill" : "square")
                                    .font(.system(size: 24))
                                    .foregroundStyle(held ? Color.nzInk : Color.govLine)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(settings.elementName(id)).font(.gov(.body, .semibold)).foregroundStyle(Color.govInk)
                                    if retain { Text(settings.t("share.retainNote")).font(.gov(.caption)).foregroundStyle(.orange) }
                                    if !held { Text(settings.t("share.notHeld")).font(.gov(.caption)).foregroundStyle(Color.govMuted) }
                                }
                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!held)
                        .accessibilityAddTraits(on ? .isSelected : [])
                        .padding(.horizontal, 16).padding(.vertical, 10)
                        if i < rows.count - 1 { Rectangle().fill(Color.govLine).frame(height: 1).padding(.leading, 16) }
                    }
                }
            }
            Button {
                Task { await share.approve(reason: settings.t("share.reason")) }
            } label: { Label(settings.t("share.approve"), systemImage: "faceid") }
            .buttonStyle(GovButtonStyle())
            .disabled(share.selection.values.allSatisfy(\.isEmpty))
            Button(settings.t("share.decline")) { share.decline() }
                .buttonStyle(GovButtonStyle(prominent: false))
        }
    }

    private func status(icon: String, key: String, color: Color, busy: Bool = false) -> some View {
        VStack(spacing: 14) {
            Image(systemName: icon).font(.system(size: 54)).foregroundStyle(color)
            Text(settings.t(key)).font(.gov(.headline)).multilineTextAlignment(.center)
            if busy { ProgressView() }
        }
        .padding(.vertical, 40)
    }

    private func finished(icon: String, key: String, color: Color) -> some View {
        VStack(spacing: 14) {
            status(icon: icon, key: key, color: color)
            Button(settings.t("share.again")) { share.newSession() }.buttonStyle(GovButtonStyle())
        }
    }
}

private struct IdentifiedResult: Identifiable {
    let id = UUID()
    let value: MDLVerification
}

// MARK: - Reader: check a licence

@MainActor
final class CheckController: ObservableObject {
    enum Phase { case choose, connecting, waiting, result(MDLVerification), failed(String) }

    @Published var phase: Phase = .choose
    @Published var scenario: Scenario = .identity
    private var session: MDLReaderSession?
    private var transport: MDLTransport?

    func start(qr: String) {
        guard let s = MDLReaderSession(qr: qr, request: scenario.mdlRequest, trustedIACAKeys: WalletStore.mdlTrustList) else {
            phase = .failed("reader.badQR"); return
        }
        session = s
        phase = .connecting
        s.onStateChange = { [weak self] st in
            Task { @MainActor in
                switch st {
                case .requesting: self?.phase = .waiting
                case .done(let v): self?.phase = .result(v)
                case .failed(let r): self?.phase = .failed(r)
                case .idle: break
                }
            }
        }
        transport = s.startBluetooth { [weak self] err in
            Task { @MainActor in self?.phase = .failed("reader.ble.\(err.rawValue)") }
        }
        if transport == nil { phase = .failed("reader.noBluetoothMode") }
    }

    func reset() {
        session?.cancel(); transport?.close()
        session = nil; transport = nil
        phase = .choose
    }
}

struct CheckLicenceView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @StateObject private var check = CheckController()
    @State private var pasted = ""
    private let hasCamera = AVCaptureDevice.default(for: .video) != nil

    var body: some View {
        NavigationStack {
            Group {
                switch check.phase {
                case .choose: chooser
                case .connecting: progress("reader.connecting")
                case .waiting: progress("reader.waiting")
                case .result(let v):
                    VStack(spacing: 0) {
                        MDLResultView(result: v)
                        again
                    }
                case .failed(let key):
                    ScrollView {
                        VStack(spacing: 16) {
                            Image(systemName: "xmark.octagon.fill").font(.system(size: 54)).foregroundStyle(.red)
                            Text(settings.t(key)).font(.gov(.headline)).multilineTextAlignment(.center)
                            again
                        }
                        .padding(.vertical, 40)
                    }
                }
            }
            .background(Color.govPage)
            .govHeader(settings.t("reader.title"))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(settings.t("common.done")) { dismiss() }.foregroundStyle(Color.nzInk)
                }
            }
            .onDisappear { check.reset() }
        }
    }

    private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GovPanel(title: settings.t("reader.what")) {
                    Picker(settings.t("reader.what"), selection: $check.scenario) {
                        ForEach(Scenario.allCases) { Text(settings.t($0.titleKey)).tag($0) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                    .padding(.horizontal, 8)
                }
                GovPanel(title: settings.t("reader.scan")) {
                    VStack(spacing: 10) {
                        if hasCamera {
                            QRScannerView { code in check.start(qr: code) }
                                .frame(height: 280)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(settings.t("reader.scanHint")).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                        } else {
                            Text(settings.t("reader.noCamera")).font(.gov(.footnote)).foregroundStyle(Color.govMuted)
                        }
                        TextField(settings.t("reader.paste"), text: $pasted, axis: .vertical)
                            .font(.gov(.footnote).monospaced())
                            .textInputAutocapitalization(.never).autocorrectionDisabled()
                            .padding(10).background(Color.govPage).clipShape(RoundedRectangle(cornerRadius: 4))
                        Button(settings.t("reader.check")) { check.start(qr: pasted) }
                            .buttonStyle(GovButtonStyle()).disabled(pasted.isEmpty)
                    }
                    .padding(14)
                }
                GovNotice(text: settings.t("reader.trustNote"), icon: "checkmark.shield.fill")

            }
            .padding(16)
        }
    }

    private func progress(_ key: String) -> some View {
        VStack(spacing: 16) {
            ProgressView().controlSize(.large)
            Text(settings.t(key)).font(.gov(.headline))
            Button(settings.t("common.cancel")) { check.reset() }.buttonStyle(GovButtonStyle(prominent: false)).frame(width: 200)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var again: some View {
        Button(settings.t("reader.again")) { check.reset() }
            .buttonStyle(GovButtonStyle()).padding(16)
    }
}

/// Camera QR scanner (AVFoundation). Calls `onCode` once per scan.
struct QRScannerView: UIViewRepresentable {
    let onCode: (String) -> Void

    final class Preview: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }

    final class Coordinator: NSObject, AVCaptureMetadataOutputObjectsDelegate {
        let session = AVCaptureSession()
        var onCode: (String) -> Void
        var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
            guard !done, let code = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
                  code.hasPrefix("mdoc:") else { return }
            done = true
            session.stopRunning()
            onCode(code)
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    func makeUIView(context: Context) -> Preview {
        let v = Preview()
        let s = context.coordinator.session
        v.preview.session = s
        v.preview.videoGravity = .resizeAspectFill
        if let dev = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: dev), s.canAddInput(input) {
            s.addInput(input)
            let out = AVCaptureMetadataOutput()
            if s.canAddOutput(out) {
                s.addOutput(out)
                out.setMetadataObjectsDelegate(context.coordinator, queue: .main)
                out.metadataObjectTypes = [.qr]
            }
            DispatchQueue.global(qos: .userInitiated).async { s.startRunning() }
        }
        return v
    }

    func updateUIView(_ v: Preview, context: Context) {}

    static func dismantleUIView(_ v: Preview, coordinator: Coordinator) { coordinator.session.stopRunning() }
}

// MARK: - Result

struct MDLResultView: View {
    @EnvironmentObject private var settings: AppSettings
    let result: MDLVerification

    private var style: (title: String, icon: String, color: Color, reason: String?) {
        switch result.outcome {
        case .valid: ("mdl.result.valid", "checkmark.seal.fill", Color(red: 0.13, green: 0.55, blue: 0.27), nil)
        case .untrustedIssuer: ("mdl.result.untrusted", "questionmark.diamond.fill", .orange, "mdl.reason.untrusted")
        case .invalid(let r): ("mdl.result.invalid", "xmark.octagon.fill", .red, r)
        case .expired: ("mdl.result.expired", "clock.badge.xmark.fill", .red, nil)
        }
    }

    var body: some View {
        let s = style
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: s.icon).font(.system(size: 40)).foregroundStyle(.white)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(settings.t(s.title)).font(.gov(.title2, .bold)).foregroundStyle(.white)
                        if let r = s.reason { Text(settings.t(r)).font(.gov(.footnote)).foregroundStyle(.white.opacity(0.9)) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(s.color, in: RoundedRectangle(cornerRadius: 4))

                if !result.elements.isEmpty {
                    GovPanel(title: settings.t("result.verifierSees")) {
                        if let photo = result.value("portrait")?.bytes, let img = UIImage(data: photo) {
                            Image(uiImage: img).resizable().scaledToFit().frame(height: 150)
                                .overlay(Rectangle().stroke(Color.govLine))
                                .padding(16)
                                .frame(maxWidth: .infinity)
                        }
                        let rows = result.elements.sorted { $0.key < $1.key }.flatMap { ns, els in
                            MDLDisplayOrder.sorted(Array(els.keys)).compactMap { id in settings.elementValue(id, els[id]!).map { (id, $0) } }
                        }
                        ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                            GovRow(label: settings.elementName(row.0), value: row.1, showDivider: i < rows.count - 1)
                        }
                    }
                }
                if !result.missing.isEmpty {
                    GovNotice(text: settings.t("reader.missing", result.missing.map(settings.elementName).joined(separator: ", ")),
                              icon: "exclamationmark.circle.fill", color: .orange)
                }
                GovPanel(title: settings.t("result.checks")) {
                    if let name = result.issuerName {
                        GovRow(label: settings.t("reader.issuer"), value: [name, result.issuerCountry].compactMap { $0 }.joined(separator: " · "))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(result.checks) { c in
                            Label(settings.t(c.id), systemImage: c.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                                .foregroundStyle(c.passed ? Color(red: 0.13, green: 0.55, blue: 0.27) : Color.red)
                                .font(.gov(.subheadline))
                        }
                    }
                    .padding(16)
                }
            }
            .padding(16)
        }
        .background(Color.govPage)
    }
}

// SPDX-License-Identifier: GPL-3.0-only
import Foundation

/// App-wide input for previews, simulator demos and both credential formats.
/// Pass a copy to WalletStore(appData:) to render another fictional test fixture.
struct SharedAppData: Codable, Equatable {
    var licence: DemoLicenceData

    static let demo = SharedAppData(licence: .current)
}

/// All changeable fields of the fictional demo driver licence.
/// Dates use ISO `yyyy-MM-dd`.
struct DemoLicenceData: Codable, Equatable {
    struct DrivingClass: Codable, Equatable {
        var iso: String
        var nzClass: String
        var stage: String
    }


    // MARK: Identity
    var surname: String
    var firstNames: String
    /// Date of birth, `yyyy-MM-dd`.
    var dateOfBirth: String

    // MARK: Document
    var licenceNumber: String
    var cardVersion: String
    /// Issue date, `yyyy-MM-dd`.
    var issueDate: String
    /// Expiry date printed on the card, `yyyy-MM-dd`.
    var expiryDate: String

    // MARK: Driving entitlements
    /// Each class: the ISO 18013-5 category, the NZ class number, and the stage
    /// (L = learner, R = restricted, F = full). e.g. ("B", "1", "F") = car, full.
    var classes: [DrivingClass]
    /// Endorsements (P, V, I, …). Empty means none.
    var endorsements: [String]
    var isOrganDonor: Bool
    var demeritPoints: Int

    // MARK: Residence (not printed on the NZ card; shown on the details / verifier side)
    var residentialAddress: String
    var nationality: String

    // MARK: Issuer labels (shown on the licence, replaced by the real authority in production)
    var issuingCountry: String        // ISO 3166 alpha-2
    var issuingAuthority: String

    // MARK: Render images
    /// PNG/JPEG file path, e.g. "/path/to/demo-portrait.jpg".
    /// Absolute paths work where the app can read them (Mac/simulator).
    /// On iPhone, use a bundled relative filename or an accessible app-container path.
    /// Bundled demo files go in TEST FILES CHANGE FOR DEPLOYMENT/; rerun xcodegen generate after adding them.
    /// Recommended: 600 x 800 px, 3:4 portrait, upright, sRGB, under 2 MB.
    /// The card crops to fill; the mDL uses the same image converted to JPEG.
    /// nil, missing or unreadable files use the fictional silhouette.
    var portraitImagePath: String? = nil

    /// PNG/JPEG file path, e.g. "/path/to/demo-signature.png".
    /// Mac paths are not accessible from a physical iPhone. For iPhone builds,
    /// bundle the file in TEST FILES CHANGE FOR DEPLOYMENT/ and use its relative filename instead.
    /// Recommended: transparent PNG, 600 x 180 px, dark strokes, sRGB, under 1 MB.
    /// Keep whitespace tight around the signature; the card fits without cropping.
    /// nil, missing or unreadable files use an illustrated fictional sample signature.
    var signatureImagePath: String? = nil

    // MARK: Derived
    var fullName: String { "\(firstNames) \(surname)" }
    /// Card-face class string, e.g. "1F, 6L".
    var classesDisplay: String { classes.map { "\($0.nzClass)\($0.stage)" }.joined(separator: ", ") }
    var endorsementsDisplay: String { endorsements.isEmpty ? "none" : endorsements.joined(separator: ", ") }

    /// Parses a `yyyy-MM-dd` demo date (UTC). Falls back to today on a typo.
    static func date(_ iso: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: iso) ?? Date()
    }

    /// Age by local calendar date, so the 18th birthday counts from local midnight.
    /// Invalid or future dates never grant an adult age result.
    static func age(_ dob: String, now: Date = Date(), timeZone: TimeZone = .current) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        let today = calendar.startOfDay(for: now)
        guard let birth = formatter.date(from: dob), formatter.string(from: birth) == dob,
              birth <= today else { return 0 }
        return calendar.dateComponents([.year], from: birth, to: today).year ?? 0
    }

    // ------------------------------------------------------------------------
    //  THE DEMO IDENTITY. Fictional. Edit here to change the whole app's demo.
    // ------------------------------------------------------------------------
    static let current = DemoLicenceData(
        surname: "Citizen",
        firstNames: "Jane Smith",
        dateOfBirth: "2000-09-29",
        licenceNumber: "DE123456",
        cardVersion: "141",
        issueDate: "2024-05-30",
        expiryDate: "2034-05-30",
        classes: [
            .init(iso: "B", nzClass: "1", stage: "F"),
            .init(iso: "A", nzClass: "6", stage: "L")
        ],
        endorsements: [],
        isOrganDonor: true,
        demeritPoints: 0,
        residentialAddress: "12 Sample Street, Thorndon, Wellington 6011",
        nationality: "NZ",
        issuingCountry: "NZ",
        issuingAuthority: "TEST NZ licensing authority",
        // Portrait: PNG/JPEG, ideally 600 x 800 px (3:4), upright sRGB, under 2 MB.
        // Bundled in the app: replace TEST FILES CHANGE FOR DEPLOYMENT/demo-portrait.jpg to change it.
        // This filename works on iPhone offline; no Mac path is needed.
        portraitImagePath: "demo-portrait.jpg",
        // Signature: transparent PNG preferred (JPEG also supported),
        // ideally 600 x 180 px, dark strokes, tightly cropped, under 1 MB.
        // Bundled in the app: replace TEST FILES CHANGE FOR DEPLOYMENT/demo-signature.png to change it.
        // Keep this filename; rebuild and reinstall to send the new image to iPhone.
        signatureImagePath: "demo-signature.png"
    )
}

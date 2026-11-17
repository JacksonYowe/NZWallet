# API and issuer integration guide

**Proposed design only. No production API client or government identity integration is implemented in this repository.** Keep the demo and production paths separate. Public examples below contain fictional records.

## Architecture

```text
iPhone wallet → authenticated HTTPS API / credential issuer → authoritative database
```

The app should never connect directly to a government database. Database credentials and issuer signing keys remain on server infrastructure. Device authentication unlocks local access; it does not authenticate the user to a government service.

Proposed additions (these files do not exist yet):

```text
Sources/
  Core/
    LicenceRecord.swift               # Validated display model
    VerifiedCredential.swift          # Constructed by validation, not a demo flag
    CredentialRepository.swift         # Load, renew and check status
  Services/
    AuthenticationService.swift       # Approved login/token lifecycle
    GovernmentAPIClient.swift         # HTTPS, auth and response validation
    GovernmentCredentialRepository.swift
    CredentialValidator.swift         # Signature, trust, device binding and validity
    ProtectedCredentialStorage.swift
  Configuration/
    IssuerConfiguration.swift         # Approved public endpoints/trust material
```

Inject a repository into `WalletStore` from `Sources/App/NZWalletApp.swift`. Give the store signed-out, loading, ready, stale/unavailable and error states. Production must not silently fall back to `SharedAppData.demo` or create a local credential when a request fails.

## Existing code to replace or adapt

| Location | Integration work |
| --- | --- |
| `TEST FILES CHANGE FOR DEPLOYMENT/TEST_FILE_ONLY.swift` | Keep as a test fixture. Move shared production model definitions into Core before excluding fixtures from production target membership. |
| `WalletStore.init`, `reset`, `refresh` | Replace automatic local issuance with authenticated fetching and policy-controlled caching. |
| `WalletStore.issueLicence`, `issueMDoc`, `issue` | Keep local issuer implementations in the demo target. Production receives and validates server-issued credentials. |
| `WalletStore.mdlTrustList`, `Verifier`, `Sources/Core/MDL/` | Configure authorised public issuer trust anchors and validate the agreed credential format. The custom demo Credential format is not automatically compatible with a production format. |
| `portraitJPEG`, `signaturePNG` and `DemoLicenceImages` | Replace local fixture loading with authenticated image/credential data. The current loader normalises/resizes/re-encodes local images; do not use it to alter an already-signed portrait. |
| `project.yml` | Define distinct demo/production target memberships. Exclude local issuer keys, test roots, bundled personal-image fixtures, hidden attack tools and loopback simulations from production. |

## Agree the data contract

These application endpoints are illustrative, not deployed routes or standard OpenID4VCI endpoint definitions:

| Operation | Example |
| --- | --- |
| Authorised user's display record | `GET /v1/me/licence` |
| Authenticated image retrieval | `GET /v1/me/licence/images/{portrait-or-signature}` |
| Issuance/renewal | Use the issuer-advertised credential endpoint and agreed protocol |
| Status/revocation | Use the issuer's agreed authenticated status mechanism |

Example display record:

```json
{
  "recordVersion": "42",
  "licenceNumber": "DE123456",
  "cardVersion": "141",
  "firstNames": "Jane Smith",
  "surname": "Citizen",
  "dateOfBirth": "2000-09-29",
  "issueDate": "2024-05-30",
  "expiryDate": "2034-05-30",
  "classes": [{"iso": "B", "nzClass": "1", "stage": "F"}],
  "endorsements": [],
  "status": "current",
  "portraitVersion": "7",
  "signatureVersion": "3"
}
```

Treat licence/card numbers as strings. Parse dates strictly as `yyyy-MM-dd`; do not use demo date fallbacks. Agree issuer identifiers, allowed status values, class/stage codes, image MIME/size limits and refresh semantics. Additional displayed fields such as donor state and demerit points also need authoritative mapping if retained.

A JSON display record is not a government credential. Bind supplementary display data and signature images to the same authenticated record/version as the issued credential. Prefer display fields from verified signed content. Do not let client-supplied licence numbers authorise access to another person's record.

## Credential and image flow

1. Authenticate through the chosen identity provider using its approved native-app flow; securely manage access/refresh tokens.
2. Generate/persist a device key using appropriate protected storage and prove possession to the authorised issuer.
3. Obtain a signed credential through the agreed issuance profile. [OpenID for Verifiable Credential Issuance 1.0](https://openid.net/specs/openid-4-verifiable-credential-issuance-1_0-final.html) is an integration option, not an implemented client here.
4. Validate issuer trust, signatures, requested format, device binding, dates and status. Import verified data into the wallet; never locally re-sign it as if issued by the authority.
5. Display and share the exact verified portrait data. Fetch supplementary signature images through authenticated HTTPS and verify record/version association. No runtime TEST overlay is applied to supplied images; existing TEST labels are part of the demo image pixels/fallbacks.
6. Define renewal, suspension/revocation, lost-device re-enrolment and offline freshness limits. The local age badge is not a substitute for issuer-verifiable age claims.

Protect tokens and cached identity data with appropriate Keychain/file-protection controls. Do not embed private issuer keys, client secrets or database passwords. Do not log tokens, personal fields, images or credential payloads. Preserve atomic consistency between displayed data, images and shared credentials when refreshing.

Production should show an error/unavailable state for missing or invalid records/images, not a fictional fixture. Legitimate production credentials require a separately verified production path; retain clearly labelled fixtures and demo branding for public test builds.

## Acceptance work

Obtain the issuer's API/OpenAPI specification, authentication metadata, sandbox, credential profile, public trust anchors, image contract and status policy. Review device-key persistence/software fallback, transport, reader authentication, storage and all hidden developer code.

Test per-user authorisation, record/image consistency, expired/revoked/untrusted/tampered credentials, token expiry, network loss, renewal, app switching during authentication and device recovery. Validate sharing on physical devices and against intended independent readers. The included tests do not establish standards certification, real issuer acceptance or production security.

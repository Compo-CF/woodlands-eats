import Foundation

/// v3.0: the single outbound-link affiliate layer. Every monetizable partner
/// link — OpenTable reservations, DoorDash / Uber Eats delivery — is routed
/// through `AffiliateLinks.track(_:for:)`. Until a partner's Impact.com program
/// is approved and its tracking template is filled in below, `track` returns the
/// raw URL unchanged (a true passthrough — nothing half-built, today's behavior
/// is identical). When a program goes live, uncomment ONE line in `templates`
/// and every click across the app carries attribution — no call-site edits.
///
/// Impact.com tracking-link format (what goes in `templates`): the standard
/// vanity-domain deep link, with `{DEST}` where the URL-encoded destination
/// belongs and a `subId1` tagging the traffic as app-sourced for reporting:
///
///   https://subtlefoodie.pxf.io/c/<pubId>/<campaignId>/<adId>?subId1=stier&u={DEST}
///
/// Paste the real tracking link straight from the Impact dashboard — never
/// guess the IDs. (Impact account = `subtlefoodie`; see the impact-affiliate
/// memory. OpenTable was declined once on scale — reapply via the Dispatch
/// property. DoorDash/Uber Eats programs exist but are low-value.)
enum AffiliatePartner: Hashable {
    case opentable
    case doordash
    case ubereats
}

enum AffiliateLinks {
    /// Impact.com tracking templates keyed by partner. An absent entry means
    /// "not yet approved" → passthrough. `{DEST}` is replaced with the
    /// URL-encoded destination at click time.
    private static let templates: [AffiliatePartner: String] = [
        // .opentable: "https://subtlefoodie.pxf.io/c/<pub>/<camp>/<ad>?subId1=stier&u={DEST}",
        // .doordash:  "https://subtlefoodie.pxf.io/c/<pub>/<camp>/<ad>?subId1=stier&u={DEST}",
        // .ubereats:  "https://subtlefoodie.pxf.io/c/<pub>/<camp>/<ad>?subId1=stier&u={DEST}",
    ]

    /// Route a raw partner URL through the affiliate layer. Returns the Impact
    /// tracking link when the partner has a configured template, otherwise the
    /// destination unchanged.
    ///
    /// The destination is encoded with `.alphanumerics` (not `.urlQueryAllowed`)
    /// so that `://`, `?`, `&`, and `=` inside it are all percent-encoded — i.e.
    /// the whole URL survives as a single `u=` query-param value.
    static func track(_ destination: URL, for partner: AffiliatePartner) -> URL {
        guard let template = templates[partner],
              let encoded = destination.absoluteString
                  .addingPercentEncoding(withAllowedCharacters: .alphanumerics),
              let wrapped = URL(string: template.replacingOccurrences(of: "{DEST}", with: encoded))
        else {
            return destination
        }
        return wrapped
    }
}

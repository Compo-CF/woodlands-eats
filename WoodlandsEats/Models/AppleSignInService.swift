import Foundation
import AuthenticationServices

/// v1.7 Feature B: Sign in with Apple — LAYERED on top of the existing
/// implicit-iCloud identity, not replacing it.
///
/// What this service is for:
///   - Capture the user's Apple-verified real name on first sign-in so
///     ProfileView can pre-fill `displayName` (one tap instead of typing).
///   - Hold a stable cross-device user identifier (the opaque `user` field
///     from Apple) that future features (friend sharing in v1.8) can use
///     to look up another user across devices.
///   - Surface an "Apple-verified" badge that telegraphs a real-name
///     account to other foodies.
///
/// What this service is NOT for:
///   - It does NOT replace CloudKit's `userRecordID` as the primary key
///     for Placement / VisitedList / FoodieProfile / DishPhoto records.
///     Those records keep working unchanged whether the user signs in
///     with Apple or not. SIWA is purely additive.
///
/// Apple's contract:
///   - On the FIRST sign-in for a given (App, Apple ID) pair, the
///     credential includes `fullName` and `email`. We persist `fullName`
///     because we'll never see it again.
///   - On all subsequent sign-ins, `fullName` is `nil`. We read the
///     persisted value back from UserDefaults.
///   - Apple may revoke server-side. `credentialState(forUserID:)`
///     tells us if the credential is still valid; we call this on
///     launch and sign the user out locally if it's been revoked.
@Observable
final class AppleSignInService {
    /// The opaque, stable, per-app-per-Apple-ID identifier. Persisted
    /// across launches in UserDefaults. Never displayed to the user;
    /// used internally for credential-state checks and (future) friend
    /// lookups.
    private(set) var userID: String?

    /// The user's Apple-verified real name as a formatted string
    /// ("Anthony Compofelice"). Captured on first sign-in only; Apple
    /// won't send it again. nil if the user signed in but declined to
    /// share their name (Apple lets them opt out per-sign-in).
    private(set) var fullName: String?

    /// True iff we have a persisted Apple user ID. Doesn't mean Apple
    /// still considers the credential valid — call refreshCredentialState
    /// periodically to catch server-side revocations.
    private(set) var isSignedIn: Bool = false

    private let userIDKey = "WoodlandsEats.siwa.userID"
    private let fullNameKey = "WoodlandsEats.siwa.fullName"

    init() {
        userID = UserDefaults.standard.string(forKey: userIDKey)
        fullName = UserDefaults.standard.string(forKey: fullNameKey)
        isSignedIn = userID != nil
    }

    /// Wire the SwiftUI SignInWithAppleButton's `onCompletion` to this.
    /// Persists the user ID + name (when provided) to UserDefaults and
    /// flips `isSignedIn`.
    func handleSignInResult(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
            return
        }
        userID = credential.user
        UserDefaults.standard.set(credential.user, forKey: userIDKey)

        // fullName is only populated on the FIRST sign-in for this app +
        // Apple ID combo. On subsequent sign-ins it's nil, so we hold
        // onto the persisted version. Apple's design: name is shared
        // once, the app is responsible for remembering it.
        if let nameComponents = credential.fullName {
            let formatter = PersonNameComponentsFormatter()
            formatter.style = .default
            let name = formatter.string(from: nameComponents)
            if !name.isEmpty {
                fullName = name
                UserDefaults.standard.set(name, forKey: fullNameKey)
            }
        }
        isSignedIn = true
    }

    /// Local sign-out — clears our cached identifier + name. The iOS
    /// "Sign in with Apple" link to this app still exists in the user's
    /// Apple ID settings; full revocation has to happen there.
    func signOut() {
        userID = nil
        fullName = nil
        isSignedIn = false
        UserDefaults.standard.removeObject(forKey: userIDKey)
        UserDefaults.standard.removeObject(forKey: fullNameKey)
    }

    /// Ask Apple if the stored credential is still authorized. Call on
    /// app launch and after long backgrounds. Apple can revoke server-
    /// side (user removed the app from their Apple ID's sign-in list,
    /// or didn't use the app for 6+ months on some account types) and
    /// we silently sign them out locally to keep state consistent.
    @MainActor
    func refreshCredentialState() async {
        guard let uid = userID else { return }
        let provider = ASAuthorizationAppleIDProvider()
        do {
            let state = try await provider.credentialState(forUserID: uid)
            if state != .authorized {
                signOut()
            }
        } catch {
            // Network / Apple-side transient error — leave state alone
            // and try again on the next call. Don't sign the user out
            // on transient failures (would be annoying offline).
        }
    }
}

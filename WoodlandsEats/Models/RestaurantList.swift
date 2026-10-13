import Foundation

/// v3.0: a user-made, shareable collection of restaurants ("Top 10 Tacos",
/// "Date-night S-tier"). Stored in the Firestore `lists/{id}` collection and
/// (de)serialized manually in FirebaseService (parseList / dict writes), matching
/// the rest of that service's style. `restaurantIDs` is an ordered list.
struct RestaurantList: Identifiable, Hashable {
    let id: String          // Firestore document id
    var ownerId: String     // client-asserted owner (same identity as placements)
    var title: String
    var emoji: String
    var restaurantIDs: [UUID]
    var isPublic: Bool
    var updatedAt: Date
}

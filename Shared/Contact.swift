import Foundation

/// A person in the address book, as the server gives it to a device.
struct Contact: Codable, Identifiable, Equatable {
    /// The server's id for this entry; the person's own id never leaves it.
    let id: String
    var label: String
    var position: Int
    /// A close person: a circle first. Optional: older servers leave it out.
    var close: Bool?
    /// The owner's color for them, an index into `Palette`.
    var color: Int?
    /// The person's Love ID link, as it was added: shown on the iPhone, so it
    /// can be passed on. A wrong code comes back too, so a link never tells
    /// whether its code belongs to anyone.
    var invite_url: String? = nil

    var isClose: Bool { close ?? false }
}

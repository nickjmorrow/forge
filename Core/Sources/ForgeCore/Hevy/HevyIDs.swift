import CryptoKit
import Foundation

/// Ids derived from names, so the same record created independently on two devices is one record rather than two.
public enum StableIDs {
    /// A starter-library exercise, identified by its name.
    public static func starterExercise(_ name: String) -> String { v5("starter:\(name.lowercased())") }

    private static let namespace = UUID(uuidString: "6F3D2C84-5B1A-4E7A-9C0D-4A1E8B7F2D10")!

    /// RFC 4122 version 5 (SHA-1) UUID.
    static func v5(_ name: String) -> String {
        var data = Data()
        withUnsafeBytes(of: namespace.uuid) { data.append(contentsOf: $0) }
        data.append(Data(name.utf8))
        var bytes = Array(Insecure.SHA1.hash(data: data).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        let u = bytes
        return UUID(uuid: (u[0], u[1], u[2], u[3], u[4], u[5], u[6], u[7], u[8], u[9], u[10], u[11], u[12], u[13], u[14], u[15])).uuidString
    }
}

/// Ids derived from Hevy ids, so importing the same Hevy data on two devices produces the same records rather than duplicates.
enum HevyIDs {
    static func exercise(_ hevyID: String) -> String { StableIDs.v5("exercise:\(hevyID)") }
    static func routine(_ hevyID: String) -> String { StableIDs.v5("routine:\(hevyID)") }
    static func workout(_ hevyID: String) -> String { StableIDs.v5("workout:\(hevyID)") }
}

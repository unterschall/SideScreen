import Foundation

struct DecodedPenEvent: Equatable {
    let flags: UInt8
    let x: Float
    let y: Float
    let pressure: Float
    let tiltX: Float
    let tiltY: Float
    let action: UInt8
}

enum WirePenMessage {
    /// 1 type + 1 flags + 5 floats (x,y,pressure,tiltX,tiltY) + 1 action.
    static let byteCount = 23

    /// Decodes a pen-event frame: `[type][flags][x][y][pressure][tiltX][tiltY][action]`.
    /// `data` is expected to include the leading type byte (unused here beyond
    /// the length check). Returns nil if truncated.
    static func decode(_ data: Data) -> DecodedPenEvent? {
        guard data.count >= byteCount else { return nil }
        let flags = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 1, as: UInt8.self) }
        let x = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 2, as: Float.self) }
        let y = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 6, as: Float.self) }
        let pressure = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 10, as: Float.self) }
        let tiltX = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 14, as: Float.self) }
        let tiltY = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 18, as: Float.self) }
        let action = data.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 22, as: UInt8.self) }
        return DecodedPenEvent(flags: flags, x: x, y: y, pressure: pressure, tiltX: tiltX, tiltY: tiltY, action: action)
    }
}

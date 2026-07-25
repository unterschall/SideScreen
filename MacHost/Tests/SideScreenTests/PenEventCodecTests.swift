import XCTest
@testable import SideScreen

final class PenEventCodecTests: XCTestCase {
    private func encode(
        flags: UInt8, x: Float, y: Float, pressure: Float, tiltX: Float, tiltY: Float, action: UInt8
    ) -> Data {
        var data = Data()
        data.append(12) // type: penEvent
        data.append(flags)
        withUnsafeBytes(of: x) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: y) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: pressure) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: tiltX) { data.append(contentsOf: $0) }
        withUnsafeBytes(of: tiltY) { data.append(contentsOf: $0) }
        data.append(action)
        return data
    }

    func testDecodesAllFields() throws {
        let data = encode(flags: 0x05, x: 0.25, y: 0.75, pressure: 0.9, tiltX: -0.5, tiltY: 0.5, action: 1)
        let event = try XCTUnwrap(WirePenMessage.decode(data))
        XCTAssertEqual(event.flags, 0x05)
        XCTAssertEqual(event.x, 0.25)
        XCTAssertEqual(event.y, 0.75)
        XCTAssertEqual(event.pressure, 0.9)
        XCTAssertEqual(event.tiltX, -0.5)
        XCTAssertEqual(event.tiltY, 0.5)
        XCTAssertEqual(event.action, 1)
    }

    func testEraserAndBarrelFlagsRoundTrip() throws {
        // bit0 eraser, bit1 barrel-primary, bit2 barrel-secondary
        let data = encode(flags: 0x07, x: 0, y: 0, pressure: 0, tiltX: 0, tiltY: 0, action: 0)
        let event = try XCTUnwrap(WirePenMessage.decode(data))
        XCTAssertEqual(event.flags, 0x07)
    }

    func testDecodeReturnsNilWhenTruncated() {
        var data = encode(flags: 0, x: 0, y: 0, pressure: 0, tiltX: 0, tiltY: 0, action: 0)
        data.removeLast()
        XCTAssertNil(WirePenMessage.decode(data))
    }

    func testDecodeReturnsNilForEmptyData() {
        XCTAssertNil(WirePenMessage.decode(Data()))
    }

    func testByteCountIs23() {
        XCTAssertEqual(WirePenMessage.byteCount, 23)
    }
}

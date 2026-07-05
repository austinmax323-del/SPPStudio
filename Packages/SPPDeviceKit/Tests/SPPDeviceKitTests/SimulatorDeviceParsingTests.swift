import XCTest
@testable import SPPDeviceKit

final class SimulatorDeviceParsingTests: XCTestCase {

    /// Modern Xcode simctl JSON: `isAvailable` bool, no `availability` string.
    /// This is the shape that previously produced zero devices (the "No
    /// Simulators" bug) because the parser required the obsolete key.
    func testModernJSONYieldsDevices() throws {
        let json = """
        {
          "devices": {
            "com.apple.CoreSimulator.SimRuntime.iOS-26-5": [
              {
                "udid": "F28E8EBF-413D-4363-B78C-D871EC218658",
                "name": "iPhone 17",
                "state": "Booted",
                "isAvailable": true,
                "deviceTypeIdentifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"
              },
              {
                "udid": "AAAAAAAA-0000-0000-0000-000000000001",
                "name": "iPad Air 11-inch (M4)",
                "state": "Shutdown",
                "isAvailable": true
              }
            ]
          }
        }
        """
        let devices = SimulatorDeviceProvider.parseDevices(from: Data(json.utf8))
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(devices.first?.name, "iPad Air 11-inch (M4)")   // sorted by name
        let iphone = devices.first { $0.name == "iPhone 17" }
        XCTAssertEqual(iphone?.id, "F28E8EBF-413D-4363-B78C-D871EC218658")
        XCTAssertEqual(iphone?.systemVersion, "iOS 26.5")
        XCTAssertTrue(iphone?.isSimulator ?? false)
    }

    func testSkipsUnavailableViaIsAvailableBool() throws {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
          {"udid":"U1","name":"Good","isAvailable":true},
          {"udid":"U2","name":"Broken","isAvailable":false}
        ]}}
        """
        let devices = SimulatorDeviceProvider.parseDevices(from: Data(json.utf8))
        XCTAssertEqual(devices.map(\.name), ["Good"])
    }

    func testSkipsLegacyUnavailableString() throws {
        let json = """
        {"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-16-4":[
          {"udid":"U1","name":"Old Good","availability":"(available)"},
          {"udid":"U2","name":"Old Broken","availability":"(unavailable)"}
        ]}}
        """
        let devices = SimulatorDeviceProvider.parseDevices(from: Data(json.utf8))
        XCTAssertEqual(devices.map(\.name), ["Old Good"])
    }

    func testEmptyOrGarbageIsSafe() {
        XCTAssertTrue(SimulatorDeviceProvider.parseDevices(from: Data("not json".utf8)).isEmpty)
        XCTAssertTrue(SimulatorDeviceProvider.parseDevices(from: Data(#"{"devices":{}}"#.utf8)).isEmpty)
    }
}

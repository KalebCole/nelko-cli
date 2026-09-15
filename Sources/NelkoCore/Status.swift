import Foundation
import NativeRFCOMM

public let p21Address = "FC:50:17:13:FF:8A"
public let p21RFCOMMChannel: UInt8 = 1

public enum TransportFailure: Error, Equatable, Sendable {
    case connectionConflict
    case timedOut
    case invalidMTU
    case openFailed
    case writeFailed
    case closeFailed
}

public protocol RFCOMMTransport: Sendable {
    func request(_ command: Data, timeout: TimeInterval) async throws -> Data
}

public enum MTUChunker {
    public static func chunk(_ data: Data, mtu: Int) throws -> [Data] {
        guard mtu > 0 else { throw TransportFailure.invalidMTU }
        return stride(from: 0, to: data.count, by: mtu).map { start in
            data.subdata(in: start..<min(start + mtu, data.count))
        }
    }
}

public final class NativeRFCOMMTransport: RFCOMMTransport, @unchecked Sendable {
    private let address: String
    private let channelID: UInt8

    public init(address: String = p21Address, channelID: UInt8 = p21RFCOMMChannel) {
        self.address = address
        self.channelID = channelID
    }

    public func request(_ command: Data, timeout: TimeInterval) async throws -> Data {
        try await Task.detached { [address, channelID] in
            let transport = NKRFCOMMTransport(address: address, channelID: channelID)
            do {
                return try transport.request(command, timeout: timeout)
            } catch let error as NSError {
                throw Self.map(error)
            }
        }.value
    }

    private static func map(_ error: NSError?) -> TransportFailure {
        guard let error else { return .openFailed }
        let raw = (error.userInfo["ioReturn"] as? NSNumber)?.uint32Value
        if raw == 0xe00002bc { return .connectionConflict }
        switch error.code {
        case 3: return .timedOut
        case 4: return .closeFailed
        case 5: return .invalidMTU
        case 2: return .writeFailed
        default: return .openFailed
        }
    }
}

public struct StatusResult: Codable, Equatable, Sendable {
    public let batteryPercent: Int
    public let isReady: Bool
    public init(batteryPercent: Int, isReady: Bool) { self.batteryPercent = batteryPercent; self.isReady = isReady }
}

public enum StatusFailure: Error, Equatable, Sendable {
    case transport(TransportFailure)
    case malformedBatteryResponse
    case malformedReadinessResponse

    public var code: String {
        switch self {
        case .transport(.connectionConflict): return "connection_conflict"
        case .transport(.timedOut): return "response_timeout"
        case .transport(.invalidMTU): return "invalid_mtu"
        case .transport(.openFailed): return "open_failed"
        case .transport(.writeFailed): return "write_failed"
        case .transport(.closeFailed): return "close_failed"
        case .malformedBatteryResponse: return "malformed_battery_response"
        case .malformedReadinessResponse: return "malformed_readiness_response"
        }
    }
    public var message: String {
        switch self {
        case .transport(.connectionConflict): return "RFCOMM channel is unavailable; disconnect generic Bluetooth clients and retry."
        case .transport(.timedOut): return "Timed out waiting for printer response."
        case .transport(.invalidMTU): return "RFCOMM channel reported an invalid MTU."
        case .transport(.openFailed): return "Could not open direct RFCOMM channel 1."
        case .transport(.writeFailed): return "RFCOMM write failed."
        case .transport(.closeFailed): return "RFCOMM channel close failed."
        case .malformedBatteryResponse: return "Printer returned a malformed battery response."
        case .malformedReadinessResponse: return "Printer returned a malformed readiness response."
        }
    }
}

public struct StatusOperation: Sendable {
    private let transport: any RFCOMMTransport
    private let timeout: TimeInterval
    public init(transport: any RFCOMMTransport, timeout: TimeInterval = 2) { self.transport = transport; self.timeout = timeout }
    public func run() async throws -> StatusResult {
        let battery: Data
        do { battery = try await transport.request(Data("BATTERY?\r\n".utf8), timeout: timeout) }
        catch let failure as TransportFailure { throw StatusFailure.transport(failure) }
        guard battery.count >= 12, battery.prefix(8) == Data("BATTERY ".utf8), battery[9] == 0, battery.suffix(2) == Data([13, 10]) else { throw StatusFailure.malformedBatteryResponse }
        let batteryByte = battery[8]
        let batteryPercent = Int(batteryByte >> 4) * 10 + Int(batteryByte & 0x0f)
        guard batteryByte >> 4 <= 9, batteryByte & 0x0f <= 9, batteryPercent <= 100 else { throw StatusFailure.malformedBatteryResponse }
        let readiness: Data
        do { readiness = try await transport.request(Data([0x1b, 0x21, 0x3f, 13, 10]), timeout: timeout) }
        catch let failure as TransportFailure { throw StatusFailure.transport(failure) }
        guard readiness == Data([0]) else { throw StatusFailure.malformedReadinessResponse }
        return StatusResult(batteryPercent: batteryPercent, isReady: true)
    }
}

public enum StatusCommandOutput {
    private struct ErrorDTO: Encodable { let code: String; let message: String }
    private struct SuccessDTO: Encodable { let batteryPercent: Int; let ready: Bool; let status = "ok" }
    private struct FailureDTO: Encodable { let error: ErrorDTO; let status = "error" }
    public static func json(_ result: Result<StatusResult, StatusFailure>) throws -> String {
        let payload: any Encodable
        switch result {
        case .success(let status): payload = SuccessDTO(batteryPercent: status.batteryPercent, ready: status.isReady)
        case .failure(let error): payload = FailureDTO(error: ErrorDTO(code: error.code, message: error.message))
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(AnyEncodable(payload)), as: UTF8.self)
    }
    public static func human(_ result: Result<StatusResult, StatusFailure>) -> String {
        switch result { case .success(let s): return "P21 ready: yes\nBattery: \(s.batteryPercent)%"; case .failure(let e): return "Error [\(e.code)]: \(e.message)" }
    }
}
private struct AnyEncodable: Encodable { let value: any Encodable; init(_ value: any Encodable) { self.value = value }; func encode(to encoder: Encoder) throws { try value.encode(to: encoder) } }

import Foundation
import NelkoCore

private final class FakeTransport: RFCOMMTransport, @unchecked Sendable {
    var replies: [Result<Data, TransportFailure>]
    private(set) var commands: [Data] = []
    init(_ replies: [Result<Data, TransportFailure>]) { self.replies = replies }
    func request(_ command: Data, timeout: TimeInterval) async throws -> Data {
        commands.append(command)
        return try replies.removeFirst().get()
    }
}

@main struct StatusOperationTests {
    static func main() async {
        let tests: [(String, () async throws -> Void)] = [
            ("typed status seam", happyPath),
            ("malformed response", malformedBattery),
            ("response timeout", timeout),
            ("connection conflict", conflict),
            ("MTU chunking", mtuChunking),
            ("invalid MTU", invalidMTU),
            ("stable success JSON", successJSON),
            ("stable error JSON", errorJSON),
        ]
        var failures = 0
        for (name, test) in tests {
            do { try await test(); print("PASS \(name)") }
            catch { failures += 1; fputs("FAIL \(name): \(error)\n", stderr) }
        }
        exit(failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE)
    }

    static func happyPath() async throws {
        let transport = FakeTransport([.success(Data([0x42,0x41,0x54,0x54,0x45,0x52,0x59,0x20,0x75,0,13,10])), .success(Data([0]))])
        let result = try await StatusOperation(transport: transport).run()
        try require(result == StatusResult(batteryPercent: 75, isReady: true))
        try require(transport.commands == [Data("BATTERY?\r\n".utf8), Data([0x1b,0x21,0x3f,13,10])])
    }
    static func malformedBattery() async throws {
        let transport = FakeTransport([.success(Data("BATTERY 75\r\n".utf8))])
        do { _ = try await StatusOperation(transport: transport).run(); throw TestError.failed("expected malformed response") }
        catch let error as StatusFailure { try require(error == .malformedBatteryResponse) }
    }
    static func timeout() async throws {
        let transport = FakeTransport([.failure(.timedOut)])
        do { _ = try await StatusOperation(transport: transport).run(); throw TestError.failed("expected timeout") }
        catch let error as StatusFailure { try require(error == .transport(.timedOut)) }
    }
    static func conflict() async throws {
        let transport = FakeTransport([.failure(.connectionConflict)])
        do { _ = try await StatusOperation(transport: transport).run(); throw TestError.failed("expected conflict") }
        catch let error as StatusFailure { try require(error == .transport(.connectionConflict)) }
    }
    static func mtuChunking() throws { try require(MTUChunker.chunk(Data(0..<10), mtu: 4) == [Data([0,1,2,3]),Data([4,5,6,7]),Data([8,9])]) }
    static func invalidMTU() throws { do { _ = try MTUChunker.chunk(Data([1]), mtu: 0); throw TestError.failed("expected invalid MTU") } catch let e as TransportFailure { try require(e == .invalidMTU) } }
    static func successJSON() throws { try require(StatusCommandOutput.json(.success(StatusResult(batteryPercent: 75, isReady: true))) == #"{"batteryPercent":75,"ready":true,"status":"ok"}"#) }
    static func errorJSON() throws { try require(StatusCommandOutput.json(.failure(.transport(.timedOut))) == #"{"error":{"code":"response_timeout","message":"Timed out waiting for printer response."},"status":"error"}"#) }
}
private enum TestError: Error { case failed(String) }
private func require(_ condition: @autoclosure () throws -> Bool) throws { if try !condition() { throw TestError.failed("assertion failed") } }

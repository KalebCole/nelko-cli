import Foundation
import NelkoCore

@main struct NelkoCLI {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.contains("status") else { usage(); exit(64) }
        let json = arguments.contains("--json")
        guard arguments.allSatisfy({ ["status", "--json", "--no-input"].contains($0) }) else { usage(); exit(64) }
        fputs("Checking P21 status via direct RFCOMM channel 1...\n", stderr)
        let result: Result<StatusResult, StatusFailure>
        do { result = .success(try await StatusOperation(transport: NativeRFCOMMTransport()).run()) }
        catch let error as StatusFailure { result = .failure(error) }
        catch { result = .failure(.transport(.openFailed)) }
        let output: String
        do { output = json ? try StatusCommandOutput.json(result) : StatusCommandOutput.human(result) }
        catch { fputs("Unable to encode status result.\n", stderr); exit(70) }
        print(output)
        if case .failure = result { exit(1) }
    }
    private static func usage() { print("Usage: nelko status [--json] [--no-input]") }
}

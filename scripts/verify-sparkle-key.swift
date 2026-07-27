import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("\(message)\n".utf8))
    exit(1)
}

guard CommandLine.arguments.count == 3 else {
    fail("Usage: verify-sparkle-key.swift <private-key-file> <expected-public-key>")
}

let privateKeyPath = CommandLine.arguments[1]
let expectedPublicKey = CommandLine.arguments[2]

do {
    let encodedKey = try String(contentsOfFile: privateKeyPath, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    guard let rawKey = Data(base64Encoded: encodedKey) else {
        fail("Explicit Sparkle private key is not valid base64")
    }

    let privateKey = try Curve25519.Signing.PrivateKey(rawRepresentation: rawKey)
    guard privateKey.publicKey.rawRepresentation.base64EncodedString() == expectedPublicKey else {
        fail("Explicit Sparkle private key does not match SUPublicEDKey")
    }
} catch {
    fail("Could not validate explicit Sparkle private key")
}

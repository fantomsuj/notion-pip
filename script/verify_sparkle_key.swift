#!/usr/bin/env swift

import CryptoKit
import Darwin
import Foundation

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(
        Data("usage: verify_sparkle_key.swift <expected-public-key>\n".utf8)
    )
    exit(2)
}

let privateKeyInput = FileHandle.standardInput.readDataToEndOfFile()
guard let encodedPrivateKey = String(data: privateKeyInput, encoding: .utf8)?
    .trimmingCharacters(in: .whitespacesAndNewlines),
    let privateKeyData = Data(base64Encoded: encodedPrivateKey)
else {
    FileHandle.standardError.write(
        Data("error: Sparkle private key is not valid base64\n".utf8)
    )
    exit(1)
}

do {
    let privateKey = try Curve25519.Signing.PrivateKey(
        rawRepresentation: privateKeyData
    )
    let actualPublicKey = privateKey.publicKey.rawRepresentation
        .base64EncodedString()
    guard actualPublicKey == CommandLine.arguments[1] else {
        FileHandle.standardError.write(
            Data("error: Sparkle private key does not match SUPublicEDKey\n".utf8)
        )
        exit(1)
    }
} catch {
    FileHandle.standardError.write(
        Data("error: Sparkle private key has an unsupported representation\n".utf8)
    )
    exit(1)
}

print("Sparkle signing key matches SUPublicEDKey")

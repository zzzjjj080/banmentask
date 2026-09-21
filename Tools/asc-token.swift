import Foundation
import CryptoKit

// App Store Connect API を叩くためのトークンを作る。
//
// 掲載情報（サポートURL・概要・審査メモなど）は、この API で入れられる。
// 画面から手で入れなくてよくなるので、次のアプリでも使い回す。
//
//   swiftc -O Tools-ASCToken.swift -o /tmp/asctoken
//   /tmp/asctoken <キーID> <IssuerID> <.p8のパス>
//
// 出たトークンは 20 分で切れる。切れたら作り直す。

func base64url(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

guard CommandLine.arguments.count == 4 else {
    FileHandle.standardError.write("使い方: asctoken <keyID> <issuerID> <p8のパス>\n".data(using: .utf8)!)
    exit(2)
}
let keyID = CommandLine.arguments[1]
let issuerID = CommandLine.arguments[2]
let pem = try String(contentsOfFile: CommandLine.arguments[3], encoding: .utf8)

let header = #"{"alg":"ES256","kid":"\#(keyID)","typ":"JWT"}"#
let issued = Int(Date().timeIntervalSince1970)
let payload = #"{"iss":"\#(issuerID)","iat":\#(issued),"exp":\#(issued + 1200),"aud":"appstoreconnect-v1"}"#

let signingInput = base64url(Data(header.utf8)) + "." + base64url(Data(payload.utf8))
let key = try P256.Signing.PrivateKey(pemRepresentation: pem)
let signature = try key.signature(for: Data(signingInput.utf8))
print(signingInput + "." + base64url(signature.rawRepresentation))

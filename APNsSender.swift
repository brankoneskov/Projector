//
//  APNsSender.swift
//  Projector
//
//  Push delivery for Projector Go. iOS uses direct APNs and Android uses
//  Firebase Cloud Messaging HTTP v1. Registrations are keyed by authenticated
//  person UUIDs rather than user-supplied names.
//


import Foundation
import CryptoKit
import Security

struct DeviceRegistration: Codable {
    let deviceID: UUID
    let personID: UUID
    let personName: String
    let platform: String
    let token: String
    let updatedAt: Date
}

final class APNsSender {
    static let shared = APNsSender()

    private let teamID = "MCQGCJFJP6"
    private let keyID = "56GADA269T"
    private let bundleID = "pt.loudness-films.projectorgo"

    private var keyPath: String {
        let local = DataPaths.secretFile("AuthKey_56GADA269T.p8")
        if FileManager.default.fileExists(atPath: local.path) { return local.path }
        // Read the former location during migration; new installations should
        // import the key into the local Secrets folder.
        return DataPaths.file("AuthKey_56GADA269T.p8").path
    }

    private init() {}

    // MARK: - Public API

    func sendNewBooking(title: String, date: Date, forPeopleIDs personIDs: [UUID]) {
        guard !personIDs.isEmpty else { return }
        let dateText = DateFormatter.localizedString(
            from: date,
            dateStyle: .medium,
            timeStyle: .short
        )
        sendToDevices(
            belongingTo: personIDs,
            notificationTitle: "New booking",
            body: "\(title) on \(dateText)"
        )
    }

    func sendNewMessage(from senderName: String, text: String, forPeopleIDs personIDs: [UUID]) {
        guard !personIDs.isEmpty else { return }
        sendToDevices(
            belongingTo: personIDs,
            notificationTitle: "Message from \(senderName)",
            body: text
        )
    }

    // MARK: - Device loading

    private func loadRegistrations() -> [DeviceRegistration] {
        let root = DataPaths.privateFolder("DeviceTokens")
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var registrations: [DeviceRegistration] = []
        for case let url as URL in enumerator where url.pathExtension.lowercased() == "json" {
            guard let data = try? Data(contentsOf: url),
                  let registration = try? decoder.decode(DeviceRegistration.self, from: data) else {
                continue
            }
            registrations.append(registration)
        }
        return registrations
    }

    private func sendToDevices(
        belongingTo personIDs: [UUID],
        notificationTitle: String,
        body: String
    ) {
        let wanted = Set(personIDs).intersection(activePersonIDs())
        let devices = loadRegistrations().filter { wanted.contains($0.personID) }
        guard !devices.isEmpty else {
            print("📱 No registered devices for the assigned technicians")
            return
        }

        for device in devices {
            switch device.platform {
            case "ios":
                sendAPNs(token: device.token, title: notificationTitle, body: body, sandbox: false) {
                    success in
                    if !success {
                        self.sendAPNs(
                            token: device.token,
                            title: notificationTitle,
                            body: body,
                            sandbox: true
                        ) { _ in }
                    }
                }
            case "android":
                FCMSender.shared.send(token: device.token, title: notificationTitle, body: body)
            default:
                break
            }
        }
    }

    private func activePersonIDs() -> Set<UUID> {
        struct PersonEntry: Decodable {
            let id: String
            let isActive: Bool
        }
        guard let data = try? Data(contentsOf: DataPaths.file("people_index.json")),
              let people = try? JSONDecoder().decode([PersonEntry].self, from: data) else {
            return []
        }
        return Set(people.compactMap { person in
            guard person.isActive else { return nil }
            return UUID(uuidString: person.id)
        })
    }

    // MARK: - APNs HTTP/2

    private func sendAPNs(
        token: String,
        title: String,
        body: String,
        sandbox: Bool,
        completion: @escaping (Bool) -> Void
    ) {
        guard let jwt = makeAPNsJWT() else {
            print("⚠️ Could not create APNs JWT")
            completion(false)
            return
        }

        let host = sandbox ? "api.sandbox.push.apple.com" : "api.push.apple.com"
        guard let url = URL(string: "https://\(host)/3/device/\(token)") else {
            completion(false)
            return
        }
        let payload: [String: Any] = [
            "aps": [
                "alert": ["title": title, "body": body],
                "sound": "default"
            ]
        ]
        guard let payloadData = try? JSONSerialization.data(withJSONObject: payload) else {
            completion(false)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("bearer \(jwt)", forHTTPHeaderField: "authorization")
        request.setValue(bundleID, forHTTPHeaderField: "apns-topic")
        request.setValue("alert", forHTTPHeaderField: "apns-push-type")
        request.setValue("10", forHTTPHeaderField: "apns-priority")
        request.httpBody = payloadData

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                print("✅ APNs notification sent (\(sandbox ? "sandbox" : "production"))")
                completion(true)
            } else {
                if let error { print("⚠️ APNs request failed: \(error.localizedDescription)") }
                completion(false)
            }
        }.resume()
    }

    // MARK: - APNs JWT

    private func makeAPNsJWT() -> String? {
        guard FileManager.default.fileExists(atPath: keyPath),
              let keyString = try? String(contentsOfFile: keyPath, encoding: .utf8) else {
            print("⚠️ APNs signing key is not configured")
            return nil
        }
        let pemBody = keyString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let keyData = Data(base64Encoded: pemBody) else { return nil }

        let privateKey: P256.Signing.PrivateKey
        if let parsed = try? P256.Signing.PrivateKey(derRepresentation: keyData) {
            privateKey = parsed
        } else if let parsed = try? P256.Signing.PrivateKey(x963Representation: keyData) {
            privateKey = parsed
        } else {
            return nil
        }

        let now = Int(Date().timeIntervalSince1970)
        let header = base64URL(Data("{\"alg\":\"ES256\",\"kid\":\"\(keyID)\"}".utf8))
        let claims = base64URL(Data("{\"iss\":\"\(teamID)\",\"iat\":\(now)}".utf8))
        let unsigned = "\(header).\(claims)"
        guard let signature = try? privateKey.signature(for: Data(unsigned.utf8)) else { return nil }
        return "\(unsigned).\(base64URL(signature.rawRepresentation))"
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Firebase Cloud Messaging

private final class FCMSender {
    static let shared = FCMSender()

    private struct ServiceAccount: Decodable {
        let projectID: String
        let clientEmail: String
        let privateKey: String
        let tokenURI: String?

        enum CodingKeys: String, CodingKey {
            case projectID = "project_id"
            case clientEmail = "client_email"
            case privateKey = "private_key"
            case tokenURI = "token_uri"
        }
    }

    private let lock = NSLock()
    private var cachedAccessToken: String?
    private var accessTokenExpiry = Date.distantPast

    private var serviceAccountURL: URL {
        DataPaths.secretFile("firebase-service-account.json")
    }

    private init() {}

    func send(token: String, title: String, body: String) {
        guard let account = loadServiceAccount() else {
            print("⚠️ Android push is not configured: firebase-service-account.json is missing")
            return
        }
        withAccessToken(account: account) { accessToken in
            guard let accessToken else { return }
            self.sendMessage(
                deviceToken: token,
                title: title,
                body: body,
                account: account,
                accessToken: accessToken
            )
        }
    }

    private func loadServiceAccount() -> ServiceAccount? {
        guard let data = try? Data(contentsOf: serviceAccountURL) else { return nil }
        return try? JSONDecoder().decode(ServiceAccount.self, from: data)
    }

    private func withAccessToken(
        account: ServiceAccount,
        completion: @escaping (String?) -> Void
    ) {
        lock.lock()
        if let cachedAccessToken, accessTokenExpiry > Date().addingTimeInterval(60) {
            lock.unlock()
            completion(cachedAccessToken)
            return
        }
        lock.unlock()

        guard let assertion = makeServiceAccountJWT(account) else {
            print("⚠️ Could not sign Firebase service-account JWT")
            completion(nil)
            return
        }
        let tokenURI = account.tokenURI ?? "https://oauth2.googleapis.com/token"
        guard let url = URL(string: tokenURI) else {
            completion(nil)
            return
        }
        let form = [
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": assertion
        ].map { key, value in
            "\(percentEncode(key))=\(percentEncode(value))"
        }.joined(separator: "&")

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(form.utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard error == nil,
                  let http = response as? HTTPURLResponse,
                  http.statusCode == 200,
                  let data,
                  let object = try? JSONSerialization.jsonObject(with: data),
                  let json = object as? [String: Any],
                  let accessToken = json["access_token"] as? String,
                  let expiresIn = json["expires_in"] as? NSNumber else {
                print("⚠️ Firebase OAuth token request failed")
                DispatchQueue.main.async { completion(nil) }
                return
            }
            DispatchQueue.main.async {
                self.lock.lock()
                self.cachedAccessToken = accessToken
                self.accessTokenExpiry = Date().addingTimeInterval(expiresIn.doubleValue)
                self.lock.unlock()
                completion(accessToken)
            }
        }.resume()
    }

    private func sendMessage(
        deviceToken: String,
        title: String,
        body: String,
        account: ServiceAccount,
        accessToken: String
    ) {
        guard let url = URL(string:
            "https://fcm.googleapis.com/v1/projects/\(account.projectID)/messages:send") else { return }
        let payload: [String: Any] = [
            "message": [
                "token": deviceToken,
                "notification": ["title": title, "body": body],
                "android": ["priority": "high"]
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        URLSession.shared.dataTask(with: request) { _, response, error in
            if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                print("✅ Android push notification sent")
            } else if let error {
                print("⚠️ Android push failed: \(error.localizedDescription)")
            } else {
                print("⚠️ Android push was rejected by Firebase")
            }
        }.resume()
    }

    private func makeServiceAccountJWT(_ account: ServiceAccount) -> String? {
        let now = Int(Date().timeIntervalSince1970)
        let tokenURI = account.tokenURI ?? "https://oauth2.googleapis.com/token"
        let header: [String: Any] = ["alg": "RS256", "typ": "JWT"]
        let claims: [String: Any] = [
            "iss": account.clientEmail,
            "scope": "https://www.googleapis.com/auth/firebase.messaging",
            "aud": tokenURI,
            "iat": now,
            "exp": now + 3_600
        ]
        guard let headerData = try? JSONSerialization.data(withJSONObject: header),
              let claimsData = try? JSONSerialization.data(withJSONObject: claims) else { return nil }
        let unsigned = "\(base64URL(headerData)).\(base64URL(claimsData))"
        guard let key = makeRSAKey(account.privateKey),
              SecKeyIsAlgorithmSupported(key, .sign, .rsaSignatureMessagePKCS1v15SHA256),
              let signatureData = SecKeyCreateSignature(
                  key,
                  .rsaSignatureMessagePKCS1v15SHA256,
                  Data(unsigned.utf8) as CFData,
                  nil
              ) else { return nil }
        return "\(unsigned).\(base64URL(signatureData as Data))"
    }

    private func makeRSAKey(_ pem: String) -> SecKey? {
        let body = pem
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
        guard let der = Data(base64Encoded: body) else { return nil }
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate
        ]
        if let key = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil) {
            return key
        }
        // Google service-account keys use PKCS#8. Some macOS versions expect
        // the inner PKCS#1 RSA key when importing through Security.framework.
        guard let pkcs1 = extractPrivateKeyOctets(fromPKCS8: der) else { return nil }
        return SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, nil)
    }

    private func extractPrivateKeyOctets(fromPKCS8 data: Data) -> Data? {
        var index = 0
        guard let outer = readDERElement(data, index: &index), outer.tag == 0x30 else { return nil }
        var innerIndex = outer.content.lowerBound
        guard let version = readDERElement(data, index: &innerIndex), version.tag == 0x02,
              let algorithm = readDERElement(data, index: &innerIndex), algorithm.tag == 0x30,
              let privateKey = readDERElement(data, index: &innerIndex), privateKey.tag == 0x04 else {
            return nil
        }
        return data.subdata(in: privateKey.content)
    }

    private func readDERElement(
        _ data: Data,
        index: inout Int
    ) -> (tag: UInt8, content: Range<Int>)? {
        guard index < data.count else { return nil }
        let tag = data[index]
        index += 1
        guard index < data.count else { return nil }
        let firstLengthByte = Int(data[index])
        index += 1

        let length: Int
        if firstLengthByte & 0x80 == 0 {
            length = firstLengthByte
        } else {
            let byteCount = firstLengthByte & 0x7f
            guard byteCount > 0, byteCount <= 4, index + byteCount <= data.count else { return nil }
            var accumulated = 0
            for _ in 0..<byteCount {
                accumulated = (accumulated << 8) | Int(data[index])
                index += 1
            }
            length = accumulated
        }
        guard length >= 0, index + length <= data.count else { return nil }
        let range = index..<(index + length)
        index += length
        return (tag, range)
    }

    private func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private func percentEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
    }
}


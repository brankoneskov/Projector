//
//  LicenceManager.swift
//  Projector
//
//  Manages trial period, licence activation, and validation via LemonSqueezy.
//  Licence keys and validation state are stored in the macOS Keychain.
//
//  LemonSqueezy License API — no API key required in the app.
//  The licence key itself authenticates all requests.
//  Endpoints:
//    POST https://api.lemonsqueezy.com/v1/licenses/activate
//    POST https://api.lemonsqueezy.com/v1/licenses/validate
//    POST https://api.lemonsqueezy.com/v1/licenses/deactivate
//

import Foundation
import Combine
import Security

// MARK: - Licence State

enum LicenceState: Equatable {
    case trial(daysRemaining: Int)         // within 14-day trial
    case trialExpired                      // trial over, no licence
    case licensed(expiresOn: Date?)        // valid (nil = perpetual)
    case expiryWarning(daysRemaining: Int) // annual, within 7 days of expiry
    case gracePeriod(daysRemaining: Int)   // expired but within 5-day grace
    case expired                           // no valid licence, grace over
}

// MARK: - LicenceManager

final class LicenceManager: ObservableObject {
    static let shared = LicenceManager()

    @Published private(set) var state: LicenceState = .trial(daysRemaining: 14)
    @Published private(set) var isValidating = false
    @Published private(set) var lastError: String? = nil

    // MARK: - Constants

    private let trialDays        = 14
    private let warningDays      = 7
    private let graceDays        = 5
    private let offlineGraceDays = 7
    private let revalidateAfter: TimeInterval = 86400   // 24 hours

    private let apiBase = "https://api.lemonsqueezy.com/v1/licenses"

    /// Notification posted after the server explicitly rejects a licence twice.
    /// userInfo["reason"] contains the reason string.
    static let licenceRevokedNotification = Notification.Name("projector.licence.revoked")

    // MARK: - Keychain keys

    private let kFirstLaunch   = "projector.licence.firstLaunch"
    private let kLicenceKey    = "projector.licence.key"
    private let kInstanceID    = "projector.licence.instanceID"
    private let kExpiryDate    = "projector.licence.expiry"
    private let kLastValidated = "projector.licence.lastValidated"
    private let kRemoteInvalidCount  = "projector.licence.remoteInvalidCount"
    private let kRemoteInvalidSince  = "projector.licence.remoteInvalidSince"
    private let kRemoteInvalidReason = "projector.licence.remoteInvalidReason"

    private init() {
        ensureFirstLaunchDate()
        refreshState()
    }

    // MARK: - Public API

    func checkOnLaunch() {
        refreshState()
        revalidateIfNeeded()
    }

    var isAppFunctional: Bool {
        switch state {
        case .trial, .licensed, .expiryWarning, .gracePeriod: return true
        case .trialExpired, .expired: return false
        }
    }

    var showWarningBanner: Bool {
        switch state {
        case .expiryWarning, .gracePeriod: return true
        default: return false
        }
    }

    var warningBannerMessage: String {
        switch state {
        case .expiryWarning(let days):
            return "Your Projector licence expires in \(days) day\(days == 1 ? "" : "s"). Renew to avoid interruption."
        case .gracePeriod(let days):
            return "Your Projector licence has expired. The app will stop working in \(days) day\(days == 1 ? "" : "s")."
        default: return ""
        }
    }

    // MARK: - Activation

    func activate(key: String, completion: @escaping (Result<Void, Error>) -> Void) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            completion(.failure(LicenceError.emptyKey)); return
        }
        isValidating = true
        lastError = nil

        let instanceName = Host.current().localizedName ?? "Projector Mac"

        callAPI(endpoint: "activate",
                params: ["license_key": trimmed, "instance_name": instanceName]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                if response.activated == true, let instance = response.instance {
                    self.setKeychainString(trimmed, for: self.kLicenceKey)
                    self.setKeychainString(instance.id, for: self.kInstanceID)
                    self.setKeychainDate(Date(), for: self.kLastValidated)
                    self.clearRemoteInvalidState()
                    if let expiryStr = response.licenceKey?.expiresAt {
                        if let date = ISO8601DateFormatter().date(from: expiryStr) {
                            self.setKeychainDate(date, for: self.kExpiryDate)
                        }
                    } else {
                        // No expiry = perpetual
                        self.deleteKeychain(self.kExpiryDate)
                    }
                    DispatchQueue.main.async {
                        self.isValidating = false
                        self.refreshState()
                        completion(.success(()))
                    }
                } else {
                    let msg = response.error ?? "Could not activate licence key."
                    DispatchQueue.main.async {
                        self.isValidating = false
                        self.lastError = msg
                        completion(.failure(LicenceError.invalidKey(msg)))
                    }
                }
            case .failure(let error):
                DispatchQueue.main.async {
                    self.isValidating = false
                    self.lastError = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }

    // MARK: - Deactivation

    func deactivate(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let key = keychainString(for: kLicenceKey),
              let instanceID = keychainString(for: kInstanceID) else {
            clearLicenceData()
            refreshState()
            completion(.success(()))
            return
        }
        isValidating = true
        callAPI(endpoint: "deactivate",
                params: ["license_key": key, "instance_id": instanceID]) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isValidating = false
                self.clearLicenceData()
                self.refreshState()
                completion(.success(()))
            }
        }
    }

    // MARK: - Private: State

    private func refreshState() {
        let now = Date()

        if let key = keychainString(for: kLicenceKey), !key.isEmpty {
            // A single explicit rejection may be transient. Only two consecutive
            // rejections start the grace period, and the credentials are retained
            // so a later successful validation can recover automatically.
            if remoteInvalidCount >= 2, let invalidSince = remoteInvalidSince {
                let cutoff = invalidSince.addingTimeInterval(Double(graceDays) * 86400)
                if now < cutoff {
                    let left = Int(ceil(cutoff.timeIntervalSince(now) / 86400))
                    state = .gracePeriod(daysRemaining: max(1, left))
                } else {
                    state = .expired
                }
                return
            }

            if let expiry = licenceExpiry {
                let interval = expiry.timeIntervalSince(now)
                let days = Int(ceil(interval / 86400))
                if interval > Double(warningDays) * 86400 {
                    state = .licensed(expiresOn: expiry)
                } else if interval > 0 {
                    state = .expiryWarning(daysRemaining: max(1, days))
                } else {
                    let graceCutoff = expiry.addingTimeInterval(Double(graceDays) * 86400)
                    if now < graceCutoff {
                        let left = Int(ceil(graceCutoff.timeIntervalSince(now) / 86400))
                        state = .gracePeriod(daysRemaining: max(1, left))
                    } else if let last = lastValidatedDate,
                              now.timeIntervalSince(last) < Double(offlineGraceDays) * 86400 {
                        state = .gracePeriod(daysRemaining: 1)
                    } else {
                        state = .expired
                    }
                }
            } else {
                // No expiry stored = perpetual
                state = .licensed(expiresOn: nil)
            }
            return
        }

        guard let firstLaunch = firstLaunchDate else {
            state = .trial(daysRemaining: trialDays); return
        }
        let elapsed = Int(now.timeIntervalSince(firstLaunch) / 86400)
        let remaining = trialDays - elapsed
        state = remaining > 0 ? .trial(daysRemaining: remaining) : .trialExpired
    }

    func revalidateIfNeeded() {
        guard let key = keychainString(for: kLicenceKey),
              let instanceID = keychainString(for: kInstanceID) else { return }

        if let last = lastValidatedDate,
           Date().timeIntervalSince(last) < revalidateAfter { return }

        // URLSession performs the network request off the main thread; there is
        // no need to call this MainActor-isolated manager from a global queue.
        callAPI(endpoint: "validate",
                params: ["license_key": key, "instance_id": instanceID]) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let response):
                // A successful validate response must explicitly contain `valid`.
                // Missing/unknown fields are treated as a temporary API anomaly.
                guard let isValid = response.valid else { return }

                if isValid {
                    // ✅ Valid — update expiry and last validated date
                    if let licenceKey = response.licenceKey {
                        if let expiryStr = licenceKey.expiresAt,
                           let date = ISO8601DateFormatter().date(from: expiryStr) {
                            self.setKeychainDate(date, for: self.kExpiryDate)
                        } else if licenceKey.expiresAt == nil {
                            // A licence may be changed from annual to perpetual.
                            self.deleteKeychain(self.kExpiryDate)
                        }
                    }
                    self.setKeychainDate(Date(), for: self.kLastValidated)
                    self.clearRemoteInvalidState()
                    self.lastError = nil
                    self.refreshState()

                } else {
                    // An explicit rejection is recorded, but one response never
                    // disables Projector. Two consecutive rejections start the
                    // grace period; credentials remain available for recovery.
                    let reason = response.error ?? "Your licence is no longer valid."
                    self.recordRemoteInvalidResponse(reason: reason)
                }

            case .failure:
                // Network failure — keep cached state; offline grace applies.
                break
            }
        }
    }

    // MARK: - Private: API call

    private func callAPI(endpoint: String,
                          params: [String: String],
                          completion: @escaping (Result<LSResponse, Error>) -> Void) {
        guard let url = URL(string: "\(apiBase)/\(endpoint)") else {
            completion(.failure(LicenceError.networkError)); return
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, urlResponse, error in
            // This target uses MainActor as its default isolation. LSResponse's
            // Codable conformance must therefore be used on the main actor.
            let statusCode = (urlResponse as? HTTPURLResponse)?.statusCode
            let requestFailed = error != nil
            DispatchQueue.main.async {
                if requestFailed {
                    completion(.failure(LicenceError.networkError)); return
                }
                guard let statusCode, let data else {
                    completion(.failure(LicenceError.networkError)); return
                }

                // LemonSqueezy returns JSON error bodies for 4xx responses. They
                // may decode into LSResponse with `valid == nil`, so never treat
                // them as a successful validation or a licence revocation.
                guard (200...299).contains(statusCode) else {
                    let errorResponse = try? JSONDecoder().decode(LSResponse.self, from: data)
                    let message = errorResponse?.error
                        ?? "Licence server returned HTTP \(statusCode)."
                    completion(.failure(LicenceError.serverError(message)))
                    return
                }

                do {
                    let response = try JSONDecoder().decode(LSResponse.self, from: data)
                    completion(.success(response))
                } catch {
                    completion(.failure(LicenceError.networkError))
                }
            }
        }.resume()
    }

    // MARK: - Private: Stored values

    private var licenceExpiry: Date? { keychainDate(for: kExpiryDate) }
    private var lastValidatedDate: Date? { keychainDate(for: kLastValidated) }
    private var remoteInvalidSince: Date? { keychainDate(for: kRemoteInvalidSince) }
    private var remoteInvalidCount: Int {
        Int(keychainString(for: kRemoteInvalidCount) ?? "0") ?? 0
    }

    /// Records an explicit `valid: false` response. The first response is silent
    /// and non-blocking. The second consecutive response starts the grace period.
    private func recordRemoteInvalidResponse(reason: String) {
        let count = remoteInvalidCount + 1
        setKeychainString(String(count), for: kRemoteInvalidCount)
        setKeychainString(reason, for: kRemoteInvalidReason)

        guard count >= 2 else { return }
        if remoteInvalidSince == nil {
            setKeychainDate(Date(), for: kRemoteInvalidSince)
        }

        DispatchQueue.main.async {
            self.lastError = reason
            self.refreshState()
            NotificationCenter.default.post(
                name: LicenceManager.licenceRevokedNotification,
                object: nil,
                userInfo: ["reason": reason]
            )
        }
    }

    private func clearRemoteInvalidState() {
        deleteKeychain(kRemoteInvalidCount)
        deleteKeychain(kRemoteInvalidSince)
        deleteKeychain(kRemoteInvalidReason)
    }

    private var firstLaunchDate: Date? {
        UserDefaults.standard.object(forKey: kFirstLaunch) as? Date
    }
    private func ensureFirstLaunchDate() {
        if UserDefaults.standard.object(forKey: kFirstLaunch) == nil {
            UserDefaults.standard.set(Date(), forKey: kFirstLaunch)
        }
    }

    private func clearLicenceData() {
        deleteKeychain(kLicenceKey)
        deleteKeychain(kInstanceID)
        deleteKeychain(kExpiryDate)
        deleteKeychain(kLastValidated)
        clearRemoteInvalidState()
    }

    // MARK: - Keychain

    private func keychainString(for key: String) -> String? {
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                   kSecAttrAccount: key,
                                   kSecReturnData: true,
                                   kSecMatchLimit: kSecMatchLimitOne]
        var result: AnyObject?
        SecItemCopyMatching(q as CFDictionary, &result)
        guard let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func setKeychainString(_ value: String, for key: String) {
        deleteKeychain(key)
        let q: [CFString: Any] = [kSecClass: kSecClassGenericPassword,
                                   kSecAttrAccount: key,
                                   kSecValueData: Data(value.utf8)]
        SecItemAdd(q as CFDictionary, nil)
    }

    private func keychainDate(for key: String) -> Date? {
        guard let s = keychainString(for: key) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    private func setKeychainDate(_ date: Date, for key: String) {
        setKeychainString(ISO8601DateFormatter().string(from: date), for: key)
    }

    private func deleteKeychain(_ key: String) {
        SecItemDelete([kSecClass: kSecClassGenericPassword,
                       kSecAttrAccount: key] as CFDictionary)
    }
}

// MARK: - LemonSqueezy API response models

private struct LSResponse: Codable {
    let activated: Bool?   // activate endpoint
    let valid: Bool?       // validate endpoint
    let error: String?
    let licenceKey: LSLicenceKey?
    let instance: LSInstance?

    enum CodingKeys: String, CodingKey {
        case activated, valid, error
        case licenceKey = "license_key"
        case instance
    }
}

private struct LSLicenceKey: Codable {
    let status: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case status
        case expiresAt = "expires_at"
    }
}

private struct LSInstance: Codable {
    let id: String
    let name: String?
}

// MARK: - Errors

enum LicenceError: LocalizedError {
    case emptyKey
    case invalidKey(String)
    case networkError
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .emptyKey:          return "Please enter a licence key."
        case .invalidKey(let m): return m
        case .networkError:      return "Could not reach the licence server. Please check your internet connection."
        case .serverError(let m): return m
        }
    }
}


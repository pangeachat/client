//
//  NotificationService.swift
//  Notification Extension
//
//  Created by Christian Pauly on 26.08.25.
//

import UserNotifications
import os

/// Shared with the app through the App Group container. Both targets already
/// declare `group.com.talktolearn.chat`, so no new entitlement is needed.
private let appGroupId = "group.com.talktolearn.chat"
private let sessionFileName = "nse_session.json"

private let log = OSLog(subsystem: "chat.pangea.nse", category: "avatar")

/// The subset of the app's session the extension needs to fetch authenticated
/// media. Written by `AppDelegate` on every client init.
private struct SharedSession: Decodable {
    let accessToken: String
    let homeserver: String
    /// Mirrors `AppConfig.allowedImageHosts`; empty means allow nothing.
    let allowedImageHosts: [String]

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case homeserver
        case allowedImageHosts = "allowed_image_hosts"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        accessToken = try c.decode(String.self, forKey: .accessToken)
        homeserver = try c.decode(String.self, forKey: .homeserver)
        allowedImageHosts = try c.decodeIfPresent([String].self, forKey: .allowedImageHosts) ?? []
    }

    static func load() -> SharedSession? {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            os_log("no app group container", log: log, type: .error)
            return nil
        }
        let url = container.appendingPathComponent(sessionFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SharedSession.self, from: data)
    }
}

/// Resolves a room or sender avatar to image bytes using the app's access token.
///
/// The push payload carries `room_id` and `sender` (Sygnal puts both in the FCM
/// data dict) but no avatar URL, so the mxc has to be looked up first.
private struct AvatarLoader {
    let session: SharedSession

    func load(roomId: String?, sender: String?) async -> Data? {
        var mxc: String?
        if let roomId {
            mxc = await roomAvatar(roomId: roomId)
        }

        // A DM has no m.room.avatar state (404), and an invite arrives before
        // the user has joined (403). Either way the other party's own avatar is
        // the sensible stand-in.
        if mxc == nil {
            guard let sender else {
                os_log("no sender in payload, nothing to fall back to",
                       log: log, type: .default)
                return nil
            }
            os_log("no room avatar, falling back to sender %{public}@",
                   log: log, type: .default, sender)
            mxc = await senderAvatar(userId: sender)
        }

        guard let mxc else {
            os_log("no avatar resolved for room or sender",
                   log: log, type: .default)
            return nil
        }
        if let media = Self.parseMxc(mxc) {
            return await thumbnail(server: media.server, mediaId: media.id)
        }
        return await allowListedImage(mxc)
    }

    private func roomAvatar(roomId: String) async -> String? {
        guard let url = url("/_matrix/client/v3/rooms/\(Self.encode(roomId))/state/m.room.avatar"),
              let data = await get(url) else { return nil }
        let json = try? JSONSerialization.jsonObject(with: data)
        return (json as? [String: Any])?["url"] as? String
    }

    private func senderAvatar(userId: String) async -> String? {
        guard let url = url("/_matrix/client/v3/profile/\(Self.encode(userId))/avatar_url"),
              let data = await get(url) else { return nil }
        let json = try? JSONSerialization.jsonObject(with: data)
        let avatarUrl = (json as? [String: Any])?["avatar_url"] as? String
        if avatarUrl == nil {
            os_log("sender profile has no avatar_url", log: log, type: .default)
        }
        return avatarUrl
    }

    private func thumbnail(server: String, mediaId: String) async -> Data? {
        guard let url = url(
            "/_matrix/client/v1/media/thumbnail/\(Self.encode(server))/\(Self.encode(mediaId))"
                + "?width=200&height=200&method=crop"
        ) else { return nil }
        return await get(url)
    }

    /// Not every avatar is an mxc upload: courses and some profiles carry a plain
    /// https URL on our asset or CDN hosts (#8550). Those need no Matrix auth --
    /// and must never be sent it. The allow-list includes third parties such as
    /// img.youtube.com, so attaching the access token here would hand a user's
    /// credential to another company.
    private func allowListedImage(_ urlString: String) async -> Data? {
        guard let url = URL(string: urlString),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              let host = url.host else {
            os_log("avatar is neither mxc nor http", log: log, type: .default)
            return nil
        }
        guard session.allowedImageHosts.contains(host) else {
            os_log("avatar host not allow-listed: %{public}@",
                   log: log, type: .default, host)
            return nil
        }
        return await get(url, authenticated: false)
    }

    /// Ids are percent-encoded to alphanumerics, so the joined string is always
    /// a valid URL and needs no further escaping.
    private func url(_ path: String) -> URL? {
        var base = session.homeserver
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }

    /// Authenticated media requires the bearer token; an unauthenticated fetch
    /// 403s, which is the whole reason the extension exists.
    private func get(_ url: URL, authenticated: Bool = true) async -> Data? {
        var request = URLRequest(url: url)
        if authenticated {
            request.setValue("Bearer \(session.accessToken)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let status = (response as? HTTPURLResponse)?.statusCode else { return nil }
            guard status == 200 else {
                os_log("GET %{public}@ -> %{public}d", log: log, type: .default, url.path, status)
                return nil
            }
            return data
        } catch {
            os_log("GET %{public}@ failed", log: log, type: .error, url.path)
            return nil
        }
    }

    private static func parseMxc(_ mxc: String) -> (server: String, id: String)? {
        guard mxc.hasPrefix("mxc://") else { return nil }
        let parts = mxc.dropFirst("mxc://".count).split(separator: "/", maxSplits: 1)
        guard parts.count == 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }

    /// Room and user ids carry `!`, `@` and `:`. Over-encoding is always safe here.
    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? value
    }
}

class NotificationService: UNNotificationServiceExtension {
    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    private var work: Task<Void, Never>?
    private let lock = NSLock()

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        let content = request.content.mutableCopy() as? UNMutableNotificationContent
        bestAttemptContent = content

        guard let content else {
            deliver(request.content)
            return
        }

        // Groups a room's notifications together; free, and independent of the avatar.
        if let roomId = content.userInfo["room_id"] as? String {
            content.threadIdentifier = roomId
        }

        guard let session = SharedSession.load() else {
            os_log("no shared session, delivering unchanged", log: log, type: .default)
            deliver(content)
            return
        }

        let roomId = content.userInfo["room_id"] as? String
        let sender = content.userInfo["sender"] as? String

        work = Task {
            if let data = await AvatarLoader(session: session).load(roomId: roomId, sender: sender) {
                Self.attach(data, to: content)
            }
            deliver(content)
        }
    }

    override func serviceExtensionTimeWillExpire() {
        work?.cancel()
        if let bestAttemptContent {
            deliver(bestAttemptContent)
        }
    }

    /// iOS kills the extension on a second call, and the timeout can race the
    /// fetch, so the handler is consumed exactly once.
    private func deliver(_ content: UNNotificationContent) {
        lock.lock()
        let handler = contentHandler
        contentHandler = nil
        lock.unlock()
        handler?(content)
    }

    /// The attachment is the trailing thumbnail. iOS *moves* the file into its
    /// own store, so the name must be unique per notification.
    private static func attach(_ data: Data, to content: UNMutableNotificationContent) {
        guard let ext = fileExtension(for: data) else {
            os_log("unrecognised image format, skipping attachment", log: log, type: .default)
            return
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("avatar-\(UUID().uuidString).\(ext)")
        do {
            try data.write(to: url)
            content.attachments = [try UNNotificationAttachment(identifier: "avatar", url: url, options: nil)]
            os_log("attached avatar (%{public}d bytes)", log: log, type: .default, data.count)
        } catch {
            // A rejected attachment would drop the whole notification, so the
            // banner goes out without it instead.
            os_log("attachment failed", log: log, type: .error)
        }
    }

    private static func fileExtension(for data: Data) -> String? {
        let bytes = [UInt8](data.prefix(4))
        if bytes.starts(with: [0xFF, 0xD8]) { return "jpg" }
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return "png" }
        return nil
    }
}

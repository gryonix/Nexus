import Foundation

public protocol TVServerReceiving: Sendable {
    func receive(_ items: [TVSentServer]) throws
}

public struct TVLinkInbox: Sendable {
    private let servers: TVServerReceiving
    private let phones: TVPhoneStore

    public init(servers: TVServerReceiving, phones: TVPhoneStore) {
        self.servers = servers
        self.phones = phones
    }

    public func handle(_ request: TVMessage, from phoneID: String, now: Date = Date()) -> TVMessage {
        guard var phone = phones.record(phoneID) else { return TVMessage(t: .error, code: "unknown-phone") }
        phone.lastSeen = now
        if let licence = request.licence {
            phone.licence = licence
            phone.licenceAt = now
        }
        if request.t == .unpair {
            phones.remove(phoneID)
            return TVMessage(t: .ok)
        }
        defer { try? phones.save(phone) }

        switch request.t {
        case .list:
            return TVMessage(t: .servers, items: phone.received)
        case .put:
            let items = request.items ?? []
            do {
                try servers.receive(items)
            } catch TVLinkStoreError.unusable(let id) {
                return TVMessage(t: .error, items: [TVSentServer(id: id, name: "", transfer: nil)], code: "unusable")
            } catch {
                return TVMessage(t: .error, code: "storage")
            }
            let sent = Set(items.map(\.id))
            phone.received = phone.received.filter { !sent.contains($0.id) } + items.map(\.withoutTransfer)
            return TVMessage(t: .servers, items: phone.received)
        case .licence, .unpair:
            return TVMessage(t: .ok)
        case .paired, .servers, .ok, .error:
            return TVMessage(t: .error, code: "unexpected")
        }
    }

    /// Removes a phone from the TV's own settings
    public func forget(_ phoneID: String) {
        phones.remove(phoneID)
    }
}

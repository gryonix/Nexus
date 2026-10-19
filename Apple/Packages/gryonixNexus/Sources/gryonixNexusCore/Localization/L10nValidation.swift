import ServiceCatalog

/// Compiled-in translation tables for `ValidationError` messages
enum L10nValidation {
    static func invalidDomain(_ l: AppLanguage, value: String) -> String {
        l.pick([
            .en: "Invalid domain: \"\(value)\". Expected a format like example.com.",
            .de: "Ungültige Domain: „\(value)“. Erwartet wird ein Format wie example.com.",
            .fr: "Domaine invalide : « \(value) ». Format attendu : example.com.",
            .es: "Dominio no válido: «\(value)». Se espera un formato como example.com.",
            .ru: "Некорректный домен: «\(value)». Ожидается формат вида example.com.",
            .uk: "Некоректний домен: «\(value)». Очікується формат на кшталт example.com.",
            .it: "Dominio non valido: \"\(value)\". È atteso un formato come example.com.",
            .ja: "ドメインが正しくありません: 「\(value)」。example.com のような形式が必要です。",
            .zh: "域名无效：“\(value)”。应为类似 example.com 的格式。"
        ])
    }

    static func invalidHostname(_ l: AppLanguage, value: String) -> String {
        l.pick([
            .en: "Invalid hostname: \"\(value)\". Expected a format like mail.example.com.",
            .de: "Ungültiger Hostname: „\(value)“. Erwartet wird ein Format wie mail.example.com.",
            .fr: "Nom d'hôte invalide : « \(value) ». Format attendu : mail.example.com.",
            .es: "Nombre de host no válido: «\(value)». Se espera un formato como mail.example.com.",
            .ru: "Некорректное имя хоста: «\(value)». Ожидается формат вида mail.example.com.",
            .uk: "Некоректне ім'я хоста: «\(value)». Очікується формат на кшталт mail.example.com.",
            .it: "Nome host non valido: \"\(value)\". È atteso un formato come mail.example.com.",
            .ja: "ホスト名が正しくありません: 「\(value)」。mail.example.com のような形式が必要です。",
            .zh: "主机名无效：“\(value)”。应为类似 mail.example.com 的格式。"
        ])
    }

    static func invalidAddress(_ l: AppLanguage, value: String) -> String {
        l.pick([
            .en: "Invalid IP address: \"\(value)\".",
            .de: "Ungültige IP-Adresse: „\(value)“.",
            .fr: "Adresse IP invalide : « \(value) ».",
            .es: "Dirección IP no válida: «\(value)».",
            .ru: "Некорректный IP-адрес: «\(value)».",
            .uk: "Некоректна IP-адреса: «\(value)».",
            .it: "Indirizzo IP non valido: \"\(value)\".",
            .ja: "IP アドレスが正しくありません: 「\(value)」。",
            .zh: "IP 地址无效：“\(value)”。"
        ])
    }

    static func missingPublicIP(_ l: AppLanguage, role: String) -> String {
        l.pick([
            .en: "No public IP address specified for node \"\(role)\".",
            .de: "Für den Knoten „\(role)“ ist keine öffentliche IP-Adresse angegeben.",
            .fr: "Aucune adresse IP publique indiquée pour le nœud « \(role) ».",
            .es: "No se ha indicado una dirección IP pública para el nodo «\(role)».",
            .ru: "Для узла «\(role)» не указан публичный IP-адрес.",
            .uk: "Для вузла «\(role)» не вказано публічну IP-адресу.",
            .it: "Nessun indirizzo IP pubblico specificato per il nodo \"\(role)\".",
            .ja: "ノード「\(role)」のパブリック IP アドレスが指定されていません。",
            .zh: "未为节点“\(role)”指定公网 IP 地址。"
        ])
    }

    static func missingVPNAddress(_ l: AppLanguage, role: String) -> String {
        l.pick([
            .en: "No WireGuard-internal address specified for node \"\(role)\".",
            .de: "Für den Knoten „\(role)“ ist keine Adresse innerhalb von WireGuard angegeben.",
            .fr: "Aucune adresse interne WireGuard indiquée pour le nœud « \(role) ».",
            .es: "No se ha indicado una dirección interna de WireGuard para el nodo «\(role)».",
            .ru: "Для узла «\(role)» не указан адрес внутри WireGuard.",
            .uk: "Для вузла «\(role)» не вказано адресу всередині WireGuard.",
            .it: "Nessun indirizzo interno a WireGuard specificato per il nodo \"\(role)\".",
            .ja: "ノード「\(role)」の WireGuard 内アドレスが指定されていません。",
            .zh: "未为节点“\(role)”指定 WireGuard 内部地址。"
        ])
    }
}

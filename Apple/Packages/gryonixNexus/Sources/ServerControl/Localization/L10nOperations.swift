import ServiceCatalog

/// Compiled-in translations for ServiceOperations error messages
public enum L10nOperations {
    public static func restartNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support restart",
            .de: "Dienst \(service) unterstützt keinen Neustart",
            .fr: "le service \(service) ne prend pas en charge le redémarrage",
            .es: "el servicio \(service) no admite el reinicio",
            .ru: "сервис \(service) не поддерживает перезапуск",
            .uk: "сервіс \(service) не підтримує перезапуск",
            .it: "il servizio \(service) non supporta il riavvio",
            .ja: "サービス \(service) は再起動をサポートしていません",
            .zh: "服务 \(service) 不支持重启"
        ])
    }

    public static func startNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support being started",
            .de: "Dienst \(service) unterstützt kein Starten",
            .fr: "le service \(service) ne prend pas en charge le démarrage",
            .es: "el servicio \(service) no admite el inicio",
            .ru: "сервис \(service) не поддерживает запуск",
            .uk: "сервіс \(service) не підтримує запуск",
            .it: "il servizio \(service) non supporta l’avvio",
            .ja: "サービス \(service) は起動をサポートしていません",
            .zh: "服务 \(service) 不支持启动"
        ])
    }

    public static func stopNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support being stopped",
            .de: "Dienst \(service) unterstützt kein Stoppen",
            .fr: "le service \(service) ne prend pas en charge l’arrêt",
            .es: "el servicio \(service) no admite la detención",
            .ru: "сервис \(service) не поддерживает остановку",
            .uk: "сервіс \(service) не підтримує зупинку",
            .it: "il servizio \(service) non supporta l’arresto",
            .ja: "サービス \(service) は停止をサポートしていません",
            .zh: "服务 \(service) 不支持停止"
        ])
    }

    public static func logsNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not expose a log to read",
            .de: "Dienst \(service) stellt kein lesbares Protokoll bereit",
            .fr: "le service \(service) n’expose aucun journal à lire",
            .es: "el servicio \(service) no expone un registro que se pueda leer",
            .ru: "сервис \(service) не отдаёт лог для чтения",
            .uk: "сервіс \(service) не віддає лог для читання",
            .it: "il servizio \(service) non espone un registro da leggere",
            .ja: "サービス \(service) は読み取れるログを提供していません",
            .zh: "服务 \(service) 未提供可读取的日志"
        ])
    }

    public static func restoreNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) cannot be restored from a backup",
            .de: "Dienst \(service) kann nicht aus einem Backup wiederhergestellt werden",
            .fr: "le service \(service) ne peut pas être restauré à partir d’une sauvegarde",
            .es: "el servicio \(service) no se puede restaurar desde una copia de seguridad",
            .ru: "сервис \(service) нельзя восстановить из резервной копии",
            .uk: "сервіс \(service) не можна відновити з резервної копії",
            .it: "il servizio \(service) non può essere ripristinato da un backup",
            .ja: "サービス \(service) はバックアップから復元できません",
            .zh: "服务 \(service) 无法从备份恢复"
        ])
    }

    public static func restoreNeedsPassphrase(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "the \(service) backup is encrypted — its passphrase is required",
            .de: "das \(service)-Backup ist verschlüsselt — die Passphrase wird benötigt",
            .fr: "la sauvegarde \(service) est chiffrée — sa phrase secrète est requise",
            .es: "la copia de \(service) está cifrada: se necesita su frase de contraseña",
            .ru: "резервная копия \(service) зашифрована — нужна её парольная фраза",
            .uk: "резервна копія \(service) зашифрована — потрібна її парольна фраза",
            .it: "il backup di \(service) è cifrato: serve la sua passphrase",
            .ja: "\(service) のバックアップは暗号化されています。パスフレーズが必要です",
            .zh: "\(service) 备份已加密 — 需要其密码短语"
        ])
    }

    public static func restoreBadPath(_ l: AppLanguage, path: String) -> String {
        l.pick([
            .en: "\(path) is not inside this service's backup directory",
            .de: "\(path) liegt nicht im Backup-Verzeichnis dieses Dienstes",
            .fr: "\(path) ne se trouve pas dans le répertoire de sauvegarde de ce service",
            .es: "\(path) no está dentro del directorio de copias de este servicio",
            .ru: "\(path) находится вне каталога резервных копий этого сервиса",
            .uk: "\(path) розташовано поза каталогом резервних копій цього сервісу",
            .it: "\(path) non si trova nella cartella di backup di questo servizio",
            .ja: "\(path) はこのサービスのバックアップディレクトリ内にありません",
            .zh: "\(path) 不在此服务的备份目录中"
        ])
    }

    public static func updateNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support update",
            .de: "Dienst \(service) unterstützt keine Aktualisierung",
            .fr: "le service \(service) ne prend pas en charge la mise à jour",
            .es: "el servicio \(service) no admite la actualización",
            .ru: "сервис \(service) не поддерживает обновление",
            .uk: "сервіс \(service) не підтримує оновлення",
            .it: "il servizio \(service) non supporta l'aggiornamento",
            .ja: "サービス \(service) は更新をサポートしていません",
            .zh: "服务 \(service) 不支持更新"
        ])
    }

    public static func backupKindNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support this kind of backup",
            .de: "Dienst \(service) unterstützt diese Art von Backup nicht",
            .fr: "le service \(service) ne prend pas en charge ce type de sauvegarde",
            .es: "el servicio \(service) no admite este tipo de copia de seguridad",
            .ru: "сервис \(service) не поддерживает такой бэкап",
            .uk: "сервіс \(service) не підтримує такий бекап",
            .it: "il servizio \(service) non supporta questo tipo di backup",
            .ja: "サービス \(service) はこの種類のバックアップをサポートしていません",
            .zh: "服务 \(service) 不支持此类备份"
        ])
    }

    public static func mailboxInvalidAddress(_ l: AppLanguage, address: String) -> String {
        l.pick([
            .en: "\(address) is not a usable mailbox address: one name, one domain, latin letters, digits and . _ + - only",
            .de: "\(address) ist keine verwendbare Postfachadresse: ein Name, eine Domain, nur lateinische Buchstaben, Ziffern und . _ + -",
            .fr: "\(address) n’est pas une adresse de boîte utilisable : un nom, un domaine, uniquement lettres latines, chiffres et . _ + -",
            .es: "\(address) no es una dirección de buzón utilizable: un nombre, un dominio, solo letras latinas, dígitos y . _ + -",
            .ru: "\(address) — недопустимый адрес ящика: одно имя, один домен, только латинские буквы, цифры и . _ + -",
            .uk: "\(address) — неприпустима адреса скриньки: одне ім’я, один домен, лише латинські літери, цифри та . _ + -",
            .it: "\(address) non è un indirizzo di casella utilizzabile: un nome, un dominio, solo lettere latine, cifre e . _ + -",
            .ja: "\(address) は使用できないメールボックスアドレスです。名前とドメインは各1つ、使えるのはラテン文字・数字と . _ + - のみです",
            .zh: "\(address) 不是可用的邮箱地址：一个名称、一个域名，仅限拉丁字母、数字和 . _ + -"
        ])
    }

    public static func mailboxPasswordEmpty(_ l: AppLanguage) -> String {
        l.pick([
            .en: "a mailbox password is required",
            .de: "ein Postfach-Passwort wird benötigt",
            .fr: "un mot de passe de boîte est requis",
            .es: "se necesita una contraseña del buzón",
            .ru: "нужен пароль для ящика",
            .uk: "потрібен пароль для скриньки",
            .it: "serve una password della casella",
            .ja: "メールボックスのパスワードが必要です",
            .zh: "需要邮箱密码"
        ])
    }

    public static func mailboxesNotAvailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "this server has no Docker Mailserver installed",
            .de: "auf diesem Server ist kein Docker Mailserver installiert",
            .fr: "aucun Docker Mailserver n’est installé sur ce serveur",
            .es: "este servidor no tiene Docker Mailserver instalado",
            .ru: "на этом сервере не установлен Docker Mailserver",
            .uk: "на цьому сервері не встановлено Docker Mailserver",
            .it: "su questo server non è installato Docker Mailserver",
            .ja: "このサーバーには Docker Mailserver がインストールされていません",
            .zh: "此服务器未安装 Docker Mailserver"
        ])
    }

    public static func encryptedBackupNotSupported(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "service \(service) does not support encrypted backup",
            .de: "Dienst \(service) unterstützt kein verschlüsseltes Backup",
            .fr: "le service \(service) ne prend pas en charge la sauvegarde chiffrée",
            .es: "el servicio \(service) no admite la copia de seguridad cifrada",
            .ru: "сервис \(service) не поддерживает шифрованный бэкап",
            .uk: "сервіс \(service) не підтримує шифрований бекап",
            .it: "il servizio \(service) non supporta il backup cifrato",
            .ja: "サービス \(service) は暗号化バックアップをサポートしていません",
            .zh: "服务 \(service) 不支持加密备份"
        ])
    }
}

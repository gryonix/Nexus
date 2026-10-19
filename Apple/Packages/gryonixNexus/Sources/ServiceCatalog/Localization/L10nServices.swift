public enum L10nServices {
    /// Suffix for "<ServiceName>: <starting>" log lines
    public static func serviceStarting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "starting",
            .de: "Start",
            .fr: "démarrage",
            .es: "inicio",
            .ru: "запуск",
            .uk: "запуск",
            .it: "avvio",
            .ja: "起動",
            .zh: "启动"
        ])
    }

    // MARK: - Mailcow

    public static func mailcowInstalling(_ l: AppLanguage, path: String) -> String {
        l.pick([
            .en: "Mailcow: installing into \(path)",
            .de: "Mailcow: Installation in \(path)",
            .fr: "Mailcow : installation dans \(path)",
            .es: "Mailcow: instalación en \(path)",
            .ru: "Mailcow: установка в \(path)",
            .uk: "Mailcow: встановлення у \(path)",
            .it: "Mailcow: installazione in \(path)",
            .ja: "Mailcow: \(path) にインストール",
            .zh: "Mailcow: 安装到 \(path)"
        ])
    }

    public static func mailcowRecreatingForNewHostname(_ l: AppLanguage, hostname: String) -> String {
        l.pick([
            .en: "Mailcow: the domain changed — installing again for \(hostname) (existing mail data is removed)",
            .de: "Mailcow: Domain geändert — Neuinstallation für \(hostname) (vorhandene Maildaten werden entfernt)",
            .fr: "Mailcow : domaine modifié — réinstallation pour \(hostname) (les données de messagerie existantes sont supprimées)",
            .es: "Mailcow: el dominio cambió — se instala de nuevo para \(hostname) (se eliminan los datos de correo existentes)",
            .ru: "Mailcow: домен изменился — устанавливаем заново для \(hostname) (существующие данные почты удаляются)",
            .uk: "Mailcow: домен змінився — встановлюємо наново для \(hostname) (наявні дані пошти видаляються)",
            .it: "Mailcow: il dominio è cambiato — nuova installazione per \(hostname) (i dati di posta esistenti vengono rimossi)",
            .ja: "Mailcow: ドメインが変更されました — \(hostname) 用に再インストールします（既存のメールデータは削除されます）",
            .zh: "Mailcow：域名已更改 — 为 \(hostname) 重新安装（现有邮件数据将被删除）"
        ])
    }

    public static func amneziaPanelWithoutPassword(_ l: AppLanguage) -> String {
        l.pick([
            .en: "AmneziaWG: could not hash a panel password — its built-in panel stays open on localhost only. The VPN itself works; manage clients at vpn.<domain>.",
            .de: "AmneziaWG: Das Panel-Passwort konnte nicht gehasht werden — sein eingebautes Panel bleibt nur auf localhost offen. Das VPN funktioniert; Clients verwalten Sie unter vpn.<domain>.",
            .fr: "AmneziaWG : impossible de hacher un mot de passe pour le panneau — son panneau intégré reste ouvert sur localhost uniquement. Le VPN fonctionne ; gérez les clients sur vpn.<domain>.",
            .es: "AmneziaWG: no se pudo cifrar una contraseña para el panel; su panel integrado queda abierto solo en localhost. La VPN funciona; gestiona los clientes en vpn.<domain>.",
            .ru: "AmneziaWG: не удалось захешировать пароль панели — его встроенная панель остаётся без пароля, но только на localhost. Сам VPN работает; клиентами управляйте на vpn.<domain>.",
            .uk: "AmneziaWG: не вдалося захешувати пароль панелі — його вбудована панель лишається без пароля, але лише на localhost. Сам VPN працює; клієнтами керуйте на vpn.<domain>.",
            .it: "AmneziaWG: impossibile calcolare l'hash della password del pannello — il suo pannello integrato resta aperto solo su localhost. La VPN funziona; gestisci i client su vpn.<domain>.",
            .ja: "AmneziaWG: パネル用パスワードのハッシュ化に失敗しました。内蔵パネルは localhost 上でのみパスワードなしになります。VPN 自体は動作します。クライアントは vpn.<domain> で管理してください。",
            .zh: "AmneziaWG：无法为面板生成密码哈希 — 其内置面板将仅在 localhost 上无密码开放。VPN 本身可正常工作；请在 vpn.<domain> 管理客户端。"
        ])
    }

    /// Printed under the default credentials in the report
    public static func mailcowDefaultPasswordNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "This is mailcow's standard password — change it after the first sign-in (System → Administrator).",
            .de: "Dies ist das Standardpasswort von mailcow — ändern Sie es nach der ersten Anmeldung (System → Administrator).",
            .fr: "C'est le mot de passe standard de mailcow — changez-le après la première connexion (Système → Administrateur).",
            .es: "Es la contraseña estándar de mailcow: cámbiela tras el primer inicio de sesión (Sistema → Administrador).",
            .ru: "Это стандартный пароль mailcow — смените его после первого входа (System → Administrator).",
            .uk: "Це стандартний пароль mailcow — змініть його після першого входу (System → Administrator).",
            .it: "È la password standard di mailcow: cambiarla dopo il primo accesso (Sistema → Amministratore).",
            .ja: "これは mailcow の標準パスワードです。初回サインイン後に変更してください（System → Administrator）。",
            .zh: "这是 mailcow 的默认密码——首次登录后请修改（System → Administrator）。"
        ])
    }

    /// Word used in "(directory: <path>)" of the report header line
    public static func directoryLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "directory",
            .de: "Verzeichnis",
            .fr: "répertoire",
            .es: "directorio",
            .ru: "каталог",
            .uk: "каталог",
            .it: "directory",
            .ja: "ディレクトリ",
            .zh: "目录"
        ])
    }

    public static func passwordLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Password",
            .de: "Passwort",
            .fr: "Mot de passe",
            .es: "Contraseña",
            .ru: "Пароль",
            .uk: "Пароль",
            .it: "Password",
            .ja: "パスワード",
            .zh: "密码"
        ])
    }

    public static func mailcowProvisioningDomain(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "Mailcow: adding domain \(domain) and its DKIM key over the API",
            .de: "Mailcow: Domain \(domain) und ihr DKIM-Schlüssel werden über die API angelegt",
            .fr: "Mailcow : ajout du domaine \(domain) et de sa clé DKIM via l'API",
            .es: "Mailcow: añadiendo el dominio \(domain) y su clave DKIM mediante la API",
            .ru: "Mailcow: добавление домена \(domain) и его DKIM-ключа через API",
            .uk: "Mailcow: додавання домену \(domain) та його DKIM-ключа через API",
            .it: "Mailcow: aggiunta del dominio \(domain) e della sua chiave DKIM tramite API",
            .ja: "Mailcow：API経由でドメイン \(domain) とそのDKIMキーを追加しています",
            .zh: "Mailcow：正在通过 API 添加域名 \(domain) 及其 DKIM 密钥"
        ])
    }

    public static func mailcowWaitingForAPI(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mailcow: waiting for the API to come up",
            .de: "Mailcow: Warten auf die API",
            .fr: "Mailcow : en attente de l'API",
            .es: "Mailcow: esperando a que la API esté disponible",
            .ru: "Mailcow: ждём, пока поднимется API",
            .uk: "Mailcow: чекаємо, доки підніметься API",
            .it: "Mailcow: in attesa che l'API sia disponibile",
            .ja: "Mailcow：APIの起動を待機しています",
            .zh: "Mailcow：正在等待 API 启动"
        ])
    }

    /// The API never answered
    public static func mailcowAPIUnreachable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mailcow: the API did not answer — the domain and DKIM key were NOT created. Mailcow itself is running: add the domain under Configuration → Domains in its admin UI, or re-run the setup.",
            .de: "Mailcow: Die API hat nicht geantwortet — Domain und DKIM-Schlüssel wurden NICHT angelegt. Mailcow selbst läuft: Domain in der Admin-UI unter Konfiguration → Domains anlegen oder das Setup erneut ausführen.",
            .fr: "Mailcow : l'API n'a pas répondu — le domaine et la clé DKIM n'ont PAS été créés. Mailcow fonctionne : ajoutez le domaine dans Configuration → Domaines de l'interface d'administration, ou relancez l'installation.",
            .es: "Mailcow: la API no respondió; el dominio y la clave DKIM NO se crearon. Mailcow sí está en marcha: añada el dominio en Configuración → Dominios de su interfaz de administración, o vuelva a ejecutar la instalación.",
            .ru: "Mailcow: API не ответил — домен и DKIM-ключ НЕ созданы. Сам mailcow работает: добавьте домен в админке (Configuration → Domains) или перезапустите установку.",
            .uk: "Mailcow: API не відповів — домен і DKIM-ключ НЕ створені. Сам mailcow працює: додайте домен в адмінці (Configuration → Domains) або перезапустіть встановлення.",
            .it: "Mailcow: l'API non ha risposto: il dominio e la chiave DKIM NON sono stati creati. Mailcow è comunque attivo: aggiungere il dominio in Configurazione → Domini nell'interfaccia di amministrazione, oppure rieseguire l'installazione.",
            .ja: "Mailcow：APIが応答しなかったため、ドメインとDKIMキーは作成されていません。Mailcow自体は稼働しています。管理画面の Configuration → Domains でドメインを追加するか、セットアップを再実行してください。",
            .zh: "Mailcow：API 未响应，域名和 DKIM 密钥均未创建。Mailcow 本身正在运行：请在管理界面的 Configuration → Domains 中添加域名，或重新运行安装。"
        ])
    }

    /// One domain could not be created
    public static func mailcowDomainAddFailed(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "Mailcow: could not add domain \(domain) over the API — add it under Configuration → Domains in the admin UI.",
            .de: "Mailcow: Domain \(domain) konnte nicht über die API angelegt werden — in der Admin-UI unter Konfiguration → Domains anlegen.",
            .fr: "Mailcow : impossible d'ajouter le domaine \(domain) via l'API — ajoutez-le dans Configuration → Domaines de l'interface d'administration.",
            .es: "Mailcow: no se pudo añadir el dominio \(domain) mediante la API; añádalo en Configuración → Dominios de la interfaz de administración.",
            .ru: "Mailcow: не удалось добавить домен \(domain) через API — добавьте его в админке (Configuration → Domains).",
            .uk: "Mailcow: не вдалося додати домен \(domain) через API — додайте його в адмінці (Configuration → Domains).",
            .it: "Mailcow: impossibile aggiungere il dominio \(domain) tramite API: aggiungerlo in Configurazione → Domini nell'interfaccia di amministrazione.",
            .ja: "Mailcow：API経由でドメイン \(domain) を追加できませんでした。管理画面の Configuration → Domains から追加してください。",
            .zh: "Mailcow：无法通过 API 添加域名 \(domain)——请在管理界面的 Configuration → Domains 中添加。"
        ])
    }

    public static func mailcowDKIMAddFailed(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "Mailcow: could not create the DKIM key for \(domain) over the API — create it under Configuration → ARC/DKIM keys in the admin UI.",
            .de: "Mailcow: DKIM-Schlüssel für \(domain) konnte nicht über die API erzeugt werden — in der Admin-UI unter Konfiguration → ARC/DKIM-Schlüssel anlegen.",
            .fr: "Mailcow : impossible de créer la clé DKIM pour \(domain) via l'API — créez-la dans Configuration → Clés ARC/DKIM de l'interface d'administration.",
            .es: "Mailcow: no se pudo crear la clave DKIM de \(domain) mediante la API; créela en Configuración → Claves ARC/DKIM de la interfaz de administración.",
            .ru: "Mailcow: не удалось создать DKIM-ключ для \(domain) через API — создайте его в админке (Configuration → ARC/DKIM keys).",
            .uk: "Mailcow: не вдалося створити DKIM-ключ для \(domain) через API — створіть його в адмінці (Configuration → ARC/DKIM keys).",
            .it: "Mailcow: impossibile creare la chiave DKIM per \(domain) tramite API: crearla in Configurazione → Chiavi ARC/DKIM nell'interfaccia di amministrazione.",
            .ja: "Mailcow：API経由で \(domain) のDKIMキーを作成できませんでした。管理画面の Configuration → ARC/DKIM keys から作成してください。",
            .zh: "Mailcow：无法通过 API 为 \(domain) 创建 DKIM 密钥——请在管理界面的 Configuration → ARC/DKIM keys 中创建。"
        ])
    }

    public static func mailcowDKIMHeader(_ l: AppLanguage, record: String) -> String {
        l.pick([
            .en: "DKIM DNS record (add as TXT for \(record)):",
            .de: "DKIM-DNS-Eintrag (als TXT für \(record) anlegen):",
            .fr: "Enregistrement DNS DKIM (à ajouter en TXT pour \(record)) :",
            .es: "Registro DNS DKIM (añadir como TXT para \(record)):",
            .ru: "DKIM DNS-запись (добавьте как TXT для \(record)):",
            .uk: "DKIM DNS-запис (додайте як TXT для \(record)):",
            .it: "Record DNS DKIM (aggiungere come TXT per \(record)):",
            .ja: "DKIM DNSレコード（\(record) のTXTとして追加）：",
            .zh: "DKIM DNS 记录（作为 \(record) 的 TXT 添加）："
        ])
    }

    public static func mailcowDKIMNotReady(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DKIM is not ready yet — re-run the script or check Configuration → ARC/DKIM keys in the mailcow admin UI.",
            .de: "DKIM ist noch nicht bereit — Skript erneut ausführen oder in der mailcow-Admin-UI unter Konfiguration → ARC/DKIM-Schlüssel nachsehen.",
            .fr: "DKIM n'est pas encore prêt — relancez le script ou vérifiez Configuration → Clés ARC/DKIM dans l'admin mailcow.",
            .es: "DKIM aún no está listo: vuelva a ejecutar el script o revise Configuración → Claves ARC/DKIM en la interfaz de mailcow.",
            .ru: "DKIM ещё не готов — перезапустите скрипт или проверьте Configuration → ARC/DKIM keys в админке mailcow.",
            .uk: "DKIM ще не готовий — перезапустіть скрипт або перевірте Configuration → ARC/DKIM keys в адмінці mailcow.",
            .it: "DKIM non è ancora pronto: rieseguire lo script o controllare Configurazione → Chiavi ARC/DKIM nell'admin di mailcow.",
            .ja: "DKIMはまだ準備できていません。スクリプトを再実行するか、mailcow管理画面の Configuration → ARC/DKIM keys を確認してください。",
            .zh: "DKIM 尚未就绪——请重新运行脚本，或在 mailcow 管理界面查看 Configuration → ARC/DKIM keys。"
        ])
    }

    public static func mailcowSelfSignedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mail (SMTP/IMAPS) currently uses Mailcow's self-signed certificate.",
            .de: "Mail (SMTP/IMAPS) verwendet derzeit das selbstsignierte Zertifikat von Mailcow.",
            .fr: "La messagerie (SMTP/IMAPS) utilise pour le moment le certificat auto-signé de Mailcow.",
            .es: "El correo (SMTP/IMAPS) usa por ahora el certificado autofirmado de Mailcow.",
            .ru: "Почта (SMTP/IMAPS) пока использует самоподписанный сертификат Mailcow.",
            .uk: "Пошта (SMTP/IMAPS) поки що використовує самопідписаний сертифікат Mailcow.",
            .it: "La posta (SMTP/IMAPS) usa per ora il certificato autofirmato di Mailcow.",
            .ja: "メール（SMTP/IMAPS）は現在、Mailcow の自己署名証明書を使用しています。",
            .zh: "邮件（SMTP/IMAPS）目前使用 Mailcow 的自签名证书。"
        ])
    }

    public static func mailcowAutoCertNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "SMTP/IMAPS use a trusted TLS certificate automatically (synced from Caddy and refreshed on renewal). Right after setup it may briefly be self-signed until Caddy issues the certificate — usually a few minutes.",
            .de: "SMTP/IMAPS verwenden automatisch ein vertrauenswürdiges TLS-Zertifikat (von Caddy übernommen und bei Erneuerung aktualisiert). Direkt nach der Einrichtung kann es kurz selbstsigniert sein, bis Caddy das Zertifikat ausgestellt hat — meist wenige Minuten.",
            .fr: "SMTP/IMAPS utilisent automatiquement un certificat TLS de confiance (repris de Caddy et actualisé au renouvellement). Juste après l'installation, il peut être brièvement auto-signé jusqu'à ce que Caddy émette le certificat — généralement quelques minutes.",
            .es: "SMTP/IMAPS usan automáticamente un certificado TLS de confianza (tomado de Caddy y actualizado al renovar). Justo tras la instalación puede ser autofirmado un momento hasta que Caddy emita el certificado — normalmente unos minutos.",
            .ru: "SMTP/IMAPS автоматически используют доверенный TLS-сертификат (берётся из Caddy и обновляется при продлении). Сразу после установки он может быть самоподписанным, пока Caddy не выпустит сертификат — обычно несколько минут.",
            .uk: "SMTP/IMAPS автоматично використовують довірений TLS-сертифікат (береться з Caddy й оновлюється при продовженні). Одразу після встановлення він може бути самопідписаним, доки Caddy не випустить сертифікат — зазвичай кілька хвилин.",
            .it: "SMTP/IMAPS usano automaticamente un certificato TLS attendibile (preso da Caddy e aggiornato al rinnovo). Subito dopo l'installazione può essere autofirmato per poco, finché Caddy non emette il certificato — di solito pochi minuti.",
            .ja: "SMTP/IMAPS は信頼された TLS 証明書を自動的に使用します（Caddy から同期し、更新時にも反映）。設定直後は Caddy が証明書を発行するまで一時的に自己署名になることがあります（通常は数分）。",
            .zh: "SMTP/IMAPS 会自动使用受信任的 TLS 证书（从 Caddy 同步，续期时刷新）。刚安装后，在 Caddy 签发证书之前可能短暂为自签名——通常几分钟。"
        ])
    }

    public static func mailcowTrustedCertHint(_ l: AppLanguage, domain: String, path: String) -> String {
        let ssl = "\(path)/data/assets/ssl"
        return l.pick([
            .en: "For a trusted certificate, copy the Caddy certificate for mail.\(domain) to \(ssl)/cert.pem and key.pem, then restart Mailcow.",
            .de: "Für ein vertrauenswürdiges Zertifikat kopieren Sie das Caddy-Zertifikat für mail.\(domain) nach \(ssl)/cert.pem und key.pem und starten Sie Mailcow danach neu.",
            .fr: "Pour un certificat de confiance, copiez le certificat Caddy de mail.\(domain) vers \(ssl)/cert.pem et key.pem, puis redémarrez Mailcow.",
            .es: "Para un certificado de confianza, copie el certificado Caddy de mail.\(domain) a \(ssl)/cert.pem y key.pem, y luego reinicie Mailcow.",
            .ru: "Для доверенного скопируйте сертификат Caddy для mail.\(domain) в \(ssl)/cert.pem и key.pem, затем перезапустите Mailcow.",
            .uk: "Для довіреного скопіюйте сертифікат Caddy для mail.\(domain) у \(ssl)/cert.pem і key.pem, потім перезапустіть Mailcow.",
            .it: "Per un certificato attendibile, copia il certificato Caddy di mail.\(domain) in \(ssl)/cert.pem e key.pem, poi riavvia Mailcow.",
            .ja: "信頼された証明書にするには、mail.\(domain) 用の Caddy 証明書を \(ssl)/cert.pem と key.pem にコピーし、その後 Mailcow を再起動してください。",
            .zh: "如需受信任的证书，请将 mail.\(domain) 的 Caddy 证书复制到 \(ssl)/cert.pem 和 key.pem，然后重启 Mailcow。"
        ])
    }

    // MARK: - Vaultwarden

    public static func adminPanelLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Admin panel",
            .de: "Admin-Panel",
            .fr: "Panneau d'administration",
            .es: "Panel de administración",
            .ru: "Админ-панель",
            .uk: "Адмін-панель",
            .it: "Pannello di amministrazione",
            .ja: "管理パネル",
            .zh: "管理面板"
        ])
    }

    public static func vaultwardenAdminTokenLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Admin token (generated on the server)",
            .de: "Admin-Token (auf dem Server generiert)",
            .fr: "Jeton administrateur (généré sur le serveur)",
            .es: "Token de administrador (generado en el servidor)",
            .ru: "Токен админа (сгенерирован на сервере)",
            .uk: "Токен адміністратора (згенеровано на сервері)",
            .it: "Token amministratore (generato sul server)",
            .ja: "管理者トークン（サーバー上で生成）",
            .zh: "管理员令牌（在服务器上生成）"
        ])
    }

    public static func vaultwardenSignupsOpen(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Signups: open",
            .de: "Registrierung: offen",
            .fr: "Inscriptions : ouvertes",
            .es: "Registro: abierto",
            .ru: "Регистрация: открыта",
            .uk: "Реєстрація: відкрита",
            .it: "Registrazioni: aperte",
            .ja: "登録：可能",
            .zh: "注册：开放"
        ])
    }

    public static func vaultwardenSignupsClosed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Signups: closed — invite users from the admin panel",
            .de: "Registrierung: geschlossen — laden Sie Benutzer über das Admin-Panel ein",
            .fr: "Inscriptions : fermées — invitez les utilisateurs depuis le panneau d'administration",
            .es: "Registro: cerrado — invite a los usuarios desde el panel de administración",
            .ru: "Регистрация: закрыта — приглашайте пользователей из админ-панели",
            .uk: "Реєстрація: закрита — запрошуйте користувачів з адмін-панелі",
            .it: "Registrazioni: chiuse — invita gli utenti dal pannello di amministrazione",
            .ja: "登録：不可 — 管理パネルからユーザーを招待してください",
            .zh: "注册：关闭 — 请从管理面板邀请用户"
        ])
    }

    public static func vaultwardenRegisterNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Sign-in: open the URL and create your own account (your email + a master password you choose). The admin token above is only for the /admin panel.",
            .de: "Anmeldung: Öffnen Sie die URL und erstellen Sie Ihr eigenes Konto (Ihre E-Mail + ein selbst gewähltes Master-Passwort). Das Admin-Token oben ist nur für das /admin-Panel.",
            .fr: "Connexion : ouvrez l'URL et créez votre propre compte (votre e-mail + un mot de passe maître de votre choix). Le jeton administrateur ci-dessus sert uniquement au panneau /admin.",
            .es: "Inicio de sesión: abra la URL y cree su propia cuenta (su correo + una contraseña maestra que elija). El token de administrador de arriba es solo para el panel /admin.",
            .ru: "Вход: откройте URL и создайте СВОЙ аккаунт (ваш email + мастер-пароль на ваш выбор). Токен админа выше — только для панели /admin.",
            .uk: "Вхід: відкрийте URL і створіть СВІЙ акаунт (ваш email + майстер-пароль на ваш вибір). Токен адміністратора вище — лише для панелі /admin.",
            .it: "Accesso: apri l'URL e crea il tuo account (la tua email + una password principale a tua scelta). Il token amministratore sopra è solo per il pannello /admin.",
            .ja: "サインイン：URLを開いて自分のアカウントを作成してください（あなたのメール＋自分で決めるマスターパスワード）。上の管理者トークンは/adminパネル専用です。",
            .zh: "登录：打开该网址并创建您自己的账户（您的邮箱 + 您自选的主密码）。上面的管理员令牌仅用于 /admin 面板。"
        ])
    }

    // MARK: - Nextcloud

    public static func nextcloudOccUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Nextcloud: occ did not answer — trusted domains were not applied; set them in config.php or re-run the setup.",
            .de: "Nextcloud: occ hat nicht geantwortet — vertrauenswürdige Domains wurden nicht gesetzt; in config.php eintragen oder Setup erneut ausführen.",
            .fr: "Nextcloud : occ n'a pas répondu — les domaines de confiance n'ont pas été appliqués ; renseignez-les dans config.php ou relancez l'installation.",
            .es: "Nextcloud: occ no respondió; no se aplicaron los dominios de confianza. Configúrelos en config.php o vuelva a ejecutar la instalación.",
            .ru: "Nextcloud: occ не ответил — доверенные домены не применены; пропишите их в config.php или перезапустите установку.",
            .uk: "Nextcloud: occ не відповів — довірені домени не застосовані; пропишіть їх у config.php або перезапустіть встановлення.",
            .it: "Nextcloud: occ non ha risposto: i domini attendibili non sono stati applicati; impostarli in config.php o rieseguire l'installazione.",
            .ja: "Nextcloud：occ が応答しませんでした。信頼済みドメインは適用されていません。config.php で設定するかセットアップを再実行してください。",
            .zh: "Nextcloud：occ 未响应，未应用受信任域名；请在 config.php 中设置或重新运行安装。"
        ])
    }

    /// One config value could not be set
    public static func nextcloudConfigSetFailed(_ l: AppLanguage, key: String) -> String {
        l.pick([
            .en: "Nextcloud: could not set \(key) — set it under Administration settings or in config.php.",
            .de: "Nextcloud: \(key) konnte nicht gesetzt werden — in den Administrationseinstellungen oder in config.php setzen.",
            .fr: "Nextcloud : impossible de définir \(key) — définissez-le dans les paramètres d'administration ou dans config.php.",
            .es: "Nextcloud: no se pudo establecer \(key); configúrelo en los ajustes de administración o en config.php.",
            .ru: "Nextcloud: не удалось задать \(key) — задайте его в настройках администратора или в config.php.",
            .uk: "Nextcloud: не вдалося задати \(key) — задайте його в налаштуваннях адміністратора або в config.php.",
            .it: "Nextcloud: impossibile impostare \(key): impostarlo nelle impostazioni di amministrazione o in config.php.",
            .ja: "Nextcloud：\(key) を設定できませんでした。管理設定または config.php で設定してください。",
            .zh: "Nextcloud：无法设置 \(key)——请在管理设置或 config.php 中设置。"
        ])
    }

    public static func administratorLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Administrator",
            .de: "Administrator",
            .fr: "Administrateur",
            .es: "Administrador",
            .ru: "Администратор",
            .uk: "Адміністратор",
            .it: "Amministratore",
            .ja: "管理者",
            .zh: "管理员"
        ])
    }

    public static func passwordGeneratedOnServerLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Password (generated on the server)",
            .de: "Passwort (auf dem Server generiert)",
            .fr: "Mot de passe (généré sur le serveur)",
            .es: "Contraseña (generada en el servidor)",
            .ru: "Пароль (сгенерирован на сервере)",
            .uk: "Пароль (згенеровано на сервері)",
            .it: "Password (generata sul server)",
            .ja: "パスワード（サーバー上で生成）",
            .zh: "密码（在服务器上生成）"
        ])
    }

    // MARK: - WireGuard VPN

    public static func vpnEndpointLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "VPN endpoint for clients",
            .de: "VPN-Endpunkt für Clients",
            .fr: "Point de terminaison VPN pour les clients",
            .es: "Punto de conexión VPN para clientes",
            .ru: "VPN-endpoint для клиентов",
            .uk: "VPN-endpoint для клієнтів",
            .it: "Endpoint VPN per i client",
            .ja: "クライアント用 VPN エンドポイント",
            .zh: "客户端 VPN 接入点"
        ])
    }

    public static func vpnClientsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Add client devices in the panel: it generates their configs and QR codes.",
            .de: "Client-Geräte im Panel hinzufügen: Es erzeugt deren Konfigurationen und QR-Codes.",
            .fr: "Ajoutez les appareils clients dans le panneau : il génère leurs configurations et QR codes.",
            .es: "Añada los dispositivos cliente en el panel: genera sus configuraciones y códigos QR.",
            .ru: "Клиентские устройства добавляются в панели: она генерирует их конфиги и QR-коды.",
            .uk: "Клієнтські пристрої додаються в панелі: вона генерує їхні конфіги та QR-коди.",
            .it: "Aggiungi i dispositivi client nel pannello: genera le loro configurazioni e i codici QR.",
            .ja: "クライアント端末はパネルで追加します。設定ファイルと QR コードが生成されます。",
            .zh: "在面板中添加客户端设备：面板会生成其配置文件和二维码。"
        ])
    }

    public static func shadowsocksLinkLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Connection link (ss://) for clients",
            .de: "Verbindungslink (ss://) für Clients",
            .fr: "Lien de connexion (ss://) pour les clients",
            .es: "Enlace de conexión (ss://) para clientes",
            .ru: "Ссылка для подключения (ss://) для клиентов",
            .uk: "Посилання для підключення (ss://) для клієнтів",
            .it: "Link di connessione (ss://) per i client",
            .ja: "クライアント用の接続リンク（ss://）",
            .zh: "客户端连接链接（ss://）"
        ])
    }

    public static func shadowsocksClientsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Paste the ss:// link into an Outline / Shadowsocks client, or turn it into a QR code.",
            .de: "Fügen Sie den ss://-Link in einen Outline-/Shadowsocks-Client ein oder erzeugen Sie daraus einen QR-Code.",
            .fr: "Collez le lien ss:// dans un client Outline / Shadowsocks, ou convertissez-le en QR code.",
            .es: "Pegue el enlace ss:// en un cliente Outline / Shadowsocks, o conviértalo en un código QR.",
            .ru: "Вставьте ссылку ss:// в клиент Outline / Shadowsocks или сделайте из неё QR-код.",
            .uk: "Вставте посилання ss:// у клієнт Outline / Shadowsocks або зробіть із нього QR-код.",
            .it: "Incolla il link ss:// in un client Outline / Shadowsocks, o convertilo in un codice QR.",
            .ja: "ss:// リンクを Outline / Shadowsocks クライアントに貼り付けるか、QR コードに変換してください。",
            .zh: "将 ss:// 链接粘贴到 Outline / Shadowsocks 客户端，或将其转换为二维码。"
        ])
    }

    public static func xrayLinkLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Connection link (vless://) for clients",
            .de: "Verbindungslink (vless://) für Clients",
            .fr: "Lien de connexion (vless://) pour les clients",
            .es: "Enlace de conexión (vless://) para clientes",
            .ru: "Ссылка для подключения (vless://) для клиентов",
            .uk: "Посилання для підключення (vless://) для клієнтів",
            .it: "Link di connessione (vless://) per i client",
            .ja: "クライアント用の接続リンク（vless://）",
            .zh: "客户端连接链接（vless://）"
        ])
    }

    public static func xrayClientsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Paste the vless:// link into an Xray client (v2rayN, Streisand, Hiddify), or turn it into a QR code.",
            .de: "Fügen Sie den vless://-Link in einen Xray-Client (v2rayN, Streisand, Hiddify) ein oder erzeugen Sie daraus einen QR-Code.",
            .fr: "Collez le lien vless:// dans un client Xray (v2rayN, Streisand, Hiddify), ou convertissez-le en QR code.",
            .es: "Pegue el enlace vless:// en un cliente Xray (v2rayN, Streisand, Hiddify), o conviértalo en un código QR.",
            .ru: "Вставьте ссылку vless:// в клиент Xray (v2rayN, Streisand, Hiddify) или сделайте из неё QR-код.",
            .uk: "Вставте посилання vless:// у клієнт Xray (v2rayN, Streisand, Hiddify) або зробіть із нього QR-код.",
            .it: "Incolla il link vless:// in un client Xray (v2rayN, Streisand, Hiddify), o convertilo in un codice QR.",
            .ja: "vless:// リンクを Xray クライアント（v2rayN、Streisand、Hiddify）に貼り付けるか、QR コードに変換してください。",
            .zh: "将 vless:// 链接粘贴到 Xray 客户端（v2rayN、Streisand、Hiddify），或将其转换为二维码。"
        ])
    }

    public static func openVPNConfigLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Client profile (.ovpn) — copy everything between the markers into a file and import it",
            .de: "Client-Profil (.ovpn) — alles zwischen den Markierungen in eine Datei kopieren und importieren",
            .fr: "Profil client (.ovpn) — copiez tout ce qui se trouve entre les marqueurs dans un fichier et importez-le",
            .es: "Perfil de cliente (.ovpn) — copie todo lo que hay entre los marcadores en un archivo e impórtelo",
            .ru: "Профиль клиента (.ovpn) — скопируйте всё между маркерами в файл и импортируйте",
            .uk: "Профіль клієнта (.ovpn) — скопіюйте все між маркерами у файл та імпортуйте",
            .it: "Profilo client (.ovpn) — copia tutto ciò che è tra i marcatori in un file e importalo",
            .ja: "クライアントプロファイル（.ovpn）— マーカーの間をすべてファイルにコピーしてインポートしてください",
            .zh: "客户端配置（.ovpn）— 将标记之间的全部内容复制到文件并导入"
        ])
    }

    public static func openVPNClientsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Import the .ovpn into OpenVPN Connect (iOS/Android/desktop). The same profile can be downloaded later from the Files tab.",
            .de: "Importieren Sie die .ovpn in OpenVPN Connect (iOS/Android/Desktop). Dasselbe Profil kann später im Tab „Dateien“ heruntergeladen werden.",
            .fr: "Importez le .ovpn dans OpenVPN Connect (iOS/Android/ordinateur). Le même profil peut être téléchargé plus tard depuis l'onglet Fichiers.",
            .es: "Importe el .ovpn en OpenVPN Connect (iOS/Android/escritorio). El mismo perfil se puede descargar luego desde la pestaña Archivos.",
            .ru: "Импортируйте .ovpn в OpenVPN Connect (iOS/Android/десктоп). Тот же профиль позже можно скачать во вкладке «Файлы».",
            .uk: "Імпортуйте .ovpn в OpenVPN Connect (iOS/Android/десктоп). Той самий профіль пізніше можна завантажити у вкладці «Файли».",
            .it: "Importa il .ovpn in OpenVPN Connect (iOS/Android/desktop). Lo stesso profilo può essere scaricato in seguito dalla scheda File.",
            .ja: "OpenVPN Connect（iOS/Android/デスクトップ）に .ovpn をインポートしてください。同じプロファイルは後で「ファイル」タブからダウンロードできます。",
            .zh: "将 .ovpn 导入 OpenVPN Connect（iOS/Android/桌面）。稍后也可从「文件」标签下载同一配置。"
        ])
    }

    public static func adminViaWireGuardNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Note: the admin panels (mail, cloud, photos, vault) are reachable ONLY over WireGuard — add a WireGuard client in the VPN panel and connect with it to manage them. AmneziaWG and this protocol are for general internet access; they do not reach the admin panels.",
            .de: "Hinweis: Die Admin-Oberflächen (Mail, Cloud, Fotos, Vault) sind NUR über WireGuard erreichbar — legen Sie im VPN-Panel einen WireGuard-Client an und verbinden Sie sich damit, um sie zu verwalten. AmneziaWG und dieses Protokoll dienen dem allgemeinen Internetzugang und erreichen die Admin-Oberflächen nicht.",
            .fr: "Remarque : les panneaux d'administration (courrier, cloud, photos, vault) ne sont accessibles QUE via WireGuard — créez un client WireGuard dans le panneau VPN et connectez-vous avec pour les gérer. AmneziaWG et ce protocole servent à l'accès Internet général ; ils n'atteignent pas les panneaux d'administration.",
            .es: "Nota: los paneles de administración (correo, nube, fotos, vault) solo son accesibles a través de WireGuard — cree un cliente WireGuard en el panel VPN y conéctese con él para gestionarlos. AmneziaWG y este protocolo son para el acceso general a Internet; no llegan a los paneles de administración.",
            .ru: "Примечание: админ-панели (почта, облако, фото, vault) доступны ТОЛЬКО через WireGuard — создайте клиента WireGuard в VPN-панели и подключитесь им для управления. AmneziaWG и этот протокол предназначены для обычного доступа в интернет, до админ-панелей они не доходят.",
            .uk: "Примітка: адмін-панелі (пошта, хмара, фото, vault) доступні ЛИШЕ через WireGuard — створіть клієнта WireGuard у VPN-панелі та підключіться ним для керування. AmneziaWG і цей протокол призначені для звичайного доступу до інтернету, до адмін-панелей вони не доходять.",
            .it: "Nota: i pannelli di amministrazione (posta, cloud, foto, vault) sono raggiungibili SOLO tramite WireGuard — crea un client WireGuard nel pannello VPN e connettiti con quello per gestirli. AmneziaWG e questo protocollo servono all'accesso generale a Internet e non raggiungono i pannelli di amministrazione.",
            .ja: "注: 管理パネル（メール、クラウド、写真、Vault）は WireGuard 経由でのみアクセスできます。VPN パネルで WireGuard クライアントを作成し、それで接続して管理してください。AmneziaWG とこのプロトコルは一般的なインターネット接続用で、管理パネルには到達しません。",
            .zh: "注意：管理面板（邮件、云盘、相册、Vault）只能通过 WireGuard 访问 — 请在 VPN 面板中创建 WireGuard 客户端并用它连接以进行管理。AmneziaWG 和本协议用于常规互联网访问，无法访问管理面板。"
        ])
    }

    public static func amneziaAdminViaWireGuardNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Note: AmneziaWG carries general internet traffic, but the admin panels (mail, cloud, photos, vault) do NOT open over it — they are reachable only over plain WireGuard. Add a WireGuard client in the VPN panel and connect with it to manage them.",
            .de: "Hinweis: AmneziaWG transportiert den allgemeinen Internetverkehr, aber die Admin-Oberflächen (Mail, Cloud, Fotos, Vault) lassen sich darüber NICHT öffnen — sie sind nur über einfaches WireGuard erreichbar. Legen Sie im VPN-Panel einen WireGuard-Client an und verbinden Sie sich damit, um sie zu verwalten.",
            .fr: "Remarque : AmneziaWG achemine le trafic Internet général, mais les panneaux d'administration (courrier, cloud, photos, vault) ne s'ouvrent PAS via ce protocole — ils ne sont accessibles que via WireGuard classique. Créez un client WireGuard dans le panneau VPN et connectez-vous avec pour les gérer.",
            .es: "Nota: AmneziaWG transporta el tráfico general de Internet, pero los paneles de administración (correo, nube, fotos, vault) NO se abren a través de él — solo son accesibles mediante WireGuard normal. Cree un cliente WireGuard en el panel VPN y conéctese con él para gestionarlos.",
            .ru: "Примечание: AmneziaWG подходит для обычного доступа в интернет, но админ-панели (почта, облако, фото, vault) через него НЕ открываются — они доступны только через обычный WireGuard. Создайте клиента WireGuard в VPN-панели и подключитесь им для управления.",
            .uk: "Примітка: AmneziaWG підходить для звичайного доступу до інтернету, але адмін-панелі (пошта, хмара, фото, vault) через нього НЕ відкриваються — вони доступні лише через звичайний WireGuard. Створіть клієнта WireGuard у VPN-панелі та підключіться ним для керування.",
            .it: "Nota: AmneziaWG trasporta il traffico Internet generale, ma i pannelli di amministrazione (posta, cloud, foto, vault) NON si aprono tramite esso — sono raggiungibili solo con WireGuard normale. Crea un client WireGuard nel pannello VPN e connettiti con quello per gestirli.",
            .ja: "注: AmneziaWG は一般的なインターネット通信には使えますが、管理パネル（メール、クラウド、写真、Vault）は開けません。管理パネルは通常の WireGuard 経由でのみアクセスできます。VPN パネルで WireGuard クライアントを作成し、それで接続して管理してください。",
            .zh: "注意：AmneziaWG 可用于常规互联网访问，但无法打开管理面板（邮件、云盘、相册、Vault）— 管理面板只能通过普通 WireGuard 访问。请在 VPN 面板中创建 WireGuard 客户端并用它连接以进行管理。"
        ])
    }

    // MARK: - Immich

    public static func immichAdminWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and create the administrator — until then, anyone who opens the page can register.",
            .de: "WICHTIG: Öffnen Sie diese URL sofort und legen Sie den Administrator an — bis dahin kann sich jeder registrieren, der die Seite öffnet.",
            .fr: "IMPORTANT : ouvrez cette URL dès maintenant et créez l'administrateur — d'ici là, quiconque ouvre la page peut s'inscrire.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y cree el administrador — hasta entonces, cualquiera que abra la página puede registrarse.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и создайте администратора — до этого зарегистрироваться может любой, кто откроет страницу.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і створіть адміністратора — доти зареєструватися може будь-хто, хто відкриє сторінку.",
            .it: "IMPORTANTE: apri questo URL subito e crea l'amministratore — fino ad allora chiunque apra la pagina può registrarsi.",
            .ja: "重要：今すぐこの URL を開いて管理者を作成してください — それまでは、ページを開いた誰でも登録できます。",
            .zh: "重要：请立即打开此地址并创建管理员 — 在此之前，任何打开该页面的人都可以注册。"
        ])
    }

    // MARK: - Seafile

    /// Heartbeat while the first start runs
    public static func seafileWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Seafile: waiting for the first start to write its configuration",
            .de: "Seafile: warte darauf, dass der erste Start seine Konfiguration schreibt",
            .fr: "Seafile : en attente de l'ecriture de la configuration au premier demarrage",
            .es: "Seafile: esperando a que el primer arranque escriba su configuración",
            .ru: "Seafile: ждём, пока первый запуск запишет свою конфигурацию",
            .uk: "Seafile: чекаємо, доки перший запуск запише свою конфігурацію",
            .it: "Seafile: in attesa che il primo avvio scriva la sua configurazione",
            .ja: "Seafile: 初回起動が設定ファイルを書き出すのを待っています",
            .zh: "Seafile: 正在等待首次启动写入配置文件"
        ])
    }

    public static func seafileUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Seafile did not finish its first start in time — sign-in will be refused until the trusted addresses are set in conf/seahub_settings.py",
            .de: "Seafile hat den ersten Start nicht rechtzeitig beendet — die Anmeldung wird abgelehnt, bis die vertrauten Adressen in conf/seahub_settings.py eingetragen sind",
            .fr: "Seafile n'a pas termine son premier demarrage a temps — la connexion sera refusee tant que les adresses de confiance ne sont pas inscrites dans conf/seahub_settings.py",
            .es: "Seafile no terminó su primer arranque a tiempo: el inicio de sesión será rechazado hasta que las direcciones de confianza estén en conf/seahub_settings.py",
            .ru: "Seafile не завершил первый запуск вовремя — вход будет отклоняться, пока доверенные адреса не прописаны в conf/seahub_settings.py",
            .uk: "Seafile не завершив перший запуск вчасно — вхід відхилятиметься, доки довірені адреси не буде прописано в conf/seahub_settings.py",
            .it: "Seafile non ha completato il primo avvio in tempo: l'accesso verrà rifiutato finché gli indirizzi attendibili non saranno in conf/seahub_settings.py",
            .ja: "Seafile の初回起動が時間内に完了しませんでした — conf/seahub_settings.py に信頼するアドレスを設定するまで、ログインは拒否されます",
            .zh: "Seafile 首次启动未能及时完成 — 在 conf/seahub_settings.py 中写入受信任地址之前，登录都会被拒绝"
        ])
    }

    // MARK: - PhotoPrism

    /// Report label for the directory PhotoPrism indexes
    public static func photoprismOriginalsLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Put your pictures here, then start indexing in the web interface",
            .de: "Legen Sie Ihre Bilder hier ab und starten Sie dann die Indizierung in der Weboberfläche",
            .fr: "Placez vos photos ici, puis lancez l'indexation dans l'interface web",
            .es: "Coloque aquí sus fotos y luego inicie la indexación en la interfaz web",
            .ru: "Положите сюда свои фотографии и запустите индексацию в веб-интерфейсе",
            .uk: "Покладіть сюди свої фотографії та запустіть індексацію у вебінтерфейсі",
            .it: "Metti qui le tue foto e poi avvia l'indicizzazione nell'interfaccia web",
            .ja: "写真をここに置き、ウェブ画面でインデックス作成を開始してください",
            .zh: "请把照片放在这里，然后在网页界面中开始建立索引"
        ])
    }

    // MARK: - AdGuard Home

    public static func adguardWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "AdGuard Home: waiting for the service to answer",
            .de: "AdGuard Home: Warten auf Antwort des Dienstes",
            .fr: "AdGuard Home : en attente de la réponse du service",
            .es: "AdGuard Home: esperando la respuesta del servicio",
            .ru: "AdGuard Home: ждём ответа сервиса",
            .uk: "AdGuard Home: чекаємо на відповідь сервісу",
            .it: "AdGuard Home: in attesa della risposta del servizio",
            .ja: "AdGuard Home: サービスの応答を待っています",
            .zh: "AdGuard Home: 正在等待服务响应"
        ])
    }

    public static func adguardConfigureFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "AdGuard Home: the initial configuration failed — the setup wizard is still open, finish it yourself right away",
            .de: "AdGuard Home: Ersteinrichtung fehlgeschlagen — der Assistent ist noch offen, schließen Sie ihn sofort selbst ab",
            .fr: "AdGuard Home : la configuration initiale a échoué — l'assistant est encore ouvert, terminez-le vous-même sans attendre",
            .es: "AdGuard Home: la configuración inicial falló — el asistente sigue abierto, complételo usted mismo de inmediato",
            .ru: "AdGuard Home: первичная настройка не удалась — мастер установки всё ещё открыт, пройдите его сами прямо сейчас",
            .uk: "AdGuard Home: первинне налаштування не вдалося — майстер встановлення ще відкритий, пройдіть його самі просто зараз",
            .it: "AdGuard Home: la configurazione iniziale non è riuscita — la procedura guidata è ancora aperta, completala subito",
            .ja: "AdGuard Home: 初期設定に失敗しました — セットアップウィザードは開いたままです。今すぐご自身で完了してください",
            .zh: "AdGuard Home: 初始配置失败 — 设置向导仍然开放，请立即自行完成"
        ])
    }

    public static func adguardUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "AdGuard Home did not answer in time — the initial configuration was skipped",
            .de: "AdGuard Home hat nicht rechtzeitig geantwortet — die Ersteinrichtung wurde übersprungen",
            .fr: "AdGuard Home n'a pas répondu à temps — la configuration initiale a été ignorée",
            .es: "AdGuard Home no respondió a tiempo: se omitió la configuración inicial",
            .ru: "AdGuard Home не ответил вовремя — первичная настройка пропущена",
            .uk: "AdGuard Home не відповів вчасно — первинне налаштування пропущено",
            .it: "AdGuard Home non ha risposto in tempo: la configurazione iniziale è stata saltata",
            .ja: "AdGuard Home が時間内に応答しませんでした — 初期設定をスキップしました",
            .zh: "AdGuard Home 未及时响应 — 已跳过初始配置"
        ])
    }

    public static func adguardDoHKeyMissing(_ l: AppLanguage) -> String {
        l.pick([
            .en: "AdGuard Home: could not enable DNS-over-HTTPS behind the proxy — turn it on under Settings, Encryption",
            .de: "AdGuard Home: DNS-over-HTTPS hinter dem Proxy konnte nicht aktiviert werden — schalten Sie es unter Einstellungen, Verschlüsselung ein",
            .fr: "AdGuard Home : impossible d'activer DNS-over-HTTPS derriere le proxy — activez-le dans Parametres, Chiffrement",
            .es: "AdGuard Home: no se pudo activar DNS-over-HTTPS detrás del proxy: actívelo en Ajustes, Cifrado",
            .ru: "AdGuard Home: не удалось включить DNS-over-HTTPS за прокси — включите его в настройках, раздел шифрования",
            .uk: "AdGuard Home: не вдалося увімкнути DNS-over-HTTPS за проксі — увімкніть його в налаштуваннях, розділ шифрування",
            .it: "AdGuard Home: non è stato possibile attivare DNS-over-HTTPS dietro il proxy: attivalo in Impostazioni, Crittografia",
            .ja: "AdGuard Home: プロキシ経由の DNS-over-HTTPS を有効にできませんでした — 設定の暗号化から有効にしてください",
            .zh: "AdGuard Home: 无法启用代理后的 DNS-over-HTTPS — 请在设置的加密页面中开启"
        ])
    }

    // MARK: - Authelia

    public static func autheliaHashFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Authelia: could not create the first account — sign-in is not possible until a user is added to config/users_database.yml",
            .de: "Authelia: Das erste Konto konnte nicht angelegt werden — eine Anmeldung ist erst möglich, wenn ein Benutzer in config/users_database.yml steht",
            .fr: "Authelia : impossible de créer le premier compte — aucune connexion n'est possible tant qu'un utilisateur n'est pas ajouté à config/users_database.yml",
            .es: "Authelia: no se pudo crear la primera cuenta: no se podrá iniciar sesión hasta añadir un usuario a config/users_database.yml",
            .ru: "Authelia: не удалось создать первую учётную запись — войти будет нельзя, пока пользователь не добавлен в config/users_database.yml",
            .uk: "Authelia: не вдалося створити перший обліковий запис — увійти буде неможливо, доки користувача не додано до config/users_database.yml",
            .it: "Authelia: non è stato possibile creare il primo account: non sarà possibile accedere finché un utente non viene aggiunto a config/users_database.yml",
            .ja: "Authelia: 最初のアカウントを作成できませんでした — config/users_database.yml にユーザーを追加するまでサインインできません",
            .zh: "Authelia: 无法创建第一个账户——在向 config/users_database.yml 添加用户之前无法登录"
        ])
    }

    public static func autheliaProtectsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Asks for this login before",
            .de: "Verlangt diese Anmeldung vor",
            .fr: "Demande cette connexion avant",
            .es: "Pide este inicio de sesión antes de",
            .ru: "Спрашивает этот вход перед",
            .uk: "Запитує цей вхід перед",
            .it: "Chiede questo accesso prima di",
            .ja: "この認証を求める対象",
            .zh: "在以下站点前要求此登录"
        ])
    }

    // MARK: - Homepage

    /// Report label for the file the install regenerates every run
    public static func homepageGeneratedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Built from your services and rewritten on every install",
            .de: "Aus Ihren Diensten erzeugt und bei jeder Installation neu geschrieben",
            .fr: "Construit à partir de vos services et réécrit à chaque installation",
            .es: "Generado a partir de sus servicios y reescrito en cada instalación",
            .ru: "Собирается из ваших сервисов и переписывается при каждой установке",
            .uk: "Збирається з ваших сервісів і перезаписується при кожному встановленні",
            .it: "Generato dai tuoi servizi e riscritto a ogni installazione",
            .ja: "あなたのサービスから生成され、インストールのたびに書き直されます",
            .zh: "由你的服务生成，每次安装都会重写"
        ])
    }

    public static func homepageOwnEditsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Yours to edit — never touched again after it is created",
            .de: "Ihre Datei — wird nach dem Anlegen nie wieder angefasst",
            .fr: "À vous de la modifier — jamais retouchée après sa création",
            .es: "Suyo para editar: no se vuelve a tocar después de crearse",
            .ru: "Ваш файл — после создания больше не трогается",
            .uk: "Ваш файл — після створення більше не чіпається",
            .it: "È tuo da modificare: dopo la creazione non viene più toccato",
            .ja: "こちらは自由に編集できます — 作成後は二度と変更されません",
            .zh: "这个文件归你编辑——创建之后不会再被修改"
        ])
    }

    // MARK: - Pi-hole

    public static func piholeWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Pi-hole: waiting for the resolver to answer (it is downloading its blocklists)",
            .de: "Pi-hole: Warten auf Antwort des Resolvers (die Blocklisten werden geladen)",
            .fr: "Pi-hole : en attente de la réponse du résolveur (il télécharge ses listes de blocage)",
            .es: "Pi-hole: esperando la respuesta del resolutor (está descargando sus listas de bloqueo)",
            .ru: "Pi-hole: ждём ответа резолвера (он скачивает свои списки блокировки)",
            .uk: "Pi-hole: чекаємо на відповідь резолвера (він завантажує свої списки блокування)",
            .it: "Pi-hole: in attesa della risposta del resolver (sta scaricando le sue blocklist)",
            .ja: "Pi-hole: リゾルバーの応答を待っています（ブロックリストを取得中です）",
            .zh: "Pi-hole: 正在等待解析器响应（它正在下载屏蔽列表）"
        ])
    }

    public static func piholeUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Pi-hole did not answer a query in time — it is installed and may still be building its blocklists; check the admin page",
            .de: "Pi-hole hat nicht rechtzeitig auf eine Anfrage geantwortet — es ist installiert und baut möglicherweise noch seine Blocklisten auf; prüfen Sie die Admin-Seite",
            .fr: "Pi-hole n'a pas répondu à une requête à temps — il est installé et construit peut-être encore ses listes de blocage ; vérifiez la page d'administration",
            .es: "Pi-hole no respondió a una consulta a tiempo: está instalado y puede seguir construyendo sus listas de bloqueo; revise la página de administración",
            .ru: "Pi-hole не ответил на запрос вовремя — он установлен и, возможно, ещё строит списки блокировки; проверьте админ-страницу",
            .uk: "Pi-hole не відповів на запит вчасно — він встановлений і, можливо, ще будує списки блокування; перевірте адмін-сторінку",
            .it: "Pi-hole non ha risposto a una query in tempo: è installato e potrebbe stare ancora costruendo le blocklist; controlla la pagina di amministrazione",
            .ja: "Pi-hole が時間内に問い合わせへ応答しませんでした — インストールは済んでおり、ブロックリストの構築中の可能性があります。管理ページを確認してください",
            .zh: "Pi-hole 未及时响应查询——它已安装，可能仍在构建屏蔽列表；请检查管理页面"
        ])
    }

    /// Says which clients can actually USE the filter
    public static func piholeServesNetworkNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DNS is served to the whole network on port 53 — point your router or your devices at this server's address. Make sure port 53 is not reachable from the internet.",
            .de: "DNS wird auf Port 53 im gesamten Netzwerk bereitgestellt — richten Sie Ihren Router oder Ihre Geräte auf die Adresse dieses Servers. Stellen Sie sicher, dass Port 53 aus dem Internet nicht erreichbar ist.",
            .fr: "Le DNS est servi à tout le réseau sur le port 53 — pointez votre routeur ou vos appareils vers l'adresse de ce serveur. Assurez-vous que le port 53 n'est pas joignable depuis internet.",
            .es: "El DNS se sirve a toda la red en el puerto 53: apunte su router o sus dispositivos a la dirección de este servidor. Asegúrese de que el puerto 53 no sea accesible desde internet.",
            .ru: "DNS отдаётся всей сети на порт 53 — направьте роутер или устройства на адрес этого сервера. Убедитесь, что порт 53 недоступен из интернета.",
            .uk: "DNS віддається всій мережі на порт 53 — спрямуйте роутер або пристрої на адресу цього сервера. Переконайтеся, що порт 53 недоступний з інтернету.",
            .it: "Il DNS è servito a tutta la rete sulla porta 53: punta il router o i dispositivi all'indirizzo di questo server. Assicurati che la porta 53 non sia raggiungibile da internet.",
            .ja: "DNS はポート 53 でネットワーク全体に提供されます — ルーターまたは各端末をこのサーバーのアドレスに向けてください。ポート 53 がインターネットから到達できないことを確認してください。",
            .zh: "DNS 在 53 端口向整个网络提供服务——请把路由器或各设备指向这台服务器的地址。请确认 53 端口无法从互联网访问。"
        ])
    }

    public static func piholeLoopbackNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DNS answers on this machine only (127.0.0.1:53), so no open resolver is exposed. To serve the network, turn that on in the server's settings and reinstall — only do it where port 53 cannot be reached from the internet.",
            .de: "DNS antwortet nur auf dieser Maschine (127.0.0.1:53), es wird also kein offener Resolver bereitgestellt. Um das Netzwerk zu bedienen, schalten Sie das in den Servereinstellungen ein und installieren Sie neu — nur dort, wo Port 53 aus dem Internet nicht erreichbar ist.",
            .fr: "Le DNS ne répond que sur cette machine (127.0.0.1:53) : aucun résolveur ouvert n'est exposé. Pour servir le réseau, activez-le dans les réglages du serveur et réinstallez — uniquement là où le port 53 est injoignable depuis internet.",
            .es: "El DNS responde solo en esta máquina (127.0.0.1:53), así que no se expone ningún resolutor abierto. Para servir a la red, actívelo en los ajustes del servidor y reinstale, solo donde el puerto 53 no sea accesible desde internet.",
            .ru: "DNS отвечает только на этой машине (127.0.0.1:53), поэтому открытого резолвера нет. Чтобы отдавать DNS сети, включите это в настройках сервера и переустановите — только там, где порт 53 недоступен из интернета.",
            .uk: "DNS відповідає лише на цій машині (127.0.0.1:53), тож відкритого резолвера немає. Щоб віддавати DNS мережі, увімкніть це в налаштуваннях сервера й перевстановіть — лише там, де порт 53 недоступний з інтернету.",
            .it: "Il DNS risponde solo su questa macchina (127.0.0.1:53), quindi non viene esposto alcun resolver aperto. Per servire la rete, attivalo nelle impostazioni del server e reinstalla — solo dove la porta 53 non è raggiungibile da internet.",
            .ja: "DNS はこのマシン上（127.0.0.1:53）だけで応答するため、オープンリゾルバーは公開されません。ネットワークに提供するにはサーバー設定で有効にして再インストールしてください — ポート 53 がインターネットから到達できない場所でのみ行ってください。",
            .zh: "DNS 仅在本机（127.0.0.1:53）应答，因此不会暴露开放解析器。若要为网络提供服务，请在服务器设置中开启并重新安装——只在 53 端口无法从互联网访问的地方这样做。"
        ])
    }

    /// Report label for the DoH endpoint clients point at
    public static func cloudflaredNoTokenNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Cloudflare Tunnel is installed but not started: it has no token yet",
            .de: "Cloudflare Tunnel ist installiert, aber nicht gestartet: es fehlt noch das Token",
            .fr: "Cloudflare Tunnel est installé mais pas démarré : il n’a pas encore de jeton",
            .es: "Cloudflare Tunnel está instalado pero no iniciado: aún no tiene token",
            .ru: "Cloudflare Tunnel установлен, но не запущен: у него ещё нет токена",
            .uk: "Cloudflare Tunnel встановлено, але не запущено: у нього ще немає токена",
            .it: "Cloudflare Tunnel è installato ma non avviato: non ha ancora un token",
            .ja: "Cloudflare Tunnel はインストール済みですが未起動です。トークンがまだありません",
            .zh: "Cloudflare Tunnel 已安装但未启动：尚未提供令牌"
        ])
    }

    public static func cloudflaredTokenNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Create a tunnel in the Cloudflare dashboard and put its token in",
            .de: "Erstellen Sie einen Tunnel im Cloudflare-Dashboard und tragen Sie sein Token ein in",
            .fr: "Créez un tunnel dans le tableau de bord Cloudflare et placez son jeton dans",
            .es: "Crea un túnel en el panel de Cloudflare y pon su token en",
            .ru: "Создайте туннель в панели Cloudflare и впишите его токен в",
            .uk: "Створіть тунель у панелі Cloudflare і впишіть його токен у",
            .it: "Crea un tunnel nel pannello Cloudflare e inserisci il suo token in",
            .ja: "Cloudflare のダッシュボードでトンネルを作成し、そのトークンを次に記入してください",
            .zh: "在 Cloudflare 控制台创建隧道，并将其令牌填入"
        ])
    }

    public static func cloudflaredRoutesNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Then add these routes to the tunnel",
            .de: "Fügen Sie dem Tunnel dann diese Routen hinzu",
            .fr: "Ajoutez ensuite ces routes au tunnel",
            .es: "Después añade estas rutas al túnel",
            .ru: "Затем добавьте туннелю эти маршруты",
            .uk: "Потім додайте тунелю ці маршрути",
            .it: "Poi aggiungi queste rotte al tunnel",
            .ja: "その後、トンネルに次のルートを追加します",
            .zh: "然后为该隧道添加以下路由"
        ])
    }

    public static func cloudflaredNoPortsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "With the tunnel running this server needs no inbound port open at all.",
            .de: "Mit laufendem Tunnel braucht dieser Server überhaupt keinen offenen eingehenden Port.",
            .fr: "Avec le tunnel actif, ce serveur n’a besoin d’aucun port entrant ouvert.",
            .es: "Con el túnel en marcha, este servidor no necesita ningún puerto entrante abierto.",
            .ru: "С работающим туннелем этому серверу не нужен ни один открытый входящий порт.",
            .uk: "З працюючим тунелем цьому серверу не потрібен жоден відкритий вхідний порт.",
            .it: "Con il tunnel attivo questo server non ha bisogno di alcuna porta in ingresso aperta.",
            .ja: "トンネルが動いていれば、このサーバーに開放すべき受信ポートは一つもありません。",
            .zh: "隧道运行时，这台服务器无需开放任何入站端口。"
        ])
    }

    public static func headscaleNoWebUINote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "This address is the control server for your devices, not a web page",
            .de: "Diese Adresse ist der Steuerserver für Ihre Geräte, keine Webseite",
            .fr: "Cette adresse est le serveur de contrôle de vos appareils, pas une page web",
            .es: "Esta dirección es el servidor de control de tus dispositivos, no una página web",
            .ru: "Этот адрес — управляющий сервер для ваших устройств, а не веб-страница",
            .uk: "Ця адреса — керуючий сервер для ваших пристроїв, а не вебсторінка",
            .it: "Questo indirizzo è il server di controllo dei tuoi dispositivi, non una pagina web",
            .ja: "このアドレスはデバイスの管理サーバーであり、Web ページではありません",
            .zh: "该地址是设备的控制服务器，不是网页"
        ])
    }

    public static func headscaleCreateUserNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Create a user and a join key on the server",
            .de: "Benutzer und Beitrittsschlüssel auf dem Server anlegen",
            .fr: "Créez un utilisateur et une clé d’adhésion sur le serveur",
            .es: "Crea un usuario y una clave de incorporación en el servidor",
            .ru: "Заведите пользователя и ключ подключения на сервере",
            .uk: "Створіть користувача та ключ підключення на сервері",
            .it: "Crea un utente e una chiave di adesione sul server",
            .ja: "サーバー上でユーザーと参加キーを作成します",
            .zh: "在服务器上创建用户和加入密钥"
        ])
    }

    public static func headscaleJoinNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Then join each device with the official Tailscale client",
            .de: "Dann jedes Gerät mit dem offiziellen Tailscale-Client verbinden",
            .fr: "Puis connectez chaque appareil avec le client Tailscale officiel",
            .es: "Después une cada dispositivo con el cliente oficial de Tailscale",
            .ru: "Затем подключите каждое устройство официальным клиентом Tailscale",
            .uk: "Потім підключіть кожен пристрій офіційним клієнтом Tailscale",
            .it: "Poi collega ogni dispositivo con il client Tailscale ufficiale",
            .ja: "その後、公式 Tailscale クライアントで各デバイスを参加させます",
            .zh: "然后用官方 Tailscale 客户端让每台设备加入"
        ])
    }

    public static func headscaleMagicDNSNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Devices reach each other by name",
            .de: "Geräte erreichen einander über den Namen",
            .fr: "Les appareils se joignent par leur nom",
            .es: "Los dispositivos se alcanzan por su nombre",
            .ru: "Устройства находят друг друга по имени",
            .uk: "Пристрої знаходять одне одного за іменем",
            .it: "I dispositivi si raggiungono per nome",
            .ja: "デバイスは名前で互いに到達できます",
            .zh: "设备之间可通过名称互相访问"
        ])
    }

    public static func meshNodeTitle(_ l: AppLanguage) -> String {
        l.pick([
            .en: "This server inside the mesh",
            .de: "Dieser Server im Mesh",
            .fr: "Ce serveur dans le maillage",
            .es: "Este servidor dentro de la malla",
            .ru: "Этот сервер внутри mesh-сети",
            .uk: "Цей сервер усередині mesh-мережі",
            .it: "Questo server nella rete mesh",
            .ja: "メッシュ内のこのサーバー",
            .zh: "网状网络中的本服务器"
        ])
    }

    public static func meshNodeExplainNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Your devices reach this server by this name once they join",
            .de: "Ihre Geräte erreichen diesen Server nach dem Beitritt unter diesem Namen",
            .fr: "Vos appareils joignent ce serveur sous ce nom une fois connectés",
            .es: "Tus dispositivos llegan a este servidor con este nombre una vez unidos",
            .ru: "После подключения ваши устройства обращаются к серверу по этому имени",
            .uk: "Після підключення ваші пристрої звертаються до сервера за цим іменем",
            .it: "Una volta collegati, i tuoi dispositivi raggiungono il server con questo nome",
            .ja: "参加後、デバイスはこの名前でこのサーバーに接続します",
            .zh: "设备加入后即可通过该名称访问本服务器"
        ])
    }

    public static func meshNodeJoinedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The server joined its own mesh as",
            .de: "Der Server ist seinem eigenen Mesh beigetreten als",
            .fr: "Le serveur a rejoint son propre maillage sous le nom",
            .es: "El servidor se unió a su propia malla como",
            .ru: "Сервер подключился к своей же mesh-сети как",
            .uk: "Сервер підключився до власної mesh-мережі як",
            .it: "Il server si è unito alla propria rete mesh come",
            .ja: "サーバーが自身のメッシュに参加しました:",
            .zh: "服务器已加入自身的网状网络，名称为"
        ])
    }

    public static func meshNodeNoKeyNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "could not mint a join key — the server will not be in its own mesh until one is given",
            .de: "Beitrittsschlüssel konnte nicht erstellt werden — der Server bleibt bis dahin nicht im eigenen Mesh",
            .fr: "impossible de créer une clé d’adhésion — le serveur restera hors de son propre maillage",
            .es: "no se pudo crear una clave de incorporación — el servidor no estará en su propia malla",
            .ru: "не удалось выпустить ключ подключения — сервер не войдёт в собственную mesh-сеть, пока ключ не выдан",
            .uk: "не вдалося випустити ключ підключення — сервер не ввійде у власну mesh-мережу, доки ключа немає",
            .it: "impossibile creare una chiave di adesione — il server resterà fuori dalla propria rete mesh",
            .ja: "参加キーを発行できませんでした。キーを与えるまでサーバーは自身のメッシュに入りません",
            .zh: "无法签发加入密钥——在提供密钥之前服务器不会加入自身的网状网络"
        ])
    }

    public static func adguardDoHNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DNS-over-HTTPS for your devices",
            .de: "DNS-over-HTTPS für Ihre Geräte",
            .fr: "DNS-over-HTTPS pour vos appareils",
            .es: "DNS-over-HTTPS para sus dispositivos",
            .ru: "DNS-over-HTTPS для ваших устройств",
            .uk: "DNS-over-HTTPS для ваших пристроїв",
            .it: "DNS-over-HTTPS per i tuoi dispositivi",
            .ja: "デバイス向けの DNS-over-HTTPS",
            .zh: "供你的设备使用的 DNS-over-HTTPS"
        ])
    }

    public static func adguardPlainDNSNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Plain DNS on port 53 answers on this server only: a resolver open to the internet is abused for amplification attacks within days.",
            .de: "Klassisches DNS auf Port 53 antwortet nur auf diesem Server: ein im Internet offener Resolver wird binnen Tagen für Amplification-Angriffe missbraucht.",
            .fr: "Le DNS classique sur le port 53 ne répond que sur ce serveur : un résolveur ouvert sur internet est détourné pour des attaques par amplification en quelques jours.",
            .es: "El DNS clásico en el puerto 53 solo responde en este servidor: un resolutor abierto a internet se usa para ataques de amplificación en pocos días.",
            .ru: "Обычный DNS на порту 53 отвечает только на этом сервере: открытый в интернет резолвер за считанные дни используют для атак усиления.",
            .uk: "Звичайний DNS на порту 53 відповідає лише на цьому сервері: відкритий в інтернет резолвер за лічені дні використають для атак підсилення.",
            .it: "Il DNS classico sulla porta 53 risponde solo su questo server: un resolver aperto su internet viene sfruttato per attacchi di amplificazione in pochi giorni.",
            .ja: "ポート 53 の通常の DNS はこのサーバー内でのみ応答します。インターネットに開いたリゾルバは数日で増幅攻撃に悪用されます。",
            .zh: "端口 53 上的普通 DNS 仅在本服务器内响应：对互联网开放的解析器几天内就会被用于放大攻击。"
        ])
    }

    // MARK: - Jellyfin

    // MARK: - Minecraft

    /// Label for the server flavour on the report line
    public static func minecraftFlavourLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Server type",
            .de: "Servertyp",
            .fr: "Type de serveur",
            .es: "Tipo de servidor",
            .ru: "Тип сервера",
            .uk: "Тип сервера",
            .it: "Tipo di server",
            .ja: "サーバーの種類",
            .zh: "服务器类型"
        ])
    }

    public static func minecraftEULANotAccepted(_ l: AppLanguage) -> String {
        l.pick([
            .en: "NOT STARTED: Mojang's EULA is not accepted. Accept it in the app and reinstall.",
            .de: "NICHT GESTARTET: Mojangs EULA ist nicht akzeptiert. In der App akzeptieren und neu installieren.",
            .fr: "NON DEMARRE : le CLUF de Mojang n'est pas accepte. Acceptez-le dans l'app et reinstallez.",
            .es: "NO INICIADO: no se ha aceptado el EULA de Mojang. Acepte en la app y reinstale.",
            .ru: "НЕ ЗАПУЩЕН: лицензия Mojang не принята. Примите её в приложении и переустановите.",
            .uk: "НЕ ЗАПУЩЕНО: ліцензію Mojang не прийнято. Прийміть її в застосунку і перевстановіть.",
            .it: "NON AVVIATO: l'EULA di Mojang non e accettato. Accettalo nell'app e reinstalla.",
            .ja: "起動していません: Mojang の EULA が未承諾です。アプリで承諾して再インストールしてください。",
            .zh: "未启动：尚未接受 Mojang 的 EULA。请在应用中接受后重新安装。"
        ])
    }

    /// No whitelist: anyone who knows the address can join
    public static func minecraftVersionFollowsLatest(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Version: latest. A restart after a new release moves this world to it.",
            .de: "Version: neueste. Ein Neustart nach einer neuen Ausgabe verschiebt diese Welt dorthin.",
            .fr: "Version : la plus recente. Un redemarrage apres une nouvelle sortie y deplace ce monde.",
            .es: "Version: la mas reciente. Un reinicio tras una nueva version mueve este mundo a ella.",
            .ru: "Версия: последняя. Перезапуск после нового релиза переносит этот мир на него.",
            .uk: "Версія: остання. Перезапуск після нового релізу переносить цей світ на нього.",
            .it: "Versione: la piu recente. Un riavvio dopo una nuova uscita sposta questo mondo su di essa.",
            .ja: "バージョン: 最新。新しいリリース後の再起動で、このワールドはそちらへ移ります。",
            .zh: "版本：最新。新版本发布后重启会把这个世界迁移过去。"
        ])
    }

    /// Label for the mod list on the report line
    public static func minecraftModsLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mods",
            .de: "Mods",
            .fr: "Mods",
            .es: "Mods",
            .ru: "Моды",
            .uk: "Моди",
            .it: "Mod",
            .ja: "Mod",
            .zh: "模组"
        ])
    }

    public static func minecraftModsNeedLoader(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mods are listed, but a Vanilla server loads none. Pick Fabric or Forge (mods), or Paper (plugins).",
            .de: "Mods sind eingetragen, ein Vanilla-Server ladt aber keine. Wahle Fabric oder Forge (Mods) oder Paper (Plugins).",
            .fr: "Des mods sont listes, mais un serveur Vanilla n'en charge aucun. Choisissez Fabric ou Forge (mods), ou Paper (plugins).",
            .es: "Hay mods en la lista, pero un servidor Vanilla no carga ninguno. Elija Fabric o Forge (mods), o Paper (plugins).",
            .ru: "Моды указаны, но сервер Vanilla не загружает ни одного. Выберите Fabric или Forge (моды) либо Paper (плагины).",
            .uk: "Моди вказано, але сервер Vanilla не завантажує жодного. Виберiть Fabric або Forge (моди) чи Paper (плагiни).",
            .it: "Sono elencate delle mod, ma un server Vanilla non ne carica nessuna. Scegli Fabric o Forge (mod), oppure Paper (plugin).",
            .ja: "Mod が指定されていますが、Vanilla サーバーはどれも読み込みません。Fabric か Forge (Mod)、または Paper (プラグイン) を選んでください。",
            .zh: "已列出模组，但 Vanilla 服务器不会加载任何模组。请选择 Fabric 或 Forge（模组）或 Paper（插件）。"
        ])
    }

    public static func minecraftModsClientSide(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Players need the same mods installed in their game to join.",
            .de: "Spieler brauchen dieselben Mods in ihrem Spiel, um beizutreten.",
            .fr: "Les joueurs doivent avoir les memes mods dans leur jeu pour se connecter.",
            .es: "Los jugadores necesitan los mismos mods en su juego para entrar.",
            .ru: "Чтобы зайти, у игроков должны стоять те же моды.",
            .uk: "Щоб зайти, у гравцiв мають бути тi самi моди.",
            .it: "I giocatori devono avere le stesse mod nel loro gioco per entrare.",
            .ja: "参加するには、プレイヤーの側にも同じ Mod が必要です。",
            .zh: "玩家需要在自己的游戏里安装相同的模组才能加入。"
        ])
    }

    public static func minecraftNoWhitelist(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No whitelist: anyone who knows the address can join.",
            .de: "Keine Whitelist: jeder, der die Adresse kennt, kann beitreten.",
            .fr: "Pas de liste blanche : quiconque connait l'adresse peut se connecter.",
            .es: "Sin lista blanca: cualquiera que sepa la direccion puede entrar.",
            .ru: "Без белого списка: зайти может любой, кто знает адрес.",
            .uk: "Без білого списку: увійти може будь-хто, хто знає адресу.",
            .it: "Nessuna whitelist: chiunque conosca l'indirizzo puo entrare.",
            .ja: "ホワイトリストなし: アドレスを知っていれば誰でも参加できます。",
            .zh: "没有白名单：知道地址的人都能加入。"
        ])
    }

    /// Bedrock on ARM runs the x86-64 server under box64
    public static func minecraftBedrockOnArm(_ l: AppLanguage) -> String {
        l.pick([
            .en: "On ARM machines this runs the x86-64 server under emulation (box64): slower, and only on kernels with 4 KB pages (not the Raspberry Pi 5 default).",
            .de: "Auf ARM-Maschinen laeuft der x86-64-Server unter Emulation (box64): langsamer und nur mit einem Kernel mit 4-KB-Seiten (nicht der Standard des Raspberry Pi 5).",
            .fr: "Sur les machines ARM, le serveur x86-64 tourne sous emulation (box64) : plus lent, et seulement avec un noyau a pages de 4 Ko (pas celui du Raspberry Pi 5 par defaut).",
            .es: "En maquinas ARM ejecuta el servidor x86-64 bajo emulacion (box64): mas lento, y solo con un kernel de paginas de 4 KB (no el de serie del Raspberry Pi 5).",
            .ru: "На ARM-машинах это x86-64 сервер под эмуляцией (box64): медленнее и только с ядром на страницах 4 КБ (у Raspberry Pi 5 по умолчанию не так).",
            .uk: "На ARM-машинах це x86-64 сервер під емуляцією (box64): повільніше і лише з ядром на сторінках 4 КБ (у Raspberry Pi 5 типово не так).",
            .it: "Su macchine ARM esegue il server x86-64 in emulazione (box64): piu lento, e solo con un kernel a pagine da 4 KB (non quello predefinito del Raspberry Pi 5).",
            .ja: "ARM マシンでは x86-64 のサーバーをエミュレーション (box64) で動かします。遅くなり、4 KB ページのカーネルでしか動きません (Raspberry Pi 5 の既定とは異なります)。",
            .zh: "在 ARM 机器上，这是通过模拟 (box64) 运行的 x86-64 服务器：速度更慢，且只能在 4 KB 页的内核上运行（Raspberry Pi 5 默认不是）。"
        ])
    }

    /// Bedrock left stopped on a kernel the emulator cannot use
    public static func minecraftBedrockNeedsSmallPages(_ l: AppLanguage) -> String {
        l.pick([
            .en: "not started: the x86 emulator needs a kernel with 4 KB pages. On a Raspberry Pi 5 add kernel=kernel8.img to /boot/firmware/config.txt and reboot.",
            .de: "nicht gestartet: der x86-Emulator braucht einen Kernel mit 4-KB-Seiten. Auf einem Raspberry Pi 5 kernel=kernel8.img in /boot/firmware/config.txt eintragen und neu starten.",
            .fr: "non demarre : l'emulateur x86 a besoin d'un noyau a pages de 4 Ko. Sur un Raspberry Pi 5, ajoutez kernel=kernel8.img dans /boot/firmware/config.txt et redemarrez.",
            .es: "no iniciado: el emulador x86 necesita un kernel con paginas de 4 KB. En un Raspberry Pi 5 anade kernel=kernel8.img a /boot/firmware/config.txt y reinicia.",
            .ru: "не запущен: эмулятору x86 нужно ядро со страницами 4 КБ. На Raspberry Pi 5 добавьте kernel=kernel8.img в /boot/firmware/config.txt и перезагрузите.",
            .uk: "не запущено: емулятору x86 потрібне ядро зі сторінками 4 КБ. На Raspberry Pi 5 додайте kernel=kernel8.img у /boot/firmware/config.txt і перезавантажте.",
            .it: "non avviato: l'emulatore x86 richiede un kernel con pagine da 4 KB. Su un Raspberry Pi 5 aggiungi kernel=kernel8.img a /boot/firmware/config.txt e riavvia.",
            .ja: "起動していません: x86 エミュレーターには 4 KB ページのカーネルが必要です。Raspberry Pi 5 では /boot/firmware/config.txt に kernel=kernel8.img を追加して再起動してください。",
            .zh: "未启动：x86 模拟器需要 4 KB 页的内核。在 Raspberry Pi 5 上，请在 /boot/firmware/config.txt 中加入 kernel=kernel8.img 并重启。"
        ])
    }

    public static func craftyFirstLogin(_ l: AppLanguage) -> String {
        l.pick([
            .en: "First login is printed on the server in",
            .de: "Erster Login steht auf dem Server in",
            .fr: "Le premier identifiant est ecrit sur le serveur dans",
            .es: "El primer acceso se escribe en el servidor en",
            .ru: "Первый логин напечатан на сервере в",
            .uk: "Перший логін надруковано на сервері в",
            .it: "Il primo accesso e scritto sul server in",
            .ja: "最初のログイン情報はサーバー上のこのファイルにあります:",
            .zh: "首次登录信息写在服务器上的这个文件里：",
        ])
    }

    public static func jellyfinAdminWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and finish the setup wizard — until you do, whoever opens the page becomes the administrator.",
            .de: "WICHTIG: Öffnen Sie diese URL sofort und schließen Sie den Einrichtungsassistenten ab — bis dahin wird jeder, der die Seite öffnet, zum Administrator.",
            .fr: "IMPORTANT : ouvrez cette URL dès maintenant et terminez l'assistant de configuration — d'ici là, quiconque ouvre la page devient administrateur.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y complete el asistente de configuración — hasta entonces, quien abra la página se convierte en administrador.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и пройдите мастер настройки — до этого администратором станет любой, кто откроет страницу.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і пройдіть майстер налаштування — доти адміністратором стане будь-хто, хто відкриє сторінку.",
            .it: "IMPORTANTE: apri questo URL subito e completa la procedura guidata — fino ad allora chiunque apra la pagina diventa amministratore.",
            .ja: "重要：今すぐこの URL を開いて初期設定を完了してください — それまでは、ページを開いた人が管理者になります。",
            .zh: "重要：请立即打开此地址并完成初始设置向导 — 在此之前，打开该页面的人将成为管理员。"
        ])
    }

    /// Label for the media directory line in the report
    public static func jellyfinLibraryLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Media library (mounted read-only)",
            .de: "Medienbibliothek (schreibgeschützt eingebunden)",
            .fr: "Bibliotheque multimedia (montee en lecture seule)",
            .es: "Biblioteca multimedia (montada en solo lectura)",
            .ru: "Медиатека (примонтирована только для чтения)",
            .uk: "Медіатека (змонтована лише для читання)",
            .it: "Libreria multimediale (montata in sola lettura)",
            .ja: "メディアライブラリ（読み取り専用でマウント）",
            .zh: "媒体库（以只读方式挂载）"
        ])
    }

    // MARK: - Forgejo

    public static func forgejoWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Forgejo: waiting for the server to answer",
            .de: "Forgejo: warte auf eine Antwort des Servers",
            .fr: "Forgejo : en attente de la réponse du serveur",
            .es: "Forgejo: esperando la respuesta del servidor",
            .ru: "Forgejo: ожидание ответа сервера",
            .uk: "Forgejo: очікування відповіді сервера",
            .it: "Forgejo: in attesa della risposta del server",
            .ja: "Forgejo: サーバーの応答を待機中",
            .zh: "Forgejo：等待服务器响应"
        ])
    }

    public static func forgejoAdminCreateFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Forgejo: could not create the administrator — create it on the server with: forgejo admin user create",
            .de: "Forgejo: Administrator konnte nicht angelegt werden — legen Sie ihn auf dem Server an mit: forgejo admin user create",
            .fr: "Forgejo : impossible de créer l'administrateur — créez-le sur le serveur avec : forgejo admin user create",
            .es: "Forgejo: no se pudo crear el administrador — créelo en el servidor con: forgejo admin user create",
            .ru: "Forgejo: не удалось создать администратора — создайте его на сервере командой: forgejo admin user create",
            .uk: "Forgejo: не вдалося створити адміністратора — створіть його на сервері командою: forgejo admin user create",
            .it: "Forgejo: impossibile creare l'amministratore — crealo sul server con: forgejo admin user create",
            .ja: "Forgejo: 管理者を作成できませんでした — サーバー上で forgejo admin user create を実行して作成してください",
            .zh: "Forgejo：无法创建管理员 — 请在服务器上使用 forgejo admin user create 创建"
        ])
    }

    public static func forgejoUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Forgejo did not answer in time — the administrator was not created; check the container logs",
            .de: "Forgejo hat nicht rechtzeitig geantwortet — der Administrator wurde nicht angelegt; prüfen Sie die Container-Logs",
            .fr: "Forgejo n'a pas répondu à temps — l'administrateur n'a pas été créé ; consultez les journaux du conteneur",
            .es: "Forgejo no respondió a tiempo — no se creó el administrador; revise los registros del contenedor",
            .ru: "Forgejo не ответил вовремя — администратор не создан; посмотрите логи контейнера",
            .uk: "Forgejo не відповів вчасно — адміністратора не створено; перегляньте логи контейнера",
            .it: "Forgejo non ha risposto in tempo — l'amministratore non è stato creato; controlla i log del container",
            .ja: "Forgejo が時間内に応答しませんでした — 管理者は作成されていません。コンテナのログを確認してください",
            .zh: "Forgejo 未在时限内响应 — 管理员尚未创建；请检查容器日志"
        ])
    }

    public static func forgejoRegistrationClosedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Registration is closed — add further users in Site Administration.",
            .de: "Registrierung ist geschlossen — weitere Benutzer legen Sie in der Website-Verwaltung an.",
            .fr: "L'inscription est fermée — ajoutez d'autres utilisateurs dans l'administration du site.",
            .es: "El registro está cerrado — añada más usuarios en la administración del sitio.",
            .ru: "Регистрация закрыта — новых пользователей заводите в администрировании сайта.",
            .uk: "Реєстрацію закрито — нових користувачів створюйте в адмініструванні сайту.",
            .it: "La registrazione è chiusa — aggiungi altri utenti nell'amministrazione del sito.",
            .ja: "登録は閉じています — 追加のユーザーはサイト管理から作成してください。",
            .zh: "注册已关闭 — 请在站点管理中添加其他用户。"
        ])
    }

    public static func forgejoSSHNote(_ l: AppLanguage, host: String, port: Int) -> String {
        l.pick([
            .en: "Git over SSH: port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .de: "Git über SSH: Port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .fr: "Git via SSH : port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .es: "Git por SSH: puerto \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .ru: "Git по SSH: порт \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .uk: "Git через SSH: порт \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .it: "Git via SSH: porta \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .ja: "SSH 経由の Git: ポート \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .zh: "通过 SSH 使用 Git：端口 \(port) — git clone ssh://git@\(host):\(port)/user/repo.git"
        ])
    }

    public static func forgejoSSHDisabledNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Git over SSH is off — clone and push over HTTPS with an access token.",
            .de: "Git über SSH ist aus — klonen und pushen Sie über HTTPS mit einem Zugriffstoken.",
            .fr: "Git via SSH est désactivé — clonez et poussez via HTTPS avec un jeton d'accès.",
            .es: "Git por SSH está desactivado — clone y suba por HTTPS con un token de acceso.",
            .ru: "Git по SSH выключен — клонируйте и отправляйте изменения по HTTPS с токеном доступа.",
            .uk: "Git через SSH вимкнено — клонуйте та надсилайте зміни через HTTPS з токеном доступу.",
            .it: "Git via SSH è disattivato — clona e invia tramite HTTPS con un token di accesso.",
            .ja: "SSH 経由の Git は無効です — アクセストークンを使って HTTPS でクローンおよびプッシュしてください。",
            .zh: "已关闭通过 SSH 使用 Git — 请使用访问令牌通过 HTTPS 克隆和推送。"
        ])
    }

    // MARK: - GitLab

    /// Heartbeat while the omnibus image runs its first reconfigure
    public static func gitlabWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "GitLab: waiting for the first start to finish — this takes several minutes",
            .de: "GitLab: warte auf den Abschluss des ersten Starts — das dauert einige Minuten",
            .fr: "GitLab : en attente de la fin du premier démarrage — cela prend plusieurs minutes",
            .es: "GitLab: esperando a que termine el primer arranque — tarda varios minutos",
            .ru: "GitLab: ожидание завершения первого запуска — это занимает несколько минут",
            .uk: "GitLab: очікування завершення першого запуску — це триває кілька хвилин",
            .it: "GitLab: in attesa del completamento del primo avvio — richiede alcuni minuti",
            .ja: "GitLab: 初回起動の完了を待機中 — 数分かかります",
            .zh: "GitLab：等待首次启动完成 — 需要几分钟"
        ])
    }

    /// The deadline expired
    public static func gitlabStillStarting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "GitLab has not finished starting yet — it continues in the background; sign-up must then be closed in the Admin Area",
            .de: "GitLab ist noch nicht fertig gestartet — es läuft im Hintergrund weiter; die Registrierung muss dann im Admin-Bereich geschlossen werden",
            .fr: "GitLab n'a pas fini de démarrer — il continue en arrière-plan ; l'inscription devra alors être fermée dans la zone d'administration",
            .es: "GitLab aún no ha terminado de arrancar — continúa en segundo plano; entonces hay que cerrar el registro en el área de administración",
            .ru: "GitLab ещё не завершил запуск — он продолжается в фоне; регистрацию тогда нужно закрыть в панели администратора",
            .uk: "GitLab ще не завершив запуск — він триває у фоні; реєстрацію тоді потрібно закрити в панелі адміністратора",
            .it: "GitLab non ha ancora finito di avviarsi — prosegue in background; la registrazione va poi chiusa nell'area di amministrazione",
            .ja: "GitLab の起動はまだ完了していません — バックグラウンドで継続します。その場合は管理エリアで登録を閉じてください",
            .zh: "GitLab 尚未启动完成 — 它会在后台继续；届时请在管理区域关闭注册"
        ])
    }

    public static func gitlabSignupCloseFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "GitLab: could not close registration — turn off Sign-up enabled in the Admin Area, General settings",
            .de: "GitLab: Registrierung konnte nicht geschlossen werden — deaktivieren Sie die Registrierung im Admin-Bereich unter Allgemein",
            .fr: "GitLab : impossible de fermer l'inscription — désactivez l'inscription dans la zone d'administration, paramètres généraux",
            .es: "GitLab: no se pudo cerrar el registro — desactive el registro en el área de administración, ajustes generales",
            .ru: "GitLab: не удалось закрыть регистрацию — отключите её в панели администратора, общие настройки",
            .uk: "GitLab: не вдалося закрити реєстрацію — вимкніть її в панелі адміністратора, загальні налаштування",
            .it: "GitLab: impossibile chiudere la registrazione — disattivala nell'area di amministrazione, impostazioni generali",
            .ja: "GitLab: 登録を閉じられませんでした — 管理エリアの一般設定でサインアップを無効にしてください",
            .zh: "GitLab：无法关闭注册 — 请在管理区域的常规设置中关闭注册"
        ])
    }

    public static func gitlabRegistrationClosedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Registration is closed — add further users in the Admin Area.",
            .de: "Registrierung ist geschlossen — weitere Benutzer legen Sie im Admin-Bereich an.",
            .fr: "L'inscription est fermée — ajoutez d'autres utilisateurs dans la zone d'administration.",
            .es: "El registro está cerrado — añada más usuarios en el área de administración.",
            .ru: "Регистрация закрыта — новых пользователей заводите в панели администратора.",
            .uk: "Реєстрацію закрито — нових користувачів створюйте в панелі адміністратора.",
            .it: "La registrazione è chiusa — aggiungi altri utenti nell'area di amministrazione.",
            .ja: "登録は閉じています — 追加のユーザーは管理エリアから作成してください。",
            .zh: "注册已关闭 — 请在管理区域添加其他用户。"
        ])
    }

    public static func gitlabFirstStartNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The first start takes several minutes — until it finishes the address answers with an error.",
            .de: "Der erste Start dauert einige Minuten — bis dahin antwortet die Adresse mit einem Fehler.",
            .fr: "Le premier démarrage prend plusieurs minutes — jusque-là l'adresse répond par une erreur.",
            .es: "El primer arranque tarda varios minutos — hasta que termine, la dirección responde con un error.",
            .ru: "Первый запуск занимает несколько минут — до его окончания адрес отвечает ошибкой.",
            .uk: "Перший запуск триває кілька хвилин — до його завершення адреса відповідає помилкою.",
            .it: "Il primo avvio richiede alcuni minuti — fino ad allora l'indirizzo risponde con un errore.",
            .ja: "初回起動には数分かかります — 完了するまでこのアドレスはエラーを返します。",
            .zh: "首次启动需要几分钟 — 在此之前该地址会返回错误。"
        ])
    }

    public static func gitlabSSHNote(_ l: AppLanguage, host: String, port: Int) -> String {
        l.pick([
            .en: "Git over SSH: port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .de: "Git über SSH: Port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .fr: "Git via SSH : port \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .es: "Git por SSH: puerto \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .ru: "Git по SSH: порт \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .uk: "Git через SSH: порт \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .it: "Git via SSH: porta \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .ja: "SSH 経由の Git: ポート \(port) — git clone ssh://git@\(host):\(port)/user/repo.git",
            .zh: "通过 SSH 使用 Git：端口 \(port) — git clone ssh://git@\(host):\(port)/user/repo.git"
        ])
    }

    public static func gitlabSSHDisabledNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Git over SSH is off — clone and push over HTTPS with an access token.",
            .de: "Git über SSH ist aus — klonen und pushen Sie über HTTPS mit einem Zugriffstoken.",
            .fr: "Git via SSH est désactivé — clonez et poussez via HTTPS avec un jeton d'accès.",
            .es: "Git por SSH está desactivado — clone y suba por HTTPS con un token de acceso.",
            .ru: "Git по SSH выключен — клонируйте и отправляйте изменения по HTTPS с токеном доступа.",
            .uk: "Git через SSH вимкнено — клонуйте та надсилайте зміни через HTTPS з токеном доступу.",
            .it: "Git via SSH è disattivato — clona e invia tramite HTTPS con un token di accesso.",
            .ja: "SSH 経由の Git は無効です — アクセストークンを使って HTTPS でクローンおよびプッシュしてください。",
            .zh: "已关闭通过 SSH 使用 Git — 请使用访问令牌通过 HTTPS 克隆和推送。"
        ])
    }

    // MARK: - Mailu

    public static func mailuWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mailu: waiting for the admin service to answer",
            .de: "Mailu: warten auf eine Antwort des Admin-Dienstes",
            .fr: "Mailu : en attente de la réponse du service d'administration",
            .es: "Mailu: esperando respuesta del servicio de administración",
            .ru: "Mailu: ждём ответа админ-сервиса",
            .uk: "Mailu: чекаємо на відповідь адмін-сервісу",
            .it: "Mailu: in attesa della risposta del servizio di amministrazione",
            .ja: "Mailu：管理サービスの応答を待っています",
            .zh: "Mailu：正在等待管理服务响应"
        ])
    }

    public static func mailuDomainImportFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mailu: the mail domains were NOT created. Mailu itself is running: add them under Domains in its admin UI, or re-run the setup.",
            .de: "Mailu: Die Mail-Domains wurden NICHT angelegt. Mailu selbst läuft: Legen Sie sie in der Admin-UI unter Domains an oder führen Sie das Setup erneut aus.",
            .fr: "Mailu : les domaines de messagerie n'ont PAS été créés. Mailu fonctionne : ajoutez-les dans Domaines de son interface d'administration, ou relancez l'installation.",
            .es: "Mailu: los dominios de correo NO se crearon. Mailu está en marcha: añádelos en Dominios de su panel de administración o vuelve a ejecutar la instalación.",
            .ru: "Mailu: почтовые домены НЕ созданы. Сам Mailu работает: добавьте их в разделе Domains его админки или перезапустите установку.",
            .uk: "Mailu: поштові домени НЕ створено. Сам Mailu працює: додайте їх у розділі Domains його адмінки або перезапустіть встановлення.",
            .it: "Mailu: i domini di posta NON sono stati creati. Mailu è in funzione: aggiungili in Domini nel suo pannello di amministrazione o ripeti l'installazione.",
            .ja: "Mailu：メールドメインは作成されませんでした。Mailu 自体は稼働しています。管理画面の Domains から追加するか、セットアップをやり直してください。",
            .zh: "Mailu：邮件域名未创建。Mailu 本身正在运行：请在其管理界面的 Domains 中添加，或重新运行安装。"
        ])
    }

    public static func mailuUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mailu did not answer in time — the mail domains and DKIM keys were not created; check the container logs",
            .de: "Mailu hat nicht rechtzeitig geantwortet — Mail-Domains und DKIM-Schlüssel wurden nicht angelegt; prüfen Sie die Container-Logs",
            .fr: "Mailu n'a pas répondu à temps — les domaines et les clés DKIM n'ont pas été créés ; consultez les journaux du conteneur",
            .es: "Mailu no respondió a tiempo: los dominios y las claves DKIM no se crearon; revisa los registros del contenedor",
            .ru: "Mailu не ответил вовремя — почтовые домены и DKIM-ключи не созданы; смотрите логи контейнера",
            .uk: "Mailu не відповів вчасно — поштові домени та DKIM-ключі не створено; дивіться логи контейнера",
            .it: "Mailu non ha risposto in tempo: i domini e le chiavi DKIM non sono stati creati; controlla i log del container",
            .ja: "Mailu が時間内に応答しませんでした — メールドメインと DKIM キーは作成されていません。コンテナのログを確認してください",
            .zh: "Mailu 未及时响应 — 邮件域名和 DKIM 密钥未创建；请查看容器日志"
        ])
    }

    public static func mailuDKIMPendingNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "not ready yet — open Domains in the Mailu admin UI to see the DKIM record",
            .de: "noch nicht bereit — öffnen Sie Domains in der Mailu-Admin-UI, um den DKIM-Eintrag zu sehen",
            .fr: "pas encore prêt — ouvrez Domaines dans l'interface d'administration Mailu pour voir l'enregistrement DKIM",
            .es: "aún no está listo: abre Dominios en el panel de Mailu para ver el registro DKIM",
            .ru: "ещё не готово — откройте Domains в админке Mailu, чтобы увидеть DKIM-запись",
            .uk: "ще не готово — відкрийте Domains в адмінці Mailu, щоб побачити DKIM-запис",
            .it: "non ancora pronto: apri Domini nel pannello di Mailu per vedere il record DKIM",
            .ja: "まだ準備できていません — Mailu の管理画面の Domains で DKIM レコードを確認してください",
            .zh: "尚未就绪 — 请在 Mailu 管理界面的 Domains 中查看 DKIM 记录"
        ])
    }

    public static func webmailLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Webmail",
            .de: "Webmail",
            .fr: "Webmail",
            .es: "Correo web",
            .ru: "Веб-почта",
            .uk: "Вебпошта",
            .it: "Webmail",
            .ja: "ウェブメール",
            .zh: "网页邮箱"
        ])
    }

    public static func dkimRecordsLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DKIM records (add them to DNS)",
            .de: "DKIM-Einträge (in DNS eintragen)",
            .fr: "Enregistrements DKIM (à ajouter au DNS)",
            .es: "Registros DKIM (añádelos al DNS)",
            .ru: "DKIM-записи (добавьте их в DNS)",
            .uk: "DKIM-записи (додайте їх до DNS)",
            .it: "Record DKIM (aggiungili al DNS)",
            .ja: "DKIM レコード（DNS に追加してください）",
            .zh: "DKIM 记录（请添加到 DNS）"
        ])
    }

    /// Which client ports the engine actually answers on
    public static func mailuClientPortsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Mail clients: IMAP 993 and SMTP 465, both with TLS (ports 143 and 587 are not served)",
            .de: "Mail-Programme: IMAP 993 und SMTP 465, beide mit TLS (Ports 143 und 587 werden nicht bedient)",
            .fr: "Clients de messagerie : IMAP 993 et SMTP 465, tous deux en TLS (les ports 143 et 587 ne sont pas servis)",
            .es: "Clientes de correo: IMAP 993 y SMTP 465, ambos con TLS (los puertos 143 y 587 no se sirven)",
            .ru: "Почтовые клиенты: IMAP 993 и SMTP 465, оба с TLS (порты 143 и 587 не обслуживаются)",
            .uk: "Поштові клієнти: IMAP 993 і SMTP 465, обидва з TLS (порти 143 і 587 не обслуговуються)",
            .it: "Client di posta: IMAP 993 e SMTP 465, entrambi con TLS (le porte 143 e 587 non sono servite)",
            .ja: "メールクライアント：IMAP 993 と SMTP 465（どちらも TLS）。ポート 143 と 587 は提供されません",
            .zh: "邮件客户端：IMAP 993 与 SMTP 465，均使用 TLS（不提供 143 和 587 端口）"
        ])
    }

    // MARK: - Docker Mailserver

    public static func dmsWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Docker Mailserver: waiting for the container to finish its own setup",
            .de: "Docker Mailserver: warten, bis der Container sein Setup abgeschlossen hat",
            .fr: "Docker Mailserver : attente de la fin de sa propre installation",
            .es: "Docker Mailserver: esperando a que el contenedor termine su configuración",
            .ru: "Docker Mailserver: ждём, пока контейнер закончит собственную настройку",
            .uk: "Docker Mailserver: чекаємо, доки контейнер завершить власне налаштування",
            .it: "Docker Mailserver: in attesa che il container completi la propria configurazione",
            .ja: "Docker Mailserver：コンテナ自身のセットアップ完了を待っています",
            .zh: "Docker Mailserver：正在等待容器完成自身初始化"
        ])
    }

    public static func dmsPlaceholderCertFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Docker Mailserver: could not create the temporary certificate — the mail container will not start until the real certificate arrives",
            .de: "Docker Mailserver: Das temporäre Zertifikat konnte nicht erstellt werden — der Mail-Container startet erst mit dem echten Zertifikat",
            .fr: "Docker Mailserver : impossible de créer le certificat temporaire — le conteneur mail ne démarrera qu'avec le vrai certificat",
            .es: "Docker Mailserver: no se pudo crear el certificado temporal: el contenedor de correo no arrancará hasta que llegue el certificado real",
            .ru: "Docker Mailserver: не удалось создать временный сертификат — почтовый контейнер не стартует, пока не приедет настоящий",
            .uk: "Docker Mailserver: не вдалося створити тимчасовий сертифікат — поштовий контейнер не стартує, доки не приїде справжній",
            .it: "Docker Mailserver: impossibile creare il certificato temporaneo — il container di posta non partirà finché non arriva quello reale",
            .ja: "Docker Mailserver：一時証明書を作成できませんでした — 本物の証明書が届くまでメールコンテナは起動しません",
            .zh: "Docker Mailserver：无法创建临时证书 — 在真实证书到位前邮件容器不会启动"
        ])
    }

    public static func dmsMailboxFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Docker Mailserver: the first mailbox was NOT created. The server is running: add it from the app, or with 'setup email add' on the server.",
            .de: "Docker Mailserver: Das erste Postfach wurde NICHT angelegt. Der Server läuft: Legen Sie es in der App an oder mit 'setup email add' auf dem Server.",
            .fr: "Docker Mailserver : la première boîte n'a PAS été créée. Le serveur fonctionne : ajoutez-la depuis l'application ou avec 'setup email add' sur le serveur.",
            .es: "Docker Mailserver: el primer buzón NO se creó. El servidor está en marcha: añádelo desde la aplicación o con 'setup email add' en el servidor.",
            .ru: "Docker Mailserver: первый ящик НЕ создан. Сервер работает: заведите его из приложения или командой 'setup email add' на сервере.",
            .uk: "Docker Mailserver: першу скриньку НЕ створено. Сервер працює: заведіть її з застосунку або командою 'setup email add' на сервері.",
            .it: "Docker Mailserver: la prima casella NON è stata creata. Il server è in funzione: aggiungila dall'app o con 'setup email add' sul server.",
            .ja: "Docker Mailserver：最初のメールボックスは作成されませんでした。サーバーは稼働しています。アプリから、またはサーバー上の 'setup email add' で追加してください。",
            .zh: "Docker Mailserver：首个邮箱未创建。服务器正在运行：可从应用中添加，或在服务器上执行 'setup email add'。"
        ])
    }

    public static func dmsUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Docker Mailserver did not finish its setup in time — no mailbox and no DKIM keys were created; check the container logs",
            .de: "Docker Mailserver hat sein Setup nicht rechtzeitig beendet — weder Postfach noch DKIM-Schlüssel wurden angelegt; prüfen Sie die Container-Logs",
            .fr: "Docker Mailserver n'a pas terminé son installation à temps — ni boîte ni clés DKIM créées ; consultez les journaux du conteneur",
            .es: "Docker Mailserver no terminó su configuración a tiempo: no se creó ni el buzón ni las claves DKIM; revisa los registros del contenedor",
            .ru: "Docker Mailserver не закончил настройку вовремя — ни ящик, ни DKIM-ключи не созданы; смотрите логи контейнера",
            .uk: "Docker Mailserver не завершив налаштування вчасно — ні скриньку, ні DKIM-ключі не створено; дивіться логи контейнера",
            .it: "Docker Mailserver non ha completato la configurazione in tempo: né casella né chiavi DKIM sono state create; controlla i log del container",
            .ja: "Docker Mailserver がセットアップを時間内に完了しませんでした — メールボックスも DKIM キーも作成されていません。コンテナのログを確認してください",
            .zh: "Docker Mailserver 未及时完成初始化 — 邮箱和 DKIM 密钥均未创建；请查看容器日志"
        ])
    }

    public static func dmsDKIMFailed(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "Docker Mailserver: could not create the DKIM key for \(domain) — add it later from the server",
            .de: "Docker Mailserver: DKIM-Schlüssel für \(domain) konnte nicht erstellt werden — später auf dem Server nachholen",
            .fr: "Docker Mailserver : impossible de créer la clé DKIM pour \(domain) — à refaire plus tard depuis le serveur",
            .es: "Docker Mailserver: no se pudo crear la clave DKIM de \(domain): créala más tarde desde el servidor",
            .ru: "Docker Mailserver: не удалось создать DKIM-ключ для \(domain) — заведите его позже на сервере",
            .uk: "Docker Mailserver: не вдалося створити DKIM-ключ для \(domain) — заведіть його пізніше на сервері",
            .it: "Docker Mailserver: impossibile creare la chiave DKIM per \(domain) — creala più tardi dal server",
            .ja: "Docker Mailserver：\(domain) の DKIM キーを作成できませんでした — 後でサーバー上で作成してください",
            .zh: "Docker Mailserver：无法为 \(domain) 创建 DKIM 密钥 — 请稍后在服务器上创建"
        ])
    }

    public static func dmsDKIMPendingNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "not ready yet — run the DKIM setup again on the server",
            .de: "noch nicht bereit — DKIM-Einrichtung auf dem Server erneut ausführen",
            .fr: "pas encore prêt — relancez la configuration DKIM sur le serveur",
            .es: "aún no está listo: vuelve a ejecutar la configuración DKIM en el servidor",
            .ru: "ещё не готово — перезапустите настройку DKIM на сервере",
            .uk: "ще не готово — перезапустіть налаштування DKIM на сервері",
            .it: "non ancora pronto: riesegui la configurazione DKIM sul server",
            .ja: "まだ準備できていません — サーバーで DKIM のセットアップをやり直してください",
            .zh: "尚未就绪 — 请在服务器上重新运行 DKIM 设置"
        ])
    }

    public static func dmsMailboxesNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Further mailboxes are added from the app — this engine has no web admin of its own",
            .de: "Weitere Postfächer werden in der App angelegt — diese Engine hat keine eigene Web-Administration",
            .fr: "Les autres boîtes s'ajoutent depuis l'application — ce moteur n'a pas d'administration web",
            .es: "Los demás buzones se añaden desde la aplicación: este motor no tiene panel web propio",
            .ru: "Остальные ящики заводятся из приложения — своей веб-админки у этого движка нет",
            .uk: "Решта скриньок заводяться із застосунку — власної вебадмінки цей рушій не має",
            .it: "Le altre caselle si aggiungono dall'app: questo motore non ha un pannello web proprio",
            .ja: "追加のメールボックスはアプリから作成します — このエンジンに独自の管理画面はありません",
            .zh: "其余邮箱通过应用添加 — 该引擎没有自带的网页管理界面"
        ])
    }

    public static func firstMailboxLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "First mailbox",
            .de: "Erstes Postfach",
            .fr: "Première boîte",
            .es: "Primer buzón",
            .ru: "Первый ящик",
            .uk: "Перша скринька",
            .it: "Prima casella",
            .ja: "最初のメールボックス",
            .zh: "首个邮箱"
        ])
    }

    // MARK: - Psono

    public static func psonoWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Psono: waiting for the database to become reachable",
            .de: "Psono: warte, bis die Datenbank erreichbar wird",
            .fr: "Psono : en attente que la base de données devienne accessible",
            .es: "Psono: esperando a que la base de datos esté accesible",
            .ru: "Psono: ждём, пока база данных станет доступна",
            .uk: "Psono: чекаємо, доки база даних стане доступною",
            .it: "Psono: in attesa che il database diventi raggiungibile",
            .ja: "Psono: データベースに到達できるようになるのを待っています",
            .zh: "Psono: 正在等待数据库变为可访问"
        ])
    }

    /// migrate ran after presetup succeeded but itself failed
    public static func psonoMigrateFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Psono: could not apply database migrations — run them manually inside the container (manage.py migrate)",
            .de: "Psono: Datenbankmigrationen konnten nicht angewendet werden — führen Sie sie manuell im Container aus (manage.py migrate)",
            .fr: "Psono : impossible d'appliquer les migrations de la base de données — exécutez-les manuellement dans le conteneur (manage.py migrate)",
            .es: "Psono: no se pudieron aplicar las migraciones de la base de datos — ejecútelas manualmente dentro del contenedor (manage.py migrate)",
            .ru: "Psono: не удалось применить миграции базы данных — примените их вручную внутри контейнера (manage.py migrate)",
            .uk: "Psono: не вдалося застосувати міграції бази даних — застосуйте їх вручну всередині контейнера (manage.py migrate)",
            .it: "Psono: impossibile applicare le migrazioni del database — eseguile manualmente nel container (manage.py migrate)",
            .ja: "Psono: データベースのマイグレーションを適用できませんでした — コンテナ内で手動で実行してください（manage.py migrate）",
            .zh: "Psono: 无法应用数据库迁移 — 请在容器内手动执行（manage.py migrate）"
        ])
    }

    /// createuser/promoteuser/verifyuseremail failed on a fresh install
    public static func psonoAdminCreateFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Psono: could not create the administrator account — create one manually inside the container (manage.py createuser, then promoteuser)",
            .de: "Psono: Administratorkonto konnte nicht angelegt werden — legen Sie eines manuell im Container an (manage.py createuser, danach promoteuser)",
            .fr: "Psono : impossible de créer le compte administrateur — créez-en un manuellement dans le conteneur (manage.py createuser, puis promoteuser)",
            .es: "Psono: no se pudo crear la cuenta de administrador — cree una manualmente dentro del contenedor (manage.py createuser y luego promoteuser)",
            .ru: "Psono: не удалось создать учётную запись администратора — создайте её вручную внутри контейнера (manage.py createuser, затем promoteuser)",
            .uk: "Psono: не вдалося створити обліковий запис адміністратора — створіть його вручну всередині контейнера (manage.py createuser, потім promoteuser)",
            .it: "Psono: impossibile creare l'account amministratore — creane uno manualmente nel container (manage.py createuser, poi promoteuser)",
            .ja: "Psono: 管理者アカウントを作成できませんでした — コンテナ内で手動で作成してください（manage.py createuser の後に promoteuser）",
            .zh: "Psono: 无法创建管理员账户 — 请在容器内手动创建（先执行 manage.py createuser，再执行 promoteuser）"
        ])
    }

    public static func psonoUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Psono did not become reachable in time — the administrator account was not created; re-run the setup or create it manually",
            .de: "Psono wurde nicht rechtzeitig erreichbar — das Administratorkonto wurde nicht angelegt; führen Sie die Einrichtung erneut aus oder legen Sie es manuell an",
            .fr: "Psono n'est pas devenu accessible à temps — le compte administrateur n'a pas été créé ; relancez l'installation ou créez-le manuellement",
            .es: "Psono no estuvo accesible a tiempo — la cuenta de administrador no se creó; vuelva a ejecutar la instalación o créela manualmente",
            .ru: "Psono не стал доступен вовремя — учётная запись администратора не создана; перезапустите установку или создайте её вручную",
            .uk: "Psono не став доступним вчасно — обліковий запис адміністратора не створено; перезапустіть встановлення або створіть його вручну",
            .it: "Psono non è diventato raggiungibile in tempo — l'account amministratore non è stato creato; rieseguire l'installazione o crearlo manualmente",
            .ja: "Psono が時間内に到達可能になりませんでした — 管理者アカウントは作成されていません。セットアップを再実行するか、手動で作成してください",
            .zh: "Psono 未能及时变为可访问 — 管理员账户未被创建；请重新运行安装，或手动创建"
        ])
    }

    // MARK: - Passbolt

    public static func passboltWaiting(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Passbolt: waiting for the server to generate its GPG key and finish installing",
            .de: "Passbolt: warte darauf, dass der Server seinen GPG-Schlüssel erzeugt und die Installation abschließt",
            .fr: "Passbolt : en attente que le serveur génère sa clé GPG et termine l'installation",
            .es: "Passbolt: esperando a que el servidor genere su clave GPG y termine de instalarse",
            .ru: "Passbolt: ждём, пока сервер сгенерирует свой ключ GPG и завершит установку",
            .uk: "Passbolt: чекаємо, доки сервер згенерує свій ключ GPG і завершить встановлення",
            .it: "Passbolt: in attesa che il server generi la sua chiave GPG e completi l'installazione",
            .ja: "Passbolt: サーバーが GPG 鍵を生成しインストールを完了するのを待っています",
            .zh: "Passbolt: 正在等待服务器生成其 GPG 密钥并完成安装"
        ])
    }

    /// register_user itself failed (non-zero exit) on a fresh install
    public static func passboltRegisterFailed(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Passbolt: could not register the administrator — invite one manually inside the container (cake passbolt register_user)",
            .de: "Passbolt: Administrator konnte nicht registriert werden — laden Sie manuell einen im Container ein (cake passbolt register_user)",
            .fr: "Passbolt : impossible d'enregistrer l'administrateur — invitez-en un manuellement dans le conteneur (cake passbolt register_user)",
            .es: "Passbolt: no se pudo registrar al administrador — invite a uno manualmente dentro del contenedor (cake passbolt register_user)",
            .ru: "Passbolt: не удалось зарегистрировать администратора — пригласите его вручную внутри контейнера (cake passbolt register_user)",
            .uk: "Passbolt: не вдалося зареєструвати адміністратора — запросіть його вручну всередині контейнера (cake passbolt register_user)",
            .it: "Passbolt: impossibile registrare l'amministratore — invitane uno manualmente nel container (cake passbolt register_user)",
            .ja: "Passbolt: 管理者を登録できませんでした — コンテナ内で手動で招待してください（cake passbolt register_user）",
            .zh: "Passbolt: 无法注册管理员 — 请在容器内手动邀请（cake passbolt register_user）"
        ])
    }

    public static func passboltRegisterNoURL(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Passbolt: the administrator was registered, but no setup link was found in the output — check the container logs",
            .de: "Passbolt: der Administrator wurde registriert, aber in der Ausgabe wurde kein Einrichtungslink gefunden — prüfen Sie die Container-Logs",
            .fr: "Passbolt : l'administrateur a été enregistré, mais aucun lien de configuration n'a été trouvé dans la sortie — vérifiez les journaux du conteneur",
            .es: "Passbolt: el administrador se registró, pero no se encontró ningún enlace de configuración en la salida — revise los registros del contenedor",
            .ru: "Passbolt: администратор зарегистрирован, но в выводе не найдена ссылка для настройки — проверьте логи контейнера",
            .uk: "Passbolt: адміністратора зареєстровано, але в виводі не знайдено посилання для налаштування — перевірте логи контейнера",
            .it: "Passbolt: l'amministratore è stato registrato, ma nell'output non è stato trovato alcun link di configurazione — controlla i log del container",
            .ja: "Passbolt: 管理者は登録されましたが、出力の中にセットアップリンクが見つかりませんでした — コンテナのログを確認してください",
            .zh: "Passbolt: 管理员已注册，但在输出中未找到设置链接 — 请检查容器日志"
        ])
    }

    public static func passboltUnavailable(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Passbolt did not finish its first start in time — the administrator was NOT invited; re-run the setup once it comes up",
            .de: "Passbolt hat den ersten Start nicht rechtzeitig abgeschlossen — der Administrator wurde NICHT eingeladen; führen Sie die Einrichtung erneut aus, sobald der Dienst läuft",
            .fr: "Passbolt n'a pas terminé son premier démarrage à temps — l'administrateur n'a PAS été invité ; relancez l'installation une fois qu'il est opérationnel",
            .es: "Passbolt no terminó su primer arranque a tiempo — el administrador NO fue invitado; vuelva a ejecutar la instalación cuando esté disponible",
            .ru: "Passbolt не завершил первый запуск вовремя — администратор НЕ приглашён; перезапустите установку, когда сервис поднимется",
            .uk: "Passbolt не завершив перший запуск вчасно — адміністратора НЕ запрошено; перезапустіть встановлення, коли сервіс підніметься",
            .it: "Passbolt non ha completato il primo avvio in tempo — l'amministratore NON è stato invitato; rieseguire l'installazione quando sarà attivo",
            .ja: "Passbolt の初回起動が時間内に完了しませんでした — 管理者は招待されていません。サービスが起動したらセットアップを再実行してください",
            .zh: "Passbolt 首次启动未能及时完成 — 管理员尚未被邀请；请在服务启动后重新运行安装"
        ])
    }

    /// Header above the one-time setup link in the report
    public static func passboltSetupURLLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Finish setting up the administrator (this link works ONCE):",
            .de: "Richten Sie den Administrator fertig ein (dieser Link funktioniert NUR EINMAL):",
            .fr: "Terminez la configuration de l'administrateur (ce lien ne fonctionne qu'UNE SEULE FOIS) :",
            .es: "Termine de configurar al administrador (este enlace funciona UNA SOLA VEZ):",
            .ru: "Завершите настройку администратора (эта ссылка работает ОДИН РАЗ):",
            .uk: "Завершіть налаштування адміністратора (це посилання працює ОДИН РАЗ):",
            .it: "Completa la configurazione dell'amministratore (questo link funziona UNA SOLA VOLTA):",
            .ja: "管理者の設定を完了してください（このリンクは一度だけ使用できます）：",
            .zh: "请完成管理员设置（此链接仅可使用一次）："
        ])
    }

    public static func passboltAlreadyConfiguredNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No setup link available here — if an administrator was already invited, sign in with that account; otherwise check the container logs and invite one manually (cake passbolt register_user).",
            .de: "Hier ist kein Einrichtungslink verfügbar — wenn bereits ein Administrator eingeladen wurde, melden Sie sich mit diesem Konto an; andernfalls prüfen Sie die Container-Logs und laden Sie manuell einen ein (cake passbolt register_user).",
            .fr: "Aucun lien de configuration disponible ici — si un administrateur a déjà été invité, connectez-vous avec ce compte ; sinon, vérifiez les journaux du conteneur et invitez-en un manuellement (cake passbolt register_user).",
            .es: "No hay ningún enlace de configuración disponible aquí — si ya se invitó a un administrador, inicie sesión con esa cuenta; si no, revise los registros del contenedor e invite a uno manualmente (cake passbolt register_user).",
            .ru: "Здесь нет ссылки для настройки — если администратор уже приглашён, войдите под этой учётной записью; иначе проверьте логи контейнера и пригласите его вручную (cake passbolt register_user).",
            .uk: "Тут немає посилання для налаштування — якщо адміністратора вже запрошено, увійдіть під цим обліковим записом; інакше перевірте логи контейнера й запросіть його вручну (cake passbolt register_user).",
            .it: "Qui non è disponibile alcun link di configurazione — se un amministratore è già stato invitato, accedi con quell'account; altrimenti controlla i log del container e invitane uno manualmente (cake passbolt register_user).",
            .ja: "ここにはセットアップリンクがありません — 管理者がすでに招待されている場合はそのアカウントでサインインしてください。そうでない場合はコンテナのログを確認し、手動で招待してください（cake passbolt register_user）。",
            .zh: "此处没有可用的设置链接 — 如果管理员已被邀请，请使用该账户登录；否则请检查容器日志并手动邀请管理员（cake passbolt register_user）。"
        ])
    }

    // MARK: - AI shelf

    public static func ollamaNoModelsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No model is installed — the setup deliberately downloaded none. Add the first one with:",
            .de: "Es ist kein Modell installiert — die Einrichtung hat absichtlich keines heruntergeladen. Fügen Sie das erste so hinzu:",
            .fr: "Aucun modele n'est installe — l'installation n'en a telecharge aucun, volontairement. Ajoutez le premier ainsi :",
            .es: "No hay ningun modelo instalado — la instalacion no descargo ninguno a proposito. Agregue el primero asi:",
            .ru: "Ни одной модели нет — установка намеренно ничего не скачивала. Первую добавьте так:",
            .uk: "Жодної моделі немає — встановлення навмисно нічого не завантажувало. Першу додайте так:",
            .it: "Nessun modello installato — l'installazione non ne ha scaricato nessuno di proposito. Aggiungi il primo cosi:",
            .ja: "モデルは一つも入っていません — セットアップは意図的に何もダウンロードしていません。最初の一つは次のように追加します:",
            .zh: "尚未安装任何模型 — 安装过程有意未下载。用下面的命令添加第一个:"
        ])
    }

    public static func ollamaModelSizeNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "A small model is around 4 GB, a large one around 40 GB — check free disk space first.",
            .de: "Ein kleines Modell belegt etwa 4 GB, ein grosses etwa 40 GB — pruefen Sie zuerst den freien Speicherplatz.",
            .fr: "Un petit modele pese environ 4 Go, un grand environ 40 Go — verifiez d'abord l'espace disque libre.",
            .es: "Un modelo pequeno ocupa unos 4 GB y uno grande unos 40 GB — compruebe antes el espacio libre en disco.",
            .ru: "Маленькая модель — около 4 ГБ, большая — около 40 ГБ. Сначала проверьте свободное место на диске.",
            .uk: "Мала модель — близько 4 ГБ, велика — близько 40 ГБ. Спершу перевірте вільне місце на диску.",
            .it: "Un modello piccolo pesa circa 4 GB, uno grande circa 40 GB — controlla prima lo spazio libero su disco.",
            .ja: "小さいモデルで約 4 GB、大きいモデルで約 40 GB です — 先に空き容量を確認してください。",
            .zh: "小模型约 4 GB，大模型约 40 GB — 请先检查磁盘剩余空间。"
        ])
    }

    public static func openWebUIAdminWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and register — the FIRST account created becomes the administrator. Then switch registration off in the admin settings.",
            .de: "WICHTIG: Oeffnen Sie diese URL sofort und registrieren Sie sich — das ERSTE angelegte Konto wird zum Administrator. Schalten Sie die Registrierung danach in den Admin-Einstellungen ab.",
            .fr: "IMPORTANT : ouvrez cette URL des maintenant et inscrivez-vous — le PREMIER compte cree devient administrateur. Desactivez ensuite l'inscription dans les reglages d'administration.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y registrese — la PRIMERA cuenta creada se convierte en administrador. Despues desactive el registro en los ajustes de administracion.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и зарегистрируйтесь — ПЕРВАЯ созданная учётная запись становится администратором. После этого отключите регистрацию в настройках администратора.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і зареєструйтеся — ПЕРШИЙ створений обліковий запис стає адміністратором. Після цього вимкніть реєстрацію в налаштуваннях адміністратора.",
            .it: "IMPORTANTE: apri questo URL subito e registrati — il PRIMO account creato diventa amministratore. Poi disattiva la registrazione nelle impostazioni di amministrazione.",
            .ja: "重要：今すぐこの URL を開いて登録してください — 最初に作成されたアカウントが管理者になります。その後、管理設定で新規登録を無効にしてください。",
            .zh: "重要：请立即打开此地址并注册 — 第一个创建的账户将成为管理员。随后请在管理设置中关闭注册。"
        ])
    }

    /// Printed only when the deployment installs no local engine
    public static func openWebUINoEngineNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No local model engine is installed, so the model list starts empty: add a provider and its API key in the admin settings.",
            .de: "Es ist keine lokale Modell-Engine installiert, daher ist die Modellliste zunaechst leer: Tragen Sie einen Anbieter und dessen API-Schluessel in den Admin-Einstellungen ein.",
            .fr: "Aucun moteur de modeles local n'est installe, la liste des modeles est donc vide au depart : ajoutez un fournisseur et sa cle d'API dans les reglages d'administration.",
            .es: "No hay ningun motor de modelos local instalado, por lo que la lista de modelos empieza vacia: anada un proveedor y su clave de API en los ajustes de administracion.",
            .ru: "Локального движка моделей нет, поэтому список моделей пуст: добавьте провайдера и его ключ API в настройках администратора.",
            .uk: "Локального рушія моделей немає, тому список моделей порожній: додайте провайдера та його ключ API в налаштуваннях адміністратора.",
            .it: "Nessun motore di modelli locale e installato, quindi l'elenco dei modelli parte vuoto: aggiungi un provider e la sua chiave API nelle impostazioni di amministrazione.",
            .ja: "ローカルのモデルエンジンが入っていないため、モデル一覧は空の状態で始まります。管理設定でプロバイダーと API キーを追加してください。",
            .zh: "未安装本地模型引擎，因此模型列表初始为空：请在管理设置中添加提供商及其 API 密钥。"
        ])
    }

    public static func liteLLMMasterKeyLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Master key",
            .de: "Hauptschluessel",
            .fr: "Cle maitresse",
            .es: "Clave maestra",
            .ru: "Главный ключ",
            .uk: "Головний ключ",
            .it: "Chiave principale",
            .ja: "マスターキー",
            .zh: "主密钥"
        ])
    }

    public static func liteLLMKeysNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Keys for OpenAI, Anthropic and the rest are added from the app and stored on this server, encrypted. Without the agent installed, put them in the file below by hand and restart the container.",
            .de: "Schluessel fuer OpenAI, Anthropic und die uebrigen werden aus der App hinzugefuegt und auf diesem Server verschluesselt gespeichert. Ohne installierten Agenten tragen Sie sie von Hand in die Datei unten ein und starten den Container neu.",
            .fr: "Les cles pour OpenAI, Anthropic et les autres s'ajoutent depuis l'application et sont stockees chiffrees sur ce serveur. Sans agent installe, inscrivez-les a la main dans le fichier ci-dessous et redemarrez le conteneur.",
            .es: "Las claves de OpenAI, Anthropic y las demas se agregan desde la aplicacion y se guardan cifradas en este servidor. Sin el agente instalado, escribalas a mano en el archivo de abajo y reinicie el contenedor.",
            .ru: "Ключи от OpenAI, Anthropic и остальных добавляются из приложения и хранятся на этом сервере в зашифрованном виде. Без установленного агента впишите их в файл ниже руками и перезапустите контейнер.",
            .uk: "Ключі від OpenAI, Anthropic та інших додаються з застосунку і зберігаються на цьому сервері в зашифрованому вигляді. Без встановленого агента впишіть їх у файл нижче руками й перезапустіть контейнер.",
            .it: "Le chiavi per OpenAI, Anthropic e le altre si aggiungono dall'app e sono conservate cifrate su questo server. Senza l'agente installato, scrivile a mano nel file qui sotto e riavvia il container.",
            .ja: "OpenAI や Anthropic などのキーはアプリから追加され、このサーバーに暗号化して保存されます。エージェントが入っていない場合は、下のファイルに手で書き入れてコンテナを再起動してください。",
            .zh: "OpenAI、Anthropic 等的密钥从应用中添加，并加密保存在这台服务器上。若未安装代理，请手动写入下面的文件并重启容器。"
        ])
    }

    /// The file the note above points at
    public static func liteLLMKeysFileLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Provider keys",
            .de: "Anbieterschluessel",
            .fr: "Cles des fournisseurs",
            .es: "Claves de proveedores",
            .ru: "Ключи провайдеров",
            .uk: "Ключі провайдерів",
            .it: "Chiavi dei fornitori",
            .ja: "プロバイダーのキー",
            .zh: "提供商密钥"
        ])
    }

    public static func n8nOwnerWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and create the owner account — the FIRST person to open it becomes the owner of every workflow.",
            .de: "WICHTIG: Oeffnen Sie diese URL sofort und legen Sie das Eigentuemerkonto an — die ERSTE Person, die sie oeffnet, wird Eigentuemer aller Ablaeufe.",
            .fr: "IMPORTANT : ouvrez cette URL des maintenant et creez le compte proprietaire — la PREMIERE personne qui l'ouvre devient proprietaire de tous les flux.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y cree la cuenta de propietario — la PRIMERA persona que la abra se convierte en propietaria de todos los flujos.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и заведите учётную запись владельца — ПЕРВЫЙ, кто её откроет, станет владельцем всех сценариев.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і створіть обліковий запис власника — ПЕРШИЙ, хто її відкриє, стане власником усіх сценаріїв.",
            .it: "IMPORTANTE: apri questo URL subito e crea l'account proprietario — la PRIMA persona che lo apre diventa proprietaria di tutti i flussi.",
            .ja: "重要：今すぐこの URL を開いてオーナーアカウントを作成してください — 最初に開いた人がすべてのワークフローのオーナーになります。",
            .zh: "重要：请立即打开此地址并创建所有者账户 — 第一个打开它的人将成为所有工作流的所有者。"
        ])
    }

    public static func n8nWebhooksPublicNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The editor is behind the admin guard like every other panel, but the /webhook/ and /webhook-test/ addresses answer the whole internet — that is what makes an incoming trigger work. Anyone who knows a webhook address can call it, so treat it as a password.",
            .de: "Der Editor liegt wie jedes andere Panel hinter dem Admin-Schutz, aber die Adressen /webhook/ und /webhook-test/ antworten dem gesamten Internet — nur so funktioniert ein eingehender Ausloeser. Wer eine Webhook-Adresse kennt, kann sie aufrufen: behandeln Sie sie wie ein Passwort.",
            .fr: "L'editeur est derriere la protection d'administration comme tous les autres panneaux, mais les adresses /webhook/ et /webhook-test/ repondent a tout l'internet — c'est ce qui fait fonctionner un declencheur entrant. Quiconque connait une adresse de webhook peut l'appeler : traitez-la comme un mot de passe.",
            .es: "El editor esta detras de la proteccion de administracion como los demas paneles, pero las direcciones /webhook/ y /webhook-test/ responden a todo internet — es lo que hace funcionar un disparador entrante. Cualquiera que conozca una direccion de webhook puede llamarla: tratela como una contrasena.",
            .ru: "Редактор закрыт админ-гардом, как и остальные панели, но адреса /webhook/ и /webhook-test/ отвечают всему интернету — иначе входящий триггер не сработает. Кто знает адрес вебхука, тот может его дёрнуть: относитесь к нему как к паролю.",
            .uk: "Редактор закритий адмін-гардом, як і решта панелей, але адреси /webhook/ та /webhook-test/ відповідають усьому інтернету — інакше вхідний тригер не спрацює. Хто знає адресу вебхука, той може його смикнути: ставтеся до неї як до пароля.",
            .it: "L'editor sta dietro la protezione di amministrazione come ogni altro pannello, ma gli indirizzi /webhook/ e /webhook-test/ rispondono a tutta la rete — e cio che fa funzionare un trigger in entrata. Chi conosce un indirizzo di webhook puo chiamarlo: trattalo come una password.",
            .ja: "エディターは他のパネルと同じく管理ガードの内側にありますが、/webhook/ と /webhook-test/ のアドレスはインターネット全体に応答します — 受信トリガーはそれで動きます。webhook のアドレスを知っている人は誰でも呼び出せるので、パスワードと同じように扱ってください。",
            .zh: "编辑器与其他面板一样处于管理防护之后，但 /webhook/ 和 /webhook-test/ 地址会响应整个互联网 — 传入触发器正是靠它工作。知道 webhook 地址的人都能调用它，请像对待密码一样对待它。"
        ])
    }

    public static func anythingLLMAdminWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and create the first account — whoever opens it first becomes the administrator of every workspace and every document in it.",
            .de: "WICHTIG: Oeffnen Sie diese URL sofort und legen Sie das erste Konto an — wer sie zuerst oeffnet, wird Administrator jedes Arbeitsbereichs und jedes Dokuments darin.",
            .fr: "IMPORTANT : ouvrez cette URL des maintenant et creez le premier compte — celui qui l'ouvre en premier devient administrateur de chaque espace de travail et de chaque document.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y cree la primera cuenta — quien la abra primero se convierte en administrador de cada espacio de trabajo y de cada documento.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и заведите первую учётную запись — кто откроет первым, тот станет администратором всех рабочих пространств и всех документов в них.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і створіть перший обліковий запис — хто відкриє першим, той стане адміністратором усіх робочих просторів і всіх документів у них.",
            .it: "IMPORTANTE: apri questo URL subito e crea il primo account — chi lo apre per primo diventa amministratore di ogni spazio di lavoro e di ogni documento.",
            .ja: "重要：今すぐこの URL を開いて最初のアカウントを作成してください — 最初に開いた人が、すべてのワークスペースとその中の文書の管理者になります。",
            .zh: "重要：请立即打开此地址并创建第一个账户 — 最先打开的人将成为所有工作区及其中所有文档的管理员。"
        ])
    }

    public static func anythingLLMNoModelNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No model backend is installed, so no provider is preset: the service asks for one when you first open it. Uploading and searching documents already works without one.",
            .de: "Es ist kein Modell-Backend installiert, daher ist kein Anbieter voreingestellt: der Dienst fragt beim ersten Oeffnen danach. Dokumente hochladen und durchsuchen geht auch ohne.",
            .fr: "Aucun moteur de modeles n'est installe, donc aucun fournisseur n'est preconfigure : le service en demande un a la premiere ouverture. Televerser et rechercher des documents fonctionne deja sans.",
            .es: "No hay ningun backend de modelos instalado, asi que no hay proveedor preconfigurado: el servicio pide uno al abrirlo por primera vez. Subir y buscar documentos ya funciona sin el.",
            .ru: "Движка моделей нет, поэтому провайдер не выставлен: сервис спросит о нём при первом открытии. Загружать документы и искать по ним можно уже сейчас.",
            .uk: "Рушія моделей немає, тому провайдер не виставлений: сервіс запитає про нього під час першого відкриття. Завантажувати документи й шукати по них можна вже зараз.",
            .it: "Nessun backend di modelli e installato, quindi nessun provider e preimpostato: il servizio ne chiede uno alla prima apertura. Caricare e cercare documenti funziona gia senza.",
            .ja: "モデルのバックエンドが入っていないため、プロバイダーは設定されていません。初回起動時に尋ねられます。文書のアップロードと検索は、それがなくても動きます。",
            .zh: "未安装模型后端，因此没有预设提供商：首次打开时服务会询问。上传和搜索文档在没有它的情况下已经可用。"
        ])
    }

    public static func anythingLLMSettingsNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The model and the vector store were set once, from what this server runs. Change them in the service's own settings from now on — the install does not write them again.",
            .de: "Modell und Vektorspeicher wurden einmal gesetzt, aus dem, was dieser Server betreibt. Aendern Sie sie ab jetzt in den Einstellungen des Dienstes — die Installation schreibt sie nicht erneut.",
            .fr: "Le modele et le magasin de vecteurs ont ete definis une fois, d'apres ce que ce serveur execute. Modifiez-les desormais dans les reglages du service — l'installation ne les reecrit pas.",
            .es: "El modelo y el almacen de vectores se fijaron una vez, a partir de lo que este servidor ejecuta. Cambielos de ahora en adelante en los ajustes del servicio — la instalacion no los vuelve a escribir.",
            .ru: "Модель и векторное хранилище выставлены один раз — из того, что крутится на этом сервере. Дальше меняйте их в настройках самого сервиса: установка их больше не переписывает.",
            .uk: "Модель і векторне сховище виставлені один раз — з того, що працює на цьому сервері. Далі змінюйте їх у налаштуваннях самого сервісу: встановлення їх більше не переписує.",
            .it: "Il modello e l'archivio vettoriale sono stati impostati una volta, da cio che questo server esegue. D'ora in poi cambiali nelle impostazioni del servizio — l'installazione non li riscrive.",
            .ja: "モデルとベクトルストアは、このサーバーが動かしているものから一度だけ設定されました。以降はサービス自身の設定で変更してください — インストールが書き直すことはありません。",
            .zh: "模型和向量库只根据这台服务器运行的内容设置了一次。此后请在服务自身的设置中更改 — 安装不会再写入它们。"
        ])
    }

    public static func qdrantLoopbackNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The vector store answers on this machine only and is not published on any hostname — what it holds is your documents in a form that still answers questions about them. Its key is in /etc/gryonixnexus/qdrant.key.",
            .de: "Der Vektorspeicher antwortet nur auf dieser Maschine und wird unter keinem Hostnamen veroeffentlicht — er haelt Ihre Dokumente in einer Form, die weiterhin Fragen dazu beantwortet. Sein Schluessel liegt in /etc/gryonixnexus/qdrant.key.",
            .fr: "Le magasin de vecteurs ne repond que sur cette machine et n'est publie sous aucun nom d'hote — il contient vos documents sous une forme qui repond encore aux questions les concernant. Sa cle est dans /etc/gryonixnexus/qdrant.key.",
            .es: "El almacen de vectores responde solo en esta maquina y no se publica en ningun nombre de host — contiene sus documentos en una forma que aun responde preguntas sobre ellos. Su clave esta en /etc/gryonixnexus/qdrant.key.",
            .ru: "Векторное хранилище отвечает только на этой машине и не публикуется ни под каким именем — в нём лежат ваши документы в виде, который по-прежнему отвечает на вопросы о них. Ключ — в /etc/gryonixnexus/qdrant.key.",
            .uk: "Векторне сховище відповідає лише на цій машині й не публікується під жодним іменем — у ньому лежать ваші документи у вигляді, який досі відповідає на питання про них. Ключ — у /etc/gryonixnexus/qdrant.key.",
            .it: "L'archivio vettoriale risponde solo su questa macchina e non e pubblicato su alcun hostname — contiene i tuoi documenti in una forma che risponde ancora a domande su di essi. La sua chiave e in /etc/gryonixnexus/qdrant.key.",
            .ja: "ベクトルストアはこのマシン上でのみ応答し、どのホスト名でも公開されません。中身は、質問に答えられる形のままのあなたの文書です。鍵は /etc/gryonixnexus/qdrant.key にあります。",
            .zh: "向量库只在本机响应，不会发布到任何主机名上 — 它保存的是仍能回答相关问题的你的文档。其密钥在 /etc/gryonixnexus/qdrant.key。"
        ])
    }

    /// The search engine's line in the install report
    public static func searxngLoopbackNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Web search for the services on this shelf. It answers on this machine only and is published on no hostname — the chat beside it queries it by itself.",
            .de: "Websuche fuer die Dienste in diesem Regal. Sie antwortet nur auf dieser Maschine und wird unter keinem Hostnamen veroeffentlicht — der Chat daneben fragt sie von selbst.",
            .fr: "Recherche web pour les services de cette etagere. Elle ne repond que sur cette machine et n'est publiee sous aucun nom d'hote — le chat a cote l'interroge tout seul.",
            .es: "Busqueda web para los servicios de este estante. Responde solo en esta maquina y no se publica en ningun nombre de host — el chat de al lado la consulta por si mismo.",
            .ru: "Поиск в интернете для сервисов этой полки. Отвечает только на этой машине и не публикуется ни под каким именем — чат рядом обращается к нему сам.",
            .uk: "Пошук в інтернеті для сервісів цієї полиці. Відповідає лише на цій машині й не публікується під жодним іменем — чат поруч звертається до нього сам.",
            .it: "Ricerca web per i servizi di questo scaffale. Risponde solo su questa macchina e non e pubblicata su alcun hostname — la chat accanto la interroga da sola.",
            .ja: "この棚のサービスのためのウェブ検索です。このマシン上でのみ応答し、どのホスト名でも公開されません。隣のチャットが自分で問い合わせます。",
            .zh: "供本棚服务使用的网页搜索。它只在本机响应，不会发布到任何主机名上 — 旁边的聊天会自行查询它。"
        ])
    }

    /// The token that guards the gateway's web UI
    public static func openclawTokenNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Gateway token",
            .de: "Gateway-Token",
            .fr: "Jeton de la passerelle",
            .es: "Token de la puerta de enlace",
            .ru: "Токен шлюза",
            .uk: "Токен шлюзу",
            .it: "Token del gateway",
            .ja: "ゲートウェイトークン",
            .zh: "网关令牌"
        ])
    }

    public static func openclawPairingNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Pair WhatsApp, Telegram or Discord in its own web UI — those tokens stay in this container and are never held by gryonixNexus.",
            .de: "WhatsApp, Telegram oder Discord werden in seiner eigenen Weboberflaeche verbunden — diese Token bleiben in diesem Container und werden von gryonixNexus nie gehalten.",
            .fr: "Associez WhatsApp, Telegram ou Discord dans sa propre interface web — ces jetons restent dans ce conteneur et ne sont jamais detenus par gryonixNexus.",
            .es: "Vincule WhatsApp, Telegram o Discord en su propia interfaz web — esos tokens se quedan en este contenedor y gryonixNexus nunca los guarda.",
            .ru: "WhatsApp, Telegram или Discord подключаются в его собственном веб-интерфейсе — эти токены остаются в этом контейнере, gryonixNexus их не хранит.",
            .uk: "WhatsApp, Telegram чи Discord підключаються в його власному вебінтерфейсі — ці токени лишаються в цьому контейнері, gryonixNexus їх не зберігає.",
            .it: "Collega WhatsApp, Telegram o Discord nella sua interfaccia web — quei token restano in questo container e gryonixNexus non li conserva mai.",
            .ja: "WhatsApp・Telegram・Discord の連携は、このサービス自身の Web UI で行います。これらのトークンはこのコンテナ内に留まり、gryonixNexus が保持することはありません。",
            .zh: "在它自己的网页界面中配对 WhatsApp、Telegram 或 Discord — 这些令牌留在该容器内，gryonixNexus 从不持有它们。"
        ])
    }

    /// The address of whichever model backend this deployment does run
    public static func openclawModelNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No model provider is set yet; paste this address into its settings",
            .de: "Es ist noch kein Modellanbieter gesetzt; diese Adresse in seine Einstellungen einfuegen",
            .fr: "Aucun fournisseur de modele n'est encore defini; collez cette adresse dans ses parametres",
            .es: "Aun no hay proveedor de modelos; pegue esta direccion en sus ajustes",
            .ru: "Провайдер модели ещё не задан; вставьте этот адрес в его настройки",
            .uk: "Провайдера моделі ще не задано; вставте цю адресу в його налаштування",
            .it: "Nessun fornitore di modelli e ancora impostato; incolla questo indirizzo nelle sue impostazioni",
            .ja: "モデルのプロバイダーはまだ設定されていません。次のアドレスを設定画面に貼り付けてください",
            .zh: "尚未设置模型提供方；请把这个地址粘贴到它的设置中"
        ])
    }

    public static func openclawNoModelNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "This deployment runs no model of its own, so the provider and its key are set in its own web UI.",
            .de: "Diese Installation betreibt kein eigenes Modell; Anbieter und Schluessel werden daher in seiner eigenen Weboberflaeche gesetzt.",
            .fr: "Cette installation n'execute aucun modele a elle; le fournisseur et sa cle se definissent donc dans sa propre interface web.",
            .es: "Esta instalacion no ejecuta ningun modelo propio, asi que el proveedor y su clave se configuran en su propia interfaz web.",
            .ru: "В этой установке своей модели нет — провайдер и ключ задаются в его собственном веб-интерфейсе.",
            .uk: "У цій установці власної моделі немає — провайдер і ключ задаються в його власному вебінтерфейсі.",
            .it: "Questa installazione non esegue alcun modello proprio, quindi il fornitore e la sua chiave si impostano nella sua interfaccia web.",
            .ja: "この構成には自前のモデルがないため、プロバイダーと鍵はこのサービス自身の Web UI で設定します。",
            .zh: "本次部署没有自己的模型，因此提供方和密钥在它自己的网页界面中设置。"
        ])
    }

    public static func ollamaGPUToolkitInstalling(_ l: AppLanguage) -> String {
        l.pick([
            .en: "teaching docker about the graphics card (NVIDIA container toolkit)",
            .de: "Docker die Grafikkarte beibringen (NVIDIA Container Toolkit)",
            .fr: "apprentissage de la carte graphique a docker (NVIDIA container toolkit)",
            .es: "ensenando a docker sobre la tarjeta grafica (NVIDIA container toolkit)",
            .ru: "учим docker видеть видеокарту (NVIDIA container toolkit)",
            .uk: "вчимо docker бачити відеокарту (NVIDIA container toolkit)",
            .it: "insegnare a docker la scheda grafica (NVIDIA container toolkit)",
            .ja: "グラフィックカードを docker に認識させています (NVIDIA container toolkit)",
            .zh: "让 docker 认识显卡 (NVIDIA container toolkit)"
        ])
    }

    public static func ollamaGPUEnabledNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The engine runs on the NVIDIA card in this machine — answers are as fast as the card, not as fast as the processor.",
            .de: "Die Engine laeuft auf der NVIDIA-Karte in dieser Maschine — die Antworten sind so schnell wie die Karte, nicht wie der Prozessor.",
            .fr: "Le moteur tourne sur la carte NVIDIA de cette machine — les reponses vont a la vitesse de la carte, pas du processeur.",
            .es: "El motor funciona con la tarjeta NVIDIA de esta maquina — las respuestas van a la velocidad de la tarjeta, no del procesador.",
            .ru: "Движок работает на видеокарте NVIDIA этой машины — ответы идут со скоростью карты, а не процессора.",
            .uk: "Рушій працює на відеокарті NVIDIA цієї машини — відповіді йдуть зі швидкістю карти, а не процесора.",
            .it: "Il motore gira sulla scheda NVIDIA di questa macchina — le risposte vanno alla velocita della scheda, non del processore.",
            .ja: "エンジンはこのマシンの NVIDIA カード上で動作します。応答の速さはプロセッサではなくカードのものです。",
            .zh: "引擎运行在本机的 NVIDIA 显卡上 — 回答的速度取决于显卡，而不是处理器。"
        ])
    }

    public static func ollamaGPUMissingNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "A graphics card was asked for, and no NVIDIA driver answered on this machine — the engine is running on the processor. Installing the driver is a decision about the host itself (kernel modules and a reboot), so this install does not make it for you.",
            .de: "Eine Grafikkarte wurde angefordert, aber auf dieser Maschine antwortet kein NVIDIA-Treiber — die Engine laeuft auf dem Prozessor. Den Treiber zu installieren ist eine Entscheidung ueber den Host selbst (Kernelmodule und ein Neustart), die diese Installation nicht fuer Sie trifft.",
            .fr: "Une carte graphique a ete demandee, mais aucun pilote NVIDIA ne repond sur cette machine — le moteur tourne sur le processeur. Installer le pilote est une decision sur l'hote lui-meme (modules noyau et redemarrage), que cette installation ne prend pas a votre place.",
            .es: "Se pidio una tarjeta grafica y ningun controlador NVIDIA responde en esta maquina — el motor funciona con el procesador. Instalar el controlador es una decision sobre el propio host (modulos del kernel y un reinicio), y esta instalacion no la toma por usted.",
            .ru: "Видеокарта была запрошена, но драйвер NVIDIA на этой машине не отвечает — движок работает на процессоре. Установка драйвера — это решение про сам хост (модули ядра и перезагрузка), и установка не принимает его за вас.",
            .uk: "Відеокарту було запитано, але драйвер NVIDIA на цій машині не відповідає — рушій працює на процесорі. Встановлення драйвера — це рішення про сам хост (модулі ядра та перезавантаження), і встановлення не ухвалює його за вас.",
            .it: "E stata richiesta una scheda grafica e nessun driver NVIDIA risponde su questa macchina — il motore gira sul processore. Installare il driver e una decisione sull'host stesso (moduli del kernel e un riavvio), che questa installazione non prende al posto tuo.",
            .ja: "グラフィックカードが要求されましたが、このマシンでは NVIDIA ドライバーが応答しません。エンジンはプロセッサ上で動作しています。ドライバーの導入はホスト自体に関する決定 (カーネルモジュールと再起動) であり、このインストールが代わりに行うことはありません。",
            .zh: "已请求使用显卡，但本机没有 NVIDIA 驱动响应 — 引擎正在处理器上运行。安装驱动是关于主机本身的决定 (内核模块和一次重启)，本次安装不会替你做这个决定。"
        ])
    }

    public static func ollamaGPUSecureBootNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Secure Boot is on, so the driver was not installed automatically — enrolling it needs a password typed at the machine's own screen on the next boot, which nothing here can do for you. Turn Secure Boot off in the BIOS/UEFI, or install the driver yourself.",
            .de: "Secure Boot ist aktiv, daher wurde der Treiber nicht automatisch installiert — seine Registrierung braucht beim naechsten Start ein Passwort direkt am Bildschirm der Maschine, was hier niemand fuer Sie eingeben kann. Schalten Sie Secure Boot im BIOS/UEFI aus, oder installieren Sie den Treiber selbst.",
            .fr: "Secure Boot est actif, le pilote n'a donc pas ete installe automatiquement — son enregistrement demande un mot de passe tape sur l'ecran meme de la machine au prochain demarrage, ce que rien ici ne peut faire a votre place. Desactivez Secure Boot dans le BIOS/UEFI, ou installez le pilote vous-meme.",
            .es: "Secure Boot esta activado, asi que el controlador no se instalo automaticamente — inscribirlo necesita una contrasena escrita en la propia pantalla de la maquina en el proximo arranque, y nada aqui puede hacerlo por usted. Desactive Secure Boot en la BIOS/UEFI, o instale el controlador usted mismo.",
            .ru: "Включен Secure Boot, поэтому драйвер не установился автоматически — для его регистрации при следующей загрузке нужен пароль, введённый прямо на экране этой машины, а этого отсюда сделать нельзя. Отключите Secure Boot в BIOS/UEFI или установите драйвер самостоятельно.",
            .uk: "Увімкнено Secure Boot, тому драйвер не встановився автоматично — для його реєстрації під час наступного завантаження потрібен пароль, введений прямо на екрані цієї машини, а звідси це зробити не можна. Вимкніть Secure Boot у BIOS/UEFI або встановіть драйвер самостійно.",
            .it: "Secure Boot e attivo, quindi il driver non e stato installato automaticamente — la sua registrazione richiede una password digitata sullo schermo stesso della macchina al prossimo avvio, cosa che nulla qui puo fare al posto tuo. Disattiva Secure Boot nel BIOS/UEFI, oppure installa il driver tu stesso.",
            .ja: "Secure Boot が有効なため、ドライバーは自動インストールされませんでした。登録には次回起動時にマシン自身の画面でパスワードを入力する必要があり、ここからは代行できません。BIOS/UEFI で Secure Boot を無効にするか、ドライバーを自分でインストールしてください。",
            .zh: "已启用 Secure Boot，因此未自动安装驱动 — 注册它需要在下次开机时于本机屏幕上输入密码，这里无法替你完成。请在 BIOS/UEFI 中关闭 Secure Boot，或自行安装驱动。"
        ])
    }

    /// The log line for the driver install attempt itself
    public static func ollamaGPUDriverInstalling(_ l: AppLanguage) -> String {
        l.pick([
            .en: "installing the NVIDIA driver (ubuntu-drivers autoinstall)",
            .de: "installiere den NVIDIA-Treiber (ubuntu-drivers autoinstall)",
            .fr: "installation du pilote NVIDIA (ubuntu-drivers autoinstall)",
            .es: "instalando el controlador NVIDIA (ubuntu-drivers autoinstall)",
            .ru: "устанавливаем драйвер NVIDIA (ubuntu-drivers autoinstall)",
            .uk: "встановлюємо драйвер NVIDIA (ubuntu-drivers autoinstall)",
            .it: "installazione del driver NVIDIA (ubuntu-drivers autoinstall)",
            .ja: "NVIDIA ドライバーをインストールしています (ubuntu-drivers autoinstall)",
            .zh: "正在安装 NVIDIA 驱动 (ubuntu-drivers autoinstall)"
        ])
    }

    public static func ollamaGPUDriverInstalledNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The driver was installed but is not loaded yet — reboot this machine, then run this install again (or restart Ollama) to finish enabling the card.",
            .de: "Der Treiber wurde installiert, ist aber noch nicht geladen — starten Sie diese Maschine neu und fuehren Sie diese Installation erneut aus (oder starten Sie Ollama neu), um die Karte fertig zu aktivieren.",
            .fr: "Le pilote a ete installe mais n'est pas encore charge — redemarrez cette machine, puis relancez cette installation (ou redemarrez Ollama) pour terminer d'activer la carte.",
            .es: "El controlador se instalo pero aun no esta cargado — reinicie esta maquina y vuelva a ejecutar esta instalacion (o reinicie Ollama) para terminar de activar la tarjeta.",
            .ru: "Драйвер установлен, но пока не загружен — перезагрузите эту машину и снова запустите установку (или перезапустите Ollama), чтобы включить карту до конца.",
            .uk: "Драйвер встановлено, але поки не завантажено — перезавантажте цю машину і знову запустіть установку (або перезапустіть Ollama), щоб довести вмикання карти до кінця.",
            .it: "Il driver e stato installato ma non e ancora caricato — riavvia questa macchina, poi esegui di nuovo questa installazione (o riavvia Ollama) per completare l'attivazione della scheda.",
            .ja: "ドライバーはインストールされましたが、まだ読み込まれていません。このマシンを再起動してからこのインストールを再実行する (または Ollama を再起動する) と、カードの有効化が完了します。",
            .zh: "驱动已安装但尚未加载 — 请重启本机后再次运行本次安装 (或重启 Ollama) 以完成显卡的启用。"
        ])
    }

    public static func ollamaGPUDriverUnsupportedNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "This machine has no ubuntu-drivers tool, so the driver was not installed automatically — install it yourself, then run this install again.",
            .de: "Diese Maschine hat kein ubuntu-drivers-Werkzeug, daher wurde der Treiber nicht automatisch installiert — installieren Sie ihn selbst und fuehren Sie diese Installation dann erneut aus.",
            .fr: "Cette machine n'a pas l'outil ubuntu-drivers, le pilote n'a donc pas ete installe automatiquement — installez-le vous-meme, puis relancez cette installation.",
            .es: "Esta maquina no tiene la herramienta ubuntu-drivers, asi que el controlador no se instalo automaticamente — instalelo usted mismo y vuelva a ejecutar esta instalacion.",
            .ru: "На этой машине нет утилиты ubuntu-drivers, поэтому драйвер не установился автоматически — установите его сами и снова запустите установку.",
            .uk: "На цій машині немає утиліти ubuntu-drivers, тому драйвер не встановився автоматично — встановіть його самостійно і знову запустіть установку.",
            .it: "Questa macchina non ha lo strumento ubuntu-drivers, quindi il driver non e stato installato automaticamente — installalo tu stesso, poi esegui di nuovo questa installazione.",
            .ja: "このマシンには ubuntu-drivers ツールがないため、ドライバーは自動インストールされませんでした。自分でインストールしてから、このインストールを再実行してください。",
            .zh: "本机没有 ubuntu-drivers 工具，因此未自动安装驱动 — 请自行安装后再次运行本次安装。"
        ])
    }

    // MARK: - Home Assistant

    public static func homeAssistantOwnerWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "IMPORTANT: open this URL right now and create the owner account — until you do, whoever opens the page becomes the owner.",
            .de: "WICHTIG: Öffnen Sie diese URL sofort und legen Sie das Besitzerkonto an — bis dahin wird jeder, der die Seite öffnet, zum Besitzer.",
            .fr: "IMPORTANT : ouvrez cette URL dès maintenant et créez le compte propriétaire — d'ici là, quiconque ouvre la page en devient le propriétaire.",
            .es: "IMPORTANTE: abra esta URL ahora mismo y cree la cuenta de propietario — hasta entonces, quien abra la página se convierte en propietario.",
            .ru: "ВАЖНО: откройте адрес прямо сейчас и создайте учётную запись владельца — до этого владельцем станет любой, кто откроет страницу.",
            .uk: "ВАЖЛИВО: відкрийте адресу просто зараз і створіть обліковий запис власника — доти власником стане будь-хто, хто відкриє сторінку.",
            .it: "IMPORTANTE: apri questo URL subito e crea l'account proprietario — fino ad allora chiunque apra la pagina ne diventa il proprietario.",
            .ja: "重要：今すぐこの URL を開いてオーナーアカウントを作成してください — それまでは、ページを開いた人がオーナーになります。",
            .zh: "重要：请立即打开此地址并创建所有者账户 — 在此之前，打开该页面的人将成为所有者。"
        ])
    }

    public static func mosquittoNetworkAddress(_ l: AppLanguage) -> String {
        l.pick([
            .en: "this server's address on your network",
            .de: "die Adresse dieses Servers in Ihrem Netz",
            .fr: "l'adresse de ce serveur sur votre réseau",
            .es: "la dirección de este servidor en su red",
            .ru: "адрес этого сервера в вашей сети",
            .uk: "адреса цього сервера у вашій мережі",
            .it: "l'indirizzo di questo server nella tua rete",
            .ja: "ネットワーク上のこのサーバーのアドレス",
            .zh: "此服务器在您网络中的地址"
        ])
    }

    public static func mosquittoAccountsLabel(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Accounts",
            .de: "Konten",
            .fr: "Comptes",
            .es: "Cuentas",
            .ru: "Учётные записи",
            .uk: "Облікові записи",
            .it: "Account",
            .ja: "アカウント",
            .zh: "账户"
        ])
    }

    public static func zigbee2MQTTPairingHint(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Open this page to pair devices: turn “Permit join” on, then press the button on the lamp or sensor.",
            .de: "Öffnen Sie diese Seite zum Koppeln: „Permit join“ einschalten, dann die Taste an Lampe oder Sensor drücken.",
            .fr: "Ouvrez cette page pour appairer : activez « Permit join », puis appuyez sur le bouton de la lampe ou du capteur.",
            .es: "Abra esta página para emparejar: active «Permit join» y luego pulse el botón de la lámpara o el sensor.",
            .ru: "Откройте эту страницу для привязки устройств: включите «Permit join» и нажмите кнопку на лампе или датчике.",
            .uk: "Відкрийте цю сторінку для прив'язки пристроїв: увімкніть «Permit join» і натисніть кнопку на лампі чи датчику.",
            .it: "Apri questa pagina per associare i dispositivi: attiva «Permit join», poi premi il pulsante sulla lampada o sul sensore.",
            .ja: "このページで機器をペアリングします：「Permit join」をオンにして、ランプやセンサーのボタンを押してください。",
            .zh: "在此页面配对设备：打开 “Permit join”，然后按下灯或传感器上的按钮。"
        ])
    }

    public static func homeAssistantAppHint(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Phone app: install Home Assistant and enter this address.",
            .de: "Handy-App: Home Assistant installieren und diese Adresse eingeben.",
            .fr: "Application mobile : installez Home Assistant et saisissez cette adresse.",
            .es: "App del móvil: instale Home Assistant e introduzca esta dirección.",
            .ru: "Приложение на телефоне: установите Home Assistant и введите этот адрес.",
            .uk: "Застосунок на телефоні: встановіть Home Assistant і введіть цю адресу.",
            .it: "App per telefono: installa Home Assistant e inserisci questo indirizzo.",
            .ja: "スマホアプリ：Home Assistant をインストールしてこのアドレスを入力してください。",
            .zh: "手机应用：安装 Home Assistant 并输入此地址。"
        ])
    }
}

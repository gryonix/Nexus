package com.skaymer.gryonixnexus.catalog

import com.skaymer.gryonixnexus.catalog.AppLanguage
import com.skaymer.gryonixnexus.catalog.AppLanguage.DE
import com.skaymer.gryonixnexus.catalog.AppLanguage.EN
import com.skaymer.gryonixnexus.catalog.AppLanguage.ES
import com.skaymer.gryonixnexus.catalog.AppLanguage.FR
import com.skaymer.gryonixnexus.catalog.AppLanguage.IT
import com.skaymer.gryonixnexus.catalog.AppLanguage.JA
import com.skaymer.gryonixnexus.catalog.AppLanguage.RU
import com.skaymer.gryonixnexus.catalog.AppLanguage.UK
import com.skaymer.gryonixnexus.catalog.AppLanguage.ZH

object L10nServices {
    /** Suffix for "<ServiceName>: <starting>" log lines */
    fun serviceStarting(l: AppLanguage): String = l.pick(mapOf(
        EN to "starting",
        DE to "Start",
        FR to "démarrage",
        ES to "inicio",
        RU to "запуск",
        UK to "запуск",
        IT to "avvio",
        JA to "起動",
        ZH to "启动"
    ))

    // ---------------------------------------------- Mailcow

    fun mailcowInstalling(l: AppLanguage, path: String): String = l.pick(mapOf(
        EN to "Mailcow: installing into $path",
        DE to "Mailcow: Installation in $path",
        FR to "Mailcow : installation dans $path",
        ES to "Mailcow: instalación en $path",
        RU to "Mailcow: установка в $path",
        UK to "Mailcow: встановлення у $path",
        IT to "Mailcow: installazione in $path",
        JA to "Mailcow: $path にインストール",
        ZH to "Mailcow: 安装到 $path"
    ))

    fun mailcowRecreatingForNewHostname(l: AppLanguage, hostname: String): String = l.pick(mapOf(
        EN to "Mailcow: the domain changed — installing again for $hostname (existing mail data is removed)",
        DE to "Mailcow: Domain geändert — Neuinstallation für $hostname (vorhandene Maildaten werden entfernt)",
        FR to "Mailcow : domaine modifié — réinstallation pour $hostname (les données de messagerie existantes sont supprimées)",
        ES to "Mailcow: el dominio cambió — se instala de nuevo para $hostname (se eliminan los datos de correo existentes)",
        RU to "Mailcow: домен изменился — устанавливаем заново для $hostname (существующие данные почты удаляются)",
        UK to "Mailcow: домен змінився — встановлюємо наново для $hostname (наявні дані пошти видаляються)",
        IT to "Mailcow: il dominio è cambiato — nuova installazione per $hostname (i dati di posta esistenti vengono rimossi)",
        JA to "Mailcow: ドメインが変更されました — $hostname 用に再インストールします（既存のメールデータは削除されます）",
        ZH to "Mailcow：域名已更改 — 为 $hostname 重新安装（现有邮件数据将被删除）"
    ))

    fun amneziaPanelWithoutPassword(l: AppLanguage): String = l.pick(mapOf(
        EN to "AmneziaWG: could not hash a panel password — its built-in panel stays open on localhost only. The VPN itself works; manage clients at vpn.<domain>.",
        DE to "AmneziaWG: Das Panel-Passwort konnte nicht gehasht werden — sein eingebautes Panel bleibt nur auf localhost offen. Das VPN funktioniert; Clients verwalten Sie unter vpn.<domain>.",
        FR to "AmneziaWG : impossible de hacher un mot de passe pour le panneau — son panneau intégré reste ouvert sur localhost uniquement. Le VPN fonctionne ; gérez les clients sur vpn.<domain>.",
        ES to "AmneziaWG: no se pudo cifrar una contraseña para el panel; su panel integrado queda abierto solo en localhost. La VPN funciona; gestiona los clientes en vpn.<domain>.",
        RU to "AmneziaWG: не удалось захешировать пароль панели — его встроенная панель остаётся без пароля, но только на localhost. Сам VPN работает; клиентами управляйте на vpn.<domain>.",
        UK to "AmneziaWG: не вдалося захешувати пароль панелі — його вбудована панель лишається без пароля, але лише на localhost. Сам VPN працює; клієнтами керуйте на vpn.<domain>.",
        IT to "AmneziaWG: impossibile calcolare l'hash della password del pannello — il suo pannello integrato resta aperto solo su localhost. La VPN funziona; gestisci i client su vpn.<domain>.",
        JA to "AmneziaWG: パネル用パスワードのハッシュ化に失敗しました。内蔵パネルは localhost 上でのみパスワードなしになります。VPN 自体は動作します。クライアントは vpn.<domain> で管理してください。",
        ZH to "AmneziaWG：无法为面板生成密码哈希 — 其内置面板将仅在 localhost 上无密码开放。VPN 本身可正常工作；请在 vpn.<domain> 管理客户端。"
    ))

    /** Printed under the default credentials in the report */
    fun mailcowDefaultPasswordNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "This is mailcow's standard password — change it after the first sign-in (System → Administrator).",
        DE to "Dies ist das Standardpasswort von mailcow — ändern Sie es nach der ersten Anmeldung (System → Administrator).",
        FR to "C'est le mot de passe standard de mailcow — changez-le après la première connexion (Système → Administrateur).",
        ES to "Es la contraseña estándar de mailcow: cámbiela tras el primer inicio de sesión (Sistema → Administrador).",
        RU to "Это стандартный пароль mailcow — смените его после первого входа (System → Administrator).",
        UK to "Це стандартний пароль mailcow — змініть його після першого входу (System → Administrator).",
        IT to "È la password standard di mailcow: cambiarla dopo il primo accesso (Sistema → Amministratore).",
        JA to "これは mailcow の標準パスワードです。初回サインイン後に変更してください（System → Administrator）。",
        ZH to "这是 mailcow 的默认密码——首次登录后请修改（System → Administrator）。"
    ))

    /** Word used in "(directory: <path>)" of the report header line */
    fun directoryLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "directory",
        DE to "Verzeichnis",
        FR to "répertoire",
        ES to "directorio",
        RU to "каталог",
        UK to "каталог",
        IT to "directory",
        JA to "ディレクトリ",
        ZH to "目录"
    ))

    fun passwordLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Password",
        DE to "Passwort",
        FR to "Mot de passe",
        ES to "Contraseña",
        RU to "Пароль",
        UK to "Пароль",
        IT to "Password",
        JA to "パスワード",
        ZH to "密码"
    ))

    fun mailcowProvisioningDomain(l: AppLanguage, domain: String): String = l.pick(mapOf(
        EN to "Mailcow: adding domain $domain and its DKIM key over the API",
        DE to "Mailcow: Domain $domain und ihr DKIM-Schlüssel werden über die API angelegt",
        FR to "Mailcow : ajout du domaine $domain et de sa clé DKIM via l'API",
        ES to "Mailcow: añadiendo el dominio $domain y su clave DKIM mediante la API",
        RU to "Mailcow: добавление домена $domain и его DKIM-ключа через API",
        UK to "Mailcow: додавання домену $domain та його DKIM-ключа через API",
        IT to "Mailcow: aggiunta del dominio $domain e della sua chiave DKIM tramite API",
        JA to "Mailcow：API経由でドメイン $domain とそのDKIMキーを追加しています",
        ZH to "Mailcow：正在通过 API 添加域名 $domain 及其 DKIM 密钥"
    ))

    fun mailcowWaitingForAPI(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mailcow: waiting for the API to come up",
        DE to "Mailcow: Warten auf die API",
        FR to "Mailcow : en attente de l'API",
        ES to "Mailcow: esperando a que la API esté disponible",
        RU to "Mailcow: ждём, пока поднимется API",
        UK to "Mailcow: чекаємо, доки підніметься API",
        IT to "Mailcow: in attesa che l'API sia disponibile",
        JA to "Mailcow：APIの起動を待機しています",
        ZH to "Mailcow：正在等待 API 启动"
    ))

    /** The API never answered */
    fun mailcowAPIUnreachable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mailcow: the API did not answer — the domain and DKIM key were NOT created. Mailcow itself is running: add the domain under Configuration → Domains in its admin UI, or re-run the setup.",
        DE to "Mailcow: Die API hat nicht geantwortet — Domain und DKIM-Schlüssel wurden NICHT angelegt. Mailcow selbst läuft: Domain in der Admin-UI unter Konfiguration → Domains anlegen oder das Setup erneut ausführen.",
        FR to "Mailcow : l'API n'a pas répondu — le domaine et la clé DKIM n'ont PAS été créés. Mailcow fonctionne : ajoutez le domaine dans Configuration → Domaines de l'interface d'administration, ou relancez l'installation.",
        ES to "Mailcow: la API no respondió; el dominio y la clave DKIM NO se crearon. Mailcow sí está en marcha: añada el dominio en Configuración → Dominios de su interfaz de administración, o vuelva a ejecutar la instalación.",
        RU to "Mailcow: API не ответил — домен и DKIM-ключ НЕ созданы. Сам mailcow работает: добавьте домен в админке (Configuration → Domains) или перезапустите установку.",
        UK to "Mailcow: API не відповів — домен і DKIM-ключ НЕ створені. Сам mailcow працює: додайте домен в адмінці (Configuration → Domains) або перезапустіть встановлення.",
        IT to "Mailcow: l'API non ha risposto: il dominio e la chiave DKIM NON sono stati creati. Mailcow è comunque attivo: aggiungere il dominio in Configurazione → Domini nell'interfaccia di amministrazione, oppure rieseguire l'installazione.",
        JA to "Mailcow：APIが応答しなかったため、ドメインとDKIMキーは作成されていません。Mailcow自体は稼働しています。管理画面の Configuration → Domains でドメインを追加するか、セットアップを再実行してください。",
        ZH to "Mailcow：API 未响应，域名和 DKIM 密钥均未创建。Mailcow 本身正在运行：请在管理界面的 Configuration → Domains 中添加域名，或重新运行安装。"
    ))

    /** One domain could not be created */
    fun mailcowDomainAddFailed(l: AppLanguage, domain: String): String = l.pick(mapOf(
        EN to "Mailcow: could not add domain $domain over the API — add it under Configuration → Domains in the admin UI.",
        DE to "Mailcow: Domain $domain konnte nicht über die API angelegt werden — in der Admin-UI unter Konfiguration → Domains anlegen.",
        FR to "Mailcow : impossible d'ajouter le domaine $domain via l'API — ajoutez-le dans Configuration → Domaines de l'interface d'administration.",
        ES to "Mailcow: no se pudo añadir el dominio $domain mediante la API; añádalo en Configuración → Dominios de la interfaz de administración.",
        RU to "Mailcow: не удалось добавить домен $domain через API — добавьте его в админке (Configuration → Domains).",
        UK to "Mailcow: не вдалося додати домен $domain через API — додайте його в адмінці (Configuration → Domains).",
        IT to "Mailcow: impossibile aggiungere il dominio $domain tramite API: aggiungerlo in Configurazione → Domini nell'interfaccia di amministrazione.",
        JA to "Mailcow：API経由でドメイン $domain を追加できませんでした。管理画面の Configuration → Domains から追加してください。",
        ZH to "Mailcow：无法通过 API 添加域名 $domain——请在管理界面的 Configuration → Domains 中添加。"
    ))

    fun mailcowDKIMAddFailed(l: AppLanguage, domain: String): String = l.pick(mapOf(
        EN to "Mailcow: could not create the DKIM key for $domain over the API — create it under Configuration → ARC/DKIM keys in the admin UI.",
        DE to "Mailcow: DKIM-Schlüssel für $domain konnte nicht über die API erzeugt werden — in der Admin-UI unter Konfiguration → ARC/DKIM-Schlüssel anlegen.",
        FR to "Mailcow : impossible de créer la clé DKIM pour $domain via l'API — créez-la dans Configuration → Clés ARC/DKIM de l'interface d'administration.",
        ES to "Mailcow: no se pudo crear la clave DKIM de $domain mediante la API; créela en Configuración → Claves ARC/DKIM de la interfaz de administración.",
        RU to "Mailcow: не удалось создать DKIM-ключ для $domain через API — создайте его в админке (Configuration → ARC/DKIM keys).",
        UK to "Mailcow: не вдалося створити DKIM-ключ для $domain через API — створіть його в адмінці (Configuration → ARC/DKIM keys).",
        IT to "Mailcow: impossibile creare la chiave DKIM per $domain tramite API: crearla in Configurazione → Chiavi ARC/DKIM nell'interfaccia di amministrazione.",
        JA to "Mailcow：API経由で $domain のDKIMキーを作成できませんでした。管理画面の Configuration → ARC/DKIM keys から作成してください。",
        ZH to "Mailcow：无法通过 API 为 $domain 创建 DKIM 密钥——请在管理界面的 Configuration → ARC/DKIM keys 中创建。"
    ))

    fun mailcowDKIMHeader(l: AppLanguage, record: String): String = l.pick(mapOf(
        EN to "DKIM DNS record (add as TXT for $record):",
        DE to "DKIM-DNS-Eintrag (als TXT für $record anlegen):",
        FR to "Enregistrement DNS DKIM (à ajouter en TXT pour $record) :",
        ES to "Registro DNS DKIM (añadir como TXT para $record):",
        RU to "DKIM DNS-запись (добавьте как TXT для $record):",
        UK to "DKIM DNS-запис (додайте як TXT для $record):",
        IT to "Record DNS DKIM (aggiungere come TXT per $record):",
        JA to "DKIM DNSレコード（$record のTXTとして追加）：",
        ZH to "DKIM DNS 记录（作为 $record 的 TXT 添加）："
    ))

    fun mailcowDKIMNotReady(l: AppLanguage): String = l.pick(mapOf(
        EN to "DKIM is not ready yet — re-run the script or check Configuration → ARC/DKIM keys in the mailcow admin UI.",
        DE to "DKIM ist noch nicht bereit — Skript erneut ausführen oder in der mailcow-Admin-UI unter Konfiguration → ARC/DKIM-Schlüssel nachsehen.",
        FR to "DKIM n'est pas encore prêt — relancez le script ou vérifiez Configuration → Clés ARC/DKIM dans l'admin mailcow.",
        ES to "DKIM aún no está listo: vuelva a ejecutar el script o revise Configuración → Claves ARC/DKIM en la interfaz de mailcow.",
        RU to "DKIM ещё не готов — перезапустите скрипт или проверьте Configuration → ARC/DKIM keys в админке mailcow.",
        UK to "DKIM ще не готовий — перезапустіть скрипт або перевірте Configuration → ARC/DKIM keys в адмінці mailcow.",
        IT to "DKIM non è ancora pronto: rieseguire lo script o controllare Configurazione → Chiavi ARC/DKIM nell'admin di mailcow.",
        JA to "DKIMはまだ準備できていません。スクリプトを再実行するか、mailcow管理画面の Configuration → ARC/DKIM keys を確認してください。",
        ZH to "DKIM 尚未就绪——请重新运行脚本，或在 mailcow 管理界面查看 Configuration → ARC/DKIM keys。"
    ))

    fun mailcowSelfSignedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mail (SMTP/IMAPS) currently uses Mailcow's self-signed certificate.",
        DE to "Mail (SMTP/IMAPS) verwendet derzeit das selbstsignierte Zertifikat von Mailcow.",
        FR to "La messagerie (SMTP/IMAPS) utilise pour le moment le certificat auto-signé de Mailcow.",
        ES to "El correo (SMTP/IMAPS) usa por ahora el certificado autofirmado de Mailcow.",
        RU to "Почта (SMTP/IMAPS) пока использует самоподписанный сертификат Mailcow.",
        UK to "Пошта (SMTP/IMAPS) поки що використовує самопідписаний сертифікат Mailcow.",
        IT to "La posta (SMTP/IMAPS) usa per ora il certificato autofirmato di Mailcow.",
        JA to "メール（SMTP/IMAPS）は現在、Mailcow の自己署名証明書を使用しています。",
        ZH to "邮件（SMTP/IMAPS）目前使用 Mailcow 的自签名证书。"
    ))

    fun mailcowAutoCertNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "SMTP/IMAPS use a trusted TLS certificate automatically (synced from Caddy and refreshed on renewal). Right after setup it may briefly be self-signed until Caddy issues the certificate — usually a few minutes.",
        DE to "SMTP/IMAPS verwenden automatisch ein vertrauenswürdiges TLS-Zertifikat (von Caddy übernommen und bei Erneuerung aktualisiert). Direkt nach der Einrichtung kann es kurz selbstsigniert sein, bis Caddy das Zertifikat ausgestellt hat — meist wenige Minuten.",
        FR to "SMTP/IMAPS utilisent automatiquement un certificat TLS de confiance (repris de Caddy et actualisé au renouvellement). Juste après l'installation, il peut être brièvement auto-signé jusqu'à ce que Caddy émette le certificat — généralement quelques minutes.",
        ES to "SMTP/IMAPS usan automáticamente un certificado TLS de confianza (tomado de Caddy y actualizado al renovar). Justo tras la instalación puede ser autofirmado un momento hasta que Caddy emita el certificado — normalmente unos minutos.",
        RU to "SMTP/IMAPS автоматически используют доверенный TLS-сертификат (берётся из Caddy и обновляется при продлении). Сразу после установки он может быть самоподписанным, пока Caddy не выпустит сертификат — обычно несколько минут.",
        UK to "SMTP/IMAPS автоматично використовують довірений TLS-сертифікат (береться з Caddy й оновлюється при продовженні). Одразу після встановлення він може бути самопідписаним, доки Caddy не випустить сертифікат — зазвичай кілька хвилин.",
        IT to "SMTP/IMAPS usano automaticamente un certificato TLS attendibile (preso da Caddy e aggiornato al rinnovo). Subito dopo l'installazione può essere autofirmato per poco, finché Caddy non emette il certificato — di solito pochi minuti.",
        JA to "SMTP/IMAPS は信頼された TLS 証明書を自動的に使用します（Caddy から同期し、更新時にも反映）。設定直後は Caddy が証明書を発行するまで一時的に自己署名になることがあります（通常は数分）。",
        ZH to "SMTP/IMAPS 会自动使用受信任的 TLS 证书（从 Caddy 同步，续期时刷新）。刚安装后，在 Caddy 签发证书之前可能短暂为自签名——通常几分钟。"
    ))

    fun mailcowTrustedCertHint(l: AppLanguage, domain: String, path: String): String {
        val ssl = "$path/data/assets/ssl"
        return l.pick(mapOf(
            EN to "For a trusted certificate, copy the Caddy certificate for mail.$domain to $ssl/cert.pem and key.pem, then restart Mailcow.",
            DE to "Für ein vertrauenswürdiges Zertifikat kopieren Sie das Caddy-Zertifikat für mail.$domain nach $ssl/cert.pem und key.pem und starten Sie Mailcow danach neu.",
            FR to "Pour un certificat de confiance, copiez le certificat Caddy de mail.$domain vers $ssl/cert.pem et key.pem, puis redémarrez Mailcow.",
            ES to "Para un certificado de confianza, copie el certificado Caddy de mail.$domain a $ssl/cert.pem y key.pem, y luego reinicie Mailcow.",
            RU to "Для доверенного скопируйте сертификат Caddy для mail.$domain в $ssl/cert.pem и key.pem, затем перезапустите Mailcow.",
            UK to "Для довіреного скопіюйте сертифікат Caddy для mail.$domain у $ssl/cert.pem і key.pem, потім перезапустіть Mailcow.",
            IT to "Per un certificato attendibile, copia il certificato Caddy di mail.$domain in $ssl/cert.pem e key.pem, poi riavvia Mailcow.",
            JA to "信頼された証明書にするには、mail.$domain 用の Caddy 証明書を $ssl/cert.pem と key.pem にコピーし、その後 Mailcow を再起動してください。",
            ZH to "如需受信任的证书，请将 mail.$domain 的 Caddy 证书复制到 $ssl/cert.pem 和 key.pem，然后重启 Mailcow。"
        ))
    }

    // ---------------------------------------------- Vaultwarden

    fun adminPanelLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Admin panel",
        DE to "Admin-Panel",
        FR to "Panneau d'administration",
        ES to "Panel de administración",
        RU to "Админ-панель",
        UK to "Адмін-панель",
        IT to "Pannello di amministrazione",
        JA to "管理パネル",
        ZH to "管理面板"
    ))

    fun vaultwardenAdminTokenLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Admin token (generated on the server)",
        DE to "Admin-Token (auf dem Server generiert)",
        FR to "Jeton administrateur (généré sur le serveur)",
        ES to "Token de administrador (generado en el servidor)",
        RU to "Токен админа (сгенерирован на сервере)",
        UK to "Токен адміністратора (згенеровано на сервері)",
        IT to "Token amministratore (generato sul server)",
        JA to "管理者トークン（サーバー上で生成）",
        ZH to "管理员令牌（在服务器上生成）"
    ))

    fun vaultwardenSignupsOpen(l: AppLanguage): String = l.pick(mapOf(
        EN to "Signups: open",
        DE to "Registrierung: offen",
        FR to "Inscriptions : ouvertes",
        ES to "Registro: abierto",
        RU to "Регистрация: открыта",
        UK to "Реєстрація: відкрита",
        IT to "Registrazioni: aperte",
        JA to "登録：可能",
        ZH to "注册：开放"
    ))

    fun vaultwardenSignupsClosed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Signups: closed — invite users from the admin panel",
        DE to "Registrierung: geschlossen — laden Sie Benutzer über das Admin-Panel ein",
        FR to "Inscriptions : fermées — invitez les utilisateurs depuis le panneau d'administration",
        ES to "Registro: cerrado — invite a los usuarios desde el panel de administración",
        RU to "Регистрация: закрыта — приглашайте пользователей из админ-панели",
        UK to "Реєстрація: закрита — запрошуйте користувачів з адмін-панелі",
        IT to "Registrazioni: chiuse — invita gli utenti dal pannello di amministrazione",
        JA to "登録：不可 — 管理パネルからユーザーを招待してください",
        ZH to "注册：关闭 — 请从管理面板邀请用户"
    ))

    fun vaultwardenRegisterNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Sign-in: open the URL and create your own account (your email + a master password you choose). The admin token above is only for the /admin panel.",
        DE to "Anmeldung: Öffnen Sie die URL und erstellen Sie Ihr eigenes Konto (Ihre E-Mail + ein selbst gewähltes Master-Passwort). Das Admin-Token oben ist nur für das /admin-Panel.",
        FR to "Connexion : ouvrez l'URL et créez votre propre compte (votre e-mail + un mot de passe maître de votre choix). Le jeton administrateur ci-dessus sert uniquement au panneau /admin.",
        ES to "Inicio de sesión: abra la URL y cree su propia cuenta (su correo + una contraseña maestra que elija). El token de administrador de arriba es solo para el panel /admin.",
        RU to "Вход: откройте URL и создайте СВОЙ аккаунт (ваш email + мастер-пароль на ваш выбор). Токен админа выше — только для панели /admin.",
        UK to "Вхід: відкрийте URL і створіть СВІЙ акаунт (ваш email + майстер-пароль на ваш вибір). Токен адміністратора вище — лише для панелі /admin.",
        IT to "Accesso: apri l'URL e crea il tuo account (la tua email + una password principale a tua scelta). Il token amministratore sopra è solo per il pannello /admin.",
        JA to "サインイン：URLを開いて自分のアカウントを作成してください（あなたのメール＋自分で決めるマスターパスワード）。上の管理者トークンは/adminパネル専用です。",
        ZH to "登录：打开该网址并创建您自己的账户（您的邮箱 + 您自选的主密码）。上面的管理员令牌仅用于 /admin 面板。"
    ))

    // ---------------------------------------------- Nextcloud

    fun nextcloudOccUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Nextcloud: occ did not answer — trusted domains were not applied; set them in config.php or re-run the setup.",
        DE to "Nextcloud: occ hat nicht geantwortet — vertrauenswürdige Domains wurden nicht gesetzt; in config.php eintragen oder Setup erneut ausführen.",
        FR to "Nextcloud : occ n'a pas répondu — les domaines de confiance n'ont pas été appliqués ; renseignez-les dans config.php ou relancez l'installation.",
        ES to "Nextcloud: occ no respondió; no se aplicaron los dominios de confianza. Configúrelos en config.php o vuelva a ejecutar la instalación.",
        RU to "Nextcloud: occ не ответил — доверенные домены не применены; пропишите их в config.php или перезапустите установку.",
        UK to "Nextcloud: occ не відповів — довірені домени не застосовані; пропишіть їх у config.php або перезапустіть встановлення.",
        IT to "Nextcloud: occ non ha risposto: i domini attendibili non sono stati applicati; impostarli in config.php o rieseguire l'installazione.",
        JA to "Nextcloud：occ が応答しませんでした。信頼済みドメインは適用されていません。config.php で設定するかセットアップを再実行してください。",
        ZH to "Nextcloud：occ 未响应，未应用受信任域名；请在 config.php 中设置或重新运行安装。"
    ))

    /** One config value could not be set */
    fun nextcloudConfigSetFailed(l: AppLanguage, key: String): String = l.pick(mapOf(
        EN to "Nextcloud: could not set $key — set it under Administration settings or in config.php.",
        DE to "Nextcloud: $key konnte nicht gesetzt werden — in den Administrationseinstellungen oder in config.php setzen.",
        FR to "Nextcloud : impossible de définir $key — définissez-le dans les paramètres d'administration ou dans config.php.",
        ES to "Nextcloud: no se pudo establecer $key; configúrelo en los ajustes de administración o en config.php.",
        RU to "Nextcloud: не удалось задать $key — задайте его в настройках администратора или в config.php.",
        UK to "Nextcloud: не вдалося задати $key — задайте його в налаштуваннях адміністратора або в config.php.",
        IT to "Nextcloud: impossibile impostare $key: impostarlo nelle impostazioni di amministrazione o in config.php.",
        JA to "Nextcloud：$key を設定できませんでした。管理設定または config.php で設定してください。",
        ZH to "Nextcloud：无法设置 $key——请在管理设置或 config.php 中设置。"
    ))

    fun administratorLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Administrator",
        DE to "Administrator",
        FR to "Administrateur",
        ES to "Administrador",
        RU to "Администратор",
        UK to "Адміністратор",
        IT to "Amministratore",
        JA to "管理者",
        ZH to "管理员"
    ))

    fun passwordGeneratedOnServerLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Password (generated on the server)",
        DE to "Passwort (auf dem Server generiert)",
        FR to "Mot de passe (généré sur le serveur)",
        ES to "Contraseña (generada en el servidor)",
        RU to "Пароль (сгенерирован на сервере)",
        UK to "Пароль (згенеровано на сервері)",
        IT to "Password (generata sul server)",
        JA to "パスワード（サーバー上で生成）",
        ZH to "密码（在服务器上生成）"
    ))

    // ---------------------------------------------- WireGuard VPN

    fun vpnEndpointLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "VPN endpoint for clients",
        DE to "VPN-Endpunkt für Clients",
        FR to "Point de terminaison VPN pour les clients",
        ES to "Punto de conexión VPN para clientes",
        RU to "VPN-endpoint для клиентов",
        UK to "VPN-endpoint для клієнтів",
        IT to "Endpoint VPN per i client",
        JA to "クライアント用 VPN エンドポイント",
        ZH to "客户端 VPN 接入点"
    ))

    fun vpnClientsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Add client devices in the panel: it generates their configs and QR codes.",
        DE to "Client-Geräte im Panel hinzufügen: Es erzeugt deren Konfigurationen und QR-Codes.",
        FR to "Ajoutez les appareils clients dans le panneau : il génère leurs configurations et QR codes.",
        ES to "Añada los dispositivos cliente en el panel: genera sus configuraciones y códigos QR.",
        RU to "Клиентские устройства добавляются в панели: она генерирует их конфиги и QR-коды.",
        UK to "Клієнтські пристрої додаються в панелі: вона генерує їхні конфіги та QR-коди.",
        IT to "Aggiungi i dispositivi client nel pannello: genera le loro configurazioni e i codici QR.",
        JA to "クライアント端末はパネルで追加します。設定ファイルと QR コードが生成されます。",
        ZH to "在面板中添加客户端设备：面板会生成其配置文件和二维码。"
    ))

    fun shadowsocksLinkLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Connection link (ss://) for clients",
        DE to "Verbindungslink (ss://) für Clients",
        FR to "Lien de connexion (ss://) pour les clients",
        ES to "Enlace de conexión (ss://) para clientes",
        RU to "Ссылка для подключения (ss://) для клиентов",
        UK to "Посилання для підключення (ss://) для клієнтів",
        IT to "Link di connessione (ss://) per i client",
        JA to "クライアント用の接続リンク（ss://）",
        ZH to "客户端连接链接（ss://）"
    ))

    fun shadowsocksClientsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Paste the ss:// link into an Outline / Shadowsocks client, or turn it into a QR code.",
        DE to "Fügen Sie den ss://-Link in einen Outline-/Shadowsocks-Client ein oder erzeugen Sie daraus einen QR-Code.",
        FR to "Collez le lien ss:// dans un client Outline / Shadowsocks, ou convertissez-le en QR code.",
        ES to "Pegue el enlace ss:// en un cliente Outline / Shadowsocks, o conviértalo en un código QR.",
        RU to "Вставьте ссылку ss:// в клиент Outline / Shadowsocks или сделайте из неё QR-код.",
        UK to "Вставте посилання ss:// у клієнт Outline / Shadowsocks або зробіть із нього QR-код.",
        IT to "Incolla il link ss:// in un client Outline / Shadowsocks, o convertilo in un codice QR.",
        JA to "ss:// リンクを Outline / Shadowsocks クライアントに貼り付けるか、QR コードに変換してください。",
        ZH to "将 ss:// 链接粘贴到 Outline / Shadowsocks 客户端，或将其转换为二维码。"
    ))

    fun xrayLinkLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Connection link (vless://) for clients",
        DE to "Verbindungslink (vless://) für Clients",
        FR to "Lien de connexion (vless://) pour les clients",
        ES to "Enlace de conexión (vless://) para clientes",
        RU to "Ссылка для подключения (vless://) для клиентов",
        UK to "Посилання для підключення (vless://) для клієнтів",
        IT to "Link di connessione (vless://) per i client",
        JA to "クライアント用の接続リンク（vless://）",
        ZH to "客户端连接链接（vless://）"
    ))

    fun xrayClientsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Paste the vless:// link into an Xray client (v2rayN, Streisand, Hiddify), or turn it into a QR code.",
        DE to "Fügen Sie den vless://-Link in einen Xray-Client (v2rayN, Streisand, Hiddify) ein oder erzeugen Sie daraus einen QR-Code.",
        FR to "Collez le lien vless:// dans un client Xray (v2rayN, Streisand, Hiddify), ou convertissez-le en QR code.",
        ES to "Pegue el enlace vless:// en un cliente Xray (v2rayN, Streisand, Hiddify), o conviértalo en un código QR.",
        RU to "Вставьте ссылку vless:// в клиент Xray (v2rayN, Streisand, Hiddify) или сделайте из неё QR-код.",
        UK to "Вставте посилання vless:// у клієнт Xray (v2rayN, Streisand, Hiddify) або зробіть із нього QR-код.",
        IT to "Incolla il link vless:// in un client Xray (v2rayN, Streisand, Hiddify), o convertilo in un codice QR.",
        JA to "vless:// リンクを Xray クライアント（v2rayN、Streisand、Hiddify）に貼り付けるか、QR コードに変換してください。",
        ZH to "将 vless:// 链接粘贴到 Xray 客户端（v2rayN、Streisand、Hiddify），或将其转换为二维码。"
    ))

    fun openVPNConfigLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Client profile (.ovpn) — copy everything between the markers into a file and import it",
        DE to "Client-Profil (.ovpn) — alles zwischen den Markierungen in eine Datei kopieren und importieren",
        FR to "Profil client (.ovpn) — copiez tout ce qui se trouve entre les marqueurs dans un fichier et importez-le",
        ES to "Perfil de cliente (.ovpn) — copie todo lo que hay entre los marcadores en un archivo e impórtelo",
        RU to "Профиль клиента (.ovpn) — скопируйте всё между маркерами в файл и импортируйте",
        UK to "Профіль клієнта (.ovpn) — скопіюйте все між маркерами у файл та імпортуйте",
        IT to "Profilo client (.ovpn) — copia tutto ciò che è tra i marcatori in un file e importalo",
        JA to "クライアントプロファイル（.ovpn）— マーカーの間をすべてファイルにコピーしてインポートしてください",
        ZH to "客户端配置（.ovpn）— 将标记之间的全部内容复制到文件并导入"
    ))

    fun openVPNClientsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Import the .ovpn into OpenVPN Connect (iOS/Android/desktop). The same profile can be downloaded later from the Files tab.",
        DE to "Importieren Sie die .ovpn in OpenVPN Connect (iOS/Android/Desktop). Dasselbe Profil kann später im Tab „Dateien“ heruntergeladen werden.",
        FR to "Importez le .ovpn dans OpenVPN Connect (iOS/Android/ordinateur). Le même profil peut être téléchargé plus tard depuis l'onglet Fichiers.",
        ES to "Importe el .ovpn en OpenVPN Connect (iOS/Android/escritorio). El mismo perfil se puede descargar luego desde la pestaña Archivos.",
        RU to "Импортируйте .ovpn в OpenVPN Connect (iOS/Android/десктоп). Тот же профиль позже можно скачать во вкладке «Файлы».",
        UK to "Імпортуйте .ovpn в OpenVPN Connect (iOS/Android/десктоп). Той самий профіль пізніше можна завантажити у вкладці «Файли».",
        IT to "Importa il .ovpn in OpenVPN Connect (iOS/Android/desktop). Lo stesso profilo può essere scaricato in seguito dalla scheda File.",
        JA to "OpenVPN Connect（iOS/Android/デスクトップ）に .ovpn をインポートしてください。同じプロファイルは後で「ファイル」タブからダウンロードできます。",
        ZH to "将 .ovpn 导入 OpenVPN Connect（iOS/Android/桌面）。稍后也可从「文件」标签下载同一配置。"
    ))

    fun adminViaWireGuardNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Note: the admin panels (mail, cloud, photos, vault) are reachable ONLY over WireGuard — add a WireGuard client in the VPN panel and connect with it to manage them. AmneziaWG and this protocol are for general internet access; they do not reach the admin panels.",
        DE to "Hinweis: Die Admin-Oberflächen (Mail, Cloud, Fotos, Vault) sind NUR über WireGuard erreichbar — legen Sie im VPN-Panel einen WireGuard-Client an und verbinden Sie sich damit, um sie zu verwalten. AmneziaWG und dieses Protokoll dienen dem allgemeinen Internetzugang und erreichen die Admin-Oberflächen nicht.",
        FR to "Remarque : les panneaux d'administration (courrier, cloud, photos, vault) ne sont accessibles QUE via WireGuard — créez un client WireGuard dans le panneau VPN et connectez-vous avec pour les gérer. AmneziaWG et ce protocole servent à l'accès Internet général ; ils n'atteignent pas les panneaux d'administration.",
        ES to "Nota: los paneles de administración (correo, nube, fotos, vault) solo son accesibles a través de WireGuard — cree un cliente WireGuard en el panel VPN y conéctese con él para gestionarlos. AmneziaWG y este protocolo son para el acceso general a Internet; no llegan a los paneles de administración.",
        RU to "Примечание: админ-панели (почта, облако, фото, vault) доступны ТОЛЬКО через WireGuard — создайте клиента WireGuard в VPN-панели и подключитесь им для управления. AmneziaWG и этот протокол предназначены для обычного доступа в интернет, до админ-панелей они не доходят.",
        UK to "Примітка: адмін-панелі (пошта, хмара, фото, vault) доступні ЛИШЕ через WireGuard — створіть клієнта WireGuard у VPN-панелі та підключіться ним для керування. AmneziaWG і цей протокол призначені для звичайного доступу до інтернету, до адмін-панелей вони не доходять.",
        IT to "Nota: i pannelli di amministrazione (posta, cloud, foto, vault) sono raggiungibili SOLO tramite WireGuard — crea un client WireGuard nel pannello VPN e connettiti con quello per gestirli. AmneziaWG e questo protocollo servono all'accesso generale a Internet e non raggiungono i pannelli di amministrazione.",
        JA to "注: 管理パネル（メール、クラウド、写真、Vault）は WireGuard 経由でのみアクセスできます。VPN パネルで WireGuard クライアントを作成し、それで接続して管理してください。AmneziaWG とこのプロトコルは一般的なインターネット接続用で、管理パネルには到達しません。",
        ZH to "注意：管理面板（邮件、云盘、相册、Vault）只能通过 WireGuard 访问 — 请在 VPN 面板中创建 WireGuard 客户端并用它连接以进行管理。AmneziaWG 和本协议用于常规互联网访问，无法访问管理面板。"
    ))

    fun amneziaAdminViaWireGuardNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Note: AmneziaWG carries general internet traffic, but the admin panels (mail, cloud, photos, vault) do NOT open over it — they are reachable only over plain WireGuard. Add a WireGuard client in the VPN panel and connect with it to manage them.",
        DE to "Hinweis: AmneziaWG transportiert den allgemeinen Internetverkehr, aber die Admin-Oberflächen (Mail, Cloud, Fotos, Vault) lassen sich darüber NICHT öffnen — sie sind nur über einfaches WireGuard erreichbar. Legen Sie im VPN-Panel einen WireGuard-Client an und verbinden Sie sich damit, um sie zu verwalten.",
        FR to "Remarque : AmneziaWG achemine le trafic Internet général, mais les panneaux d'administration (courrier, cloud, photos, vault) ne s'ouvrent PAS via ce protocole — ils ne sont accessibles que via WireGuard classique. Créez un client WireGuard dans le panneau VPN et connectez-vous avec pour les gérer.",
        ES to "Nota: AmneziaWG transporta el tráfico general de Internet, pero los paneles de administración (correo, nube, fotos, vault) NO se abren a través de él — solo son accesibles mediante WireGuard normal. Cree un cliente WireGuard en el panel VPN y conéctese con él para gestionarlos.",
        RU to "Примечание: AmneziaWG подходит для обычного доступа в интернет, но админ-панели (почта, облако, фото, vault) через него НЕ открываются — они доступны только через обычный WireGuard. Создайте клиента WireGuard в VPN-панели и подключитесь им для управления.",
        UK to "Примітка: AmneziaWG підходить для звичайного доступу до інтернету, але адмін-панелі (пошта, хмара, фото, vault) через нього НЕ відкриваються — вони доступні лише через звичайний WireGuard. Створіть клієнта WireGuard у VPN-панелі та підключіться ним для керування.",
        IT to "Nota: AmneziaWG trasporta il traffico Internet generale, ma i pannelli di amministrazione (posta, cloud, foto, vault) NON si aprono tramite esso — sono raggiungibili solo con WireGuard normale. Crea un client WireGuard nel pannello VPN e connettiti con quello per gestirli.",
        JA to "注: AmneziaWG は一般的なインターネット通信には使えますが、管理パネル（メール、クラウド、写真、Vault）は開けません。管理パネルは通常の WireGuard 経由でのみアクセスできます。VPN パネルで WireGuard クライアントを作成し、それで接続して管理してください。",
        ZH to "注意：AmneziaWG 可用于常规互联网访问，但无法打开管理面板（邮件、云盘、相册、Vault）— 管理面板只能通过普通 WireGuard 访问。请在 VPN 面板中创建 WireGuard 客户端并用它连接以进行管理。"
    ))

    // ---------------------------------------------- Immich

    fun immichAdminWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and create the administrator — until then, anyone who opens the page can register.",
        DE to "WICHTIG: Öffnen Sie diese URL sofort und legen Sie den Administrator an — bis dahin kann sich jeder registrieren, der die Seite öffnet.",
        FR to "IMPORTANT : ouvrez cette URL dès maintenant et créez l'administrateur — d'ici là, quiconque ouvre la page peut s'inscrire.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y cree el administrador — hasta entonces, cualquiera que abra la página puede registrarse.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и создайте администратора — до этого зарегистрироваться может любой, кто откроет страницу.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і створіть адміністратора — доти зареєструватися може будь-хто, хто відкриє сторінку.",
        IT to "IMPORTANTE: apri questo URL subito e crea l'amministratore — fino ad allora chiunque apra la pagina può registrarsi.",
        JA to "重要：今すぐこの URL を開いて管理者を作成してください — それまでは、ページを開いた誰でも登録できます。",
        ZH to "重要：请立即打开此地址并创建管理员 — 在此之前，任何打开该页面的人都可以注册。"
    ))

    // ---------------------------------------------- Seafile

    /** Heartbeat while the first start runs */
    fun seafileWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Seafile: waiting for the first start to write its configuration",
        DE to "Seafile: warte darauf, dass der erste Start seine Konfiguration schreibt",
        FR to "Seafile : en attente de l'ecriture de la configuration au premier demarrage",
        ES to "Seafile: esperando a que el primer arranque escriba su configuración",
        RU to "Seafile: ждём, пока первый запуск запишет свою конфигурацию",
        UK to "Seafile: чекаємо, доки перший запуск запише свою конфігурацію",
        IT to "Seafile: in attesa che il primo avvio scriva la sua configurazione",
        JA to "Seafile: 初回起動が設定ファイルを書き出すのを待っています",
        ZH to "Seafile: 正在等待首次启动写入配置文件"
    ))

    fun seafileUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Seafile did not finish its first start in time — sign-in will be refused until the trusted addresses are set in conf/seahub_settings.py",
        DE to "Seafile hat den ersten Start nicht rechtzeitig beendet — die Anmeldung wird abgelehnt, bis die vertrauten Adressen in conf/seahub_settings.py eingetragen sind",
        FR to "Seafile n'a pas termine son premier demarrage a temps — la connexion sera refusee tant que les adresses de confiance ne sont pas inscrites dans conf/seahub_settings.py",
        ES to "Seafile no terminó su primer arranque a tiempo: el inicio de sesión será rechazado hasta que las direcciones de confianza estén en conf/seahub_settings.py",
        RU to "Seafile не завершил первый запуск вовремя — вход будет отклоняться, пока доверенные адреса не прописаны в conf/seahub_settings.py",
        UK to "Seafile не завершив перший запуск вчасно — вхід відхилятиметься, доки довірені адреси не буде прописано в conf/seahub_settings.py",
        IT to "Seafile non ha completato il primo avvio in tempo: l'accesso verrà rifiutato finché gli indirizzi attendibili non saranno in conf/seahub_settings.py",
        JA to "Seafile の初回起動が時間内に完了しませんでした — conf/seahub_settings.py に信頼するアドレスを設定するまで、ログインは拒否されます",
        ZH to "Seafile 首次启动未能及时完成 — 在 conf/seahub_settings.py 中写入受信任地址之前，登录都会被拒绝"
    ))

    // ---------------------------------------------- PhotoPrism

    /** Report label for the directory PhotoPrism indexes */
    fun photoprismOriginalsLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Put your pictures here, then start indexing in the web interface",
        DE to "Legen Sie Ihre Bilder hier ab und starten Sie dann die Indizierung in der Weboberfläche",
        FR to "Placez vos photos ici, puis lancez l'indexation dans l'interface web",
        ES to "Coloque aquí sus fotos y luego inicie la indexación en la interfaz web",
        RU to "Положите сюда свои фотографии и запустите индексацию в веб-интерфейсе",
        UK to "Покладіть сюди свої фотографії та запустіть індексацію у вебінтерфейсі",
        IT to "Metti qui le tue foto e poi avvia l'indicizzazione nell'interfaccia web",
        JA to "写真をここに置き、ウェブ画面でインデックス作成を開始してください",
        ZH to "请把照片放在这里，然后在网页界面中开始建立索引"
    ))

    // ---------------------------------------------- AdGuard Home

    fun adguardWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "AdGuard Home: waiting for the service to answer",
        DE to "AdGuard Home: Warten auf Antwort des Dienstes",
        FR to "AdGuard Home : en attente de la réponse du service",
        ES to "AdGuard Home: esperando la respuesta del servicio",
        RU to "AdGuard Home: ждём ответа сервиса",
        UK to "AdGuard Home: чекаємо на відповідь сервісу",
        IT to "AdGuard Home: in attesa della risposta del servizio",
        JA to "AdGuard Home: サービスの応答を待っています",
        ZH to "AdGuard Home: 正在等待服务响应"
    ))

    fun adguardConfigureFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "AdGuard Home: the initial configuration failed — the setup wizard is still open, finish it yourself right away",
        DE to "AdGuard Home: Ersteinrichtung fehlgeschlagen — der Assistent ist noch offen, schließen Sie ihn sofort selbst ab",
        FR to "AdGuard Home : la configuration initiale a échoué — l'assistant est encore ouvert, terminez-le vous-même sans attendre",
        ES to "AdGuard Home: la configuración inicial falló — el asistente sigue abierto, complételo usted mismo de inmediato",
        RU to "AdGuard Home: первичная настройка не удалась — мастер установки всё ещё открыт, пройдите его сами прямо сейчас",
        UK to "AdGuard Home: первинне налаштування не вдалося — майстер встановлення ще відкритий, пройдіть його самі просто зараз",
        IT to "AdGuard Home: la configurazione iniziale non è riuscita — la procedura guidata è ancora aperta, completala subito",
        JA to "AdGuard Home: 初期設定に失敗しました — セットアップウィザードは開いたままです。今すぐご自身で完了してください",
        ZH to "AdGuard Home: 初始配置失败 — 设置向导仍然开放，请立即自行完成"
    ))

    fun adguardUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "AdGuard Home did not answer in time — the initial configuration was skipped",
        DE to "AdGuard Home hat nicht rechtzeitig geantwortet — die Ersteinrichtung wurde übersprungen",
        FR to "AdGuard Home n'a pas répondu à temps — la configuration initiale a été ignorée",
        ES to "AdGuard Home no respondió a tiempo: se omitió la configuración inicial",
        RU to "AdGuard Home не ответил вовремя — первичная настройка пропущена",
        UK to "AdGuard Home не відповів вчасно — первинне налаштування пропущено",
        IT to "AdGuard Home non ha risposto in tempo: la configurazione iniziale è stata saltata",
        JA to "AdGuard Home が時間内に応答しませんでした — 初期設定をスキップしました",
        ZH to "AdGuard Home 未及时响应 — 已跳过初始配置"
    ))

    fun adguardDoHKeyMissing(l: AppLanguage): String = l.pick(mapOf(
        EN to "AdGuard Home: could not enable DNS-over-HTTPS behind the proxy — turn it on under Settings, Encryption",
        DE to "AdGuard Home: DNS-over-HTTPS hinter dem Proxy konnte nicht aktiviert werden — schalten Sie es unter Einstellungen, Verschlüsselung ein",
        FR to "AdGuard Home : impossible d'activer DNS-over-HTTPS derriere le proxy — activez-le dans Parametres, Chiffrement",
        ES to "AdGuard Home: no se pudo activar DNS-over-HTTPS detrás del proxy: actívelo en Ajustes, Cifrado",
        RU to "AdGuard Home: не удалось включить DNS-over-HTTPS за прокси — включите его в настройках, раздел шифрования",
        UK to "AdGuard Home: не вдалося увімкнути DNS-over-HTTPS за проксі — увімкніть його в налаштуваннях, розділ шифрування",
        IT to "AdGuard Home: non è stato possibile attivare DNS-over-HTTPS dietro il proxy: attivalo in Impostazioni, Crittografia",
        JA to "AdGuard Home: プロキシ経由の DNS-over-HTTPS を有効にできませんでした — 設定の暗号化から有効にしてください",
        ZH to "AdGuard Home: 无法启用代理后的 DNS-over-HTTPS — 请在设置的加密页面中开启"
    ))

    // ---------------------------------------------- Authelia

    fun autheliaHashFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Authelia: could not create the first account — sign-in is not possible until a user is added to config/users_database.yml",
        DE to "Authelia: Das erste Konto konnte nicht angelegt werden — eine Anmeldung ist erst möglich, wenn ein Benutzer in config/users_database.yml steht",
        FR to "Authelia : impossible de créer le premier compte — aucune connexion n'est possible tant qu'un utilisateur n'est pas ajouté à config/users_database.yml",
        ES to "Authelia: no se pudo crear la primera cuenta: no se podrá iniciar sesión hasta añadir un usuario a config/users_database.yml",
        RU to "Authelia: не удалось создать первую учётную запись — войти будет нельзя, пока пользователь не добавлен в config/users_database.yml",
        UK to "Authelia: не вдалося створити перший обліковий запис — увійти буде неможливо, доки користувача не додано до config/users_database.yml",
        IT to "Authelia: non è stato possibile creare il primo account: non sarà possibile accedere finché un utente non viene aggiunto a config/users_database.yml",
        JA to "Authelia: 最初のアカウントを作成できませんでした — config/users_database.yml にユーザーを追加するまでサインインできません",
        ZH to "Authelia: 无法创建第一个账户——在向 config/users_database.yml 添加用户之前无法登录"
    ))

    fun autheliaProtectsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Asks for this login before",
        DE to "Verlangt diese Anmeldung vor",
        FR to "Demande cette connexion avant",
        ES to "Pide este inicio de sesión antes de",
        RU to "Спрашивает этот вход перед",
        UK to "Запитує цей вхід перед",
        IT to "Chiede questo accesso prima di",
        JA to "この認証を求める対象",
        ZH to "在以下站点前要求此登录"
    ))

    // ---------------------------------------------- Homepage

    /** Report label for the file the install regenerates every run */
    fun homepageGeneratedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Built from your services and rewritten on every install",
        DE to "Aus Ihren Diensten erzeugt und bei jeder Installation neu geschrieben",
        FR to "Construit à partir de vos services et réécrit à chaque installation",
        ES to "Generado a partir de sus servicios y reescrito en cada instalación",
        RU to "Собирается из ваших сервисов и переписывается при каждой установке",
        UK to "Збирається з ваших сервісів і перезаписується при кожному встановленні",
        IT to "Generato dai tuoi servizi e riscritto a ogni installazione",
        JA to "あなたのサービスから生成され、インストールのたびに書き直されます",
        ZH to "由你的服务生成，每次安装都会重写"
    ))

    fun homepageOwnEditsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Yours to edit — never touched again after it is created",
        DE to "Ihre Datei — wird nach dem Anlegen nie wieder angefasst",
        FR to "À vous de la modifier — jamais retouchée après sa création",
        ES to "Suyo para editar: no se vuelve a tocar después de crearse",
        RU to "Ваш файл — после создания больше не трогается",
        UK to "Ваш файл — після створення більше не чіпається",
        IT to "È tuo da modificare: dopo la creazione non viene più toccato",
        JA to "こちらは自由に編集できます — 作成後は二度と変更されません",
        ZH to "这个文件归你编辑——创建之后不会再被修改"
    ))

    // ---------------------------------------------- Pi-hole

    fun piholeWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Pi-hole: waiting for the resolver to answer (it is downloading its blocklists)",
        DE to "Pi-hole: Warten auf Antwort des Resolvers (die Blocklisten werden geladen)",
        FR to "Pi-hole : en attente de la réponse du résolveur (il télécharge ses listes de blocage)",
        ES to "Pi-hole: esperando la respuesta del resolutor (está descargando sus listas de bloqueo)",
        RU to "Pi-hole: ждём ответа резолвера (он скачивает свои списки блокировки)",
        UK to "Pi-hole: чекаємо на відповідь резолвера (він завантажує свої списки блокування)",
        IT to "Pi-hole: in attesa della risposta del resolver (sta scaricando le sue blocklist)",
        JA to "Pi-hole: リゾルバーの応答を待っています（ブロックリストを取得中です）",
        ZH to "Pi-hole: 正在等待解析器响应（它正在下载屏蔽列表）"
    ))

    fun piholeUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Pi-hole did not answer a query in time — it is installed and may still be building its blocklists; check the admin page",
        DE to "Pi-hole hat nicht rechtzeitig auf eine Anfrage geantwortet — es ist installiert und baut möglicherweise noch seine Blocklisten auf; prüfen Sie die Admin-Seite",
        FR to "Pi-hole n'a pas répondu à une requête à temps — il est installé et construit peut-être encore ses listes de blocage ; vérifiez la page d'administration",
        ES to "Pi-hole no respondió a una consulta a tiempo: está instalado y puede seguir construyendo sus listas de bloqueo; revise la página de administración",
        RU to "Pi-hole не ответил на запрос вовремя — он установлен и, возможно, ещё строит списки блокировки; проверьте админ-страницу",
        UK to "Pi-hole не відповів на запит вчасно — він встановлений і, можливо, ще будує списки блокування; перевірте адмін-сторінку",
        IT to "Pi-hole non ha risposto a una query in tempo: è installato e potrebbe stare ancora costruendo le blocklist; controlla la pagina di amministrazione",
        JA to "Pi-hole が時間内に問い合わせへ応答しませんでした — インストールは済んでおり、ブロックリストの構築中の可能性があります。管理ページを確認してください",
        ZH to "Pi-hole 未及时响应查询——它已安装，可能仍在构建屏蔽列表；请检查管理页面"
    ))

    /** Says which clients can actually USE the filter */
    fun piholeServesNetworkNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "DNS is served to the whole network on port 53 — point your router or your devices at this server's address. Make sure port 53 is not reachable from the internet.",
        DE to "DNS wird auf Port 53 im gesamten Netzwerk bereitgestellt — richten Sie Ihren Router oder Ihre Geräte auf die Adresse dieses Servers. Stellen Sie sicher, dass Port 53 aus dem Internet nicht erreichbar ist.",
        FR to "Le DNS est servi à tout le réseau sur le port 53 — pointez votre routeur ou vos appareils vers l'adresse de ce serveur. Assurez-vous que le port 53 n'est pas joignable depuis internet.",
        ES to "El DNS se sirve a toda la red en el puerto 53: apunte su router o sus dispositivos a la dirección de este servidor. Asegúrese de que el puerto 53 no sea accesible desde internet.",
        RU to "DNS отдаётся всей сети на порт 53 — направьте роутер или устройства на адрес этого сервера. Убедитесь, что порт 53 недоступен из интернета.",
        UK to "DNS віддається всій мережі на порт 53 — спрямуйте роутер або пристрої на адресу цього сервера. Переконайтеся, що порт 53 недоступний з інтернету.",
        IT to "Il DNS è servito a tutta la rete sulla porta 53: punta il router o i dispositivi all'indirizzo di questo server. Assicurati che la porta 53 non sia raggiungibile da internet.",
        JA to "DNS はポート 53 でネットワーク全体に提供されます — ルーターまたは各端末をこのサーバーのアドレスに向けてください。ポート 53 がインターネットから到達できないことを確認してください。",
        ZH to "DNS 在 53 端口向整个网络提供服务——请把路由器或各设备指向这台服务器的地址。请确认 53 端口无法从互联网访问。"
    ))

    fun piholeLoopbackNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "DNS answers on this machine only (127.0.0.1:53), so no open resolver is exposed. To serve the network, turn that on in the server's settings and reinstall — only do it where port 53 cannot be reached from the internet.",
        DE to "DNS antwortet nur auf dieser Maschine (127.0.0.1:53), es wird also kein offener Resolver bereitgestellt. Um das Netzwerk zu bedienen, schalten Sie das in den Servereinstellungen ein und installieren Sie neu — nur dort, wo Port 53 aus dem Internet nicht erreichbar ist.",
        FR to "Le DNS ne répond que sur cette machine (127.0.0.1:53) : aucun résolveur ouvert n'est exposé. Pour servir le réseau, activez-le dans les réglages du serveur et réinstallez — uniquement là où le port 53 est injoignable depuis internet.",
        ES to "El DNS responde solo en esta máquina (127.0.0.1:53), así que no se expone ningún resolutor abierto. Para servir a la red, actívelo en los ajustes del servidor y reinstale, solo donde el puerto 53 no sea accesible desde internet.",
        RU to "DNS отвечает только на этой машине (127.0.0.1:53), поэтому открытого резолвера нет. Чтобы отдавать DNS сети, включите это в настройках сервера и переустановите — только там, где порт 53 недоступен из интернета.",
        UK to "DNS відповідає лише на цій машині (127.0.0.1:53), тож відкритого резолвера немає. Щоб віддавати DNS мережі, увімкніть це в налаштуваннях сервера й перевстановіть — лише там, де порт 53 недоступний з інтернету.",
        IT to "Il DNS risponde solo su questa macchina (127.0.0.1:53), quindi non viene esposto alcun resolver aperto. Per servire la rete, attivalo nelle impostazioni del server e reinstalla — solo dove la porta 53 non è raggiungibile da internet.",
        JA to "DNS はこのマシン上（127.0.0.1:53）だけで応答するため、オープンリゾルバーは公開されません。ネットワークに提供するにはサーバー設定で有効にして再インストールしてください — ポート 53 がインターネットから到達できない場所でのみ行ってください。",
        ZH to "DNS 仅在本机（127.0.0.1:53）应答，因此不会暴露开放解析器。若要为网络提供服务，请在服务器设置中开启并重新安装——只在 53 端口无法从互联网访问的地方这样做。"
    ))

    /** Report label for the DoH endpoint clients point at */
    fun cloudflaredNoTokenNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Cloudflare Tunnel is installed but not started: it has no token yet",
        DE to "Cloudflare Tunnel ist installiert, aber nicht gestartet: es fehlt noch das Token",
        FR to "Cloudflare Tunnel est installé mais pas démarré : il n’a pas encore de jeton",
        ES to "Cloudflare Tunnel está instalado pero no iniciado: aún no tiene token",
        RU to "Cloudflare Tunnel установлен, но не запущен: у него ещё нет токена",
        UK to "Cloudflare Tunnel встановлено, але не запущено: у нього ще немає токена",
        IT to "Cloudflare Tunnel è installato ma non avviato: non ha ancora un token",
        JA to "Cloudflare Tunnel はインストール済みですが未起動です。トークンがまだありません",
        ZH to "Cloudflare Tunnel 已安装但未启动：尚未提供令牌"
    ))

    fun cloudflaredTokenNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Create a tunnel in the Cloudflare dashboard and put its token in",
        DE to "Erstellen Sie einen Tunnel im Cloudflare-Dashboard und tragen Sie sein Token ein in",
        FR to "Créez un tunnel dans le tableau de bord Cloudflare et placez son jeton dans",
        ES to "Crea un túnel en el panel de Cloudflare y pon su token en",
        RU to "Создайте туннель в панели Cloudflare и впишите его токен в",
        UK to "Створіть тунель у панелі Cloudflare і впишіть його токен у",
        IT to "Crea un tunnel nel pannello Cloudflare e inserisci il suo token in",
        JA to "Cloudflare のダッシュボードでトンネルを作成し、そのトークンを次に記入してください",
        ZH to "在 Cloudflare 控制台创建隧道，并将其令牌填入"
    ))

    fun cloudflaredRoutesNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Then add these routes to the tunnel",
        DE to "Fügen Sie dem Tunnel dann diese Routen hinzu",
        FR to "Ajoutez ensuite ces routes au tunnel",
        ES to "Después añade estas rutas al túnel",
        RU to "Затем добавьте туннелю эти маршруты",
        UK to "Потім додайте тунелю ці маршрути",
        IT to "Poi aggiungi queste rotte al tunnel",
        JA to "その後、トンネルに次のルートを追加します",
        ZH to "然后为该隧道添加以下路由"
    ))

    fun cloudflaredNoPortsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "With the tunnel running this server needs no inbound port open at all.",
        DE to "Mit laufendem Tunnel braucht dieser Server überhaupt keinen offenen eingehenden Port.",
        FR to "Avec le tunnel actif, ce serveur n’a besoin d’aucun port entrant ouvert.",
        ES to "Con el túnel en marcha, este servidor no necesita ningún puerto entrante abierto.",
        RU to "С работающим туннелем этому серверу не нужен ни один открытый входящий порт.",
        UK to "З працюючим тунелем цьому серверу не потрібен жоден відкритий вхідний порт.",
        IT to "Con il tunnel attivo questo server non ha bisogno di alcuna porta in ingresso aperta.",
        JA to "トンネルが動いていれば、このサーバーに開放すべき受信ポートは一つもありません。",
        ZH to "隧道运行时，这台服务器无需开放任何入站端口。"
    ))

    fun headscaleNoWebUINote(l: AppLanguage): String = l.pick(mapOf(
        EN to "This address is the control server for your devices, not a web page",
        DE to "Diese Adresse ist der Steuerserver für Ihre Geräte, keine Webseite",
        FR to "Cette adresse est le serveur de contrôle de vos appareils, pas une page web",
        ES to "Esta dirección es el servidor de control de tus dispositivos, no una página web",
        RU to "Этот адрес — управляющий сервер для ваших устройств, а не веб-страница",
        UK to "Ця адреса — керуючий сервер для ваших пристроїв, а не вебсторінка",
        IT to "Questo indirizzo è il server di controllo dei tuoi dispositivi, non una pagina web",
        JA to "このアドレスはデバイスの管理サーバーであり、Web ページではありません",
        ZH to "该地址是设备的控制服务器，不是网页"
    ))

    fun headscaleCreateUserNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Create a user and a join key on the server",
        DE to "Benutzer und Beitrittsschlüssel auf dem Server anlegen",
        FR to "Créez un utilisateur et une clé d’adhésion sur le serveur",
        ES to "Crea un usuario y una clave de incorporación en el servidor",
        RU to "Заведите пользователя и ключ подключения на сервере",
        UK to "Створіть користувача та ключ підключення на сервері",
        IT to "Crea un utente e una chiave di adesione sul server",
        JA to "サーバー上でユーザーと参加キーを作成します",
        ZH to "在服务器上创建用户和加入密钥"
    ))

    fun headscaleJoinNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Then join each device with the official Tailscale client",
        DE to "Dann jedes Gerät mit dem offiziellen Tailscale-Client verbinden",
        FR to "Puis connectez chaque appareil avec le client Tailscale officiel",
        ES to "Después une cada dispositivo con el cliente oficial de Tailscale",
        RU to "Затем подключите каждое устройство официальным клиентом Tailscale",
        UK to "Потім підключіть кожен пристрій офіційним клієнтом Tailscale",
        IT to "Poi collega ogni dispositivo con il client Tailscale ufficiale",
        JA to "その後、公式 Tailscale クライアントで各デバイスを参加させます",
        ZH to "然后用官方 Tailscale 客户端让每台设备加入"
    ))

    fun headscaleMagicDNSNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Devices reach each other by name",
        DE to "Geräte erreichen einander über den Namen",
        FR to "Les appareils se joignent par leur nom",
        ES to "Los dispositivos se alcanzan por su nombre",
        RU to "Устройства находят друг друга по имени",
        UK to "Пристрої знаходять одне одного за іменем",
        IT to "I dispositivi si raggiungono per nome",
        JA to "デバイスは名前で互いに到達できます",
        ZH to "设备之间可通过名称互相访问"
    ))

    fun meshNodeTitle(l: AppLanguage): String = l.pick(mapOf(
        EN to "This server inside the mesh",
        DE to "Dieser Server im Mesh",
        FR to "Ce serveur dans le maillage",
        ES to "Este servidor dentro de la malla",
        RU to "Этот сервер внутри mesh-сети",
        UK to "Цей сервер усередині mesh-мережі",
        IT to "Questo server nella rete mesh",
        JA to "メッシュ内のこのサーバー",
        ZH to "网状网络中的本服务器"
    ))

    fun meshNodeExplainNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Your devices reach this server by this name once they join",
        DE to "Ihre Geräte erreichen diesen Server nach dem Beitritt unter diesem Namen",
        FR to "Vos appareils joignent ce serveur sous ce nom une fois connectés",
        ES to "Tus dispositivos llegan a este servidor con este nombre una vez unidos",
        RU to "После подключения ваши устройства обращаются к серверу по этому имени",
        UK to "Після підключення ваші пристрої звертаються до сервера за цим іменем",
        IT to "Una volta collegati, i tuoi dispositivi raggiungono il server con questo nome",
        JA to "参加後、デバイスはこの名前でこのサーバーに接続します",
        ZH to "设备加入后即可通过该名称访问本服务器"
    ))

    fun meshNodeJoinedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The server joined its own mesh as",
        DE to "Der Server ist seinem eigenen Mesh beigetreten als",
        FR to "Le serveur a rejoint son propre maillage sous le nom",
        ES to "El servidor se unió a su propia malla como",
        RU to "Сервер подключился к своей же mesh-сети как",
        UK to "Сервер підключився до власної mesh-мережі як",
        IT to "Il server si è unito alla propria rete mesh come",
        JA to "サーバーが自身のメッシュに参加しました:",
        ZH to "服务器已加入自身的网状网络，名称为"
    ))

    fun meshNodeNoKeyNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "could not mint a join key — the server will not be in its own mesh until one is given",
        DE to "Beitrittsschlüssel konnte nicht erstellt werden — der Server bleibt bis dahin nicht im eigenen Mesh",
        FR to "impossible de créer une clé d’adhésion — le serveur restera hors de son propre maillage",
        ES to "no se pudo crear una clave de incorporación — el servidor no estará en su propia malla",
        RU to "не удалось выпустить ключ подключения — сервер не войдёт в собственную mesh-сеть, пока ключ не выдан",
        UK to "не вдалося випустити ключ підключення — сервер не ввійде у власну mesh-мережу, доки ключа немає",
        IT to "impossibile creare una chiave di adesione — il server resterà fuori dalla propria rete mesh",
        JA to "参加キーを発行できませんでした。キーを与えるまでサーバーは自身のメッシュに入りません",
        ZH to "无法签发加入密钥——在提供密钥之前服务器不会加入自身的网状网络"
    ))

    fun adguardDoHNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "DNS-over-HTTPS for your devices",
        DE to "DNS-over-HTTPS für Ihre Geräte",
        FR to "DNS-over-HTTPS pour vos appareils",
        ES to "DNS-over-HTTPS para sus dispositivos",
        RU to "DNS-over-HTTPS для ваших устройств",
        UK to "DNS-over-HTTPS для ваших пристроїв",
        IT to "DNS-over-HTTPS per i tuoi dispositivi",
        JA to "デバイス向けの DNS-over-HTTPS",
        ZH to "供你的设备使用的 DNS-over-HTTPS"
    ))

    fun adguardPlainDNSNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Plain DNS on port 53 answers on this server only: a resolver open to the internet is abused for amplification attacks within days.",
        DE to "Klassisches DNS auf Port 53 antwortet nur auf diesem Server: ein im Internet offener Resolver wird binnen Tagen für Amplification-Angriffe missbraucht.",
        FR to "Le DNS classique sur le port 53 ne répond que sur ce serveur : un résolveur ouvert sur internet est détourné pour des attaques par amplification en quelques jours.",
        ES to "El DNS clásico en el puerto 53 solo responde en este servidor: un resolutor abierto a internet se usa para ataques de amplificación en pocos días.",
        RU to "Обычный DNS на порту 53 отвечает только на этом сервере: открытый в интернет резолвер за считанные дни используют для атак усиления.",
        UK to "Звичайний DNS на порту 53 відповідає лише на цьому сервері: відкритий в інтернет резолвер за лічені дні використають для атак підсилення.",
        IT to "Il DNS classico sulla porta 53 risponde solo su questo server: un resolver aperto su internet viene sfruttato per attacchi di amplificazione in pochi giorni.",
        JA to "ポート 53 の通常の DNS はこのサーバー内でのみ応答します。インターネットに開いたリゾルバは数日で増幅攻撃に悪用されます。",
        ZH to "端口 53 上的普通 DNS 仅在本服务器内响应：对互联网开放的解析器几天内就会被用于放大攻击。"
    ))

    // ---------------------------------------------- Jellyfin

    // ---------------------------------------------- Minecraft

    /** Label for the server flavour on the report line */
    fun minecraftFlavourLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Server type",
        DE to "Servertyp",
        FR to "Type de serveur",
        ES to "Tipo de servidor",
        RU to "Тип сервера",
        UK to "Тип сервера",
        IT to "Tipo di server",
        JA to "サーバーの種類",
        ZH to "服务器类型"
    ))

    fun minecraftEULANotAccepted(l: AppLanguage): String = l.pick(mapOf(
        EN to "NOT STARTED: Mojang's EULA is not accepted. Accept it in the app and reinstall.",
        DE to "NICHT GESTARTET: Mojangs EULA ist nicht akzeptiert. In der App akzeptieren und neu installieren.",
        FR to "NON DEMARRE : le CLUF de Mojang n'est pas accepte. Acceptez-le dans l'app et reinstallez.",
        ES to "NO INICIADO: no se ha aceptado el EULA de Mojang. Acepte en la app y reinstale.",
        RU to "НЕ ЗАПУЩЕН: лицензия Mojang не принята. Примите её в приложении и переустановите.",
        UK to "НЕ ЗАПУЩЕНО: ліцензію Mojang не прийнято. Прийміть її в застосунку і перевстановіть.",
        IT to "NON AVVIATO: l'EULA di Mojang non e accettato. Accettalo nell'app e reinstalla.",
        JA to "起動していません: Mojang の EULA が未承諾です。アプリで承諾して再インストールしてください。",
        ZH to "未启动：尚未接受 Mojang 的 EULA。请在应用中接受后重新安装。"
    ))

    /** No whitelist: anyone who knows the address can join */
    fun minecraftVersionFollowsLatest(l: AppLanguage): String = l.pick(mapOf(
        EN to "Version: latest. A restart after a new release moves this world to it.",
        DE to "Version: neueste. Ein Neustart nach einer neuen Ausgabe verschiebt diese Welt dorthin.",
        FR to "Version : la plus recente. Un redemarrage apres une nouvelle sortie y deplace ce monde.",
        ES to "Version: la mas reciente. Un reinicio tras una nueva version mueve este mundo a ella.",
        RU to "Версия: последняя. Перезапуск после нового релиза переносит этот мир на него.",
        UK to "Версія: остання. Перезапуск після нового релізу переносить цей світ на нього.",
        IT to "Versione: la piu recente. Un riavvio dopo una nuova uscita sposta questo mondo su di essa.",
        JA to "バージョン: 最新。新しいリリース後の再起動で、このワールドはそちらへ移ります。",
        ZH to "版本：最新。新版本发布后重启会把这个世界迁移过去。"
    ))

    /** Label for the mod list on the report line */
    fun minecraftModsLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mods",
        DE to "Mods",
        FR to "Mods",
        ES to "Mods",
        RU to "Моды",
        UK to "Моди",
        IT to "Mod",
        JA to "Mod",
        ZH to "模组"
    ))

    fun minecraftModsNeedLoader(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mods are listed, but a Vanilla server loads none. Pick Fabric or Forge (mods), or Paper (plugins).",
        DE to "Mods sind eingetragen, ein Vanilla-Server ladt aber keine. Wahle Fabric oder Forge (Mods) oder Paper (Plugins).",
        FR to "Des mods sont listes, mais un serveur Vanilla n'en charge aucun. Choisissez Fabric ou Forge (mods), ou Paper (plugins).",
        ES to "Hay mods en la lista, pero un servidor Vanilla no carga ninguno. Elija Fabric o Forge (mods), o Paper (plugins).",
        RU to "Моды указаны, но сервер Vanilla не загружает ни одного. Выберите Fabric или Forge (моды) либо Paper (плагины).",
        UK to "Моди вказано, але сервер Vanilla не завантажує жодного. Виберiть Fabric або Forge (моди) чи Paper (плагiни).",
        IT to "Sono elencate delle mod, ma un server Vanilla non ne carica nessuna. Scegli Fabric o Forge (mod), oppure Paper (plugin).",
        JA to "Mod が指定されていますが、Vanilla サーバーはどれも読み込みません。Fabric か Forge (Mod)、または Paper (プラグイン) を選んでください。",
        ZH to "已列出模组，但 Vanilla 服务器不会加载任何模组。请选择 Fabric 或 Forge（模组）或 Paper（插件）。"
    ))

    fun minecraftModsClientSide(l: AppLanguage): String = l.pick(mapOf(
        EN to "Players need the same mods installed in their game to join.",
        DE to "Spieler brauchen dieselben Mods in ihrem Spiel, um beizutreten.",
        FR to "Les joueurs doivent avoir les memes mods dans leur jeu pour se connecter.",
        ES to "Los jugadores necesitan los mismos mods en su juego para entrar.",
        RU to "Чтобы зайти, у игроков должны стоять те же моды.",
        UK to "Щоб зайти, у гравцiв мають бути тi самi моди.",
        IT to "I giocatori devono avere le stesse mod nel loro gioco per entrare.",
        JA to "参加するには、プレイヤーの側にも同じ Mod が必要です。",
        ZH to "玩家需要在自己的游戏里安装相同的模组才能加入。"
    ))

    fun minecraftNoWhitelist(l: AppLanguage): String = l.pick(mapOf(
        EN to "No whitelist: anyone who knows the address can join.",
        DE to "Keine Whitelist: jeder, der die Adresse kennt, kann beitreten.",
        FR to "Pas de liste blanche : quiconque connait l'adresse peut se connecter.",
        ES to "Sin lista blanca: cualquiera que sepa la direccion puede entrar.",
        RU to "Без белого списка: зайти может любой, кто знает адрес.",
        UK to "Без білого списку: увійти може будь-хто, хто знає адресу.",
        IT to "Nessuna whitelist: chiunque conosca l'indirizzo puo entrare.",
        JA to "ホワイトリストなし: アドレスを知っていれば誰でも参加できます。",
        ZH to "没有白名单：知道地址的人都能加入。"
    ))

    /** Bedrock on ARM runs the x86-64 server under box64 */
    fun minecraftBedrockOnArm(l: AppLanguage): String = l.pick(mapOf(
        EN to "On ARM machines this runs the x86-64 server under emulation (box64): slower, and only on kernels with 4 KB pages (not the Raspberry Pi 5 default).",
        DE to "Auf ARM-Maschinen laeuft der x86-64-Server unter Emulation (box64): langsamer und nur mit einem Kernel mit 4-KB-Seiten (nicht der Standard des Raspberry Pi 5).",
        FR to "Sur les machines ARM, le serveur x86-64 tourne sous emulation (box64) : plus lent, et seulement avec un noyau a pages de 4 Ko (pas celui du Raspberry Pi 5 par defaut).",
        ES to "En maquinas ARM ejecuta el servidor x86-64 bajo emulacion (box64): mas lento, y solo con un kernel de paginas de 4 KB (no el de serie del Raspberry Pi 5).",
        RU to "На ARM-машинах это x86-64 сервер под эмуляцией (box64): медленнее и только с ядром на страницах 4 КБ (у Raspberry Pi 5 по умолчанию не так).",
        UK to "На ARM-машинах це x86-64 сервер під емуляцією (box64): повільніше і лише з ядром на сторінках 4 КБ (у Raspberry Pi 5 типово не так).",
        IT to "Su macchine ARM esegue il server x86-64 in emulazione (box64): piu lento, e solo con un kernel a pagine da 4 KB (non quello predefinito del Raspberry Pi 5).",
        JA to "ARM マシンでは x86-64 のサーバーをエミュレーション (box64) で動かします。遅くなり、4 KB ページのカーネルでしか動きません (Raspberry Pi 5 の既定とは異なります)。",
        ZH to "在 ARM 机器上，这是通过模拟 (box64) 运行的 x86-64 服务器：速度更慢，且只能在 4 KB 页的内核上运行（Raspberry Pi 5 默认不是）。"
    ))

    /** Bedrock left stopped on a kernel the emulator cannot use */
    fun minecraftBedrockNeedsSmallPages(l: AppLanguage): String = l.pick(mapOf(
        EN to "not started: the x86 emulator needs a kernel with 4 KB pages. On a Raspberry Pi 5 add kernel=kernel8.img to /boot/firmware/config.txt and reboot.",
        DE to "nicht gestartet: der x86-Emulator braucht einen Kernel mit 4-KB-Seiten. Auf einem Raspberry Pi 5 kernel=kernel8.img in /boot/firmware/config.txt eintragen und neu starten.",
        FR to "non demarre : l'emulateur x86 a besoin d'un noyau a pages de 4 Ko. Sur un Raspberry Pi 5, ajoutez kernel=kernel8.img dans /boot/firmware/config.txt et redemarrez.",
        ES to "no iniciado: el emulador x86 necesita un kernel con paginas de 4 KB. En un Raspberry Pi 5 anade kernel=kernel8.img a /boot/firmware/config.txt y reinicia.",
        RU to "не запущен: эмулятору x86 нужно ядро со страницами 4 КБ. На Raspberry Pi 5 добавьте kernel=kernel8.img в /boot/firmware/config.txt и перезагрузите.",
        UK to "не запущено: емулятору x86 потрібне ядро зі сторінками 4 КБ. На Raspberry Pi 5 додайте kernel=kernel8.img у /boot/firmware/config.txt і перезавантажте.",
        IT to "non avviato: l'emulatore x86 richiede un kernel con pagine da 4 KB. Su un Raspberry Pi 5 aggiungi kernel=kernel8.img a /boot/firmware/config.txt e riavvia.",
        JA to "起動していません: x86 エミュレーターには 4 KB ページのカーネルが必要です。Raspberry Pi 5 では /boot/firmware/config.txt に kernel=kernel8.img を追加して再起動してください。",
        ZH to "未启动：x86 模拟器需要 4 KB 页的内核。在 Raspberry Pi 5 上，请在 /boot/firmware/config.txt 中加入 kernel=kernel8.img 并重启。"
    ))

    fun craftyFirstLogin(l: AppLanguage): String = l.pick(mapOf(
        EN to "First login is printed on the server in",
        DE to "Erster Login steht auf dem Server in",
        FR to "Le premier identifiant est ecrit sur le serveur dans",
        ES to "El primer acceso se escribe en el servidor en",
        RU to "Первый логин напечатан на сервере в",
        UK to "Перший логін надруковано на сервері в",
        IT to "Il primo accesso e scritto sul server in",
        JA to "最初のログイン情報はサーバー上のこのファイルにあります:",
        ZH to "首次登录信息写在服务器上的这个文件里："
    ))

    fun jellyfinAdminWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and finish the setup wizard — until you do, whoever opens the page becomes the administrator.",
        DE to "WICHTIG: Öffnen Sie diese URL sofort und schließen Sie den Einrichtungsassistenten ab — bis dahin wird jeder, der die Seite öffnet, zum Administrator.",
        FR to "IMPORTANT : ouvrez cette URL dès maintenant et terminez l'assistant de configuration — d'ici là, quiconque ouvre la page devient administrateur.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y complete el asistente de configuración — hasta entonces, quien abra la página se convierte en administrador.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и пройдите мастер настройки — до этого администратором станет любой, кто откроет страницу.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і пройдіть майстер налаштування — доти адміністратором стане будь-хто, хто відкриє сторінку.",
        IT to "IMPORTANTE: apri questo URL subito e completa la procedura guidata — fino ad allora chiunque apra la pagina diventa amministratore.",
        JA to "重要：今すぐこの URL を開いて初期設定を完了してください — それまでは、ページを開いた人が管理者になります。",
        ZH to "重要：请立即打开此地址并完成初始设置向导 — 在此之前，打开该页面的人将成为管理员。"
    ))

    /** Label for the media directory line in the report */
    fun jellyfinLibraryLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Media library (mounted read-only)",
        DE to "Medienbibliothek (schreibgeschützt eingebunden)",
        FR to "Bibliotheque multimedia (montee en lecture seule)",
        ES to "Biblioteca multimedia (montada en solo lectura)",
        RU to "Медиатека (примонтирована только для чтения)",
        UK to "Медіатека (змонтована лише для читання)",
        IT to "Libreria multimediale (montata in sola lettura)",
        JA to "メディアライブラリ（読み取り専用でマウント）",
        ZH to "媒体库（以只读方式挂载）"
    ))

    // ---------------------------------------------- Forgejo

    fun forgejoWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Forgejo: waiting for the server to answer",
        DE to "Forgejo: warte auf eine Antwort des Servers",
        FR to "Forgejo : en attente de la réponse du serveur",
        ES to "Forgejo: esperando la respuesta del servidor",
        RU to "Forgejo: ожидание ответа сервера",
        UK to "Forgejo: очікування відповіді сервера",
        IT to "Forgejo: in attesa della risposta del server",
        JA to "Forgejo: サーバーの応答を待機中",
        ZH to "Forgejo：等待服务器响应"
    ))

    fun forgejoAdminCreateFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Forgejo: could not create the administrator — create it on the server with: forgejo admin user create",
        DE to "Forgejo: Administrator konnte nicht angelegt werden — legen Sie ihn auf dem Server an mit: forgejo admin user create",
        FR to "Forgejo : impossible de créer l'administrateur — créez-le sur le serveur avec : forgejo admin user create",
        ES to "Forgejo: no se pudo crear el administrador — créelo en el servidor con: forgejo admin user create",
        RU to "Forgejo: не удалось создать администратора — создайте его на сервере командой: forgejo admin user create",
        UK to "Forgejo: не вдалося створити адміністратора — створіть його на сервері командою: forgejo admin user create",
        IT to "Forgejo: impossibile creare l'amministratore — crealo sul server con: forgejo admin user create",
        JA to "Forgejo: 管理者を作成できませんでした — サーバー上で forgejo admin user create を実行して作成してください",
        ZH to "Forgejo：无法创建管理员 — 请在服务器上使用 forgejo admin user create 创建"
    ))

    fun forgejoUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Forgejo did not answer in time — the administrator was not created; check the container logs",
        DE to "Forgejo hat nicht rechtzeitig geantwortet — der Administrator wurde nicht angelegt; prüfen Sie die Container-Logs",
        FR to "Forgejo n'a pas répondu à temps — l'administrateur n'a pas été créé ; consultez les journaux du conteneur",
        ES to "Forgejo no respondió a tiempo — no se creó el administrador; revise los registros del contenedor",
        RU to "Forgejo не ответил вовремя — администратор не создан; посмотрите логи контейнера",
        UK to "Forgejo не відповів вчасно — адміністратора не створено; перегляньте логи контейнера",
        IT to "Forgejo non ha risposto in tempo — l'amministratore non è stato creato; controlla i log del container",
        JA to "Forgejo が時間内に応答しませんでした — 管理者は作成されていません。コンテナのログを確認してください",
        ZH to "Forgejo 未在时限内响应 — 管理员尚未创建；请检查容器日志"
    ))

    fun forgejoRegistrationClosedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Registration is closed — add further users in Site Administration.",
        DE to "Registrierung ist geschlossen — weitere Benutzer legen Sie in der Website-Verwaltung an.",
        FR to "L'inscription est fermée — ajoutez d'autres utilisateurs dans l'administration du site.",
        ES to "El registro está cerrado — añada más usuarios en la administración del sitio.",
        RU to "Регистрация закрыта — новых пользователей заводите в администрировании сайта.",
        UK to "Реєстрацію закрито — нових користувачів створюйте в адмініструванні сайту.",
        IT to "La registrazione è chiusa — aggiungi altri utenti nell'amministrazione del sito.",
        JA to "登録は閉じています — 追加のユーザーはサイト管理から作成してください。",
        ZH to "注册已关闭 — 请在站点管理中添加其他用户。"
    ))

    fun forgejoSSHNote(l: AppLanguage, host: String, port: Int): String = l.pick(mapOf(
        EN to "Git over SSH: port $port — git clone ssh://git@$host:$port/user/repo.git",
        DE to "Git über SSH: Port $port — git clone ssh://git@$host:$port/user/repo.git",
        FR to "Git via SSH : port $port — git clone ssh://git@$host:$port/user/repo.git",
        ES to "Git por SSH: puerto $port — git clone ssh://git@$host:$port/user/repo.git",
        RU to "Git по SSH: порт $port — git clone ssh://git@$host:$port/user/repo.git",
        UK to "Git через SSH: порт $port — git clone ssh://git@$host:$port/user/repo.git",
        IT to "Git via SSH: porta $port — git clone ssh://git@$host:$port/user/repo.git",
        JA to "SSH 経由の Git: ポート $port — git clone ssh://git@$host:$port/user/repo.git",
        ZH to "通过 SSH 使用 Git：端口 $port — git clone ssh://git@$host:$port/user/repo.git"
    ))

    fun forgejoSSHDisabledNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Git over SSH is off — clone and push over HTTPS with an access token.",
        DE to "Git über SSH ist aus — klonen und pushen Sie über HTTPS mit einem Zugriffstoken.",
        FR to "Git via SSH est désactivé — clonez et poussez via HTTPS avec un jeton d'accès.",
        ES to "Git por SSH está desactivado — clone y suba por HTTPS con un token de acceso.",
        RU to "Git по SSH выключен — клонируйте и отправляйте изменения по HTTPS с токеном доступа.",
        UK to "Git через SSH вимкнено — клонуйте та надсилайте зміни через HTTPS з токеном доступу.",
        IT to "Git via SSH è disattivato — clona e invia tramite HTTPS con un token di accesso.",
        JA to "SSH 経由の Git は無効です — アクセストークンを使って HTTPS でクローンおよびプッシュしてください。",
        ZH to "已关闭通过 SSH 使用 Git — 请使用访问令牌通过 HTTPS 克隆和推送。"
    ))

    // ---------------------------------------------- GitLab

    /** Heartbeat while the omnibus image runs its first reconfigure */
    fun gitlabWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "GitLab: waiting for the first start to finish — this takes several minutes",
        DE to "GitLab: warte auf den Abschluss des ersten Starts — das dauert einige Minuten",
        FR to "GitLab : en attente de la fin du premier démarrage — cela prend plusieurs minutes",
        ES to "GitLab: esperando a que termine el primer arranque — tarda varios minutos",
        RU to "GitLab: ожидание завершения первого запуска — это занимает несколько минут",
        UK to "GitLab: очікування завершення першого запуску — це триває кілька хвилин",
        IT to "GitLab: in attesa del completamento del primo avvio — richiede alcuni minuti",
        JA to "GitLab: 初回起動の完了を待機中 — 数分かかります",
        ZH to "GitLab：等待首次启动完成 — 需要几分钟"
    ))

    /** The deadline expired */
    fun gitlabStillStarting(l: AppLanguage): String = l.pick(mapOf(
        EN to "GitLab has not finished starting yet — it continues in the background; sign-up must then be closed in the Admin Area",
        DE to "GitLab ist noch nicht fertig gestartet — es läuft im Hintergrund weiter; die Registrierung muss dann im Admin-Bereich geschlossen werden",
        FR to "GitLab n'a pas fini de démarrer — il continue en arrière-plan ; l'inscription devra alors être fermée dans la zone d'administration",
        ES to "GitLab aún no ha terminado de arrancar — continúa en segundo plano; entonces hay que cerrar el registro en el área de administración",
        RU to "GitLab ещё не завершил запуск — он продолжается в фоне; регистрацию тогда нужно закрыть в панели администратора",
        UK to "GitLab ще не завершив запуск — він триває у фоні; реєстрацію тоді потрібно закрити в панелі адміністратора",
        IT to "GitLab non ha ancora finito di avviarsi — prosegue in background; la registrazione va poi chiusa nell'area di amministrazione",
        JA to "GitLab の起動はまだ完了していません — バックグラウンドで継続します。その場合は管理エリアで登録を閉じてください",
        ZH to "GitLab 尚未启动完成 — 它会在后台继续；届时请在管理区域关闭注册"
    ))

    fun gitlabSignupCloseFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "GitLab: could not close registration — turn off Sign-up enabled in the Admin Area, General settings",
        DE to "GitLab: Registrierung konnte nicht geschlossen werden — deaktivieren Sie die Registrierung im Admin-Bereich unter Allgemein",
        FR to "GitLab : impossible de fermer l'inscription — désactivez l'inscription dans la zone d'administration, paramètres généraux",
        ES to "GitLab: no se pudo cerrar el registro — desactive el registro en el área de administración, ajustes generales",
        RU to "GitLab: не удалось закрыть регистрацию — отключите её в панели администратора, общие настройки",
        UK to "GitLab: не вдалося закрити реєстрацію — вимкніть її в панелі адміністратора, загальні налаштування",
        IT to "GitLab: impossibile chiudere la registrazione — disattivala nell'area di amministrazione, impostazioni generali",
        JA to "GitLab: 登録を閉じられませんでした — 管理エリアの一般設定でサインアップを無効にしてください",
        ZH to "GitLab：无法关闭注册 — 请在管理区域的常规设置中关闭注册"
    ))

    fun gitlabRegistrationClosedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Registration is closed — add further users in the Admin Area.",
        DE to "Registrierung ist geschlossen — weitere Benutzer legen Sie im Admin-Bereich an.",
        FR to "L'inscription est fermée — ajoutez d'autres utilisateurs dans la zone d'administration.",
        ES to "El registro está cerrado — añada más usuarios en el área de administración.",
        RU to "Регистрация закрыта — новых пользователей заводите в панели администратора.",
        UK to "Реєстрацію закрито — нових користувачів створюйте в панелі адміністратора.",
        IT to "La registrazione è chiusa — aggiungi altri utenti nell'area di amministrazione.",
        JA to "登録は閉じています — 追加のユーザーは管理エリアから作成してください。",
        ZH to "注册已关闭 — 请在管理区域添加其他用户。"
    ))

    fun gitlabFirstStartNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The first start takes several minutes — until it finishes the address answers with an error.",
        DE to "Der erste Start dauert einige Minuten — bis dahin antwortet die Adresse mit einem Fehler.",
        FR to "Le premier démarrage prend plusieurs minutes — jusque-là l'adresse répond par une erreur.",
        ES to "El primer arranque tarda varios minutos — hasta que termine, la dirección responde con un error.",
        RU to "Первый запуск занимает несколько минут — до его окончания адрес отвечает ошибкой.",
        UK to "Перший запуск триває кілька хвилин — до його завершення адреса відповідає помилкою.",
        IT to "Il primo avvio richiede alcuni minuti — fino ad allora l'indirizzo risponde con un errore.",
        JA to "初回起動には数分かかります — 完了するまでこのアドレスはエラーを返します。",
        ZH to "首次启动需要几分钟 — 在此之前该地址会返回错误。"
    ))

    fun gitlabSSHNote(l: AppLanguage, host: String, port: Int): String = l.pick(mapOf(
        EN to "Git over SSH: port $port — git clone ssh://git@$host:$port/user/repo.git",
        DE to "Git über SSH: Port $port — git clone ssh://git@$host:$port/user/repo.git",
        FR to "Git via SSH : port $port — git clone ssh://git@$host:$port/user/repo.git",
        ES to "Git por SSH: puerto $port — git clone ssh://git@$host:$port/user/repo.git",
        RU to "Git по SSH: порт $port — git clone ssh://git@$host:$port/user/repo.git",
        UK to "Git через SSH: порт $port — git clone ssh://git@$host:$port/user/repo.git",
        IT to "Git via SSH: porta $port — git clone ssh://git@$host:$port/user/repo.git",
        JA to "SSH 経由の Git: ポート $port — git clone ssh://git@$host:$port/user/repo.git",
        ZH to "通过 SSH 使用 Git：端口 $port — git clone ssh://git@$host:$port/user/repo.git"
    ))

    fun gitlabSSHDisabledNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Git over SSH is off — clone and push over HTTPS with an access token.",
        DE to "Git über SSH ist aus — klonen und pushen Sie über HTTPS mit einem Zugriffstoken.",
        FR to "Git via SSH est désactivé — clonez et poussez via HTTPS avec un jeton d'accès.",
        ES to "Git por SSH está desactivado — clone y suba por HTTPS con un token de acceso.",
        RU to "Git по SSH выключен — клонируйте и отправляйте изменения по HTTPS с токеном доступа.",
        UK to "Git через SSH вимкнено — клонуйте та надсилайте зміни через HTTPS з токеном доступу.",
        IT to "Git via SSH è disattivato — clona e invia tramite HTTPS con un token di accesso.",
        JA to "SSH 経由の Git は無効です — アクセストークンを使って HTTPS でクローンおよびプッシュしてください。",
        ZH to "已关闭通过 SSH 使用 Git — 请使用访问令牌通过 HTTPS 克隆和推送。"
    ))

    // ---------------------------------------------- Mailu

    fun mailuWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mailu: waiting for the admin service to answer",
        DE to "Mailu: warten auf eine Antwort des Admin-Dienstes",
        FR to "Mailu : en attente de la réponse du service d'administration",
        ES to "Mailu: esperando respuesta del servicio de administración",
        RU to "Mailu: ждём ответа админ-сервиса",
        UK to "Mailu: чекаємо на відповідь адмін-сервісу",
        IT to "Mailu: in attesa della risposta del servizio di amministrazione",
        JA to "Mailu：管理サービスの応答を待っています",
        ZH to "Mailu：正在等待管理服务响应"
    ))

    fun mailuDomainImportFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mailu: the mail domains were NOT created. Mailu itself is running: add them under Domains in its admin UI, or re-run the setup.",
        DE to "Mailu: Die Mail-Domains wurden NICHT angelegt. Mailu selbst läuft: Legen Sie sie in der Admin-UI unter Domains an oder führen Sie das Setup erneut aus.",
        FR to "Mailu : les domaines de messagerie n'ont PAS été créés. Mailu fonctionne : ajoutez-les dans Domaines de son interface d'administration, ou relancez l'installation.",
        ES to "Mailu: los dominios de correo NO se crearon. Mailu está en marcha: añádelos en Dominios de su panel de administración o vuelve a ejecutar la instalación.",
        RU to "Mailu: почтовые домены НЕ созданы. Сам Mailu работает: добавьте их в разделе Domains его админки или перезапустите установку.",
        UK to "Mailu: поштові домени НЕ створено. Сам Mailu працює: додайте їх у розділі Domains його адмінки або перезапустіть встановлення.",
        IT to "Mailu: i domini di posta NON sono stati creati. Mailu è in funzione: aggiungili in Domini nel suo pannello di amministrazione o ripeti l'installazione.",
        JA to "Mailu：メールドメインは作成されませんでした。Mailu 自体は稼働しています。管理画面の Domains から追加するか、セットアップをやり直してください。",
        ZH to "Mailu：邮件域名未创建。Mailu 本身正在运行：请在其管理界面的 Domains 中添加，或重新运行安装。"
    ))

    fun mailuUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mailu did not answer in time — the mail domains and DKIM keys were not created; check the container logs",
        DE to "Mailu hat nicht rechtzeitig geantwortet — Mail-Domains und DKIM-Schlüssel wurden nicht angelegt; prüfen Sie die Container-Logs",
        FR to "Mailu n'a pas répondu à temps — les domaines et les clés DKIM n'ont pas été créés ; consultez les journaux du conteneur",
        ES to "Mailu no respondió a tiempo: los dominios y las claves DKIM no se crearon; revisa los registros del contenedor",
        RU to "Mailu не ответил вовремя — почтовые домены и DKIM-ключи не созданы; смотрите логи контейнера",
        UK to "Mailu не відповів вчасно — поштові домени та DKIM-ключі не створено; дивіться логи контейнера",
        IT to "Mailu non ha risposto in tempo: i domini e le chiavi DKIM non sono stati creati; controlla i log del container",
        JA to "Mailu が時間内に応答しませんでした — メールドメインと DKIM キーは作成されていません。コンテナのログを確認してください",
        ZH to "Mailu 未及时响应 — 邮件域名和 DKIM 密钥未创建；请查看容器日志"
    ))

    fun mailuDKIMPendingNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "not ready yet — open Domains in the Mailu admin UI to see the DKIM record",
        DE to "noch nicht bereit — öffnen Sie Domains in der Mailu-Admin-UI, um den DKIM-Eintrag zu sehen",
        FR to "pas encore prêt — ouvrez Domaines dans l'interface d'administration Mailu pour voir l'enregistrement DKIM",
        ES to "aún no está listo: abre Dominios en el panel de Mailu para ver el registro DKIM",
        RU to "ещё не готово — откройте Domains в админке Mailu, чтобы увидеть DKIM-запись",
        UK to "ще не готово — відкрийте Domains в адмінці Mailu, щоб побачити DKIM-запис",
        IT to "non ancora pronto: apri Domini nel pannello di Mailu per vedere il record DKIM",
        JA to "まだ準備できていません — Mailu の管理画面の Domains で DKIM レコードを確認してください",
        ZH to "尚未就绪 — 请在 Mailu 管理界面的 Domains 中查看 DKIM 记录"
    ))

    fun webmailLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Webmail",
        DE to "Webmail",
        FR to "Webmail",
        ES to "Correo web",
        RU to "Веб-почта",
        UK to "Вебпошта",
        IT to "Webmail",
        JA to "ウェブメール",
        ZH to "网页邮箱"
    ))

    fun dkimRecordsLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "DKIM records (add them to DNS)",
        DE to "DKIM-Einträge (in DNS eintragen)",
        FR to "Enregistrements DKIM (à ajouter au DNS)",
        ES to "Registros DKIM (añádelos al DNS)",
        RU to "DKIM-записи (добавьте их в DNS)",
        UK to "DKIM-записи (додайте їх до DNS)",
        IT to "Record DKIM (aggiungili al DNS)",
        JA to "DKIM レコード（DNS に追加してください）",
        ZH to "DKIM 记录（请添加到 DNS）"
    ))

    /** Which client ports the engine actually answers on */
    fun mailuClientPortsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Mail clients: IMAP 993 and SMTP 465, both with TLS (ports 143 and 587 are not served)",
        DE to "Mail-Programme: IMAP 993 und SMTP 465, beide mit TLS (Ports 143 und 587 werden nicht bedient)",
        FR to "Clients de messagerie : IMAP 993 et SMTP 465, tous deux en TLS (les ports 143 et 587 ne sont pas servis)",
        ES to "Clientes de correo: IMAP 993 y SMTP 465, ambos con TLS (los puertos 143 y 587 no se sirven)",
        RU to "Почтовые клиенты: IMAP 993 и SMTP 465, оба с TLS (порты 143 и 587 не обслуживаются)",
        UK to "Поштові клієнти: IMAP 993 і SMTP 465, обидва з TLS (порти 143 і 587 не обслуговуються)",
        IT to "Client di posta: IMAP 993 e SMTP 465, entrambi con TLS (le porte 143 e 587 non sono servite)",
        JA to "メールクライアント：IMAP 993 と SMTP 465（どちらも TLS）。ポート 143 と 587 は提供されません",
        ZH to "邮件客户端：IMAP 993 与 SMTP 465，均使用 TLS（不提供 143 和 587 端口）"
    ))

    // ---------------------------------------------- Docker Mailserver

    fun dmsWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Docker Mailserver: waiting for the container to finish its own setup",
        DE to "Docker Mailserver: warten, bis der Container sein Setup abgeschlossen hat",
        FR to "Docker Mailserver : attente de la fin de sa propre installation",
        ES to "Docker Mailserver: esperando a que el contenedor termine su configuración",
        RU to "Docker Mailserver: ждём, пока контейнер закончит собственную настройку",
        UK to "Docker Mailserver: чекаємо, доки контейнер завершить власне налаштування",
        IT to "Docker Mailserver: in attesa che il container completi la propria configurazione",
        JA to "Docker Mailserver：コンテナ自身のセットアップ完了を待っています",
        ZH to "Docker Mailserver：正在等待容器完成自身初始化"
    ))

    fun dmsPlaceholderCertFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Docker Mailserver: could not create the temporary certificate — the mail container will not start until the real certificate arrives",
        DE to "Docker Mailserver: Das temporäre Zertifikat konnte nicht erstellt werden — der Mail-Container startet erst mit dem echten Zertifikat",
        FR to "Docker Mailserver : impossible de créer le certificat temporaire — le conteneur mail ne démarrera qu'avec le vrai certificat",
        ES to "Docker Mailserver: no se pudo crear el certificado temporal: el contenedor de correo no arrancará hasta que llegue el certificado real",
        RU to "Docker Mailserver: не удалось создать временный сертификат — почтовый контейнер не стартует, пока не приедет настоящий",
        UK to "Docker Mailserver: не вдалося створити тимчасовий сертифікат — поштовий контейнер не стартує, доки не приїде справжній",
        IT to "Docker Mailserver: impossibile creare il certificato temporaneo — il container di posta non partirà finché non arriva quello reale",
        JA to "Docker Mailserver：一時証明書を作成できませんでした — 本物の証明書が届くまでメールコンテナは起動しません",
        ZH to "Docker Mailserver：无法创建临时证书 — 在真实证书到位前邮件容器不会启动"
    ))

    fun dmsMailboxFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Docker Mailserver: the first mailbox was NOT created. The server is running: add it from the app, or with 'setup email add' on the server.",
        DE to "Docker Mailserver: Das erste Postfach wurde NICHT angelegt. Der Server läuft: Legen Sie es in der App an oder mit 'setup email add' auf dem Server.",
        FR to "Docker Mailserver : la première boîte n'a PAS été créée. Le serveur fonctionne : ajoutez-la depuis l'application ou avec 'setup email add' sur le serveur.",
        ES to "Docker Mailserver: el primer buzón NO se creó. El servidor está en marcha: añádelo desde la aplicación o con 'setup email add' en el servidor.",
        RU to "Docker Mailserver: первый ящик НЕ создан. Сервер работает: заведите его из приложения или командой 'setup email add' на сервере.",
        UK to "Docker Mailserver: першу скриньку НЕ створено. Сервер працює: заведіть її з застосунку або командою 'setup email add' на сервері.",
        IT to "Docker Mailserver: la prima casella NON è stata creata. Il server è in funzione: aggiungila dall'app o con 'setup email add' sul server.",
        JA to "Docker Mailserver：最初のメールボックスは作成されませんでした。サーバーは稼働しています。アプリから、またはサーバー上の 'setup email add' で追加してください。",
        ZH to "Docker Mailserver：首个邮箱未创建。服务器正在运行：可从应用中添加，或在服务器上执行 'setup email add'。"
    ))

    fun dmsUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Docker Mailserver did not finish its setup in time — no mailbox and no DKIM keys were created; check the container logs",
        DE to "Docker Mailserver hat sein Setup nicht rechtzeitig beendet — weder Postfach noch DKIM-Schlüssel wurden angelegt; prüfen Sie die Container-Logs",
        FR to "Docker Mailserver n'a pas terminé son installation à temps — ni boîte ni clés DKIM créées ; consultez les journaux du conteneur",
        ES to "Docker Mailserver no terminó su configuración a tiempo: no se creó ni el buzón ni las claves DKIM; revisa los registros del contenedor",
        RU to "Docker Mailserver не закончил настройку вовремя — ни ящик, ни DKIM-ключи не созданы; смотрите логи контейнера",
        UK to "Docker Mailserver не завершив налаштування вчасно — ні скриньку, ні DKIM-ключі не створено; дивіться логи контейнера",
        IT to "Docker Mailserver non ha completato la configurazione in tempo: né casella né chiavi DKIM sono state create; controlla i log del container",
        JA to "Docker Mailserver がセットアップを時間内に完了しませんでした — メールボックスも DKIM キーも作成されていません。コンテナのログを確認してください",
        ZH to "Docker Mailserver 未及时完成初始化 — 邮箱和 DKIM 密钥均未创建；请查看容器日志"
    ))

    fun dmsDKIMFailed(l: AppLanguage, domain: String): String = l.pick(mapOf(
        EN to "Docker Mailserver: could not create the DKIM key for $domain — add it later from the server",
        DE to "Docker Mailserver: DKIM-Schlüssel für $domain konnte nicht erstellt werden — später auf dem Server nachholen",
        FR to "Docker Mailserver : impossible de créer la clé DKIM pour $domain — à refaire plus tard depuis le serveur",
        ES to "Docker Mailserver: no se pudo crear la clave DKIM de $domain: créala más tarde desde el servidor",
        RU to "Docker Mailserver: не удалось создать DKIM-ключ для $domain — заведите его позже на сервере",
        UK to "Docker Mailserver: не вдалося створити DKIM-ключ для $domain — заведіть його пізніше на сервері",
        IT to "Docker Mailserver: impossibile creare la chiave DKIM per $domain — creala più tardi dal server",
        JA to "Docker Mailserver：$domain の DKIM キーを作成できませんでした — 後でサーバー上で作成してください",
        ZH to "Docker Mailserver：无法为 $domain 创建 DKIM 密钥 — 请稍后在服务器上创建"
    ))

    fun dmsDKIMPendingNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "not ready yet — run the DKIM setup again on the server",
        DE to "noch nicht bereit — DKIM-Einrichtung auf dem Server erneut ausführen",
        FR to "pas encore prêt — relancez la configuration DKIM sur le serveur",
        ES to "aún no está listo: vuelve a ejecutar la configuración DKIM en el servidor",
        RU to "ещё не готово — перезапустите настройку DKIM на сервере",
        UK to "ще не готово — перезапустіть налаштування DKIM на сервері",
        IT to "non ancora pronto: riesegui la configurazione DKIM sul server",
        JA to "まだ準備できていません — サーバーで DKIM のセットアップをやり直してください",
        ZH to "尚未就绪 — 请在服务器上重新运行 DKIM 设置"
    ))

    fun dmsMailboxesNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Further mailboxes are added from the app — this engine has no web admin of its own",
        DE to "Weitere Postfächer werden in der App angelegt — diese Engine hat keine eigene Web-Administration",
        FR to "Les autres boîtes s'ajoutent depuis l'application — ce moteur n'a pas d'administration web",
        ES to "Los demás buzones se añaden desde la aplicación: este motor no tiene panel web propio",
        RU to "Остальные ящики заводятся из приложения — своей веб-админки у этого движка нет",
        UK to "Решта скриньок заводяться із застосунку — власної вебадмінки цей рушій не має",
        IT to "Le altre caselle si aggiungono dall'app: questo motore non ha un pannello web proprio",
        JA to "追加のメールボックスはアプリから作成します — このエンジンに独自の管理画面はありません",
        ZH to "其余邮箱通过应用添加 — 该引擎没有自带的网页管理界面"
    ))

    fun firstMailboxLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "First mailbox",
        DE to "Erstes Postfach",
        FR to "Première boîte",
        ES to "Primer buzón",
        RU to "Первый ящик",
        UK to "Перша скринька",
        IT to "Prima casella",
        JA to "最初のメールボックス",
        ZH to "首个邮箱"
    ))

    // ---------------------------------------------- Psono

    fun psonoWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Psono: waiting for the database to become reachable",
        DE to "Psono: warte, bis die Datenbank erreichbar wird",
        FR to "Psono : en attente que la base de données devienne accessible",
        ES to "Psono: esperando a que la base de datos esté accesible",
        RU to "Psono: ждём, пока база данных станет доступна",
        UK to "Psono: чекаємо, доки база даних стане доступною",
        IT to "Psono: in attesa che il database diventi raggiungibile",
        JA to "Psono: データベースに到達できるようになるのを待っています",
        ZH to "Psono: 正在等待数据库变为可访问"
    ))

    /** migrate ran after presetup succeeded but itself failed */
    fun psonoMigrateFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Psono: could not apply database migrations — run them manually inside the container (manage.py migrate)",
        DE to "Psono: Datenbankmigrationen konnten nicht angewendet werden — führen Sie sie manuell im Container aus (manage.py migrate)",
        FR to "Psono : impossible d'appliquer les migrations de la base de données — exécutez-les manuellement dans le conteneur (manage.py migrate)",
        ES to "Psono: no se pudieron aplicar las migraciones de la base de datos — ejecútelas manualmente dentro del contenedor (manage.py migrate)",
        RU to "Psono: не удалось применить миграции базы данных — примените их вручную внутри контейнера (manage.py migrate)",
        UK to "Psono: не вдалося застосувати міграції бази даних — застосуйте їх вручну всередині контейнера (manage.py migrate)",
        IT to "Psono: impossibile applicare le migrazioni del database — eseguile manualmente nel container (manage.py migrate)",
        JA to "Psono: データベースのマイグレーションを適用できませんでした — コンテナ内で手動で実行してください（manage.py migrate）",
        ZH to "Psono: 无法应用数据库迁移 — 请在容器内手动执行（manage.py migrate）"
    ))

    /** createuser/promoteuser/verifyuseremail failed on a fresh install */
    fun psonoAdminCreateFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Psono: could not create the administrator account — create one manually inside the container (manage.py createuser, then promoteuser)",
        DE to "Psono: Administratorkonto konnte nicht angelegt werden — legen Sie eines manuell im Container an (manage.py createuser, danach promoteuser)",
        FR to "Psono : impossible de créer le compte administrateur — créez-en un manuellement dans le conteneur (manage.py createuser, puis promoteuser)",
        ES to "Psono: no se pudo crear la cuenta de administrador — cree una manualmente dentro del contenedor (manage.py createuser y luego promoteuser)",
        RU to "Psono: не удалось создать учётную запись администратора — создайте её вручную внутри контейнера (manage.py createuser, затем promoteuser)",
        UK to "Psono: не вдалося створити обліковий запис адміністратора — створіть його вручну всередині контейнера (manage.py createuser, потім promoteuser)",
        IT to "Psono: impossibile creare l'account amministratore — creane uno manualmente nel container (manage.py createuser, poi promoteuser)",
        JA to "Psono: 管理者アカウントを作成できませんでした — コンテナ内で手動で作成してください（manage.py createuser の後に promoteuser）",
        ZH to "Psono: 无法创建管理员账户 — 请在容器内手动创建（先执行 manage.py createuser，再执行 promoteuser）"
    ))

    fun psonoUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Psono did not become reachable in time — the administrator account was not created; re-run the setup or create it manually",
        DE to "Psono wurde nicht rechtzeitig erreichbar — das Administratorkonto wurde nicht angelegt; führen Sie die Einrichtung erneut aus oder legen Sie es manuell an",
        FR to "Psono n'est pas devenu accessible à temps — le compte administrateur n'a pas été créé ; relancez l'installation ou créez-le manuellement",
        ES to "Psono no estuvo accesible a tiempo — la cuenta de administrador no se creó; vuelva a ejecutar la instalación o créela manualmente",
        RU to "Psono не стал доступен вовремя — учётная запись администратора не создана; перезапустите установку или создайте её вручную",
        UK to "Psono не став доступним вчасно — обліковий запис адміністратора не створено; перезапустіть встановлення або створіть його вручну",
        IT to "Psono non è diventato raggiungibile in tempo — l'account amministratore non è stato creato; rieseguire l'installazione o crearlo manualmente",
        JA to "Psono が時間内に到達可能になりませんでした — 管理者アカウントは作成されていません。セットアップを再実行するか、手動で作成してください",
        ZH to "Psono 未能及时变为可访问 — 管理员账户未被创建；请重新运行安装，或手动创建"
    ))

    // ---------------------------------------------- Passbolt

    fun passboltWaiting(l: AppLanguage): String = l.pick(mapOf(
        EN to "Passbolt: waiting for the server to generate its GPG key and finish installing",
        DE to "Passbolt: warte darauf, dass der Server seinen GPG-Schlüssel erzeugt und die Installation abschließt",
        FR to "Passbolt : en attente que le serveur génère sa clé GPG et termine l'installation",
        ES to "Passbolt: esperando a que el servidor genere su clave GPG y termine de instalarse",
        RU to "Passbolt: ждём, пока сервер сгенерирует свой ключ GPG и завершит установку",
        UK to "Passbolt: чекаємо, доки сервер згенерує свій ключ GPG і завершить встановлення",
        IT to "Passbolt: in attesa che il server generi la sua chiave GPG e completi l'installazione",
        JA to "Passbolt: サーバーが GPG 鍵を生成しインストールを完了するのを待っています",
        ZH to "Passbolt: 正在等待服务器生成其 GPG 密钥并完成安装"
    ))

    /** register_user itself failed (non-zero exit) on a fresh install */
    fun passboltRegisterFailed(l: AppLanguage): String = l.pick(mapOf(
        EN to "Passbolt: could not register the administrator — invite one manually inside the container (cake passbolt register_user)",
        DE to "Passbolt: Administrator konnte nicht registriert werden — laden Sie manuell einen im Container ein (cake passbolt register_user)",
        FR to "Passbolt : impossible d'enregistrer l'administrateur — invitez-en un manuellement dans le conteneur (cake passbolt register_user)",
        ES to "Passbolt: no se pudo registrar al administrador — invite a uno manualmente dentro del contenedor (cake passbolt register_user)",
        RU to "Passbolt: не удалось зарегистрировать администратора — пригласите его вручную внутри контейнера (cake passbolt register_user)",
        UK to "Passbolt: не вдалося зареєструвати адміністратора — запросіть його вручну всередині контейнера (cake passbolt register_user)",
        IT to "Passbolt: impossibile registrare l'amministratore — invitane uno manualmente nel container (cake passbolt register_user)",
        JA to "Passbolt: 管理者を登録できませんでした — コンテナ内で手動で招待してください（cake passbolt register_user）",
        ZH to "Passbolt: 无法注册管理员 — 请在容器内手动邀请（cake passbolt register_user）"
    ))

    fun passboltRegisterNoURL(l: AppLanguage): String = l.pick(mapOf(
        EN to "Passbolt: the administrator was registered, but no setup link was found in the output — check the container logs",
        DE to "Passbolt: der Administrator wurde registriert, aber in der Ausgabe wurde kein Einrichtungslink gefunden — prüfen Sie die Container-Logs",
        FR to "Passbolt : l'administrateur a été enregistré, mais aucun lien de configuration n'a été trouvé dans la sortie — vérifiez les journaux du conteneur",
        ES to "Passbolt: el administrador se registró, pero no se encontró ningún enlace de configuración en la salida — revise los registros del contenedor",
        RU to "Passbolt: администратор зарегистрирован, но в выводе не найдена ссылка для настройки — проверьте логи контейнера",
        UK to "Passbolt: адміністратора зареєстровано, але в виводі не знайдено посилання для налаштування — перевірте логи контейнера",
        IT to "Passbolt: l'amministratore è stato registrato, ma nell'output non è stato trovato alcun link di configurazione — controlla i log del container",
        JA to "Passbolt: 管理者は登録されましたが、出力の中にセットアップリンクが見つかりませんでした — コンテナのログを確認してください",
        ZH to "Passbolt: 管理员已注册，但在输出中未找到设置链接 — 请检查容器日志"
    ))

    fun passboltUnavailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "Passbolt did not finish its first start in time — the administrator was NOT invited; re-run the setup once it comes up",
        DE to "Passbolt hat den ersten Start nicht rechtzeitig abgeschlossen — der Administrator wurde NICHT eingeladen; führen Sie die Einrichtung erneut aus, sobald der Dienst läuft",
        FR to "Passbolt n'a pas terminé son premier démarrage à temps — l'administrateur n'a PAS été invité ; relancez l'installation une fois qu'il est opérationnel",
        ES to "Passbolt no terminó su primer arranque a tiempo — el administrador NO fue invitado; vuelva a ejecutar la instalación cuando esté disponible",
        RU to "Passbolt не завершил первый запуск вовремя — администратор НЕ приглашён; перезапустите установку, когда сервис поднимется",
        UK to "Passbolt не завершив перший запуск вчасно — адміністратора НЕ запрошено; перезапустіть встановлення, коли сервіс підніметься",
        IT to "Passbolt non ha completato il primo avvio in tempo — l'amministratore NON è stato invitato; rieseguire l'installazione quando sarà attivo",
        JA to "Passbolt の初回起動が時間内に完了しませんでした — 管理者は招待されていません。サービスが起動したらセットアップを再実行してください",
        ZH to "Passbolt 首次启动未能及时完成 — 管理员尚未被邀请；请在服务启动后重新运行安装"
    ))

    /** Header above the one-time setup link in the report */
    fun passboltSetupURLLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Finish setting up the administrator (this link works ONCE):",
        DE to "Richten Sie den Administrator fertig ein (dieser Link funktioniert NUR EINMAL):",
        FR to "Terminez la configuration de l'administrateur (ce lien ne fonctionne qu'UNE SEULE FOIS) :",
        ES to "Termine de configurar al administrador (este enlace funciona UNA SOLA VEZ):",
        RU to "Завершите настройку администратора (эта ссылка работает ОДИН РАЗ):",
        UK to "Завершіть налаштування адміністратора (це посилання працює ОДИН РАЗ):",
        IT to "Completa la configurazione dell'amministratore (questo link funziona UNA SOLA VOLTA):",
        JA to "管理者の設定を完了してください（このリンクは一度だけ使用できます）：",
        ZH to "请完成管理员设置（此链接仅可使用一次）："
    ))

    fun passboltAlreadyConfiguredNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "No setup link available here — if an administrator was already invited, sign in with that account; otherwise check the container logs and invite one manually (cake passbolt register_user).",
        DE to "Hier ist kein Einrichtungslink verfügbar — wenn bereits ein Administrator eingeladen wurde, melden Sie sich mit diesem Konto an; andernfalls prüfen Sie die Container-Logs und laden Sie manuell einen ein (cake passbolt register_user).",
        FR to "Aucun lien de configuration disponible ici — si un administrateur a déjà été invité, connectez-vous avec ce compte ; sinon, vérifiez les journaux du conteneur et invitez-en un manuellement (cake passbolt register_user).",
        ES to "No hay ningún enlace de configuración disponible aquí — si ya se invitó a un administrador, inicie sesión con esa cuenta; si no, revise los registros del contenedor e invite a uno manualmente (cake passbolt register_user).",
        RU to "Здесь нет ссылки для настройки — если администратор уже приглашён, войдите под этой учётной записью; иначе проверьте логи контейнера и пригласите его вручную (cake passbolt register_user).",
        UK to "Тут немає посилання для налаштування — якщо адміністратора вже запрошено, увійдіть під цим обліковим записом; інакше перевірте логи контейнера й запросіть його вручну (cake passbolt register_user).",
        IT to "Qui non è disponibile alcun link di configurazione — se un amministratore è già stato invitato, accedi con quell'account; altrimenti controlla i log del container e invitane uno manualmente (cake passbolt register_user).",
        JA to "ここにはセットアップリンクがありません — 管理者がすでに招待されている場合はそのアカウントでサインインしてください。そうでない場合はコンテナのログを確認し、手動で招待してください（cake passbolt register_user）。",
        ZH to "此处没有可用的设置链接 — 如果管理员已被邀请，请使用该账户登录；否则请检查容器日志并手动邀请管理员（cake passbolt register_user）。"
    ))

    // ---------------------------------------------- AI shelf

    fun ollamaNoModelsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "No model is installed — the setup deliberately downloaded none. Add the first one with:",
        DE to "Es ist kein Modell installiert — die Einrichtung hat absichtlich keines heruntergeladen. Fügen Sie das erste so hinzu:",
        FR to "Aucun modele n'est installe — l'installation n'en a telecharge aucun, volontairement. Ajoutez le premier ainsi :",
        ES to "No hay ningun modelo instalado — la instalacion no descargo ninguno a proposito. Agregue el primero asi:",
        RU to "Ни одной модели нет — установка намеренно ничего не скачивала. Первую добавьте так:",
        UK to "Жодної моделі немає — встановлення навмисно нічого не завантажувало. Першу додайте так:",
        IT to "Nessun modello installato — l'installazione non ne ha scaricato nessuno di proposito. Aggiungi il primo cosi:",
        JA to "モデルは一つも入っていません — セットアップは意図的に何もダウンロードしていません。最初の一つは次のように追加します:",
        ZH to "尚未安装任何模型 — 安装过程有意未下载。用下面的命令添加第一个:"
    ))

    fun ollamaModelSizeNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "A small model is around 4 GB, a large one around 40 GB — check free disk space first.",
        DE to "Ein kleines Modell belegt etwa 4 GB, ein grosses etwa 40 GB — pruefen Sie zuerst den freien Speicherplatz.",
        FR to "Un petit modele pese environ 4 Go, un grand environ 40 Go — verifiez d'abord l'espace disque libre.",
        ES to "Un modelo pequeno ocupa unos 4 GB y uno grande unos 40 GB — compruebe antes el espacio libre en disco.",
        RU to "Маленькая модель — около 4 ГБ, большая — около 40 ГБ. Сначала проверьте свободное место на диске.",
        UK to "Мала модель — близько 4 ГБ, велика — близько 40 ГБ. Спершу перевірте вільне місце на диску.",
        IT to "Un modello piccolo pesa circa 4 GB, uno grande circa 40 GB — controlla prima lo spazio libero su disco.",
        JA to "小さいモデルで約 4 GB、大きいモデルで約 40 GB です — 先に空き容量を確認してください。",
        ZH to "小模型约 4 GB，大模型约 40 GB — 请先检查磁盘剩余空间。"
    ))

    fun openWebUIAdminWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and register — the FIRST account created becomes the administrator. Then switch registration off in the admin settings.",
        DE to "WICHTIG: Oeffnen Sie diese URL sofort und registrieren Sie sich — das ERSTE angelegte Konto wird zum Administrator. Schalten Sie die Registrierung danach in den Admin-Einstellungen ab.",
        FR to "IMPORTANT : ouvrez cette URL des maintenant et inscrivez-vous — le PREMIER compte cree devient administrateur. Desactivez ensuite l'inscription dans les reglages d'administration.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y registrese — la PRIMERA cuenta creada se convierte en administrador. Despues desactive el registro en los ajustes de administracion.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и зарегистрируйтесь — ПЕРВАЯ созданная учётная запись становится администратором. После этого отключите регистрацию в настройках администратора.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і зареєструйтеся — ПЕРШИЙ створений обліковий запис стає адміністратором. Після цього вимкніть реєстрацію в налаштуваннях адміністратора.",
        IT to "IMPORTANTE: apri questo URL subito e registrati — il PRIMO account creato diventa amministratore. Poi disattiva la registrazione nelle impostazioni di amministrazione.",
        JA to "重要：今すぐこの URL を開いて登録してください — 最初に作成されたアカウントが管理者になります。その後、管理設定で新規登録を無効にしてください。",
        ZH to "重要：请立即打开此地址并注册 — 第一个创建的账户将成为管理员。随后请在管理设置中关闭注册。"
    ))

    /** Printed only when the deployment installs no local engine */
    fun openWebUINoEngineNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "No local model engine is installed, so the model list starts empty: add a provider and its API key in the admin settings.",
        DE to "Es ist keine lokale Modell-Engine installiert, daher ist die Modellliste zunaechst leer: Tragen Sie einen Anbieter und dessen API-Schluessel in den Admin-Einstellungen ein.",
        FR to "Aucun moteur de modeles local n'est installe, la liste des modeles est donc vide au depart : ajoutez un fournisseur et sa cle d'API dans les reglages d'administration.",
        ES to "No hay ningun motor de modelos local instalado, por lo que la lista de modelos empieza vacia: anada un proveedor y su clave de API en los ajustes de administracion.",
        RU to "Локального движка моделей нет, поэтому список моделей пуст: добавьте провайдера и его ключ API в настройках администратора.",
        UK to "Локального рушія моделей немає, тому список моделей порожній: додайте провайдера та його ключ API в налаштуваннях адміністратора.",
        IT to "Nessun motore di modelli locale e installato, quindi l'elenco dei modelli parte vuoto: aggiungi un provider e la sua chiave API nelle impostazioni di amministrazione.",
        JA to "ローカルのモデルエンジンが入っていないため、モデル一覧は空の状態で始まります。管理設定でプロバイダーと API キーを追加してください。",
        ZH to "未安装本地模型引擎，因此模型列表初始为空：请在管理设置中添加提供商及其 API 密钥。"
    ))

    fun liteLLMMasterKeyLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Master key",
        DE to "Hauptschluessel",
        FR to "Cle maitresse",
        ES to "Clave maestra",
        RU to "Главный ключ",
        UK to "Головний ключ",
        IT to "Chiave principale",
        JA to "マスターキー",
        ZH to "主密钥"
    ))

    fun liteLLMKeysNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Keys for OpenAI, Anthropic and the rest are added from the app and stored on this server, encrypted. Without the agent installed, put them in the file below by hand and restart the container.",
        DE to "Schluessel fuer OpenAI, Anthropic und die uebrigen werden aus der App hinzugefuegt und auf diesem Server verschluesselt gespeichert. Ohne installierten Agenten tragen Sie sie von Hand in die Datei unten ein und starten den Container neu.",
        FR to "Les cles pour OpenAI, Anthropic et les autres s'ajoutent depuis l'application et sont stockees chiffrees sur ce serveur. Sans agent installe, inscrivez-les a la main dans le fichier ci-dessous et redemarrez le conteneur.",
        ES to "Las claves de OpenAI, Anthropic y las demas se agregan desde la aplicacion y se guardan cifradas en este servidor. Sin el agente instalado, escribalas a mano en el archivo de abajo y reinicie el contenedor.",
        RU to "Ключи от OpenAI, Anthropic и остальных добавляются из приложения и хранятся на этом сервере в зашифрованном виде. Без установленного агента впишите их в файл ниже руками и перезапустите контейнер.",
        UK to "Ключі від OpenAI, Anthropic та інших додаються з застосунку і зберігаються на цьому сервері в зашифрованому вигляді. Без встановленого агента впишіть їх у файл нижче руками й перезапустіть контейнер.",
        IT to "Le chiavi per OpenAI, Anthropic e le altre si aggiungono dall'app e sono conservate cifrate su questo server. Senza l'agente installato, scrivile a mano nel file qui sotto e riavvia il container.",
        JA to "OpenAI や Anthropic などのキーはアプリから追加され、このサーバーに暗号化して保存されます。エージェントが入っていない場合は、下のファイルに手で書き入れてコンテナを再起動してください。",
        ZH to "OpenAI、Anthropic 等的密钥从应用中添加，并加密保存在这台服务器上。若未安装代理，请手动写入下面的文件并重启容器。"
    ))

    /** The file the note above points at */
    fun liteLLMKeysFileLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Provider keys",
        DE to "Anbieterschluessel",
        FR to "Cles des fournisseurs",
        ES to "Claves de proveedores",
        RU to "Ключи провайдеров",
        UK to "Ключі провайдерів",
        IT to "Chiavi dei fornitori",
        JA to "プロバイダーのキー",
        ZH to "提供商密钥"
    ))

    fun n8nOwnerWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and create the owner account — the FIRST person to open it becomes the owner of every workflow.",
        DE to "WICHTIG: Oeffnen Sie diese URL sofort und legen Sie das Eigentuemerkonto an — die ERSTE Person, die sie oeffnet, wird Eigentuemer aller Ablaeufe.",
        FR to "IMPORTANT : ouvrez cette URL des maintenant et creez le compte proprietaire — la PREMIERE personne qui l'ouvre devient proprietaire de tous les flux.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y cree la cuenta de propietario — la PRIMERA persona que la abra se convierte en propietaria de todos los flujos.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и заведите учётную запись владельца — ПЕРВЫЙ, кто её откроет, станет владельцем всех сценариев.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і створіть обліковий запис власника — ПЕРШИЙ, хто її відкриє, стане власником усіх сценаріїв.",
        IT to "IMPORTANTE: apri questo URL subito e crea l'account proprietario — la PRIMA persona che lo apre diventa proprietaria di tutti i flussi.",
        JA to "重要：今すぐこの URL を開いてオーナーアカウントを作成してください — 最初に開いた人がすべてのワークフローのオーナーになります。",
        ZH to "重要：请立即打开此地址并创建所有者账户 — 第一个打开它的人将成为所有工作流的所有者。"
    ))

    fun n8nWebhooksPublicNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The editor is behind the admin guard like every other panel, but the /webhook/ and /webhook-test/ addresses answer the whole internet — that is what makes an incoming trigger work. Anyone who knows a webhook address can call it, so treat it as a password.",
        DE to "Der Editor liegt wie jedes andere Panel hinter dem Admin-Schutz, aber die Adressen /webhook/ und /webhook-test/ antworten dem gesamten Internet — nur so funktioniert ein eingehender Ausloeser. Wer eine Webhook-Adresse kennt, kann sie aufrufen: behandeln Sie sie wie ein Passwort.",
        FR to "L'editeur est derriere la protection d'administration comme tous les autres panneaux, mais les adresses /webhook/ et /webhook-test/ repondent a tout l'internet — c'est ce qui fait fonctionner un declencheur entrant. Quiconque connait une adresse de webhook peut l'appeler : traitez-la comme un mot de passe.",
        ES to "El editor esta detras de la proteccion de administracion como los demas paneles, pero las direcciones /webhook/ y /webhook-test/ responden a todo internet — es lo que hace funcionar un disparador entrante. Cualquiera que conozca una direccion de webhook puede llamarla: tratela como una contrasena.",
        RU to "Редактор закрыт админ-гардом, как и остальные панели, но адреса /webhook/ и /webhook-test/ отвечают всему интернету — иначе входящий триггер не сработает. Кто знает адрес вебхука, тот может его дёрнуть: относитесь к нему как к паролю.",
        UK to "Редактор закритий адмін-гардом, як і решта панелей, але адреси /webhook/ та /webhook-test/ відповідають усьому інтернету — інакше вхідний тригер не спрацює. Хто знає адресу вебхука, той може його смикнути: ставтеся до неї як до пароля.",
        IT to "L'editor sta dietro la protezione di amministrazione come ogni altro pannello, ma gli indirizzi /webhook/ e /webhook-test/ rispondono a tutta la rete — e cio che fa funzionare un trigger in entrata. Chi conosce un indirizzo di webhook puo chiamarlo: trattalo come una password.",
        JA to "エディターは他のパネルと同じく管理ガードの内側にありますが、/webhook/ と /webhook-test/ のアドレスはインターネット全体に応答します — 受信トリガーはそれで動きます。webhook のアドレスを知っている人は誰でも呼び出せるので、パスワードと同じように扱ってください。",
        ZH to "编辑器与其他面板一样处于管理防护之后，但 /webhook/ 和 /webhook-test/ 地址会响应整个互联网 — 传入触发器正是靠它工作。知道 webhook 地址的人都能调用它，请像对待密码一样对待它。"
    ))

    fun anythingLLMAdminWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and create the first account — whoever opens it first becomes the administrator of every workspace and every document in it.",
        DE to "WICHTIG: Oeffnen Sie diese URL sofort und legen Sie das erste Konto an — wer sie zuerst oeffnet, wird Administrator jedes Arbeitsbereichs und jedes Dokuments darin.",
        FR to "IMPORTANT : ouvrez cette URL des maintenant et creez le premier compte — celui qui l'ouvre en premier devient administrateur de chaque espace de travail et de chaque document.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y cree la primera cuenta — quien la abra primero se convierte en administrador de cada espacio de trabajo y de cada documento.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и заведите первую учётную запись — кто откроет первым, тот станет администратором всех рабочих пространств и всех документов в них.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і створіть перший обліковий запис — хто відкриє першим, той стане адміністратором усіх робочих просторів і всіх документів у них.",
        IT to "IMPORTANTE: apri questo URL subito e crea il primo account — chi lo apre per primo diventa amministratore di ogni spazio di lavoro e di ogni documento.",
        JA to "重要：今すぐこの URL を開いて最初のアカウントを作成してください — 最初に開いた人が、すべてのワークスペースとその中の文書の管理者になります。",
        ZH to "重要：请立即打开此地址并创建第一个账户 — 最先打开的人将成为所有工作区及其中所有文档的管理员。"
    ))

    fun anythingLLMNoModelNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "No model backend is installed, so no provider is preset: the service asks for one when you first open it. Uploading and searching documents already works without one.",
        DE to "Es ist kein Modell-Backend installiert, daher ist kein Anbieter voreingestellt: der Dienst fragt beim ersten Oeffnen danach. Dokumente hochladen und durchsuchen geht auch ohne.",
        FR to "Aucun moteur de modeles n'est installe, donc aucun fournisseur n'est preconfigure : le service en demande un a la premiere ouverture. Televerser et rechercher des documents fonctionne deja sans.",
        ES to "No hay ningun backend de modelos instalado, asi que no hay proveedor preconfigurado: el servicio pide uno al abrirlo por primera vez. Subir y buscar documentos ya funciona sin el.",
        RU to "Движка моделей нет, поэтому провайдер не выставлен: сервис спросит о нём при первом открытии. Загружать документы и искать по ним можно уже сейчас.",
        UK to "Рушія моделей немає, тому провайдер не виставлений: сервіс запитає про нього під час першого відкриття. Завантажувати документи й шукати по них можна вже зараз.",
        IT to "Nessun backend di modelli e installato, quindi nessun provider e preimpostato: il servizio ne chiede uno alla prima apertura. Caricare e cercare documenti funziona gia senza.",
        JA to "モデルのバックエンドが入っていないため、プロバイダーは設定されていません。初回起動時に尋ねられます。文書のアップロードと検索は、それがなくても動きます。",
        ZH to "未安装模型后端，因此没有预设提供商：首次打开时服务会询问。上传和搜索文档在没有它的情况下已经可用。"
    ))

    fun anythingLLMSettingsNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The model and the vector store were set once, from what this server runs. Change them in the service's own settings from now on — the install does not write them again.",
        DE to "Modell und Vektorspeicher wurden einmal gesetzt, aus dem, was dieser Server betreibt. Aendern Sie sie ab jetzt in den Einstellungen des Dienstes — die Installation schreibt sie nicht erneut.",
        FR to "Le modele et le magasin de vecteurs ont ete definis une fois, d'apres ce que ce serveur execute. Modifiez-les desormais dans les reglages du service — l'installation ne les reecrit pas.",
        ES to "El modelo y el almacen de vectores se fijaron una vez, a partir de lo que este servidor ejecuta. Cambielos de ahora en adelante en los ajustes del servicio — la instalacion no los vuelve a escribir.",
        RU to "Модель и векторное хранилище выставлены один раз — из того, что крутится на этом сервере. Дальше меняйте их в настройках самого сервиса: установка их больше не переписывает.",
        UK to "Модель і векторне сховище виставлені один раз — з того, що працює на цьому сервері. Далі змінюйте їх у налаштуваннях самого сервісу: встановлення їх більше не переписує.",
        IT to "Il modello e l'archivio vettoriale sono stati impostati una volta, da cio che questo server esegue. D'ora in poi cambiali nelle impostazioni del servizio — l'installazione non li riscrive.",
        JA to "モデルとベクトルストアは、このサーバーが動かしているものから一度だけ設定されました。以降はサービス自身の設定で変更してください — インストールが書き直すことはありません。",
        ZH to "模型和向量库只根据这台服务器运行的内容设置了一次。此后请在服务自身的设置中更改 — 安装不会再写入它们。"
    ))

    fun qdrantLoopbackNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The vector store answers on this machine only and is not published on any hostname — what it holds is your documents in a form that still answers questions about them. Its key is in /etc/gryonixnexus/qdrant.key.",
        DE to "Der Vektorspeicher antwortet nur auf dieser Maschine und wird unter keinem Hostnamen veroeffentlicht — er haelt Ihre Dokumente in einer Form, die weiterhin Fragen dazu beantwortet. Sein Schluessel liegt in /etc/gryonixnexus/qdrant.key.",
        FR to "Le magasin de vecteurs ne repond que sur cette machine et n'est publie sous aucun nom d'hote — il contient vos documents sous une forme qui repond encore aux questions les concernant. Sa cle est dans /etc/gryonixnexus/qdrant.key.",
        ES to "El almacen de vectores responde solo en esta maquina y no se publica en ningun nombre de host — contiene sus documentos en una forma que aun responde preguntas sobre ellos. Su clave esta en /etc/gryonixnexus/qdrant.key.",
        RU to "Векторное хранилище отвечает только на этой машине и не публикуется ни под каким именем — в нём лежат ваши документы в виде, который по-прежнему отвечает на вопросы о них. Ключ — в /etc/gryonixnexus/qdrant.key.",
        UK to "Векторне сховище відповідає лише на цій машині й не публікується під жодним іменем — у ньому лежать ваші документи у вигляді, який досі відповідає на питання про них. Ключ — у /etc/gryonixnexus/qdrant.key.",
        IT to "L'archivio vettoriale risponde solo su questa macchina e non e pubblicato su alcun hostname — contiene i tuoi documenti in una forma che risponde ancora a domande su di essi. La sua chiave e in /etc/gryonixnexus/qdrant.key.",
        JA to "ベクトルストアはこのマシン上でのみ応答し、どのホスト名でも公開されません。中身は、質問に答えられる形のままのあなたの文書です。鍵は /etc/gryonixnexus/qdrant.key にあります。",
        ZH to "向量库只在本机响应，不会发布到任何主机名上 — 它保存的是仍能回答相关问题的你的文档。其密钥在 /etc/gryonixnexus/qdrant.key。"
    ))

    /** The search engine's line in the install report */
    fun searxngLoopbackNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Web search for the services on this shelf. It answers on this machine only and is published on no hostname — the chat beside it queries it by itself.",
        DE to "Websuche fuer die Dienste in diesem Regal. Sie antwortet nur auf dieser Maschine und wird unter keinem Hostnamen veroeffentlicht — der Chat daneben fragt sie von selbst.",
        FR to "Recherche web pour les services de cette etagere. Elle ne repond que sur cette machine et n'est publiee sous aucun nom d'hote — le chat a cote l'interroge tout seul.",
        ES to "Busqueda web para los servicios de este estante. Responde solo en esta maquina y no se publica en ningun nombre de host — el chat de al lado la consulta por si mismo.",
        RU to "Поиск в интернете для сервисов этой полки. Отвечает только на этой машине и не публикуется ни под каким именем — чат рядом обращается к нему сам.",
        UK to "Пошук в інтернеті для сервісів цієї полиці. Відповідає лише на цій машині й не публікується під жодним іменем — чат поруч звертається до нього сам.",
        IT to "Ricerca web per i servizi di questo scaffale. Risponde solo su questa macchina e non e pubblicata su alcun hostname — la chat accanto la interroga da sola.",
        JA to "この棚のサービスのためのウェブ検索です。このマシン上でのみ応答し、どのホスト名でも公開されません。隣のチャットが自分で問い合わせます。",
        ZH to "供本棚服务使用的网页搜索。它只在本机响应，不会发布到任何主机名上 — 旁边的聊天会自行查询它。"
    ))

    /** The token that guards the gateway's web UI */
    fun openclawTokenNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Gateway token",
        DE to "Gateway-Token",
        FR to "Jeton de la passerelle",
        ES to "Token de la puerta de enlace",
        RU to "Токен шлюза",
        UK to "Токен шлюзу",
        IT to "Token del gateway",
        JA to "ゲートウェイトークン",
        ZH to "网关令牌"
    ))

    fun openclawPairingNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Pair WhatsApp, Telegram or Discord in its own web UI — those tokens stay in this container and are never held by gryonixNexus.",
        DE to "WhatsApp, Telegram oder Discord werden in seiner eigenen Weboberflaeche verbunden — diese Token bleiben in diesem Container und werden von gryonixNexus nie gehalten.",
        FR to "Associez WhatsApp, Telegram ou Discord dans sa propre interface web — ces jetons restent dans ce conteneur et ne sont jamais detenus par gryonixNexus.",
        ES to "Vincule WhatsApp, Telegram o Discord en su propia interfaz web — esos tokens se quedan en este contenedor y gryonixNexus nunca los guarda.",
        RU to "WhatsApp, Telegram или Discord подключаются в его собственном веб-интерфейсе — эти токены остаются в этом контейнере, gryonixNexus их не хранит.",
        UK to "WhatsApp, Telegram чи Discord підключаються в його власному вебінтерфейсі — ці токени лишаються в цьому контейнері, gryonixNexus їх не зберігає.",
        IT to "Collega WhatsApp, Telegram o Discord nella sua interfaccia web — quei token restano in questo container e gryonixNexus non li conserva mai.",
        JA to "WhatsApp・Telegram・Discord の連携は、このサービス自身の Web UI で行います。これらのトークンはこのコンテナ内に留まり、gryonixNexus が保持することはありません。",
        ZH to "在它自己的网页界面中配对 WhatsApp、Telegram 或 Discord — 这些令牌留在该容器内，gryonixNexus 从不持有它们。"
    ))

    /** The address of whichever model backend this deployment does run */
    fun openclawModelNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "No model provider is set yet; paste this address into its settings",
        DE to "Es ist noch kein Modellanbieter gesetzt; diese Adresse in seine Einstellungen einfuegen",
        FR to "Aucun fournisseur de modele n'est encore defini; collez cette adresse dans ses parametres",
        ES to "Aun no hay proveedor de modelos; pegue esta direccion en sus ajustes",
        RU to "Провайдер модели ещё не задан; вставьте этот адрес в его настройки",
        UK to "Провайдера моделі ще не задано; вставте цю адресу в його налаштування",
        IT to "Nessun fornitore di modelli e ancora impostato; incolla questo indirizzo nelle sue impostazioni",
        JA to "モデルのプロバイダーはまだ設定されていません。次のアドレスを設定画面に貼り付けてください",
        ZH to "尚未设置模型提供方；请把这个地址粘贴到它的设置中"
    ))

    fun openclawNoModelNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "This deployment runs no model of its own, so the provider and its key are set in its own web UI.",
        DE to "Diese Installation betreibt kein eigenes Modell; Anbieter und Schluessel werden daher in seiner eigenen Weboberflaeche gesetzt.",
        FR to "Cette installation n'execute aucun modele a elle; le fournisseur et sa cle se definissent donc dans sa propre interface web.",
        ES to "Esta instalacion no ejecuta ningun modelo propio, asi que el proveedor y su clave se configuran en su propia interfaz web.",
        RU to "В этой установке своей модели нет — провайдер и ключ задаются в его собственном веб-интерфейсе.",
        UK to "У цій установці власної моделі немає — провайдер і ключ задаються в його власному вебінтерфейсі.",
        IT to "Questa installazione non esegue alcun modello proprio, quindi il fornitore e la sua chiave si impostano nella sua interfaccia web.",
        JA to "この構成には自前のモデルがないため、プロバイダーと鍵はこのサービス自身の Web UI で設定します。",
        ZH to "本次部署没有自己的模型，因此提供方和密钥在它自己的网页界面中设置。"
    ))

    fun ollamaGPUToolkitInstalling(l: AppLanguage): String = l.pick(mapOf(
        EN to "teaching docker about the graphics card (NVIDIA container toolkit)",
        DE to "Docker die Grafikkarte beibringen (NVIDIA Container Toolkit)",
        FR to "apprentissage de la carte graphique a docker (NVIDIA container toolkit)",
        ES to "ensenando a docker sobre la tarjeta grafica (NVIDIA container toolkit)",
        RU to "учим docker видеть видеокарту (NVIDIA container toolkit)",
        UK to "вчимо docker бачити відеокарту (NVIDIA container toolkit)",
        IT to "insegnare a docker la scheda grafica (NVIDIA container toolkit)",
        JA to "グラフィックカードを docker に認識させています (NVIDIA container toolkit)",
        ZH to "让 docker 认识显卡 (NVIDIA container toolkit)"
    ))

    fun ollamaGPUEnabledNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The engine runs on the NVIDIA card in this machine — answers are as fast as the card, not as fast as the processor.",
        DE to "Die Engine laeuft auf der NVIDIA-Karte in dieser Maschine — die Antworten sind so schnell wie die Karte, nicht wie der Prozessor.",
        FR to "Le moteur tourne sur la carte NVIDIA de cette machine — les reponses vont a la vitesse de la carte, pas du processeur.",
        ES to "El motor funciona con la tarjeta NVIDIA de esta maquina — las respuestas van a la velocidad de la tarjeta, no del procesador.",
        RU to "Движок работает на видеокарте NVIDIA этой машины — ответы идут со скоростью карты, а не процессора.",
        UK to "Рушій працює на відеокарті NVIDIA цієї машини — відповіді йдуть зі швидкістю карти, а не процесора.",
        IT to "Il motore gira sulla scheda NVIDIA di questa macchina — le risposte vanno alla velocita della scheda, non del processore.",
        JA to "エンジンはこのマシンの NVIDIA カード上で動作します。応答の速さはプロセッサではなくカードのものです。",
        ZH to "引擎运行在本机的 NVIDIA 显卡上 — 回答的速度取决于显卡，而不是处理器。"
    ))

    fun ollamaGPUMissingNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "A graphics card was asked for, and no NVIDIA driver answered on this machine — the engine is running on the processor. Installing the driver is a decision about the host itself (kernel modules and a reboot), so this install does not make it for you.",
        DE to "Eine Grafikkarte wurde angefordert, aber auf dieser Maschine antwortet kein NVIDIA-Treiber — die Engine laeuft auf dem Prozessor. Den Treiber zu installieren ist eine Entscheidung ueber den Host selbst (Kernelmodule und ein Neustart), die diese Installation nicht fuer Sie trifft.",
        FR to "Une carte graphique a ete demandee, mais aucun pilote NVIDIA ne repond sur cette machine — le moteur tourne sur le processeur. Installer le pilote est une decision sur l'hote lui-meme (modules noyau et redemarrage), que cette installation ne prend pas a votre place.",
        ES to "Se pidio una tarjeta grafica y ningun controlador NVIDIA responde en esta maquina — el motor funciona con el procesador. Instalar el controlador es una decision sobre el propio host (modulos del kernel y un reinicio), y esta instalacion no la toma por usted.",
        RU to "Видеокарта была запрошена, но драйвер NVIDIA на этой машине не отвечает — движок работает на процессоре. Установка драйвера — это решение про сам хост (модули ядра и перезагрузка), и установка не принимает его за вас.",
        UK to "Відеокарту було запитано, але драйвер NVIDIA на цій машині не відповідає — рушій працює на процесорі. Встановлення драйвера — це рішення про сам хост (модулі ядра та перезавантаження), і встановлення не ухвалює його за вас.",
        IT to "E stata richiesta una scheda grafica e nessun driver NVIDIA risponde su questa macchina — il motore gira sul processore. Installare il driver e una decisione sull'host stesso (moduli del kernel e un riavvio), che questa installazione non prende al posto tuo.",
        JA to "グラフィックカードが要求されましたが、このマシンでは NVIDIA ドライバーが応答しません。エンジンはプロセッサ上で動作しています。ドライバーの導入はホスト自体に関する決定 (カーネルモジュールと再起動) であり、このインストールが代わりに行うことはありません。",
        ZH to "已请求使用显卡，但本机没有 NVIDIA 驱动响应 — 引擎正在处理器上运行。安装驱动是关于主机本身的决定 (内核模块和一次重启)，本次安装不会替你做这个决定。"
    ))

    fun ollamaGPUSecureBootNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Secure Boot is on, so the driver was not installed automatically — enrolling it needs a password typed at the machine's own screen on the next boot, which nothing here can do for you. Turn Secure Boot off in the BIOS/UEFI, or install the driver yourself.",
        DE to "Secure Boot ist aktiv, daher wurde der Treiber nicht automatisch installiert — seine Registrierung braucht beim naechsten Start ein Passwort direkt am Bildschirm der Maschine, was hier niemand fuer Sie eingeben kann. Schalten Sie Secure Boot im BIOS/UEFI aus, oder installieren Sie den Treiber selbst.",
        FR to "Secure Boot est actif, le pilote n'a donc pas ete installe automatiquement — son enregistrement demande un mot de passe tape sur l'ecran meme de la machine au prochain demarrage, ce que rien ici ne peut faire a votre place. Desactivez Secure Boot dans le BIOS/UEFI, ou installez le pilote vous-meme.",
        ES to "Secure Boot esta activado, asi que el controlador no se instalo automaticamente — inscribirlo necesita una contrasena escrita en la propia pantalla de la maquina en el proximo arranque, y nada aqui puede hacerlo por usted. Desactive Secure Boot en la BIOS/UEFI, o instale el controlador usted mismo.",
        RU to "Включен Secure Boot, поэтому драйвер не установился автоматически — для его регистрации при следующей загрузке нужен пароль, введённый прямо на экране этой машины, а этого отсюда сделать нельзя. Отключите Secure Boot в BIOS/UEFI или установите драйвер самостоятельно.",
        UK to "Увімкнено Secure Boot, тому драйвер не встановився автоматично — для його реєстрації під час наступного завантаження потрібен пароль, введений прямо на екрані цієї машини, а звідси це зробити не можна. Вимкніть Secure Boot у BIOS/UEFI або встановіть драйвер самостійно.",
        IT to "Secure Boot e attivo, quindi il driver non e stato installato automaticamente — la sua registrazione richiede una password digitata sullo schermo stesso della macchina al prossimo avvio, cosa che nulla qui puo fare al posto tuo. Disattiva Secure Boot nel BIOS/UEFI, oppure installa il driver tu stesso.",
        JA to "Secure Boot が有効なため、ドライバーは自動インストールされませんでした。登録には次回起動時にマシン自身の画面でパスワードを入力する必要があり、ここからは代行できません。BIOS/UEFI で Secure Boot を無効にするか、ドライバーを自分でインストールしてください。",
        ZH to "已启用 Secure Boot，因此未自动安装驱动 — 注册它需要在下次开机时于本机屏幕上输入密码，这里无法替你完成。请在 BIOS/UEFI 中关闭 Secure Boot，或自行安装驱动。"
    ))

    /** The log line for the driver install attempt itself */
    fun ollamaGPUDriverInstalling(l: AppLanguage): String = l.pick(mapOf(
        EN to "installing the NVIDIA driver (ubuntu-drivers autoinstall)",
        DE to "installiere den NVIDIA-Treiber (ubuntu-drivers autoinstall)",
        FR to "installation du pilote NVIDIA (ubuntu-drivers autoinstall)",
        ES to "instalando el controlador NVIDIA (ubuntu-drivers autoinstall)",
        RU to "устанавливаем драйвер NVIDIA (ubuntu-drivers autoinstall)",
        UK to "встановлюємо драйвер NVIDIA (ubuntu-drivers autoinstall)",
        IT to "installazione del driver NVIDIA (ubuntu-drivers autoinstall)",
        JA to "NVIDIA ドライバーをインストールしています (ubuntu-drivers autoinstall)",
        ZH to "正在安装 NVIDIA 驱动 (ubuntu-drivers autoinstall)"
    ))

    fun ollamaGPUDriverInstalledNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "The driver was installed but is not loaded yet — reboot this machine, then run this install again (or restart Ollama) to finish enabling the card.",
        DE to "Der Treiber wurde installiert, ist aber noch nicht geladen — starten Sie diese Maschine neu und fuehren Sie diese Installation erneut aus (oder starten Sie Ollama neu), um die Karte fertig zu aktivieren.",
        FR to "Le pilote a ete installe mais n'est pas encore charge — redemarrez cette machine, puis relancez cette installation (ou redemarrez Ollama) pour terminer d'activer la carte.",
        ES to "El controlador se instalo pero aun no esta cargado — reinicie esta maquina y vuelva a ejecutar esta instalacion (o reinicie Ollama) para terminar de activar la tarjeta.",
        RU to "Драйвер установлен, но пока не загружен — перезагрузите эту машину и снова запустите установку (или перезапустите Ollama), чтобы включить карту до конца.",
        UK to "Драйвер встановлено, але поки не завантажено — перезавантажте цю машину і знову запустіть установку (або перезапустіть Ollama), щоб довести вмикання карти до кінця.",
        IT to "Il driver e stato installato ma non e ancora caricato — riavvia questa macchina, poi esegui di nuovo questa installazione (o riavvia Ollama) per completare l'attivazione della scheda.",
        JA to "ドライバーはインストールされましたが、まだ読み込まれていません。このマシンを再起動してからこのインストールを再実行する (または Ollama を再起動する) と、カードの有効化が完了します。",
        ZH to "驱动已安装但尚未加载 — 请重启本机后再次运行本次安装 (或重启 Ollama) 以完成显卡的启用。"
    ))

    fun ollamaGPUDriverUnsupportedNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "This machine has no ubuntu-drivers tool, so the driver was not installed automatically — install it yourself, then run this install again.",
        DE to "Diese Maschine hat kein ubuntu-drivers-Werkzeug, daher wurde der Treiber nicht automatisch installiert — installieren Sie ihn selbst und fuehren Sie diese Installation dann erneut aus.",
        FR to "Cette machine n'a pas l'outil ubuntu-drivers, le pilote n'a donc pas ete installe automatiquement — installez-le vous-meme, puis relancez cette installation.",
        ES to "Esta maquina no tiene la herramienta ubuntu-drivers, asi que el controlador no se instalo automaticamente — instalelo usted mismo y vuelva a ejecutar esta instalacion.",
        RU to "На этой машине нет утилиты ubuntu-drivers, поэтому драйвер не установился автоматически — установите его сами и снова запустите установку.",
        UK to "На цій машині немає утиліти ubuntu-drivers, тому драйвер не встановився автоматично — встановіть його самостійно і знову запустіть установку.",
        IT to "Questa macchina non ha lo strumento ubuntu-drivers, quindi il driver non e stato installato automaticamente — installalo tu stesso, poi esegui di nuovo questa installazione.",
        JA to "このマシンには ubuntu-drivers ツールがないため、ドライバーは自動インストールされませんでした。自分でインストールしてから、このインストールを再実行してください。",
        ZH to "本机没有 ubuntu-drivers 工具，因此未自动安装驱动 — 请自行安装后再次运行本次安装。"
    ))

    // ---------------------------------------------- Home Assistant

    fun homeAssistantOwnerWarning(l: AppLanguage): String = l.pick(mapOf(
        EN to "IMPORTANT: open this URL right now and create the owner account — until you do, whoever opens the page becomes the owner.",
        DE to "WICHTIG: Öffnen Sie diese URL sofort und legen Sie das Besitzerkonto an — bis dahin wird jeder, der die Seite öffnet, zum Besitzer.",
        FR to "IMPORTANT : ouvrez cette URL dès maintenant et créez le compte propriétaire — d'ici là, quiconque ouvre la page en devient le propriétaire.",
        ES to "IMPORTANTE: abra esta URL ahora mismo y cree la cuenta de propietario — hasta entonces, quien abra la página se convierte en propietario.",
        RU to "ВАЖНО: откройте адрес прямо сейчас и создайте учётную запись владельца — до этого владельцем станет любой, кто откроет страницу.",
        UK to "ВАЖЛИВО: відкрийте адресу просто зараз і створіть обліковий запис власника — доти власником стане будь-хто, хто відкриє сторінку.",
        IT to "IMPORTANTE: apri questo URL subito e crea l'account proprietario — fino ad allora chiunque apra la pagina ne diventa il proprietario.",
        JA to "重要：今すぐこの URL を開いてオーナーアカウントを作成してください — それまでは、ページを開いた人がオーナーになります。",
        ZH to "重要：请立即打开此地址并创建所有者账户 — 在此之前，打开该页面的人将成为所有者。"
    ))

    fun mosquittoNetworkAddress(l: AppLanguage): String = l.pick(mapOf(
        EN to "this server's address on your network",
        DE to "die Adresse dieses Servers in Ihrem Netz",
        FR to "l'adresse de ce serveur sur votre réseau",
        ES to "la dirección de este servidor en su red",
        RU to "адрес этого сервера в вашей сети",
        UK to "адреса цього сервера у вашій мережі",
        IT to "l'indirizzo di questo server nella tua rete",
        JA to "ネットワーク上のこのサーバーのアドレス",
        ZH to "此服务器在您网络中的地址"
    ))

    fun mosquittoAccountsLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Accounts",
        DE to "Konten",
        FR to "Comptes",
        ES to "Cuentas",
        RU to "Учётные записи",
        UK to "Облікові записи",
        IT to "Account",
        JA to "アカウント",
        ZH to "账户"
    ))

    fun zigbee2MQTTPairingHint(l: AppLanguage): String = l.pick(mapOf(
        EN to "Open this page to pair devices: turn “Permit join” on, then press the button on the lamp or sensor.",
        DE to "Öffnen Sie diese Seite zum Koppeln: „Permit join“ einschalten, dann die Taste an Lampe oder Sensor drücken.",
        FR to "Ouvrez cette page pour appairer : activez « Permit join », puis appuyez sur le bouton de la lampe ou du capteur.",
        ES to "Abra esta página para emparejar: active «Permit join» y luego pulse el botón de la lámpara o el sensor.",
        RU to "Откройте эту страницу для привязки устройств: включите «Permit join» и нажмите кнопку на лампе или датчике.",
        UK to "Відкрийте цю сторінку для прив'язки пристроїв: увімкніть «Permit join» і натисніть кнопку на лампі чи датчику.",
        IT to "Apri questa pagina per associare i dispositivi: attiva «Permit join», poi premi il pulsante sulla lampada o sul sensore.",
        JA to "このページで機器をペアリングします：「Permit join」をオンにして、ランプやセンサーのボタンを押してください。",
        ZH to "在此页面配对设备：打开 “Permit join”，然后按下灯或传感器上的按钮。"
    ))

    fun homeAssistantAppHint(l: AppLanguage): String = l.pick(mapOf(
        EN to "Phone app: install Home Assistant and enter this address.",
        DE to "Handy-App: Home Assistant installieren und diese Adresse eingeben.",
        FR to "Application mobile : installez Home Assistant et saisissez cette adresse.",
        ES to "App del móvil: instale Home Assistant e introduzca esta dirección.",
        RU to "Приложение на телефоне: установите Home Assistant и введите этот адрес.",
        UK to "Застосунок на телефоні: встановіть Home Assistant і введіть цю адресу.",
        IT to "App per telefono: installa Home Assistant e inserisci questo indirizzo.",
        JA to "スマホアプリ：Home Assistant をインストールしてこのアドレスを入力してください。",
        ZH to "手机应用：安装 Home Assistant 并输入此地址。"
    ))
}

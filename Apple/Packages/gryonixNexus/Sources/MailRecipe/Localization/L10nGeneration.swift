import ServiceCatalog

enum L10nGeneration {
    // MARK: - MailRecipe warnings

    static func ptrWarning(_ l: AppLanguage, ip: String, hostname: String) -> String {
        l.pick([
            .en: "Configure the PTR record (reverse DNS) at your provider: \(ip) → \(hostname). Without it your mail will land in spam.",
            .de: "Richten Sie den PTR-Eintrag (Reverse DNS) bei Ihrem Anbieter ein: \(ip) → \(hostname). Ohne ihn landen Ihre E-Mails im Spam.",
            .fr: "Configurez l'enregistrement PTR (DNS inverse) chez votre hébergeur : \(ip) → \(hostname). Sans lui, vos e-mails finiront en spam.",
            .es: "Configure el registro PTR (DNS inverso) en su proveedor: \(ip) → \(hostname). Sin él, sus correos acabarán en spam.",
            .ru: "Настройте PTR-запись (обратный DNS) у провайдера: \(ip) → \(hostname). Без неё письма будут уходить в спам.",
            .uk: "Налаштуйте PTR-запис (зворотний DNS) у провайдера: \(ip) → \(hostname). Без нього листи потраплятимуть у спам.",
            .it: "Configura il record PTR (DNS inverso) presso il tuo provider: \(ip) → \(hostname). Senza di esso le e-mail finiranno nello spam.",
            .ja: "プロバイダーで PTR レコード（逆引き DNS）を設定してください: \(ip) → \(hostname)。設定しないとメールがスパム扱いになります。",
            .zh: "请在服务商处配置 PTR 记录（反向 DNS）：\(ip) → \(hostname)。否则邮件会被判为垃圾邮件。"
        ])
    }

    static func port25Warning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Make sure your provider does not block port 25 (inbound and outbound) on the public entry point.",
            .de: "Stellen Sie sicher, dass Ihr Anbieter Port 25 (ein- und ausgehend) am öffentlichen Einstiegspunkt nicht blockiert.",
            .fr: "Vérifiez que votre hébergeur ne bloque pas le port 25 (entrant et sortant) sur le point d'entrée public.",
            .es: "Compruebe que su proveedor no bloquee el puerto 25 (entrante y saliente) en el punto de entrada público.",
            .ru: "Проверьте, что провайдер не блокирует порт 25 (входящий и исходящий) на публичной точке входа.",
            .uk: "Перевірте, що провайдер не блокує порт 25 (вхідний і вихідний) на публічній точці входу.",
            .it: "Verifica che il provider non blocchi la porta 25 (in entrata e in uscita) sul punto di ingresso pubblico.",
            .ja: "公開エントリーポイントでプロバイダーがポート 25（送受信）をブロックしていないか確認してください。",
            .zh: "请确认服务商未在公共入口上封锁 25 端口（入站和出站）。"
        ])
    }

    static func wireGuardPrivateKeysWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The scripts contain WireGuard private keys: transfer them to the servers over a secure channel (scp/SSH) and never publish them.",
            .de: "Die Skripte enthalten private WireGuard-Schlüssel: Übertragen Sie sie über einen sicheren Kanal (scp/SSH) auf die Server und veröffentlichen Sie sie nicht.",
            .fr: "Les scripts contiennent des clés privées WireGuard : transférez-les sur les serveurs via un canal sécurisé (scp/SSH) et ne les publiez pas.",
            .es: "Los scripts contienen claves privadas de WireGuard: transfiéralas a los servidores por un canal seguro (scp/SSH) y no las publique.",
            .ru: "Скрипты содержат приватные ключи WireGuard: передавайте их на серверы по защищённому каналу (scp/SSH) и не публикуйте.",
            .uk: "Скрипти містять приватні ключі WireGuard: передавайте їх на сервери захищеним каналом (scp/SSH) і не публікуйте.",
            .it: "Gli script contengono chiavi private WireGuard: trasferiscile sui server tramite un canale sicuro (scp/SSH) e non pubblicarle.",
            .ja: "スクリプトには WireGuard の秘密鍵が含まれています。安全な経路（scp/SSH）でサーバーに転送し、決して公開しないでください。",
            .zh: "脚本中包含 WireGuard 私钥：请通过安全通道（scp/SSH）传输到服务器，切勿公开。"
        ])
    }

    static func fullTunnelWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The home server runs in full-tunnel mode: all of its outbound traffic goes through the VPS. This is required so outgoing mail leaves from the VPS IP (matching PTR/SPF).",
            .de: "Der Heimserver läuft im Full-Tunnel-Modus: Sein gesamter ausgehender Verkehr läuft über den VPS. Das ist nötig, damit ausgehende E-Mails die IP des VPS verwenden (passend zu PTR/SPF).",
            .fr: "Le serveur domestique fonctionne en tunnel complet : tout son trafic sortant passe par le VPS. C'est nécessaire pour que le courrier sortant parte avec l'IP du VPS (cohérente avec PTR/SPF).",
            .es: "El servidor doméstico funciona en modo túnel completo: todo su tráfico saliente pasa por el VPS. Es necesario para que el correo saliente salga con la IP del VPS (coincide con PTR/SPF).",
            .ru: "Домашний сервер работает в режиме полного туннеля: весь его исходящий трафик пойдёт через VPS. Это нужно, чтобы исходящая почта уходила с IP VPS (совпадает с PTR/SPF).",
            .uk: "Домашній сервер працює в режимі повного тунелю: весь його вихідний трафік піде через VPS. Це потрібно, щоб вихідна пошта йшла з IP VPS (збігається з PTR/SPF).",
            .it: "Il server domestico funziona in modalità full tunnel: tutto il suo traffico in uscita passa dal VPS. Serve perché la posta in uscita parta dall'IP del VPS (coerente con PTR/SPF).",
            .ja: "自宅サーバーはフルトンネルモードで動作し、すべての送信トラフィックが VPS を経由します。送信メールを VPS の IP（PTR/SPF と一致）から送るために必要です。",
            .zh: "家庭服务器以全隧道模式运行：其所有出站流量都经过 VPS。这样发出的邮件才会使用 VPS 的 IP（与 PTR/SPF 一致）。"
        ])
    }

    // MARK: - MailRecipe notes

    static func postStepsServices(_ l: AppLanguage) -> String {
        l.pick([
            .en: "After the script: all service credentials (generated passwords/tokens) are in the script's report.",
            .de: "Nach dem Skript: Alle Zugangsdaten der Dienste (generierte Passwörter/Token) stehen im Bericht des Skripts.",
            .fr: "Après le script : tous les accès des services (mots de passe/jetons générés) figurent dans le rapport du script.",
            .es: "Después del script: todas las credenciales de los servicios (contraseñas/tokens generados) están en el informe del script.",
            .ru: "После скрипта: все доступы сервисов (сгенерированные пароли/токены) — в отчёте скрипта.",
            .uk: "Після скрипту: всі доступи сервісів (згенеровані паролі/токени) — у звіті скрипту.",
            .it: "Dopo lo script: tutte le credenziali dei servizi (password/token generati) sono nel report dello script.",
            .ja: "スクリプト実行後: 各サービスの認証情報（生成されたパスワード/トークン）はスクリプトのレポートに記載されます。",
            .zh: "脚本运行后：所有服务的访问凭据（生成的密码/令牌）都在脚本报告中。"
        ])
    }

    static func noteSingleHostDNS(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Add the DNS records from dns-records.txt at your DNS provider.",
            .de: "Fügen Sie die DNS-Einträge aus dns-records.txt bei Ihrem DNS-Anbieter hinzu.",
            .fr: "Ajoutez les enregistrements DNS de dns-records.txt chez votre fournisseur DNS.",
            .es: "Añada los registros DNS de dns-records.txt en su proveedor de DNS.",
            .ru: "Добавьте DNS-записи из dns-records.txt у вашего DNS-провайдера.",
            .uk: "Додайте DNS-записи з dns-records.txt у вашого DNS-провайдера.",
            .it: "Aggiungi i record DNS di dns-records.txt presso il tuo provider DNS.",
            .ja: "dns-records.txt の DNS レコードを DNS プロバイダーに追加してください。",
            .zh: "请在您的 DNS 服务商处添加 dns-records.txt 中的 DNS 记录。"
        ])
    }

    static func noteSingleHostRun(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Copy setup-mail-server.sh to the server and run it once: sudo bash setup-mail-server.sh. The script does everything else itself and finishes with a report.",
            .de: "Kopieren Sie setup-mail-server.sh auf den Server und führen Sie es einmal aus: sudo bash setup-mail-server.sh. Alles Weitere erledigt das Skript selbst und schließt mit einem Bericht ab.",
            .fr: "Copiez setup-mail-server.sh sur le serveur et exécutez-le une fois : sudo bash setup-mail-server.sh. Le script fait tout le reste lui-même et se termine par un rapport.",
            .es: "Copie setup-mail-server.sh al servidor y ejecútelo una vez: sudo bash setup-mail-server.sh. El script hace todo lo demás por sí solo y termina con un informe.",
            .ru: "Скопируйте setup-mail-server.sh на сервер и запустите один раз: sudo bash setup-mail-server.sh. Всё остальное скрипт сделает сам и завершится отчётом.",
            .uk: "Скопіюйте setup-mail-server.sh на сервер і запустіть один раз: sudo bash setup-mail-server.sh. Решту скрипт зробить сам і завершиться звітом.",
            .it: "Copia setup-mail-server.sh sul server ed eseguilo una volta: sudo bash setup-mail-server.sh. Lo script fa tutto il resto da solo e termina con un report.",
            .ja: "setup-mail-server.sh をサーバーにコピーして一度だけ実行してください: sudo bash setup-mail-server.sh。残りはスクリプトがすべて行い、最後にレポートを出力します。",
            .zh: "将 setup-mail-server.sh 复制到服务器并运行一次：sudo bash setup-mail-server.sh。其余工作由脚本自动完成，最后输出报告。"
        ])
    }

    static func noteSplitDNS(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Add the DNS records from dns-records.txt (A records point at the VPS public IP).",
            .de: "Fügen Sie die DNS-Einträge aus dns-records.txt hinzu (A-Einträge zeigen auf die öffentliche IP des VPS).",
            .fr: "Ajoutez les enregistrements DNS de dns-records.txt (les enregistrements A pointent vers l'IP publique du VPS).",
            .es: "Añada los registros DNS de dns-records.txt (los registros A apuntan a la IP pública del VPS).",
            .ru: "Добавьте DNS-записи из dns-records.txt (A-записи — на публичный IP VPS).",
            .uk: "Додайте DNS-записи з dns-records.txt (A-записи — на публічний IP VPS).",
            .it: "Aggiungi i record DNS di dns-records.txt (i record A puntano all'IP pubblico del VPS).",
            .ja: "dns-records.txt の DNS レコードを追加してください（A レコードは VPS のパブリック IP を指します）。",
            .zh: "请添加 dns-records.txt 中的 DNS 记录（A 记录指向 VPS 的公网 IP）。"
        ])
    }

    static func noteSplitVPS(_ l: AppLanguage) -> String {
        l.pick([
            .en: "First on the VPS: sudo bash setup-vps.sh — brings up the tunnel and port forwarding.",
            .de: "Zuerst auf dem VPS: sudo bash setup-vps.sh — richtet den Tunnel und die Portweiterleitung ein.",
            .fr: "D'abord sur le VPS : sudo bash setup-vps.sh — met en place le tunnel et la redirection de ports.",
            .es: "Primero en el VPS: sudo bash setup-vps.sh — levanta el túnel y el reenvío de puertos.",
            .ru: "Сначала на VPS: sudo bash setup-vps.sh — поднимет туннель и проброс портов.",
            .uk: "Спочатку на VPS: sudo bash setup-vps.sh — підніме тунель і проброс портів.",
            .it: "Prima sul VPS: sudo bash setup-vps.sh — attiva il tunnel e l'inoltro delle porte.",
            .ja: "まず VPS で: sudo bash setup-vps.sh — トンネルとポート転送を設定します。",
            .zh: "先在 VPS 上运行：sudo bash setup-vps.sh —— 建立隧道和端口转发。"
        ])
    }

    static func noteSplitHome(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Then on the home server: sudo bash setup-home-server.sh — waits for the tunnel, brings up the services and finishes with a report.",
            .de: "Dann auf dem Heimserver: sudo bash setup-home-server.sh — wartet auf den Tunnel, startet die Dienste und schließt mit einem Bericht ab.",
            .fr: "Puis sur le serveur domestique : sudo bash setup-home-server.sh — attend le tunnel, démarre les services et se termine par un rapport.",
            .es: "Luego en el servidor doméstico: sudo bash setup-home-server.sh — espera el túnel, levanta los servicios y termina con un informe.",
            .ru: "Затем на домашнем сервере: sudo bash setup-home-server.sh — дождётся туннеля, поднимет сервисы и завершится отчётом.",
            .uk: "Потім на домашньому сервері: sudo bash setup-home-server.sh — дочекається тунелю, підніме сервіси й завершиться звітом.",
            .it: "Poi sul server domestico: sudo bash setup-home-server.sh — attende il tunnel, avvia i servizi e termina con un report.",
            .ja: "次に自宅サーバーで: sudo bash setup-home-server.sh — トンネルを待ってサービスを起動し、最後にレポートを出力します。",
            .zh: "然后在家庭服务器上运行：sudo bash setup-home-server.sh —— 等待隧道建立，启动服务，最后输出报告。"
        ])
    }

    static func dnsMailHostComment(_ l: AppLanguage, singleHost: Bool) -> String {
        singleHost
            ? l.pick([
                .en: "The mail host points at the server's public IP.",
                .de: "Der Mail-Host zeigt auf die öffentliche IP des Servers.",
                .fr: "L'hôte de messagerie pointe vers l'IP publique du serveur.",
                .es: "El host de correo apunta a la IP pública del servidor.",
                .ru: "Почтовый хост указывает на публичный IP сервера.",
                .uk: "Поштовий хост вказує на публічний IP сервера.",
                .it: "L'host di posta punta all'IP pubblico del server.",
                .ja: "メールホストはサーバーのパブリック IP を指します。",
                .zh: "邮件主机指向服务器的公网 IP。"
            ])
            : l.pick([
                .en: "The mail host points at the VPS's public IP.",
                .de: "Der Mail-Host zeigt auf die öffentliche IP des VPS.",
                .fr: "L'hôte de messagerie pointe vers l'IP publique du VPS.",
                .es: "El host de correo apunta a la IP pública del VPS.",
                .ru: "Почтовый хост указывает на публичный IP VPS.",
                .uk: "Поштовий хост вказує на публічний IP VPS.",
                .it: "L'host di posta punta all'IP pubblico del VPS.",
                .ja: "メールホストは VPS のパブリック IP を指します。",
                .zh: "邮件主机指向 VPS 的公网 IP。"
            ])
    }

    static func dnsMXComment(_ l: AppLanguage, hostname: String) -> String {
        l.pick([
            .en: "Mail for the domain is received by host \(hostname).",
            .de: "E-Mails der Domain nimmt der Host \(hostname) entgegen.",
            .fr: "Le courrier du domaine est reçu par l'hôte \(hostname).",
            .es: "El correo del dominio lo recibe el host \(hostname).",
            .ru: "Почта домена принимается хостом \(hostname).",
            .uk: "Пошту домену приймає хост \(hostname).",
            .it: "La posta del dominio è ricevuta dall'host \(hostname).",
            .ja: "ドメイン宛のメールはホスト \(hostname) が受信します。",
            .zh: "该域名的邮件由主机 \(hostname) 接收。"
        ])
    }

    static func dnsSPFComment(_ l: AppLanguage) -> String {
        l.pick([
            .en: "SPF: only the MX host may send mail for the domain.",
            .de: "SPF: Nur der MX-Host darf E-Mails für die Domain senden.",
            .fr: "SPF : seul l'hôte MX peut envoyer du courrier pour le domaine.",
            .es: "SPF: solo el host del MX puede enviar correo del dominio.",
            .ru: "SPF: отправлять почту домена может только хост из MX.",
            .uk: "SPF: надсилати пошту домену може лише хост із MX.",
            .it: "SPF: solo l'host MX può inviare posta per il dominio.",
            .ja: "SPF: ドメインのメールを送信できるのは MX のホストのみです。",
            .zh: "SPF：只有 MX 主机可以发送该域名的邮件。"
        ])
    }

    static func dnsDMARCComment(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DMARC: mail failing SPF/DKIM goes to quarantine; reports go to postmaster.",
            .de: "DMARC: E-Mails ohne SPF/DKIM kommen in Quarantäne, Berichte gehen an postmaster.",
            .fr: "DMARC : les messages sans SPF/DKIM vont en quarantaine, rapports envoyés à postmaster.",
            .es: "DMARC: el correo sin SPF/DKIM va a cuarentena; los informes, a postmaster.",
            .ru: "DMARC: письма без SPF/DKIM — в карантин, отчёты на postmaster.",
            .uk: "DMARC: листи без SPF/DKIM — у карантин, звіти на postmaster.",
            .it: "DMARC: la posta senza SPF/DKIM va in quarantena, i report a postmaster.",
            .ja: "DMARC: SPF/DKIM に失敗したメールは隔離され、レポートは postmaster に送られます。",
            .zh: "DMARC：未通过 SPF/DKIM 的邮件进入隔离区，报告发送至 postmaster。"
        ])
    }

    static func dnsAutoconfigComment(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Autoconfig: mail apps like Outlook and Thunderbird find the server settings themselves.",
            .de: "Autoconfig: Mail-Apps wie Outlook und Thunderbird finden die Servereinstellungen selbst.",
            .fr: "Autoconfig : les applis mail comme Outlook et Thunderbird trouvent seules les réglages du serveur.",
            .es: "Autoconfig: apps de correo como Outlook y Thunderbird encuentran solas la configuración del servidor.",
            .ru: "Автонастройка: Outlook, Thunderbird и другие почтовые программы сами найдут настройки сервера.",
            .uk: "Автоналаштування: Outlook, Thunderbird та інші поштові програми самі знайдуть налаштування сервера.",
            .it: "Autoconfig: app di posta come Outlook e Thunderbird trovano da sole le impostazioni del server.",
            .ja: "自動設定: Outlook や Thunderbird などのメールアプリがサーバー設定を自動で見つけます。",
            .zh: "自动配置：Outlook、Thunderbird 等邮件应用会自动找到服务器设置。"
        ])
    }

    static func dnsServiceHostsComment(_ l: AppLanguage, singleHost: Bool) -> String {
        singleHost
            ? l.pick([
                .en: "Service hostnames — the same public IP of the server (proxied by Caddy).",
                .de: "Dienst-Hostnamen — dieselbe öffentliche IP des Servers (Caddy als Proxy).",
                .fr: "Noms d'hôte des services — la même IP publique du serveur (proxy Caddy).",
                .es: "Nombres de host de los servicios: la misma IP pública del servidor (con proxy Caddy).",
                .ru: "Хостнеймы сервисов — тот же публичный IP сервера (проксирует Caddy).",
                .uk: "Хостнейми сервісів — той самий публічний IP сервера (проксіює Caddy).",
                .it: "Hostname dei servizi — lo stesso IP pubblico del server (proxy Caddy).",
                .ja: "サービスのホスト名 — サーバーの同じパブリック IP（Caddy がプロキシ）。",
                .zh: "服务主机名 —— 与服务器相同的公网 IP（由 Caddy 代理）。"
            ])
            : l.pick([
                .en: "Service hostnames — the same public IP of the VPS (proxied by Caddy).",
                .de: "Dienst-Hostnamen — dieselbe öffentliche IP des VPS (Caddy als Proxy).",
                .fr: "Noms d'hôte des services — la même IP publique du VPS (proxy Caddy).",
                .es: "Nombres de host de los servicios: la misma IP pública del VPS (con proxy Caddy).",
                .ru: "Хостнеймы сервисов — тот же публичный IP VPS (проксирует Caddy).",
                .uk: "Хостнейми сервісів — той самий публічний IP VPS (проксіює Caddy).",
                .it: "Hostname dei servizi — lo stesso IP pubblico del VPS (proxy Caddy).",
                .ja: "サービスのホスト名 — VPS の同じパブリック IP（Caddy がプロキシ）。",
                .zh: "服务主机名 —— 与 VPS 相同的公网 IP（由 Caddy 代理）。"
            ])
    }

    static func dnsHeaderTitle(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "DNS records for \(domain) — add them at your DNS provider.",
            .de: "DNS-Einträge für \(domain) — fügen Sie sie bei Ihrem DNS-Anbieter hinzu.",
            .fr: "Enregistrements DNS pour \(domain) — à ajouter chez votre fournisseur DNS.",
            .es: "Registros DNS para \(domain): añádalos en su proveedor de DNS.",
            .ru: "DNS-записи для \(domain) — добавьте у вашего DNS-провайдера.",
            .uk: "DNS-записи для \(domain) — додайте у вашого DNS-провайдера.",
            .it: "Record DNS per \(domain) — aggiungili presso il tuo provider DNS.",
            .ja: "\(domain) の DNS レコード — DNS プロバイダーに追加してください。",
            .zh: "\(domain) 的 DNS 记录 —— 请在您的 DNS 服务商处添加。"
        ])
    }

    static func dnsHeaderFormat(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Format: name  type  value",
            .de: "Format: Name  Typ  Wert",
            .fr: "Format : nom  type  valeur",
            .es: "Formato: nombre  tipo  valor",
            .ru: "Формат: имя  тип  значение",
            .uk: "Формат: ім'я  тип  значення",
            .it: "Formato: nome  tipo  valore",
            .ja: "形式: 名前  種別  値",
            .zh: "格式：名称  类型  值"
        ])
    }

    static func dkimComment(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DKIM: the setup script prints the value in its report (the key is generated on the server).",
            .de: "DKIM: Das Setup-Skript gibt den Wert im Bericht aus (der Schlüssel wird auf dem Server erzeugt).",
            .fr: "DKIM : le script d'installation affiche la valeur dans son rapport (la clé est générée sur le serveur).",
            .es: "DKIM: el script de instalación muestra el valor en su informe (la clave se genera en el servidor).",
            .ru: "DKIM: значение выведет setup-скрипт в отчёте (ключ генерируется на сервере).",
            .uk: "DKIM: значення виведе setup-скрипт у звіті (ключ генерується на сервері).",
            .it: "DKIM: lo script di setup stampa il valore nel report (la chiave è generata sul server).",
            .ja: "DKIM: 値はセットアップスクリプトがレポートに出力します（鍵はサーバー上で生成されます）。",
            .zh: "DKIM：该值由安装脚本在报告中输出（密钥在服务器上生成）。"
        ])
    }

    /// Placeholder inside the sample DKIM TXT line: p=<...>
    static func dkimValuePlaceholder(_ l: AppLanguage) -> String {
        l.pick([
            .en: "from the setup script report",
            .de: "aus dem Bericht des Setup-Skripts",
            .fr: "du rapport du script d'installation",
            .es: "del informe del script de instalación",
            .ru: "из отчёта setup-скрипта",
            .uk: "зі звіту setup-скрипта",
            .it: "dal report dello script di setup",
            .ja: "セットアップスクリプトのレポートから",
            .zh: "来自安装脚本报告"
        ])
    }

    static func ptrComment(_ l: AppLanguage, singleHost: Bool) -> String {
        singleHost
            ? l.pick([
                .en: "PTR (reverse DNS) is configured NOT here but in the server provider's panel:",
                .de: "Der PTR-Eintrag (Reverse DNS) wird NICHT hier konfiguriert, sondern im Panel des Server-Anbieters:",
                .fr: "Le PTR (DNS inverse) se configure NON PAS ici, mais dans le panneau du fournisseur du serveur :",
                .es: "El PTR (DNS inverso) NO se configura aquí, sino en el panel del proveedor del servidor:",
                .ru: "PTR (обратный DNS) настраивается НЕ здесь, а в панели провайдера сервера:",
                .uk: "PTR (зворотний DNS) налаштовується НЕ тут, а в панелі провайдера сервера:",
                .it: "Il PTR (DNS inverso) NON si configura qui, ma nel pannello del provider del server:",
                .ja: "PTR（逆引き DNS）はここではなく、サーバーのプロバイダーの管理画面で設定します:",
                .zh: "PTR（反向 DNS）不在此处配置，而是在服务器提供商的面板中设置："
            ])
            : l.pick([
                .en: "PTR (reverse DNS) is configured NOT here but in the VPS provider's panel:",
                .de: "Der PTR-Eintrag (Reverse DNS) wird NICHT hier konfiguriert, sondern im Panel des VPS-Anbieters:",
                .fr: "Le PTR (DNS inverse) se configure NON PAS ici, mais dans le panneau du fournisseur du VPS :",
                .es: "El PTR (DNS inverso) NO se configura aquí, sino en el panel del proveedor del VPS:",
                .ru: "PTR (обратный DNS) настраивается НЕ здесь, а в панели провайдера VPS:",
                .uk: "PTR (зворотний DNS) налаштовується НЕ тут, а в панелі провайдера VPS:",
                .it: "Il PTR (DNS inverso) NON si configura qui, ma nel pannello del provider del VPS:",
                .ja: "PTR（逆引き DNS）はここではなく、VPS のプロバイダーの管理画面で設定します:",
                .zh: "PTR（反向 DNS）不在此处配置，而是在 VPS 提供商的面板中设置："
            ])
    }

    static func ptrForwardComment(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Forward record for the PTR hostname (reverse DNS must resolve back to the same IP).",
            .de: "Vorwärts-Eintrag für den PTR-Hostnamen (Reverse DNS muss auf dieselbe IP zurückauflösen).",
            .fr: "Enregistrement direct pour le nom d'hôte PTR (le DNS inverse doit résoudre vers la même IP).",
            .es: "Registro directo para el nombre de host del PTR (el DNS inverso debe resolver a la misma IP).",
            .ru: "Прямая запись для PTR-хостнейма (обратный DNS должен резолвиться обратно в тот же IP).",
            .uk: "Прямий запис для PTR-хостнейму (зворотний DNS має резолвитися назад у ту саму IP).",
            .it: "Record diretto per l'hostname del PTR (il DNS inverso deve risolvere sullo stesso IP).",
            .ja: "PTR ホスト名の正引きレコード（逆引き DNS は同じ IP に解決される必要があります）。",
            .zh: "PTR 主机名的正向记录（反向 DNS 必须解析回同一 IP）。"
        ])
    }

    static func ptrTargetLine(_ l: AppLanguage, ip: String, hostname: String) -> String {
        l.pick([
            .en: "\(ip) -> \(hostname) — critical for deliverability.",
            .de: "\(ip) -> \(hostname) — entscheidend für die Zustellbarkeit.",
            .fr: "\(ip) -> \(hostname) — essentiel pour la délivrabilité.",
            .es: "\(ip) -> \(hostname): crítico para la entregabilidad.",
            .ru: "\(ip) -> \(hostname) — критично для доставляемости.",
            .uk: "\(ip) -> \(hostname) — критично для доставлюваності.",
            .it: "\(ip) -> \(hostname) — fondamentale per la deliverability.",
            .ja: "\(ip) -> \(hostname) — 到達率に不可欠です。",
            .zh: "\(ip) -> \(hostname) —— 对送达率至关重要。"
        ])
    }

    static func dnsSummaryMail(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DNS records (A, MX, SPF, DMARC + service hostnames) for the DNS provider's panel; DKIM is added after the key is generated on the server.",
            .de: "DNS-Einträge (A, MX, SPF, DMARC + Dienst-Hostnamen) für das Panel des DNS-Anbieters; DKIM wird hinzugefügt, nachdem der Schlüssel auf dem Server erzeugt wurde.",
            .fr: "Enregistrements DNS (A, MX, SPF, DMARC + noms d'hôte des services) pour le panneau du fournisseur DNS ; DKIM s'ajoute après la génération de la clé sur le serveur.",
            .es: "Registros DNS (A, MX, SPF, DMARC + nombres de host de servicios) para el panel del proveedor de DNS; DKIM se añade tras generar la clave en el servidor.",
            .ru: "DNS-записи (A, MX, SPF, DMARC + хостнеймы сервисов) для панели DNS-провайдера; DKIM добавляется после генерации ключа на сервере.",
            .uk: "DNS-записи (A, MX, SPF, DMARC + хостнейми сервісів) для панелі DNS-провайдера; DKIM додається після генерації ключа на сервері.",
            .it: "Record DNS (A, MX, SPF, DMARC + hostname dei servizi) per il pannello del provider DNS; DKIM si aggiunge dopo la generazione della chiave sul server.",
            .ja: "DNS プロバイダーの管理画面用の DNS レコード（A、MX、SPF、DMARC + サービスのホスト名）。DKIM はサーバーで鍵を生成した後に追加します。",
            .zh: "用于 DNS 服务商面板的 DNS 记录（A、MX、SPF、DMARC + 服务主机名）；DKIM 在服务器上生成密钥后添加。"
        ])
    }

    static func dnsSummaryServicesOnly(_ l: AppLanguage) -> String {
        l.pick([
            .en: "DNS records (A records for service hostnames) for the DNS provider's panel.",
            .de: "DNS-Einträge (A-Einträge der Dienst-Hostnamen) für das Panel des DNS-Anbieters.",
            .fr: "Enregistrements DNS (enregistrements A des noms d'hôte des services) pour le panneau du fournisseur DNS.",
            .es: "Registros DNS (registros A de los nombres de host de servicios) para el panel del proveedor de DNS.",
            .ru: "DNS-записи (A-записи хостнеймов сервисов) для панели DNS-провайдера.",
            .uk: "DNS-записи (A-записи хостнеймів сервісів) для панелі DNS-провайдера.",
            .it: "Record DNS (record A degli hostname dei servizi) per il pannello del provider DNS.",
            .ja: "DNS プロバイダーの管理画面用の DNS レコード（サービスのホスト名の A レコード）。",
            .zh: "用于 DNS 服务商面板的 DNS 记录（服务主机名的 A 记录）。"
        ])
    }

    static func dnsZoneNote(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Standard BIND zone file (SOA/NS are managed by your DNS provider and aren't included) — most providers accept it under \"import zone\".",
            .de: "Standard-BIND-Zonendatei (SOA/NS werden von Ihrem DNS-Anbieter verwaltet und sind nicht enthalten) — die meisten Anbieter akzeptieren sie unter „Zone importieren“.",
            .fr: "Fichier de zone BIND standard (les enregistrements SOA/NS sont gérés par votre fournisseur DNS et ne sont pas inclus) — la plupart des fournisseurs l'acceptent via « importer une zone ».",
            .es: "Archivo de zona BIND estándar (SOA/NS los gestiona su proveedor de DNS y no se incluyen) — la mayoría de los proveedores lo aceptan en «importar zona».",
            .ru: "Стандартный BIND zone-файл (SOA/NS управляются вашим DNS-провайдером и не включены) — большинство провайдеров принимают его в разделе «импорт зоны».",
            .uk: "Стандартний BIND zone-файл (SOA/NS керуються вашим DNS-провайдером і не включені) — більшість провайдерів приймають його в розділі «імпорт зони».",
            .it: "File di zona BIND standard (SOA/NS sono gestiti dal tuo provider DNS e non sono inclusi) — la maggior parte dei provider lo accetta tramite \"importa zona\".",
            .ja: "標準的な BIND ゾーンファイルです（SOA/NS は DNS プロバイダーが管理するため含まれていません）。多くのプロバイダーは「ゾーンのインポート」で受け付けます。",
            .zh: "标准 BIND 区域文件（SOA/NS 由您的 DNS 服务商管理，未包含在内）——大多数服务商在「导入区域」中可接受此文件。"
        ])
    }

    static func dnsZoneSummary(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Standard BIND zone file with the same records — import it directly at most DNS providers.",
            .de: "Standard-BIND-Zonendatei mit denselben Einträgen — bei den meisten DNS-Anbietern direkt importierbar.",
            .fr: "Fichier de zone BIND standard avec les mêmes enregistrements — importable directement chez la plupart des fournisseurs DNS.",
            .es: "Archivo de zona BIND estándar con los mismos registros — importable directamente en la mayoría de proveedores de DNS.",
            .ru: "Стандартный BIND zone-файл с теми же записями — импортируется напрямую у большинства DNS-провайдеров.",
            .uk: "Стандартний BIND zone-файл із тими самими записами — імпортується напряму в більшості DNS-провайдерів.",
            .it: "File di zona BIND standard con gli stessi record — importabile direttamente presso la maggior parte dei provider DNS.",
            .ja: "同じレコードを含む標準的な BIND ゾーンファイルです。多くの DNS プロバイダーで直接インポートできます。",
            .zh: "包含相同记录的标准 BIND 区域文件——可直接导入大多数 DNS 服务商。"
        ])
    }

    static func dnsCSVSummary(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Generic CSV (type, name, value, ttl, priority) with the same records — for panels that prefer CSV import.",
            .de: "Generische CSV-Datei (type, name, value, ttl, priority) mit denselben Einträgen — für Panels, die CSV-Import bevorzugen.",
            .fr: "Fichier CSV générique (type, name, value, ttl, priority) avec les mêmes enregistrements — pour les panneaux qui préfèrent l'import CSV.",
            .es: "CSV genérico (type, name, value, ttl, priority) con los mismos registros — para paneles que prefieren la importación CSV.",
            .ru: "Универсальный CSV (type, name, value, ttl, priority) с теми же записями — для панелей, которые предпочитают импорт CSV.",
            .uk: "Універсальний CSV (type, name, value, ttl, priority) з тими самими записами — для панелей, які надають перевагу імпорту CSV.",
            .it: "CSV generico (type, name, value, ttl, priority) con gli stessi record — per i pannelli che preferiscono l'importazione CSV.",
            .ja: "同じレコードを含む汎用 CSV（type, name, value, ttl, priority）です。CSV インポートを好む管理画面向けです。",
            .zh: "包含相同记录的通用 CSV（type, name, value, ttl, priority）——适用于偏好 CSV 导入的面板。"
        ])
    }

    static func noteDNSImportFiles(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The same records are also available as a BIND zone file (<domain>.zone) and a CSV (dns-records.csv) — most DNS providers (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun and others) can import one of them automatically.",
            .de: "Dieselben Einträge stehen auch als BIND-Zonendatei (<domain>.zone) und als CSV (dns-records.csv) bereit — die meisten DNS-Anbieter (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun und andere) können eine davon automatisch importieren.",
            .fr: "Les mêmes enregistrements sont aussi disponibles sous forme de fichier de zone BIND (<domain>.zone) et de CSV (dns-records.csv) — la plupart des fournisseurs DNS (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun et d'autres) peuvent en importer un automatiquement.",
            .es: "Los mismos registros también están disponibles como archivo de zona BIND (<domain>.zone) y como CSV (dns-records.csv) — la mayoría de proveedores de DNS (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun y otros) pueden importar uno de ellos automáticamente.",
            .ru: "Те же записи также доступны как BIND zone-файл (<domain>.zone) и как CSV (dns-records.csv) — большинство DNS-провайдеров (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun и другие) умеют импортировать один из них автоматически.",
            .uk: "Ті самі записи також доступні як BIND zone-файл (<domain>.zone) і як CSV (dns-records.csv) — більшість DNS-провайдерів (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun та інші) вміють імпортувати один із них автоматично.",
            .it: "Gli stessi record sono disponibili anche come file di zona BIND (<domain>.zone) e come CSV (dns-records.csv) — la maggior parte dei provider DNS (Cloudflare, Route 53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun e altri) può importarne uno automaticamente.",
            .ja: "同じレコードは BIND ゾーンファイル（<domain>.zone）と CSV（dns-records.csv）としても用意されています。多くの DNS プロバイダー（Cloudflare、Route 53、Google、Namecheap、GoDaddy、Gandi、Hetzner、deSEC、DNSimple、Porkbun など）はどちらかを自動でインポートできます。",
            .zh: "相同的记录还提供 BIND 区域文件（<domain>.zone）和 CSV（dns-records.csv）两种格式——大多数 DNS 服务商（Cloudflare、Route 53、Google、Namecheap、GoDaddy、Gandi、Hetzner、deSEC、DNSimple、Porkbun 等）都能自动导入其中之一。"
        ])
    }

    static func errNoServices(_ l: AppLanguage) -> String {
        l.pick([
            .en: "No services selected: enable mail or at least one additional service.",
            .de: "Kein Dienst ausgewählt: Aktivieren Sie E-Mail oder mindestens einen zusätzlichen Dienst.",
            .fr: "Aucun service sélectionné : activez la messagerie ou au moins un service supplémentaire.",
            .es: "No se ha seleccionado ningún servicio: active el correo o al menos un servicio adicional.",
            .ru: "Не выбран ни один сервис: включите почту или хотя бы один доп. сервис.",
            .uk: "Не вибрано жодного сервісу: увімкніть пошту або хоча б один додатковий сервіс.",
            .it: "Nessun servizio selezionato: attiva la posta o almeno un servizio aggiuntivo.",
            .ja: "サービスが選択されていません。メールか、少なくとも 1 つの追加サービスを有効にしてください。",
            .zh: "未选择任何服务：请启用邮件或至少一个附加服务。"
        ])
    }

    static func errConflictingServices(_ l: AppLanguage, names: String) -> String {
        l.pick([
            .en: "The selected services conflict with each other: \(names).",
            .de: "Die ausgewählten Dienste stehen im Konflikt zueinander: \(names).",
            .fr: "Les services sélectionnés sont en conflit : \(names).",
            .es: "Los servicios seleccionados entran en conflicto entre sí: \(names).",
            .ru: "Выбранные сервисы конфликтуют между собой: \(names).",
            .uk: "Вибрані сервіси конфліктують між собою: \(names).",
            .it: "I servizi selezionati sono in conflitto tra loro: \(names).",
            .ja: "選択されたサービスが互いに競合しています: \(names)。",
            .zh: "所选服务之间存在冲突：\(names)。"
        ])
    }

    static func errLocalOnlyRequiresPublicDomain(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "\(service) needs a real, publicly resolvable domain (DNS records, inbound mail ports) and cannot be installed on a local-network-only deployment.",
            .de: "\(service) benötigt eine echte, öffentlich auflösbare Domain (DNS-Einträge, eingehende Mail-Ports) und kann in einem nur lokalen Deployment nicht installiert werden.",
            .fr: "\(service) nécessite un domaine réel et résoluble publiquement (enregistrements DNS, ports de messagerie entrants) et ne peut pas être installé sur un déploiement réseau local uniquement.",
            .es: "\(service) necesita un dominio real y resoluble públicamente (registros DNS, puertos de correo entrantes) y no se puede instalar en una implementación solo de red local.",
            .ru: "\(service) требует настоящий, публично резолвящийся домен (DNS-записи, входящие почтовые порты) и не может быть установлен на развёртывании только для локальной сети.",
            .uk: "\(service) потребує справжній, публічно резолвний домен (DNS-записи, вхідні поштові порти) і не може бути встановлений на розгортанні лише для локальної мережі.",
            .it: "\(service) richiede un dominio reale e risolvibile pubblicamente (record DNS, porte di posta in entrata) e non può essere installato su un deployment solo di rete locale.",
            .ja: "\(service) には実在の公開解決可能なドメイン（DNS レコード、受信メールポート）が必要なため、ローカルネットワーク限定のデプロイにはインストールできません。",
            .zh: "\(service) 需要真实的、可公开解析的域名（DNS 记录、入站邮件端口），无法安装在仅限本地网络的部署中。"
        ])
    }

    static func errLocalOnlyRequiresPublicIP(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "\(service) needs a public IP address for other devices to reach it from outside your network, and cannot be installed on a local-network-only deployment.",
            .de: "\(service) benötigt eine öffentliche IP-Adresse, damit andere Geräte von außerhalb Ihres Netzwerks darauf zugreifen können, und kann in einem nur lokalen Deployment nicht installiert werden.",
            .fr: "\(service) nécessite une adresse IP publique pour que d'autres appareils puissent y accéder depuis l'extérieur de votre réseau, et ne peut pas être installé sur un déploiement réseau local uniquement.",
            .es: "\(service) necesita una dirección IP pública para que otros dispositivos puedan acceder a él desde fuera de su red, y no se puede instalar en una implementación solo de red local.",
            .ru: "\(service) требует публичный IP-адрес, чтобы к нему можно было подключиться извне вашей сети, и не может быть установлен на развёртывании только для локальной сети.",
            .uk: "\(service) потребує публічну IP-адресу, щоб до нього можна було підключитися ззовні вашої мережі, і не може бути встановлений на розгортанні лише для локальної мережі.",
            .it: "\(service) richiede un indirizzo IP pubblico affinché altri dispositivi possano raggiungerlo dall'esterno della rete, e non può essere installato su un deployment solo di rete locale.",
            .ja: "\(service) は、ネットワーク外部の他のデバイスから到達できるようにするため公開 IP アドレスが必要であり、ローカルネットワーク限定のデプロイにはインストールできません。",
            .zh: "\(service) 需要公网 IP 地址才能被网络外部的其他设备访问，无法安装在仅限本地网络的部署中。"
        ])
    }

    static func errServiceNeedsHomeMachine(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "\(service) has to run on a machine in your home — it talks to the devices on your home network. Pick a local server, or confirm that this machine is at home.",
            .de: "\(service) muss auf einem Rechner bei Ihnen zu Hause laufen — es spricht mit den Geräten im Heimnetz. Wählen Sie einen lokalen Server oder bestätigen Sie, dass dieser Rechner zu Hause steht.",
            .fr: "\(service) doit tourner sur une machine chez vous — il dialogue avec les appareils de votre réseau domestique. Choisissez un serveur local ou confirmez que cette machine est chez vous.",
            .es: "\(service) tiene que funcionar en una máquina de su casa — habla con los dispositivos de su red doméstica. Elija un servidor local o confirme que esta máquina está en casa.",
            .ru: "\(service) должен работать на машине у вас дома — он общается с устройствами домашней сети. Выберите локальный сервер или подтвердите, что эта машина стоит дома.",
            .uk: "\(service) має працювати на машині у вас удома — він спілкується з пристроями домашньої мережі. Виберіть локальний сервер або підтвердьте, що ця машина стоїть удома.",
            .it: "\(service) deve girare su una macchina in casa tua — parla con i dispositivi della rete di casa. Scegli un server locale o conferma che questa macchina è in casa.",
            .ja: "\(service) は自宅にあるマシンで動かす必要があります — 自宅ネットワークのデバイスと通信するためです。ローカルサーバーを選ぶか、このマシンが自宅にあることを確認してください。",
            .zh: "\(service) 必须运行在您家中的机器上——它需要与家庭网络中的设备通信。请选择本地服务器，或确认这台机器就在家中。"
        ])
    }

    static func errAddOnNeedsTheHub(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "\(service) is an add-on for Home Assistant and does nothing without it. Add the hub, or take this one off.",
            .de: "\(service) ist ein Zusatz für Home Assistant und tut ohne ihn nichts. Fügen Sie den Hub hinzu oder nehmen Sie diesen Zusatz heraus.",
            .fr: "\(service) est un complément pour Home Assistant et ne sert à rien sans lui. Ajoutez le hub ou retirez ce complément.",
            .es: "\(service) es un complemento de Home Assistant y no hace nada sin él. Añada el hub o quite este complemento.",
            .ru: "\(service) — дополнение к Home Assistant и без него ничего не делает. Добавьте хаб или снимите это дополнение.",
            .uk: "\(service) — доповнення до Home Assistant і без нього нічого не робить. Додайте хаб або зніміть це доповнення.",
            .it: "\(service) è un componente aggiuntivo di Home Assistant e senza di esso non fa nulla. Aggiungi l'hub o togli questo componente.",
            .ja: "\(service) は Home Assistant の追加機能で、単体では何もしません。ハブを追加するか、この追加機能を外してください。",
            .zh: "\(service) 是 Home Assistant 的附加组件，没有它就毫无作用。请添加中枢，或取消这个组件。"
        ])
    }

    static func errZigbeeNeedsAStick(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Zigbee2MQTT talks to a Zigbee stick plugged into the machine, and no stick was named. Enter its path under Home Assistant's settings, or take Zigbee2MQTT off.",
            .de: "Zigbee2MQTT spricht mit einem Zigbee-Stick am Rechner, und es wurde keiner angegeben. Tragen Sie dessen Pfad in den Einstellungen von Home Assistant ein oder nehmen Sie Zigbee2MQTT heraus.",
            .fr: "Zigbee2MQTT dialogue avec une clé Zigbee branchée sur la machine, et aucune n'a été indiquée. Saisissez son chemin dans les réglages de Home Assistant, ou retirez Zigbee2MQTT.",
            .es: "Zigbee2MQTT habla con un adaptador Zigbee conectado a la máquina y no se indicó ninguno. Escriba su ruta en los ajustes de Home Assistant o quite Zigbee2MQTT.",
            .ru: "Zigbee2MQTT работает через Zigbee-стик, воткнутый в машину, а стик не указан. Впишите его путь в настройках Home Assistant или снимите Zigbee2MQTT.",
            .uk: "Zigbee2MQTT працює через Zigbee-стік, увімкнений у машину, а стік не вказано. Впишіть його шлях у налаштуваннях Home Assistant або зніміть Zigbee2MQTT.",
            .it: "Zigbee2MQTT parla con una chiavetta Zigbee collegata alla macchina e non ne è stata indicata nessuna. Inserisci il suo percorso nelle impostazioni di Home Assistant o togli Zigbee2MQTT.",
            .ja: "Zigbee2MQTT はマシンに挿した Zigbee スティックと通信しますが、スティックが指定されていません。Home Assistant の設定でパスを入力するか、Zigbee2MQTT を外してください。",
            .zh: "Zigbee2MQTT 通过插在机器上的 Zigbee 适配器工作，但没有指定适配器。请在 Home Assistant 的设置中填写其路径，或取消 Zigbee2MQTT。"
        ])
    }

    static func errStickIsNotADevicePath(_ l: AppLanguage, value: String) -> String {
        l.pick([
            .en: "\(value) is not a device on the server. A Zigbee or Z-Wave stick is named by its path, which starts with /dev/ — for example /dev/serial/by-id/usb-…, the name that survives a reboot.",
            .de: "\(value) ist kein Gerät auf dem Server. Ein Zigbee- oder Z-Wave-Stick wird über seinen Pfad benannt, der mit /dev/ beginnt — zum Beispiel /dev/serial/by-id/usb-…, der Name, der einen Neustart übersteht.",
            .fr: "\(value) n'est pas un périphérique du serveur. Une clé Zigbee ou Z-Wave se désigne par son chemin, qui commence par /dev/ — par exemple /dev/serial/by-id/usb-…, le nom qui survit à un redémarrage.",
            .es: "\(value) no es un dispositivo del servidor. Un adaptador Zigbee o Z-Wave se nombra por su ruta, que empieza por /dev/ — por ejemplo /dev/serial/by-id/usb-…, el nombre que sobrevive a un reinicio.",
            .ru: "\(value) — не устройство на сервере. Zigbee- или Z-Wave-стик называется своим путём, который начинается с /dev/ — например /dev/serial/by-id/usb-…, такое имя переживает перезагрузку.",
            .uk: "\(value) — не пристрій на сервері. Zigbee- або Z-Wave-стік називається своїм шляхом, що починається з /dev/ — наприклад /dev/serial/by-id/usb-…, таке ім'я переживає перезавантаження.",
            .it: "\(value) non è un dispositivo del server. Una chiavetta Zigbee o Z-Wave si indica con il suo percorso, che inizia con /dev/ — per esempio /dev/serial/by-id/usb-…, il nome che sopravvive a un riavvio.",
            .ja: "\(value) はサーバー上のデバイスではありません。Zigbee や Z-Wave のスティックは /dev/ で始まるパスで指定します — 例えば /dev/serial/by-id/usb-… のように、再起動後も変わらない名前です。",
            .zh: "\(value) 不是服务器上的设备。Zigbee 或 Z-Wave 适配器用以 /dev/ 开头的路径指定 — 例如 /dev/serial/by-id/usb-…，这种名字在重启后依然有效。"
        ])
    }

    static func errTunnelCarriesOnlyWeb(_ l: AppLanguage, service: String) -> String {
        l.pick([
            .en: "\(service) needs a port of its own that a Cloudflare Tunnel cannot carry — the tunnel delivers web traffic only. Use a deployment with a real inbound address for it.",
            .de: "\(service) benötigt einen eigenen Port, den ein Cloudflare Tunnel nicht transportieren kann — der Tunnel liefert nur Web-Verkehr. Verwenden Sie dafür ein Deployment mit einer echten eingehenden Adresse.",
            .fr: "\(service) nécessite un port propre qu’un tunnel Cloudflare ne peut pas transporter — le tunnel n’achemine que le trafic web. Utilisez pour cela un déploiement avec une véritable adresse entrante.",
            .es: "\(service) necesita un puerto propio que un túnel de Cloudflare no puede transportar: el túnel solo entrega tráfico web. Usa para ello un despliegue con una dirección entrante real.",
            .ru: "\(service) требует собственный порт, который туннель Cloudflare пронести не может — туннель доставляет только веб-трафик. Для него нужно развёртывание с настоящим входящим адресом.",
            .uk: "\(service) потребує власний порт, який тунель Cloudflare пронести не може — тунель доставляє лише вебтрафік. Для нього потрібне розгортання зі справжньою вхідною адресою.",
            .it: "\(service) richiede una porta propria che un tunnel Cloudflare non può trasportare: il tunnel consegna solo traffico web. Usa per questo un deployment con un vero indirizzo in ingresso.",
            .ja: "\(service) は Cloudflare トンネルが運べない専用ポートを必要とします。トンネルが届けるのは Web トラフィックだけです。実際の受信アドレスを持つデプロイをお使いください。",
            .zh: "\(service) 需要 Cloudflare 隧道无法承载的独立端口——隧道只传递 Web 流量。请为它使用具有真实入站地址的部署。"
        ])
    }

    // MARK: - DNS: step-by-step instructions

    static func dnsFormHeader(_ l: AppLanguage) -> String {
        l.pick([
            .en: "WHAT TO ADD — one block below = one record in your provider's form",
            .de: "WAS EINZUTRAGEN IST — ein Block unten = ein Eintrag im Formular Ihres Anbieters",
            .fr: "CE QU'IL FAUT AJOUTER — un bloc ci-dessous = un enregistrement dans le formulaire de votre fournisseur",
            .es: "QUÉ AÑADIR: cada bloque de abajo = un registro en el formulario de tu proveedor",
            .ru: "ЧТО ДОБАВИТЬ — один блок ниже = одна запись в форме вашего регистратора",
            .uk: "ЩО ДОДАТИ — один блок нижче = один запис у формі вашого реєстратора",
            .it: "COSA AGGIUNGERE — ogni blocco sotto = un record nel modulo del tuo provider",
            .ja: "追加する内容 — 下の1ブロック = 事業者のフォームでの1レコード",
            .zh: "需要添加的内容 — 下面每个区块 = 服务商表单中的一条记录"
        ])
    }

    static func dnsFieldType(_ l: AppLanguage) -> String {
        l.pick([.en: "Type", .de: "Typ", .fr: "Type", .es: "Tipo", .ru: "Тип", .uk: "Тип",
                .it: "Tipo", .ja: "種類", .zh: "类型"])
    }

    static func dnsFieldName(_ l: AppLanguage) -> String {
        l.pick([.en: "Name", .de: "Name", .fr: "Nom", .es: "Nombre", .ru: "Имя", .uk: "Ім'я",
                .it: "Nome", .ja: "名前", .zh: "名称"])
    }

    static func dnsFieldValue(_ l: AppLanguage) -> String {
        l.pick([.en: "Value", .de: "Wert", .fr: "Valeur", .es: "Valor", .ru: "Значение",
                .uk: "Значення", .it: "Valore", .ja: "値", .zh: "值"])
    }

    static func dnsFieldPriority(_ l: AppLanguage) -> String {
        l.pick([.en: "Priority", .de: "Priorität", .fr: "Priorité", .es: "Prioridad",
                .ru: "Приоритет", .uk: "Пріоритет", .it: "Priorità", .ja: "優先度", .zh: "优先级"])
    }

    static func dnsFieldTTL(_ l: AppLanguage) -> String {
        l.pick([.en: "TTL", .de: "TTL", .fr: "TTL", .es: "TTL", .ru: "TTL", .uk: "TTL",
                .it: "TTL", .ja: "TTL", .zh: "TTL"])
    }

    static func dnsTTLAuto(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Auto (or 3600)", .de: "Auto (oder 3600)", .fr: "Auto (ou 3600)",
            .es: "Auto (o 3600)", .ru: "Авто (или 3600)", .uk: "Авто (або 3600)",
            .it: "Auto (o 3600)", .ja: "自動（または 3600）", .zh: "自动（或 3600）"
        ])
    }

    static func dnsNameHint(_ l: AppLanguage, label: String, full: String) -> String {
        l.pick([
            .en: "most panels want just \(label) — some want the full \(full)",
            .de: "die meisten Panels wollen nur \(label) — manche das vollständige \(full)",
            .fr: "la plupart des panneaux attendent seulement \(label) — certains le nom complet \(full)",
            .es: "la mayoría de los paneles piden solo \(label); algunos, el nombre completo \(full)",
            .ru: "большинство панелей ждут просто \(label) — некоторые полное \(full)",
            .uk: "більшість панелей чекають просто \(label) — деякі повне \(full)",
            .it: "la maggior parte dei pannelli vuole solo \(label) — alcuni il nome completo \(full)",
            .ja: "多くの管理画面では \(label) だけ、一部では完全な \(full) を入力します",
            .zh: "多数面板只需填 \(label)，少数需要完整的 \(full)"
        ])
    }

    static func dnsRootNameHint(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "the domain itself — type @ (some panels want \(domain))",
            .de: "die Domain selbst — geben Sie @ ein (manche Panels wollen \(domain))",
            .fr: "le domaine lui-même — saisissez @ (certains panneaux veulent \(domain))",
            .es: "el dominio en sí: escribe @ (algunos paneles piden \(domain))",
            .ru: "сам домен — впишите @ (некоторые панели хотят \(domain))",
            .uk: "сам домен — впишіть @ (деякі панелі хочуть \(domain))",
            .it: "il dominio stesso — scrivi @ (alcuni pannelli vogliono \(domain))",
            .ja: "ドメイン自体 — @ と入力します（一部の画面では \(domain)）",
            .zh: "域名本身 — 填 @（部分面板需要 \(domain)）"
        ])
    }

    static func dnsCloudflareProxyWarning(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Cloudflare: set Proxy status to \"DNS only\" (grey cloud) for EVERY record here. The orange cloud breaks mail and the VPN.",
            .de: "Cloudflare: Setzen Sie den Proxy-Status bei JEDEM Eintrag hier auf „DNS only“ (graue Wolke). Die orange Wolke zerstört E-Mail und VPN.",
            .fr: "Cloudflare : mettez le statut proxy sur « DNS only » (nuage gris) pour CHAQUE enregistrement ici. Le nuage orange casse la messagerie et le VPN.",
            .es: "Cloudflare: pon el estado de proxy en «DNS only» (nube gris) en TODOS estos registros. La nube naranja rompe el correo y la VPN.",
            .ru: "Cloudflare: у КАЖДОЙ записи здесь поставьте Proxy status = «DNS only» (серое облако). Оранжевое облако ломает почту и VPN.",
            .uk: "Cloudflare: у КОЖНОГО запису тут поставте Proxy status = «DNS only» (сіра хмара). Помаранчева хмара ламає пошту та VPN.",
            .it: "Cloudflare: imposta Proxy status su «DNS only» (nuvola grigia) per OGNI record qui. La nuvola arancione rompe la posta e la VPN.",
            .ja: "Cloudflare: ここのすべてのレコードで Proxy status を「DNS only」（灰色の雲）にしてください。オレンジの雲はメールと VPN を壊します。",
            .zh: "Cloudflare：请把这里每一条记录的 Proxy status 设为「DNS only」（灰色云朵）。橙色云朵会破坏邮件和 VPN。"
        ])
    }

    static func dnsImportInstructions(_ l: AppLanguage, zoneFile: String, csvFile: String) -> String {
        l.pick([
            .en: """
            IMPORT INSTEAD OF TYPING
            Cloudflare: DNS → Records → "Import and Export" → "Import DNS records" → upload \(zoneFile).
            Then check every imported record is "DNS only" (grey cloud).
            The same \(zoneFile) works at Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Panels that ask for a spreadsheet instead: use \(csvFile).
            """,
            .de: """
            IMPORTIEREN STATT TIPPEN
            Cloudflare: DNS → Records → „Import and Export“ → „Import DNS records“ → \(zoneFile) hochladen.
            Danach prüfen, dass jeder importierte Eintrag auf „DNS only“ (graue Wolke) steht.
            Dieselbe \(zoneFile) funktioniert bei Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Panels, die eine Tabelle erwarten: \(csvFile) verwenden.
            """,
            .fr: """
            IMPORTER PLUTÔT QUE SAISIR
            Cloudflare : DNS → Records → « Import and Export » → « Import DNS records » → envoyez \(zoneFile).
            Vérifiez ensuite que chaque enregistrement importé est en « DNS only » (nuage gris).
            Le même \(zoneFile) fonctionne chez Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Pour les panneaux qui attendent un tableur : \(csvFile).
            """,
            .es: """
            IMPORTAR EN LUGAR DE ESCRIBIR
            Cloudflare: DNS → Records → «Import and Export» → «Import DNS records» → sube \(zoneFile).
            Después comprueba que cada registro importado esté en «DNS only» (nube gris).
            El mismo \(zoneFile) sirve en Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Paneles que piden una hoja de cálculo: usa \(csvFile).
            """,
            .ru: """
            ИМПОРТ ВМЕСТО РУЧНОГО ВВОДА
            Cloudflare: DNS → Records → «Import and Export» → «Import DNS records» → загрузите \(zoneFile).
            После импорта проверьте, что у каждой записи стоит «DNS only» (серое облако).
            Тот же \(zoneFile) принимают Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Панелям, которым нужна таблица, подойдёт \(csvFile).
            """,
            .uk: """
            ІМПОРТ ЗАМІСТЬ РУЧНОГО ВВЕДЕННЯ
            Cloudflare: DNS → Records → «Import and Export» → «Import DNS records» → завантажте \(zoneFile).
            Після імпорту перевірте, що в кожного запису стоїть «DNS only» (сіра хмара).
            Той самий \(zoneFile) приймають Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Панелям, яким потрібна таблиця, підійде \(csvFile).
            """,
            .it: """
            IMPORTA INVECE DI DIGITARE
            Cloudflare: DNS → Records → «Import and Export» → «Import DNS records» → carica \(zoneFile).
            Poi verifica che ogni record importato sia su «DNS only» (nuvola grigia).
            Lo stesso \(zoneFile) va bene su Route53, Google, Namecheap, GoDaddy, Gandi, Hetzner, deSEC, DNSimple, Porkbun.
            Per i pannelli che chiedono un foglio di calcolo: \(csvFile).
            """,
            .ja: """
            手入力の代わりにインポート
            Cloudflare: DNS → Records →「Import and Export」→「Import DNS records」→ \(zoneFile) をアップロード。
            その後、各レコードが「DNS only」（灰色の雲）になっているか確認してください。
            同じ \(zoneFile) は Route53、Google、Namecheap、GoDaddy、Gandi、Hetzner、deSEC、DNSimple、Porkbun でも使えます。
            表計算形式を求める管理画面には \(csvFile) を使ってください。
            """,
            .zh: """
            用导入代替手动录入
            Cloudflare：DNS → Records →「Import and Export」→「Import DNS records」→ 上传 \(zoneFile)。
            导入后请确认每条记录都是「DNS only」（灰色云朵）。
            同一个 \(zoneFile) 也适用于 Route53、Google、Namecheap、GoDaddy、Gandi、Hetzner、deSEC、DNSimple、Porkbun。
            需要表格的面板请使用 \(csvFile)。
            """
        ])
    }

    static func errDuplicateDomain(_ l: AppLanguage, domain: String) -> String {
        l.pick([
            .en: "The domain \(domain) is listed twice.",
            .de: "Die Domain \(domain) ist doppelt aufgeführt.",
            .fr: "Le domaine \(domain) est indiqué deux fois.",
            .es: "El dominio \(domain) aparece dos veces.",
            .ru: "Домен \(domain) указан дважды.",
            .uk: "Домен \(domain) вказано двічі.",
            .it: "Il dominio \(domain) è indicato due volte.",
            .ja: "ドメイン \(domain) が重複しています。",
            .zh: "域名 \(domain) 重复了。"
        ])
    }

    /// Two services asking for one address
    static func errDuplicateServiceHostname(_ l: AppLanguage, hostname: String) -> String {
        l.pick([
            .en: "Two services are set to answer at \(hostname). One address can only belong to one service — the web server refuses a configuration that names it twice, which would take every site on this server down with it.",
            .de: "Zwei Dienste sollen unter \(hostname) antworten. Eine Adresse kann nur zu einem Dienst gehören — der Webserver verweigert eine Konfiguration, die sie zweimal nennt, und nimmt dabei jede Website auf diesem Server mit.",
            .fr: "Deux services doivent répondre à \(hostname). Une adresse ne peut appartenir qu'à un seul service : le serveur web refuse une configuration qui la nomme deux fois, ce qui emporterait tous les sites de ce serveur.",
            .es: "Dos servicios están configurados para responder en \(hostname). Una dirección solo puede pertenecer a un servicio: el servidor web rechaza una configuración que la nombra dos veces, y se lleva por delante todos los sitios de este servidor.",
            .ru: "Два сервиса настроены отвечать на \(hostname). Один адрес может принадлежать только одному сервису — веб-сервер отказывается от конфигурации, где адрес назван дважды, и уносит с собой все сайты на этом сервере.",
            .uk: "Два сервіси налаштовані відповідати на \(hostname). Одна адреса може належати лише одному сервісу — веб-сервер відмовляється від конфігурації, де адресу названо двічі, і забирає з собою всі сайти на цьому сервері.",
            .it: "Due servizi sono impostati per rispondere su \(hostname). Un indirizzo può appartenere a un solo servizio: il web server rifiuta una configurazione che lo nomina due volte, portandosi dietro ogni sito di questo server.",
            .ja: "2 つのサービスが \(hostname) で応答するよう設定されています。1 つのアドレスは 1 つのサービスにしか属せません。ウェブサーバーは同じ名前を 2 度含む設定を拒否し、このサーバー上のすべてのサイトを巻き添えにします。",
            .zh: "有两个服务都被设置为在 \(hostname) 上应答。一个地址只能属于一个服务——Web 服务器会拒绝重复命名同一地址的配置，并让这台服务器上的所有站点一起失效。"
        ])
    }

    static func errTooManyDomains(_ l: AppLanguage, limit: Int) -> String {
        l.pick([
            .en: "At most \(limit) additional domains are supported.",
            .de: "Es werden höchstens \(limit) zusätzliche Domains unterstützt.",
            .fr: "Au maximum \(limit) domaines supplémentaires sont pris en charge.",
            .es: "Se admiten como máximo \(limit) dominios adicionales.",
            .ru: "Поддерживается не более \(limit) дополнительных доменов.",
            .uk: "Підтримується не більше \(limit) додаткових доменів.",
            .it: "Sono supportati al massimo \(limit) domini aggiuntivi.",
            .ja: "追加ドメインは最大 \(limit) 件までです。",
            .zh: "最多支持 \(limit) 个附加域名。"
        ])
    }

    static func errRequiredMailHostname(_ l: AppLanguage, engine: String, hostname: String) -> String {
        l.pick([
            .en: "With \(engine) the mail hostname must be \(hostname).",
            .de: "Mit \(engine) muss der Mail-Hostname \(hostname) lauten.",
            .fr: "Avec \(engine), le nom d'hôte de messagerie doit être \(hostname).",
            .es: "Con \(engine), el nombre de host de correo debe ser \(hostname).",
            .ru: "С \(engine) имя почтового хоста должно быть \(hostname).",
            .uk: "З \(engine) ім'я поштового хоста має бути \(hostname).",
            .it: "Con \(engine) il nome host di posta deve essere \(hostname).",
            .ja: "\(engine) ではメールホスト名は \(hostname) である必要があります。",
            .zh: "使用 \(engine) 时，邮件主机名必须为 \(hostname)。"
        ])
    }

    static func errInvalidDashboardUser(_ l: AppLanguage, user: String) -> String {
        l.pick([
            .en: "Invalid SSH user name for the dashboard: \"\(user)\".",
            .de: "Ungültiger SSH-Benutzername für das Panel: „\(user)“.",
            .fr: "Nom d'utilisateur SSH du panneau invalide : « \(user) ».",
            .es: "Nombre de usuario SSH del panel no válido: «\(user)».",
            .ru: "Некорректное имя SSH-пользователя панели управления: «\(user)».",
            .uk: "Некоректне ім'я SSH-користувача панелі керування: «\(user)».",
            .it: "Nome utente SSH del pannello non valido: \"\(user)\".",
            .ja: "管理パネルの SSH ユーザー名が正しくありません: 「\(user)」。",
            .zh: "控制面板的 SSH 用户名无效：“\(user)”。"
        ])
    }

    static func errInvalidDashboardKey(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The app's public key must be a single line in ssh-ed25519 format.",
            .de: "Der öffentliche Schlüssel der App muss eine einzelne Zeile im ssh-ed25519-Format sein.",
            .fr: "La clé publique de l'application doit être une seule ligne au format ssh-ed25519.",
            .es: "La clave pública de la aplicación debe ser una sola línea en formato ssh-ed25519.",
            .ru: "Публичный ключ приложения должен быть одной строкой формата ssh-ed25519.",
            .uk: "Публічний ключ застосунку має бути одним рядком формату ssh-ed25519.",
            .it: "La chiave pubblica dell'app deve essere una singola riga in formato ssh-ed25519.",
            .ja: "アプリの公開鍵は ssh-ed25519 形式の 1 行である必要があります。",
            .zh: "应用的公钥必须是 ssh-ed25519 格式的单行文本。"
        ])
    }

    static func errInvalidContainerName(_ l: AppLanguage, name: String) -> String {
        l.pick([
            .en: "Invalid container name: \"\(name)\".",
            .de: "Ungültiger Containername: „\(name)“.",
            .fr: "Nom de conteneur invalide : « \(name) ».",
            .es: "Nombre de contenedor no válido: «\(name)».",
            .ru: "Некорректное имя контейнера: «\(name)».",
            .uk: "Некоректне ім'я контейнера: «\(name)».",
            .it: "Nome del container non valido: \"\(name)\".",
            .ja: "コンテナ名が正しくありません: 「\(name)」。",
            .zh: "容器名称无效：“\(name)”。"
        ])
    }

    static func errInvalidPaths(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Service and backup paths must be absolute, without spaces or special characters.",
            .de: "Dienst- und Backup-Pfade müssen absolut sein, ohne Leer- und Sonderzeichen.",
            .fr: "Les chemins des services et des sauvegardes doivent être absolus, sans espaces ni caractères spéciaux.",
            .es: "Las rutas de servicios y copias de seguridad deben ser absolutas, sin espacios ni caracteres especiales.",
            .ru: "Пути сервисов и бэкапов должны быть абсолютными, без пробелов и спецсимволов.",
            .uk: "Шляхи сервісів і бекапів мають бути абсолютними, без пробілів і спецсимволів.",
            .it: "I percorsi dei servizi e dei backup devono essere assoluti, senza spazi né caratteri speciali.",
            .ja: "サービスとバックアップのパスは、空白や特殊文字を含まない絶対パスである必要があります。",
            .zh: "服务和备份路径必须是绝对路径，不含空格和特殊字符。"
        ])
    }

    static func errMinecraftEULA(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Accept Mojang's End User License Agreement for the Minecraft server before installing — the server refuses to start without it.",
            .de: "Akzeptieren Sie vor der Installation Mojangs Endbenutzer-Lizenzvereinbarung für den Minecraft-Server — ohne sie startet der Server nicht.",
            .fr: "Acceptez le contrat de license utilisateur de Mojang pour le serveur Minecraft avant l'installation — sans lui, le serveur refuse de démarrer.",
            .es: "Acepte el acuerdo de licencia de Mojang para el servidor de Minecraft antes de instalar: sin él, el servidor no arranca.",
            .ru: "Примите лицензионное соглашение Mojang для сервера Minecraft до установки — без него сервер не запускается.",
            .uk: "Прийміть ліцензійну угоду Mojang для сервера Minecraft до встановлення — без неї сервер не запускається.",
            .it: "Accetta il contratto di licenza di Mojang per il server Minecraft prima di installare: senza, il server non si avvia.",
            .ja: "インストール前に Minecraft サーバー用の Mojang エンドユーザー使用許諾契約に同意してください。同意がないとサーバーは起動しません。",
            .zh: "安装前请接受 Mojang 的最终用户许可协议，否则 Minecraft 服务器无法启动。"
        ])
    }

    static func errSingleHostTopology(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The \"single server\" scenario requires exactly one node with the singleHost role.",
            .de: "Das Szenario „ein Server“ erfordert genau einen Knoten mit der Rolle singleHost.",
            .fr: "Le scénario « serveur unique » exige exactement un nœud avec le rôle singleHost.",
            .es: "El escenario «un servidor» requiere exactamente un nodo con el rol singleHost.",
            .ru: "Сценарий «один сервер» требует ровно один узел с ролью singleHost.",
            .uk: "Сценарій «один сервер» вимагає рівно один вузол із роллю singleHost.",
            .it: "Lo scenario \"server singolo\" richiede esattamente un nodo con ruolo singleHost.",
            .ja: "「単一サーバー」シナリオには、singleHost ロールのノードがちょうど 1 つ必要です。",
            .zh: "“单服务器”方案需要恰好一个 singleHost 角色的节点。"
        ])
    }

    static func errSplitTopology(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The \"VPS + home server\" scenario requires two nodes: vpsRelay and homeBackend.",
            .de: "Das Szenario „VPS + Heimserver“ erfordert zwei Knoten: vpsRelay und homeBackend.",
            .fr: "Le scénario « VPS + serveur domestique » exige deux nœuds : vpsRelay et homeBackend.",
            .es: "El escenario «VPS + servidor doméstico» requiere dos nodos: vpsRelay y homeBackend.",
            .ru: "Сценарий «VPS + домашний сервер» требует два узла: vpsRelay и homeBackend.",
            .uk: "Сценарій «VPS + домашній сервер» вимагає два вузли: vpsRelay і homeBackend.",
            .it: "Lo scenario \"VPS + server domestico\" richiede due nodi: vpsRelay e homeBackend.",
            .ja: "「VPS + 自宅サーバー」シナリオには 2 つのノードが必要です: vpsRelay と homeBackend。",
            .zh: "“VPS + 家庭服务器”方案需要两个节点：vpsRelay 和 homeBackend。"
        ])
    }

    static func errWGNotIPv4(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Addresses inside WireGuard must be IPv4.",
            .de: "Adressen innerhalb von WireGuard müssen IPv4 sein.",
            .fr: "Les adresses dans WireGuard doivent être en IPv4.",
            .es: "Las direcciones dentro de WireGuard deben ser IPv4.",
            .ru: "Адреса внутри WireGuard должны быть IPv4.",
            .uk: "Адреси всередині WireGuard мають бути IPv4.",
            .it: "Gli indirizzi all'interno di WireGuard devono essere IPv4.",
            .ja: "WireGuard 内のアドレスは IPv4 である必要があります。",
            .zh: "WireGuard 内的地址必须是 IPv4。"
        ])
    }

    static func errWGSameAddress(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The WireGuard addresses of the VPS and the home server are identical.",
            .de: "Die WireGuard-Adressen von VPS und Heimserver sind identisch.",
            .fr: "Les adresses WireGuard du VPS et du serveur domestique sont identiques.",
            .es: "Las direcciones WireGuard del VPS y del servidor doméstico coinciden.",
            .ru: "WG-адреса VPS и домашнего сервера совпадают.",
            .uk: "WG-адреси VPS і домашнього сервера збігаються.",
            .it: "Gli indirizzi WireGuard del VPS e del server domestico coincidono.",
            .ja: "VPS と自宅サーバーの WireGuard アドレスが同一です。",
            .zh: "VPS 与家庭服务器的 WireGuard 地址相同。"
        ])
    }

    static func errWGSubnet(_ l: AppLanguage) -> String {
        l.pick([
            .en: "The WireGuard addresses must be in the same /24 subnet.",
            .de: "Die WireGuard-Adressen müssen im selben /24-Subnetz liegen.",
            .fr: "Les adresses WireGuard doivent être dans le même sous-réseau /24.",
            .es: "Las direcciones WireGuard deben estar en la misma subred /24.",
            .ru: "WG-адреса должны быть в одной /24-подсети.",
            .uk: "WG-адреси мають бути в одній /24-підмережі.",
            .it: "Gli indirizzi WireGuard devono trovarsi nella stessa sottorete /24.",
            .ja: "WireGuard アドレスは同じ /24 サブネット内にある必要があります。",
            .zh: "WireGuard 地址必须位于同一个 /24 子网内。"
        ])
    }

    static func errInvalidVPNPort(_ l: AppLanguage, port: Int) -> String {
        l.pick([
            .en: "The VPN port \(port) is invalid: use a value between 1 and 65535.",
            .de: "Der VPN-Port \(port) ist ungültig: Verwenden Sie einen Wert zwischen 1 und 65535.",
            .fr: "Le port VPN \(port) est invalide : utilisez une valeur entre 1 et 65535.",
            .es: "El puerto VPN \(port) no es válido: use un valor entre 1 y 65535.",
            .ru: "Порт VPN \(port) некорректен: укажите значение от 1 до 65535.",
            .uk: "Порт VPN \(port) некоректний: вкажіть значення від 1 до 65535.",
            .it: "La porta VPN \(port) non è valida: usa un valore tra 1 e 65535.",
            .ja: "VPN ポート \(port) は無効です。1〜65535 の値を使用してください。",
            .zh: "VPN 端口 \(port) 无效：请使用 1 到 65535 之间的值。"
        ])
    }

    static func errVPNPortCollidesWithTunnel(_ l: AppLanguage, port: Int) -> String {
        l.pick([
            .en: "In scenario B the relay tunnel already uses UDP port \(port) on the VPS — pick a different port for the WireGuard VPN service (e.g. \(port + 1)).",
            .de: "In Szenario B nutzt der Relay-Tunnel bereits UDP-Port \(port) auf dem VPS — wählen Sie für den WireGuard-VPN-Dienst einen anderen Port (z. B. \(port + 1)).",
            .fr: "Dans le scénario B, le tunnel relais utilise déjà le port UDP \(port) sur le VPS — choisissez un autre port pour le service VPN WireGuard (p. ex. \(port + 1)).",
            .es: "En el escenario B, el túnel de relé ya usa el puerto UDP \(port) en el VPS — elija otro puerto para el servicio VPN WireGuard (p. ej. \(port + 1)).",
            .ru: "В сценарии B релейный туннель уже занимает UDP-порт \(port) на VPS — выберите для сервиса WireGuard VPN другой порт (например, \(port + 1)).",
            .uk: "У сценарії B релейний тунель уже займає UDP-порт \(port) на VPS — оберіть для сервісу WireGuard VPN інший порт (наприклад, \(port + 1)).",
            .it: "Nello scenario B il tunnel relay usa già la porta UDP \(port) sul VPS — scegli un'altra porta per il servizio VPN WireGuard (ad es. \(port + 1)).",
            .ja: "シナリオ B ではリレー・トンネルが VPS の UDP ポート \(port) を既に使用しています。WireGuard VPN サービスには別のポートを選んでください（例: \(port + 1)）。",
            .zh: "在方案 B 中，中继隧道已占用 VPS 的 UDP 端口 \(port) — 请为 WireGuard VPN 服务选择其他端口（例如 \(port + 1)）。"
        ])
    }

    static func errVPNPortCollidesWithService(_ l: AppLanguage, port: Int) -> String {
        l.pick([
            .en: "Two VPN services are set to the same UDP port \(port) — give each its own port.",
            .de: "Zwei VPN-Dienste sind auf denselben UDP-Port \(port) eingestellt — geben Sie jedem einen eigenen Port.",
            .fr: "Deux services VPN utilisent le même port UDP \(port) — attribuez à chacun son propre port.",
            .es: "Dos servicios VPN usan el mismo puerto UDP \(port) — asigne a cada uno su propio puerto.",
            .ru: "Два VPN-сервиса используют один UDP-порт \(port) — задайте каждому свой порт.",
            .uk: "Два VPN-сервіси використовують один UDP-порт \(port) — задайте кожному свій порт.",
            .it: "Due servizi VPN usano la stessa porta UDP \(port) — assegna a ciascuno una porta diversa.",
            .ja: "2 つの VPN サービスが同じ UDP ポート \(port) を使用しています。それぞれに別のポートを割り当ててください。",
            .zh: "两个 VPN 服务使用了相同的 UDP 端口 \(port) — 请为每个服务分配不同的端口。"
        ])
    }

    static func errServicePortInUse(_ l: AppLanguage, port: Int, owner: String) -> String {
        l.pick([
            .en: "TCP port \(port) is already used by \(owner) — pick a different port for this service.",
            .de: "TCP-Port \(port) wird bereits von \(owner) verwendet — wählen Sie für diesen Dienst einen anderen Port.",
            .fr: "Le port TCP \(port) est déjà utilisé par \(owner) — choisissez un autre port pour ce service.",
            .es: "El puerto TCP \(port) ya lo usa \(owner) — elija otro puerto para este servicio.",
            .ru: "TCP-порт \(port) уже занят (\(owner)) — выберите для этого сервиса другой порт.",
            .uk: "TCP-порт \(port) уже зайнятий (\(owner)) — оберіть для цього сервісу інший порт.",
            .it: "La porta TCP \(port) è già usata da \(owner) — scegli un'altra porta per questo servizio.",
            .ja: "TCP ポート \(port) は既に \(owner) が使用しています。このサービスには別のポートを選んでください。",
            .zh: "TCP 端口 \(port) 已被 \(owner) 占用 — 请为该服务选择其他端口。"
        ])
    }

    static func errSplitAddressesMissing(_ l: AppLanguage) -> String {
        l.pick([
            .en: "Scenario B is missing the VPS/home node addresses.",
            .de: "Für Szenario B fehlen die Adressen des VPS-/Heimknotens.",
            .fr: "Le scénario B manque des adresses du VPS/du nœud domestique.",
            .es: "Al escenario B le faltan las direcciones del VPS/nodo doméstico.",
            .ru: "Сценарию B не хватает адресов VPS/домашнего узла.",
            .uk: "Сценарію B бракує адрес VPS/домашнього вузла.",
            .it: "Nello scenario B mancano gli indirizzi del VPS/nodo domestico.",
            .ja: "シナリオ B に VPS/ホームノードのアドレスが不足しています。",
            .zh: "方案 B 缺少 VPS/家庭节点的地址。"
        ])
    }
}

package com.skaymer.gryonixnexus.catalog.services

import com.skaymer.gryonixnexus.catalog.SH
import com.skaymer.gryonixnexus.catalog.embedding

internal object VPNPanelAssets {
    val dockerfile: String = """
        FROM python:3.12-slim
        RUN apt-get update && apt-get install -y --no-install-recommends \
            wireguard-tools iproute2 iptables qrencode ca-certificates \
            && rm -rf /var/lib/apt/lists/*
        RUN pip install --no-cache-dir flask==3.0.3
        COPY app.py /app/app.py
        COPY index.html /app/index.html
        COPY login.html /app/login.html
        COPY reset.html /app/reset.html
        WORKDIR /app
        CMD ["python", "app.py"]
        """.trimIndent()

    val neutralCSS: String = """
        :root{--bg:#f6f6f7;--sf:#ffffff;--sf2:#fafafb;--bd:#e3e3e6;--tx:#1d1d1f;--t2:#6b6b70;--inv:#ffffff;--btn:#1d1d1f;--bad:#b42318;--ok:#2f6f43;--font:-apple-system,BlinkMacSystemFont,system-ui,"Segoe UI",Roboto,Inter,sans-serif}
        @media(prefers-color-scheme:dark){:root{--bg:#0d0d0f;--sf:#161618;--sf2:#1c1c1f;--bd:#2c2c31;--tx:#ededf0;--t2:#9a9aa1;--inv:#0d0d0f;--btn:#ededf0;--bad:#f97066;--ok:#75c99a}}
        :root[data-theme=light]{--bg:#f6f6f7;--sf:#ffffff;--sf2:#fafafb;--bd:#e3e3e6;--tx:#1d1d1f;--t2:#6b6b70;--inv:#ffffff;--btn:#1d1d1f;--bad:#b42318;--ok:#2f6f43}
        :root[data-theme=dark]{--bg:#0d0d0f;--sf:#161618;--sf2:#1c1c1f;--bd:#2c2c31;--tx:#ededf0;--t2:#9a9aa1;--inv:#0d0d0f;--btn:#ededf0;--bad:#f97066;--ok:#75c99a}
        *{box-sizing:border-box}
        body{margin:0;font-family:var(--font);color:var(--tx);background:var(--bg);min-height:100vh;-webkit-font-smoothing:antialiased;font-size:14px}
        h1{font-size:17px;font-weight:600;letter-spacing:-.015em;margin:0}
        /* Wordmark: "Gryonix" light, "VPN" heavy — one lockup, no pictogram. The
           header used to carry a lone geometric glyph in a filled square, which
           read as a placeholder rather than a logo. */
        .wm{display:inline-flex;align-items:baseline;letter-spacing:-.015em;white-space:nowrap}
        .wm i{font-style:normal;font-weight:450;color:var(--t2)}
        .wm b{font-weight:680;color:var(--tx);letter-spacing:-.02em}
        .tg{width:36px;height:36px;border-radius:50%;display:grid;place-items:center;cursor:pointer;background:var(--sf);border:1px solid var(--bd);color:var(--t2);flex:none}
        .tg:hover{color:var(--tx);background:var(--sf2);border-color:var(--t2)}
        .card{background:var(--sf);border:1px solid var(--bd);border-radius:12px;margin-bottom:22px;overflow:hidden}
        .field{width:100%;font:inherit;font-size:14px;padding:11px 13px;border-radius:9px;margin-bottom:14px;background:var(--sf);border:1px solid var(--bd);color:var(--tx)}
        .field:focus{outline:none;border-color:var(--tx)}
        .btn{width:100%;font:inherit;font-size:14px;font-weight:560;padding:12px;border-radius:9px;cursor:pointer;border:1px solid var(--btn);background:var(--btn);color:var(--inv)}
        .btn:disabled{opacity:.5}
        .btn.g{background:var(--sf);border-color:var(--bd);color:var(--tx);margin-top:10px}
        .btn.g:hover{background:var(--sf2)}
        /* Round icon buttons. They were 28px squares with a text glyph inside —
           the "squares" complaint — so they are circles now, sized for a real tap
           target, and the QR one is filled because it is the primary action of a
           client row. */
        .mini{width:34px;height:34px;border-radius:50%;display:grid;place-items:center;cursor:pointer;color:var(--t2);background:var(--sf);border:1px solid var(--bd);text-decoration:none;flex:none;transition:background .12s,color .12s,border-color .12s}
        .mini:hover{color:var(--tx);background:var(--sf2);border-color:var(--t2)}
        .mini.pri{background:var(--btn);border-color:var(--btn);color:var(--inv)}
        .mini.pri:hover{opacity:.85;background:var(--btn);color:var(--inv)}
        .mini.dgr:hover{color:var(--bad);border-color:var(--bad)}
        .mini svg,.tg svg{width:16px;height:16px;display:block}
        .err{color:var(--bad);font-size:12.5px;min-height:17px;margin:4px 0 10px}
        .scrim{position:fixed;inset:0;z-index:60;display:none;place-items:center;padding:20px;background:rgba(0,0,0,.45)}
        .scrim.show{display:grid}
        .sheet{width:100%;max-width:400px;background:var(--sf);border:1px solid var(--bd);border-radius:16px;padding:26px;text-align:left}
        .sheet h2{margin:0 0 18px;font-size:16px;font-weight:600}
        .conf{font-family:ui-monospace,Menlo,monospace;font-size:11.5px;background:var(--sf2);border:1px solid var(--bd);border-radius:9px;padding:13px;color:var(--t2);white-space:pre-wrap;word-break:break-all;max-height:130px;overflow:auto;margin-bottom:16px}
        """.trimIndent()

    val iconsJS: String = """
        var ICON={
        qr:'<path d="M3 3h5v5H3zM3 11h5v5H3zM11 3h5v5h-5z"/><path d="M11 11h2v2h-2zM14 14h2v2h-2zM11 15.5h1M15 11h1"/>',
        dl:'<path d="M9.5 3v8m0 0 3.2-3.2M9.5 11 6.3 7.8"/><path d="M3.5 12.5v2a1.5 1.5 0 0 0 1.5 1.5h9a1.5 1.5 0 0 0 1.5-1.5v-2"/>',
        trash:'<path d="M3.5 5.5h12M8 5.5V4a1 1 0 0 1 1-1h1a1 1 0 0 1 1 1v1.5"/><path d="M5 5.5 5.7 15a1 1 0 0 0 1 .9h5.6a1 1 0 0 0 1-.9L14 5.5"/><path d="M8 8.5v4.5M11 8.5v4.5"/>',
        pencil:'<path d="M12.6 3.4a1.6 1.6 0 0 1 2.3 2.3L6.6 14 3.5 15l1-3.1z"/><path d="M11.2 4.8 13.5 7.1"/>',
        plus:'<path d="M9.5 4.5v10M4.5 9.5h10"/>',
        exit:'<path d="M7 15.5H4.5A1.5 1.5 0 0 1 3 14V5a1.5 1.5 0 0 1 1.5-1.5H7"/><path d="M11.5 12.5 15 9.5l-3.5-3"/><path d="M15 9.5H6.5"/>',
        theme:'<circle cx="9.5" cy="9.5" r="6"/><path d="M9.5 3.5a6 6 0 0 1 0 12z" fill="currentColor" stroke="none"/>'
        };
        // <svg> wrapper shared by every icon: no fill, 1.5px round strokes.
        function ic(n){return '<svg viewBox="0 0 19 19" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'+(ICON[n]||'')+'</svg>'}
        // Fills every [data-ic] placeholder in the static markup.
        function icons(){document.querySelectorAll('[data-ic]').forEach(function(e){e.innerHTML=ic(e.getAttribute('data-ic'))})}
        """.trimIndent()

    val i18nJS: String = """
        var I18N={
        en:{services:"VPN services",loading:"Loading…",empty:"No VPN services installed.",running:"Running",add:"Add client",newc:"New client",nameph:"Device name — e.g. iPhone",create:"Create",cancel:"Cancel",close:"Close",download:"Download",signout:"Sign out",removeq:"Remove this client?",soon:"Client management for this protocol is coming soon. Use the details from the setup report for now.",reqfail:"Request failed.",neterr:"Network error.",protected:"protected",signin:"Sign in",signingin:"Signing in…",user:"Username",pass:"Password",subtitle:"Sign in to manage your VPN",wrong:"Wrong username or password.",toomany:"Too many attempts. Please wait a few minutes.",accounts:"Accounts",adduser:"Add account",newuser:"New account",removeuserq:"Remove this account?",rsuper:"Main administrator",radmin:"Administrator",ruser:"User",forgot:"Forgot your password?",entername:"Enter your username first.",resetsent:"If that account has an e-mail address, a reset link is on its way.",newpass:"Choose a new password",passagain:"Repeat the password",nomatch:"The passwords do not match.",tooshort:"At least 8 characters, please.",save:"Save",email:"E-mail",emailsetup:"Outgoing mail",smtphost:"SMTP server",smtpport:"Port",sender:"Sender address",sendtest:"Send a test",testsent:"Test message sent.",notset:"Not configured",nosmtp:"No server set",pickbox:"Pick a mailbox…",nomailboxes:"No mailboxes found. Create one in mailcow, or fill in an external SMTP server below.",wgonly:"Admin panels (mail, cloud, photos, vault) open only over WireGuard. This protocol is for general internet access."},
        ru:{services:"VPN-сервисы",loading:"Загрузка…",empty:"VPN-сервисы не установлены.",running:"Работает",add:"Добавить клиента",newc:"Новый клиент",nameph:"Имя устройства — напр. iPhone",create:"Создать",cancel:"Отмена",close:"Закрыть",download:"Скачать",signout:"Выйти",removeq:"Удалить этого клиента?",soon:"Управление клиентами для этого протокола скоро появится. Пока используйте данные из отчёта установки.",reqfail:"Не удалось выполнить запрос.",neterr:"Ошибка сети.",protected:"защищено",signin:"Войти",signingin:"Вход…",user:"Имя пользователя",pass:"Пароль",subtitle:"Войдите, чтобы управлять VPN",wrong:"Неверное имя пользователя или пароль.",toomany:"Слишком много попыток. Подождите несколько минут.",accounts:"Учётные записи",adduser:"Добавить пользователя",newuser:"Новый пользователь",removeuserq:"Удалить эту учётную запись?",rsuper:"Главный администратор",radmin:"Администратор",ruser:"Пользователь",forgot:"Забыли пароль?",entername:"Сначала введите имя пользователя.",resetsent:"Если у этой учётной записи есть адрес почты, ссылка для сброса уже отправлена.",newpass:"Придумайте новый пароль",passagain:"Повторите пароль",nomatch:"Пароли не совпадают.",tooshort:"Минимум 8 символов.",save:"Сохранить",email:"Почта",emailsetup:"Исходящая почта",smtphost:"SMTP-сервер",smtpport:"Порт",sender:"Адрес отправителя",sendtest:"Отправить тест",testsent:"Тестовое письмо отправлено.",notset:"Не настроено",nosmtp:"Сервер не задан",pickbox:"Выберите ящик…",nomailboxes:"Ящики не найдены. Создайте ящик в mailcow или укажите внешний SMTP-сервер ниже.",wgonly:"Админ-панели (почта, облако, фото, vault) открываются только через WireGuard. Этот протокол — для обычного доступа в интернет."},
        uk:{services:"VPN-сервіси",loading:"Завантаження…",empty:"VPN-сервіси не встановлені.",running:"Працює",add:"Додати клієнта",newc:"Новий клієнт",nameph:"Назва пристрою — напр. iPhone",create:"Створити",cancel:"Скасувати",close:"Закрити",download:"Завантажити",signout:"Вийти",removeq:"Видалити цього клієнта?",soon:"Керування клієнтами для цього протоколу скоро з’явиться. Поки що скористайтеся даними зі звіту встановлення.",reqfail:"Не вдалося виконати запит.",neterr:"Помилка мережі.",protected:"захищено",signin:"Увійти",signingin:"Вхід…",user:"Ім’я користувача",pass:"Пароль",subtitle:"Увійдіть, щоб керувати VPN",wrong:"Невірне ім’я користувача або пароль.",toomany:"Забагато спроб. Зачекайте кілька хвилин.",accounts:"Облікові записи",adduser:"Додати користувача",newuser:"Новий користувач",removeuserq:"Видалити цей обліковий запис?",rsuper:"Головний адміністратор",radmin:"Адміністратор",ruser:"Користувач",forgot:"Забули пароль?",entername:"Спочатку введіть ім’я користувача.",resetsent:"Якщо в цього облікового запису є адреса пошти, посилання для скидання вже надіслано.",newpass:"Придумайте новий пароль",passagain:"Повторіть пароль",nomatch:"Паролі не збігаються.",tooshort:"Щонайменше 8 символів.",save:"Зберегти",email:"Пошта",emailsetup:"Вихідна пошта",smtphost:"SMTP-сервер",smtpport:"Порт",sender:"Адреса відправника",sendtest:"Надіслати тест",testsent:"Тестовий лист надіслано.",notset:"Не налаштовано",nosmtp:"Сервер не задано",pickbox:"Оберіть скриньку…",nomailboxes:"Скриньок не знайдено. Створіть скриньку в mailcow або вкажіть зовнішній SMTP-сервер нижче.",wgonly:"Адмін-панелі (пошта, хмара, фото, vault) відкриваються лише через WireGuard. Цей протокол — для звичайного доступу до інтернету."},
        de:{services:"VPN-Dienste",loading:"Wird geladen…",empty:"Keine VPN-Dienste installiert.",running:"Aktiv",add:"Client hinzufügen",newc:"Neuer Client",nameph:"Gerätename — z. B. iPhone",create:"Erstellen",cancel:"Abbrechen",close:"Schließen",download:"Herunterladen",signout:"Abmelden",removeq:"Diesen Client entfernen?",soon:"Die Client-Verwaltung für dieses Protokoll kommt bald. Nutzen Sie vorerst die Angaben aus dem Installationsbericht.",reqfail:"Anfrage fehlgeschlagen.",neterr:"Netzwerkfehler.",protected:"geschützt",signin:"Anmelden",signingin:"Anmeldung…",user:"Benutzername",pass:"Passwort",subtitle:"Melden Sie sich an, um Ihr VPN zu verwalten",wrong:"Falscher Benutzername oder Passwort.",toomany:"Zu viele Versuche. Bitte warten Sie einige Minuten.",accounts:"Konten",adduser:"Konto hinzufügen",newuser:"Neues Konto",removeuserq:"Dieses Konto entfernen?",rsuper:"Hauptadministrator",radmin:"Administrator",ruser:"Benutzer",forgot:"Passwort vergessen?",entername:"Bitte zuerst den Benutzernamen eingeben.",resetsent:"Falls für dieses Konto eine E-Mail-Adresse hinterlegt ist, ist der Link unterwegs.",newpass:"Neues Passwort wählen",passagain:"Passwort wiederholen",nomatch:"Die Passwörter stimmen nicht überein.",tooshort:"Mindestens 8 Zeichen.",save:"Speichern",email:"E-Mail",emailsetup:"Ausgehende E-Mail",smtphost:"SMTP-Server",smtpport:"Port",sender:"Absenderadresse",sendtest:"Test senden",testsent:"Testnachricht gesendet.",notset:"Nicht eingerichtet",nosmtp:"Kein Server gesetzt",pickbox:"Postfach wählen…",nomailboxes:"Keine Postfächer gefunden. Legen Sie eines in mailcow an oder tragen Sie unten einen externen SMTP-Server ein.",wgonly:"Admin-Oberflächen (Mail, Cloud, Fotos, Vault) lassen sich nur über WireGuard öffnen. Dieses Protokoll dient dem allgemeinen Internetzugang."},
        es:{services:"Servicios VPN",loading:"Cargando…",empty:"No hay servicios VPN instalados.",running:"En ejecución",add:"Añadir cliente",newc:"Nuevo cliente",nameph:"Nombre del dispositivo — p. ej. iPhone",create:"Crear",cancel:"Cancelar",close:"Cerrar",download:"Descargar",signout:"Cerrar sesión",removeq:"¿Eliminar este cliente?",soon:"La gestión de clientes para este protocolo llegará pronto. Por ahora usa los datos del informe de instalación.",reqfail:"Error en la solicitud.",neterr:"Error de red.",protected:"protegido",signin:"Iniciar sesión",signingin:"Iniciando sesión…",user:"Usuario",pass:"Contraseña",subtitle:"Inicia sesión para gestionar tu VPN",wrong:"Usuario o contraseña incorrectos.",toomany:"Demasiados intentos. Espera unos minutos.",accounts:"Cuentas",adduser:"Añadir cuenta",newuser:"Nueva cuenta",removeuserq:"¿Eliminar esta cuenta?",rsuper:"Administrador principal",radmin:"Administrador",ruser:"Usuario",forgot:"¿Olvidaste tu contraseña?",entername:"Introduce primero tu usuario.",resetsent:"Si esa cuenta tiene correo, el enlace ya va en camino.",newpass:"Elige una contraseña nueva",passagain:"Repite la contraseña",nomatch:"Las contraseñas no coinciden.",tooshort:"Mínimo 8 caracteres.",save:"Guardar",email:"Correo",emailsetup:"Correo saliente",smtphost:"Servidor SMTP",smtpport:"Puerto",sender:"Dirección del remitente",sendtest:"Enviar una prueba",testsent:"Mensaje de prueba enviado.",notset:"Sin configurar",nosmtp:"Sin servidor",pickbox:"Elige un buzón…",nomailboxes:"No se encontraron buzones. Crea uno en mailcow o indica abajo un servidor SMTP externo.",wgonly:"Los paneles de administración (correo, nube, fotos, vault) solo se abren a través de WireGuard. Este protocolo es para el acceso general a Internet."},
        fr:{services:"Services VPN",loading:"Chargement…",empty:"Aucun service VPN installé.",running:"Actif",add:"Ajouter un client",newc:"Nouveau client",nameph:"Nom de l’appareil — p. ex. iPhone",create:"Créer",cancel:"Annuler",close:"Fermer",download:"Télécharger",signout:"Se déconnecter",removeq:"Supprimer ce client ?",soon:"La gestion des clients pour ce protocole arrive bientôt. Utilisez pour l’instant les informations du rapport d’installation.",reqfail:"Échec de la requête.",neterr:"Erreur réseau.",protected:"protégé",signin:"Se connecter",signingin:"Connexion…",user:"Nom d’utilisateur",pass:"Mot de passe",subtitle:"Connectez-vous pour gérer votre VPN",wrong:"Nom d’utilisateur ou mot de passe incorrect.",toomany:"Trop de tentatives. Veuillez patienter quelques minutes.",accounts:"Comptes",adduser:"Ajouter un compte",newuser:"Nouveau compte",removeuserq:"Supprimer ce compte ?",rsuper:"Administrateur principal",radmin:"Administrateur",ruser:"Utilisateur",forgot:"Mot de passe oublié ?",entername:"Saisissez d’abord votre nom d’utilisateur.",resetsent:"Si ce compte a une adresse e-mail, le lien est en route.",newpass:"Choisissez un nouveau mot de passe",passagain:"Répétez le mot de passe",nomatch:"Les mots de passe ne correspondent pas.",tooshort:"8 caractères minimum.",save:"Enregistrer",email:"E-mail",emailsetup:"Courrier sortant",smtphost:"Serveur SMTP",smtpport:"Port",sender:"Adresse d’expéditeur",sendtest:"Envoyer un test",testsent:"Message de test envoyé.",notset:"Non configuré",nosmtp:"Aucun serveur",pickbox:"Choisir une boîte…",nomailboxes:"Aucune boîte trouvée. Créez-en une dans mailcow ou renseignez un serveur SMTP externe ci-dessous.",wgonly:"Les panneaux d'administration (courrier, cloud, photos, vault) ne s'ouvrent que via WireGuard. Ce protocole sert à l'accès Internet général."},
        it:{services:"Servizi VPN",loading:"Caricamento…",empty:"Nessun servizio VPN installato.",running:"Attivo",add:"Aggiungi client",newc:"Nuovo client",nameph:"Nome del dispositivo — es. iPhone",create:"Crea",cancel:"Annulla",close:"Chiudi",download:"Scarica",signout:"Esci",removeq:"Rimuovere questo client?",soon:"La gestione dei client per questo protocollo arriverà presto. Per ora usa i dati del report di installazione.",reqfail:"Richiesta non riuscita.",neterr:"Errore di rete.",protected:"protetto",signin:"Accedi",signingin:"Accesso…",user:"Nome utente",pass:"Password",subtitle:"Accedi per gestire la tua VPN",wrong:"Nome utente o password errati.",toomany:"Troppi tentativi. Attendi qualche minuto.",accounts:"Account",adduser:"Aggiungi account",newuser:"Nuovo account",removeuserq:"Rimuovere questo account?",rsuper:"Amministratore principale",radmin:"Amministratore",ruser:"Utente",forgot:"Password dimenticata?",entername:"Inserisci prima il nome utente.",resetsent:"Se quell’account ha un indirizzo e-mail, il link è in arrivo.",newpass:"Scegli una nuova password",passagain:"Ripeti la password",nomatch:"Le password non coincidono.",tooshort:"Almeno 8 caratteri.",save:"Salva",email:"E-mail",emailsetup:"Posta in uscita",smtphost:"Server SMTP",smtpport:"Porta",sender:"Indirizzo mittente",sendtest:"Invia una prova",testsent:"Messaggio di prova inviato.",notset:"Non configurato",nosmtp:"Nessun server",pickbox:"Scegli una casella…",nomailboxes:"Nessuna casella trovata. Creane una in mailcow oppure indica sotto un server SMTP esterno.",wgonly:"I pannelli di amministrazione (posta, cloud, foto, vault) si aprono solo tramite WireGuard. Questo protocollo serve all'accesso generale a Internet."},
        ja:{services:"VPNサービス",loading:"読み込み中…",empty:"VPNサービスがインストールされていません。",running:"稼働中",add:"クライアントを追加",newc:"新しいクライアント",nameph:"デバイス名 — 例: iPhone",create:"作成",cancel:"キャンセル",close:"閉じる",download:"ダウンロード",signout:"サインアウト",removeq:"このクライアントを削除しますか？",soon:"このプロトコルのクライアント管理は近日対応予定です。当面はセットアップレポートの情報をご利用ください。",reqfail:"リクエストに失敗しました。",neterr:"ネットワークエラー。",protected:"保護済み",signin:"サインイン",signingin:"サインイン中…",user:"ユーザー名",pass:"パスワード",subtitle:"サインインしてVPNを管理",wrong:"ユーザー名またはパスワードが違います。",toomany:"試行回数が多すぎます。数分お待ちください。",accounts:"アカウント",adduser:"アカウントを追加",newuser:"新しいアカウント",removeuserq:"このアカウントを削除しますか？",rsuper:"メイン管理者",radmin:"管理者",ruser:"ユーザー",forgot:"パスワードをお忘れですか？",entername:"先にユーザー名を入力してください。",resetsent:"そのアカウントにメールアドレスが登録されていれば、リセット用リンクを送信しました。",newpass:"新しいパスワードを設定",passagain:"パスワードを再入力",nomatch:"パスワードが一致しません。",tooshort:"8文字以上にしてください。",save:"保存",email:"メール",emailsetup:"送信メール",smtphost:"SMTPサーバー",smtpport:"ポート",sender:"差出人アドレス",sendtest:"テスト送信",testsent:"テストメールを送信しました。",notset:"未設定",nosmtp:"サーバー未設定",pickbox:"メールボックスを選択…",nomailboxes:"メールボックスが見つかりません。mailcow で作成するか、下に外部SMTPサーバーを入力してください。",wgonly:"管理パネル（メール、クラウド、写真、Vault）は WireGuard 経由でのみ開けます。このプロトコルは一般的なインターネット接続用です。"},
        zh:{services:"VPN 服务",loading:"加载中…",empty:"未安装 VPN 服务。",running:"运行中",add:"添加客户端",newc:"新客户端",nameph:"设备名称 — 例如 iPhone",create:"创建",cancel:"取消",close:"关闭",download:"下载",signout:"退出登录",removeq:"删除此客户端？",soon:"该协议的客户端管理即将推出。目前请使用安装报告中的信息。",reqfail:"请求失败。",neterr:"网络错误。",protected:"受保护",signin:"登录",signingin:"登录中…",user:"用户名",pass:"密码",subtitle:"登录以管理您的 VPN",wrong:"用户名或密码错误。",toomany:"尝试次数过多，请稍候几分钟。",accounts:"账户",adduser:"添加账户",newuser:"新账户",removeuserq:"删除此账户？",rsuper:"主管理员",radmin:"管理员",ruser:"用户",forgot:"忘记密码？",entername:"请先输入用户名。",resetsent:"如果该账户设置了邮箱，重置链接已发送。",newpass:"设置新密码",passagain:"再次输入密码",nomatch:"两次密码不一致。",tooshort:"至少 8 个字符。",save:"保存",email:"邮件",emailsetup:"发件设置",smtphost:"SMTP 服务器",smtpport:"端口",sender:"发件人地址",sendtest:"发送测试",testsent:"测试邮件已发送。",notset:"未配置",nosmtp:"未设置服务器",pickbox:"选择邮箱…",nomailboxes:"未找到邮箱。请在 mailcow 中创建，或在下方填写外部 SMTP 服务器。",wgonly:"管理面板（邮件、云盘、相册、Vault）只能通过 WireGuard 打开。此协议用于常规互联网访问。"}
        };
        function lang(){var l=(navigator.language||'en').slice(0,2).toLowerCase();return I18N[l]?l:'en'}
        function t(k){var d=I18N[lang()]||I18N.en;return d[k]||I18N.en[k]||k}
        """.trimIndent()

    val appPY: String = """
        import os, sys, json, base64, subprocess, ipaddress, secrets, re, socket, urllib.parse, uuid, datetime, time, hashlib, smtplib, email.message, threading
        from functools import wraps
        from flask import Flask, request, Response, jsonify, send_file, abort, session, redirect

        DATA = "/data"
        WG_IF = "wgpanel"
        WG_CONF = f"/etc/wireguard/{WG_IF}.conf"
        CLIENTS = f"{DATA}/clients.json"
        STATE = f"{DATA}/state.json"
        ADMIN_USER = os.environ.get("ADMIN_USER", "admin")
        ADMIN_PW = os.environ.get("ADMIN_PASSWORD", "")
        WG_HOST = os.environ.get("WG_HOST", "vpn.example.com")
        WG_PORT = os.environ.get("WG_PORT", "51820")
        SUBNET = os.environ.get("WG_SUBNET", "10.9.0.0/24")
        SS_CONF = "/protocols/shadowsocks/config.json"
        # The tunnel's IPv6 is a local-only range, so clients prefer IPv4.
        SUBNET6 = "fd09::/64"
        AWG_SUBNET6 = "fd10::/64"

        def ipv6_usable():
            # wg-quick fails outright when the container has no IPv6
            try:
                with open("/proc/sys/net/ipv6/conf/default/disable_ipv6") as f:
                    return f.read().strip() == "0"
            except OSError:
                return False

        TUNNEL_V6 = ipv6_usable()
        # IPv6 goes into the tunnel and is refused there, never around it.
        CLIENT_ALLOWED_IPS = "0.0.0.0/0, ::/0"
        AWG_ALLOWED_IPS = "0.0.0.0/0, ::/0"

        def ip6_of(ip, network, subnet6):
            # The same host number in the IPv6 range: 10.9.0.3 -> fd09::3
            offset = int(ipaddress.ip_address(ip)) - int(ipaddress.ip_network(network, strict=False).network_address)
            return str(ipaddress.ip_network(subnet6)[offset])

        def wg_addresses(ip, prefix, prefix6):
            # One client's or the server's tunnel addresses
            if not TUNNEL_V6:
                return f"{ip}/{prefix}"
            return f"{ip}/{prefix}, {ip6_of(ip, SUBNET, SUBNET6)}/{prefix6}"
        # Conservative enough to survive a second encapsulation: in the VPS+home
        # topology the client's packets are wrapped again by the relay tunnel, and
        # an over-large MTU lets handshakes through while stalling real payloads.
        CLIENT_MTU = 1280

        app = Flask(__name__)
        # No request in this API carries more than a short JSON body; anything
        # bigger is garbage or an attack.
        app.config["MAX_CONTENT_LENGTH"] = 16 * 1024

        def sh(cmd, inp=None):
            return subprocess.run(cmd, shell=True, input=inp, capture_output=True, text=True, check=True).stdout.strip()

        def load(path, default):
            try:
                with open(path) as f: return json.load(f)
            except Exception:
                return default

        def save(path, obj):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            tmp = path + ".tmp"
            with open(tmp, "w") as f: json.dump(obj, f, indent=2)
            os.chmod(tmp, 0o600)
            os.replace(tmp, path)

        # Every store is a JSON file rewritten whole, so a handler that reads,
        # edits and saves is a read-modify-write. The server is threaded, so two
        # overlapping state-changing requests both load the same snapshot and the
        # second save silently drops the first one's work — two clients added at
        # once lose one, and next_ip()/awg_next_ip() hand BOTH the same tunnel
        # address off the same stale list. One process-wide lock around the
        # mutating handlers is enough; each is a sub-millisecond file rewrite
        # (the openvpn ones wait on easyrsa, which is worth serialising anyway).
        STORE_LOCK = threading.RLock()

        def serialized(f):
            @wraps(f)
            def w(*a, **k):
                with STORE_LOCK:
                    return f(*a, **k)
            return w

        # ---- Session auth: a styled form login instead of a browser Basic prompt
        # (H1). The signed cookie is HttpOnly + Secure (the user reaches the panel
        # over Caddy's HTTPS) + SameSite=Lax; the secret persists so sessions
        # survive restarts. Access is still gated to VPN-side sources when the
        # dashboard's VPN-only lockdown is on. ----

        def ensure_secret():
            st = load(STATE, {})
            if "secret" not in st:
                st["secret"] = secrets.token_hex(32)
                save(STATE, st)
            return st["secret"]

        app.secret_key = ensure_secret()
        app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SECURE=True,
                          SESSION_COOKIE_SAMESITE="Lax",
                          PERMANENT_SESSION_LIFETIME=datetime.timedelta(days=7))

        # The panel sits behind Caddy, so request.remote_addr is the proxy for
        # every visitor — throttling on it would put all clients (including the
        # admin) in one bucket. The panel's Caddy site overwrites
        # X-Forwarded-For with the real peer address (header_up X-Forwarded-For
        # {remote_host}) instead of appending to whatever the client sent, so
        # its first entry is always the real client and cannot be spoofed.
        def client_ip():
            xff = request.headers.get("X-Forwarded-For", "")
            return xff.split(",")[0].strip() or request.remote_addr or "?"

        # Per-IP throttle (H3) + fail2ban-style escalating bans: the
        # single admin password must not be brute-forced. After MAX_FAILS wrong
        # attempts the source is banned; every further ban doubles, up to a day.
        #
        # Counters are keyed by (scope, ip), not by ip alone. /forgot notes a
        # "failure" on EVERY call — it has to, being unauthenticated and cheap to
        # abuse — and with one shared bucket eight password-reset requests banned
        # the sender from the LOGIN form for fifteen minutes, doubling from there.
        # Someone who cannot remember their password would lock themselves out of
        # the one thing they still had. The two limits are independent now.
        FAILS = {}
        BANS = {}
        MAX_FAILS, FAIL_WINDOW, BAN_BASE, BAN_MAX = 8, 300, 900, 86400

        def rate_limited(scope, ip):
            key = (scope, ip)
            ban = BANS.get(key)
            if ban and time.time() < ban[0]: return True
            c = FAILS.get(key)
            if not c: return False
            if time.time() - c[1] > FAIL_WINDOW:
                FAILS.pop(key, None); return False
            return c[0] >= MAX_FAILS

        def note_fail(scope, ip):
            key = (scope, ip)
            now = time.time(); c = FAILS.get(key)
            if not c or now - c[1] > FAIL_WINDOW:
                c = FAILS[key] = [1, now]
            else:
                c[0] += 1
            if c[0] >= MAX_FAILS:
                prior = BANS.get(key)
                strikes = (prior[1] if prior else 0) + 1
                BANS[key] = (now + min(BAN_BASE * (2 ** (strikes - 1)), BAN_MAX), strikes)
                FAILS.pop(key, None)

        # ---- Users and roles. One account per person instead of a single
        # shared admin login. Roles: "superadmin" (exactly one, never deletable and
        # never demotable — the account that can always get back in), "admin" (full
        # management, including other users, but cannot touch the superadmin) and
        # "user" (manages only the VPN clients it created itself). Passwords are
        # PBKDF2-SHA256 with a per-user salt; only the hash is stored. ----

        USERS = f"{DATA}/users.json"
        ROLES = ("superadmin", "admin", "user")
        PBKDF2_ROUNDS = 200000

        def hash_pw(password, salt=None):
            salt = salt or secrets.token_hex(16)
            digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt.encode(), PBKDF2_ROUNDS)
            return {"salt": salt, "hash": digest.hex()}

        def verify_pw(password, record):
            expected = record.get("hash", "")
            got = hashlib.pbkdf2_hmac(
                "sha256", password.encode(), record.get("salt", "").encode(), PBKDF2_ROUNDS).hex()
            return bool(expected) and secrets.compare_digest(got, expected)

        def set_password(record, password, source="panel"):
            ""${'"'}New credentials for `record`, and an end to every session that used the
            old ones.

            A signed session cookie is valid because it was signed, not because the
            password behind it still is: without this, changing a password — or
            RESETTING one because it was lost or stolen — left every session already
            open still working, which is exactly the session the change was meant to
            end. `pw_ver` is stamped into the session at login and re-checked on every
            request, so a change invalidates every session but the one that makes it
            (which restamps itself).
            ""${'"'}
            record.update({"pw_source": source, "pw_ver": record.get("pw_ver", 0) + 1,
                           **hash_pw(password)})
            return record


        def users():
            return load(USERS, [])

        def find_user(uid):
            for u in users():
                if u["id"] == uid: return u
            return None

        def find_user_by_name(name):
            for u in users():
                if u["username"].lower() == name.lower(): return u
            return None

        def ensure_superadmin():
            ""${'"'}Bootstraps the superadmin from the setup's ADMIN_USER/ADMIN_PASSWORD.

            The installer rewrites .env on every run, so as long as the password
            still comes from there the record follows it — the credentials printed
            in the setup report keep working. The moment the superadmin changes
            their password inside the panel the record switches to pw_source
            "panel" and the environment stops overriding it.
            ""${'"'}
            if not ADMIN_PW:
                return
            all_users = users()
            current = next((u for u in all_users if u.get("role") == "superadmin"), None)
            if current is None:
                all_users.append({
                    "id": secrets.token_hex(8), "username": ADMIN_USER, "role": "superadmin",
                    "email": "", "pw_source": "env", **hash_pw(ADMIN_PW),
                })
                save(USERS, all_users)
                return
            if current.get("pw_source") != "env":
                return
            if current["username"] != ADMIN_USER or not verify_pw(ADMIN_PW, current):
                set_password(current, ADMIN_PW, source="env")
                current["username"] = ADMIN_USER
                save(USERS, all_users)

        ensure_superadmin()

        def current_user():
            uid = session.get("uid")
            if not uid:
                return None
            user = find_user(uid)
            if user is None:
                return None
            # The session was issued against a password that has since been replaced —
            # see set_password. A deleted account already fails above.
            if session.get("pv", 0) != user.get("pw_ver", 0):
                return None
            return user

        def logged_in():
            return current_user() is not None

        def is_admin(user=None):
            user = user or current_user()
            return bool(user) and user.get("role") in ("superadmin", "admin")

        def public_user(u):
            return {"id": u["id"], "username": u["username"], "role": u["role"],
                    "email": u.get("email", "")}

        # Which clients a plain "user" may see and remove: the panel records what
        # each account created, keyed by protocol, because only some protocols keep
        # anything resembling an owner in their own configuration.
        OWNERS = f"{DATA}/client-owners.json"

        def note_owner(proto, cid, uid):
            owners = load(OWNERS, {})
            owners.setdefault(proto, {})[str(cid)] = uid
            save(OWNERS, owners)

        def drop_owner(proto, cid):
            owners = load(OWNERS, {})
            owners.get(proto, {}).pop(str(cid), None)
            save(OWNERS, owners)

        def owns(proto, cid):
            user = current_user()
            if is_admin(user): return True
            owners = load(OWNERS, {}).get(proto, {})
            return bool(user) and owners.get(str(cid)) == user["id"]

        # ---- DNS per client ----
        #
        # Each client keeps the resolvers it was made with, so changing the default
        # later never rewrites a device that is already set up. A client made before
        # this existed has no record and keeps the old fixed 1.1.1.1.

        CLIENT_DNS = f"{DATA}/client-dns.json"
        DNS_FALLBACK = ["1.1.1.1"]
        DNS_MAX = 4

        def dns_clean(raw):
            if not isinstance(raw, list) or not raw or len(raw) > DNS_MAX: abort(422)
            out = []
            for item in raw:
                try: out.append(str(ipaddress.ip_address(str(item).strip())))
                except ValueError: abort(422)
            return out

        def dns_default():
            return load(CLIENT_DNS, {}).get("default") or DNS_FALLBACK

        def dns_recorded(proto, cid):
            return load(CLIENT_DNS, {}).get(proto, {}).get(str(cid))

        def dns_of(proto, cid):
            return dns_recorded(proto, cid) or DNS_FALLBACK

        def dns_set(proto, cid, dns):
            store = load(CLIENT_DNS, {})
            if dns: store.setdefault(proto, {})[str(cid)] = dns
            else: store.get(proto, {}).pop(str(cid), None)
            save(CLIENT_DNS, store)

        def ov_with_dns(text, dns):
            # Ignore what the server pushes and use this client's own resolvers.
            lines = ['pull-filter ignore "dhcp-option DNS"']
            lines += [f"dhcp-option {'DNS6' if ':' in d else 'DNS'} {d}" for d in dns]
            head, sep, rest = text.partition("\n")
            return head + sep + "\n".join(lines) + "\n" + rest

        # ---- Password recovery by e-mail ----
        #
        # The panel sends through whatever SMTP the main administrator configures.
        # When mailcow runs on this server its mailboxes are offered as the sender:
        # its database credentials are read from the read-only mailcow.conf mount
        # and the list is queried through the agent's broker, because the panel has
        # no way to authenticate to mailcow's API on its own. The mailbox PASSWORD
        # is still typed by the administrator — mailcow only stores hashes.

        SMTP_CONF = f"{DATA}/smtp.json"
        RESETS = f"{DATA}/resets.json"
        MAILCOW_CONF = "/protocols/mailcow/mailcow.conf"
        RESET_TTL = 3600

        def smtp_conf():
            return load(SMTP_CONF, {})

        def public_smtp(c):
            # The password is write-only: the UI shows whether one is set, never
            # the value.
            return {"host": c.get("host", ""), "port": c.get("port", 587),
                    "security": c.get("security", "starttls"), "username": c.get("username", ""),
                    "sender": c.get("sender", ""), "has_password": bool(c.get("password"))}

        def mailcow_env():
            env = {}
            try:
                with open(MAILCOW_CONF) as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("#") or "=" not in line: continue
                        k, v = line.split("=", 1)
                        env[k.strip()] = v.strip()
            except OSError:
                return {}
            return env

        def mailcow_mailboxes():
            ""${'"'}Active mailbox addresses, or [] when mailcow is not installed here.""${'"'}
            env = mailcow_env()
            user, pw, db = env.get("DBUSER"), env.get("DBPASS"), env.get("DBNAME")
            if not (user and pw and db):
                return []
            r = broker("mailboxes", user=user, password=pw, db=db)
            if not r or not r.get("ok"):
                return []
            out = r.get("out", "")
            return [l.strip() for l in out.splitlines() if "@" in l]

        def send_mail(to, subject, body):
            c = smtp_conf()
            host, sender = c.get("host"), c.get("sender")
            if not (host and sender and to):
                return False
            msg = email.message.EmailMessage()
            msg["From"] = sender
            msg["To"] = to
            msg["Subject"] = subject
            msg.set_content(body)
            port = int(c.get("port") or 587)
            security = c.get("security", "starttls")
            try:
                if security == "ssl":
                    server = smtplib.SMTP_SSL(host, port, timeout=20)
                else:
                    server = smtplib.SMTP(host, port, timeout=20)
                with server:
                    if security == "starttls":
                        server.starttls()
                    if c.get("username"):
                        server.login(c["username"], c.get("password", ""))
                    server.send_message(msg)
                return True
            except Exception:
                # Never leak the reason to the caller: /forgot answers the same way
                # whatever happens, so a stranger learns nothing about the setup.
                return False

        def issue_reset(user):
            token = secrets.token_urlsafe(32)
            pending = [t for t in load(RESETS, []) if t["exp"] > time.time() and t["uid"] != user["id"]]
            # Stored hashed: a leaked file must not hand out working reset links.
            pending.append({"uid": user["id"], "exp": time.time() + RESET_TTL,
                            "hash": hashlib.sha256(token.encode()).hexdigest()})
            save(RESETS, pending)
            return token

        def consume_reset(token):
            digest = hashlib.sha256((token or "").encode()).hexdigest()
            pending = load(RESETS, [])
            match = next((t for t in pending
                          if secrets.compare_digest(t["hash"], digest) and t["exp"] > time.time()), None)
            if not match:
                return None
            save(RESETS, [t for t in pending if t is not match and t["exp"] > time.time()])
            return find_user(match["uid"])

        def services():
            return load(f"{DATA}/services.json", {"services": []}).get("services", [])

        def svc_meta(pid):
            for s in services():
                if s.get("id") == pid: return s
            abort(404)

        BROKER = "/run/gryonixnexus-panel/broker.sock"

        def broker(op, **args):
            # One request to the agent's narrow socket; None when it is unreachable
            try:
                s = socket.socket(socket.AF_UNIX)
                s.settimeout(180)
                s.connect(BROKER)
                s.sendall((json.dumps({"op": op, **args}) + "\n").encode())
                data = b""
                while not data.endswith(b"\n"):
                    chunk = s.recv(65536)
                    if not chunk: break
                    data += chunk
                s.close()
                return json.loads(data)
            except (OSError, ValueError):
                return None

        def broker_ok(op, **args):
            # The answer of a request that must succeed
            r = broker(op, **args)
            if not r or not r.get("ok"): abort(502)
            return r

        def docker_restart(name):
            broker("restart", name=name)

        def container_state(name):
            r = broker("state", name=name)
            return r.get("state") if r and r.get("ok") else None

        def restart_count(name):
            r = broker("state", name=name)
            return r.get("restart_count", 0) if r and r.get("ok") else None

        def last_log_line(name):
            # The newest line that says what failed, from the container's own log
            r = broker("log_tail", name=name)
            lines = r.get("out", "").splitlines() if r and r.get("ok") else []
            useful = [l.strip() for l in lines if l.strip()]
            for line in reversed(useful):
                if "fail" in line.lower() or "error" in line.lower(): return line[-200:]
            return useful[-1][-200:] if useful else ""

        SETTLE_SECONDS = 6

        def stays_up(name):
            # None when the service runs; otherwise why it does not
            before = restart_count(name)
            time.sleep(SETTLE_SECONDS)
            state = container_state(name)
            if state is None: return None
            if state.get("Running") and not state.get("Restarting") and restart_count(name) == before:
                return None
            return last_log_line(name) or state.get("Status", "stopped")

        def apply_config(path, conf, container):
            # Writes the change; puts the old file back if the service falls over
            try:
                with open(path) as f: before = f.read()
            except OSError:
                before = None
            save(path, conf)
            docker_restart(container)
            why = stays_up(container)
            if why is None: return
            if before is not None:
                tmp = path + ".tmp"
                with open(tmp, "w") as f: f.write(before)
                os.chmod(tmp, 0o600)
                os.replace(tmp, path)
                docker_restart(container)
            abort(422, description=f"{container} did not start with this change, so it was undone. It said: {why}")

        # ---- WireGuard (panel runs the interface itself) ----

        def ensure_server():
            st = load(STATE, {})
            if "priv" not in st:
                st["priv"] = sh("wg genkey")
                st["pub"] = sh("wg pubkey", inp=st["priv"])
                save(STATE, st)
            return st

        def wan_if():
            ""${'"'}The interface the container reaches the internet through.

            Was hard-coded to eth0, which is only right by accident: a container on
            a user-defined compose network can be given any name, and NAT bound to
            the wrong interface silently drops every client packet.
            ""${'"'}
            try:
                out = subprocess.run("ip -4 route show default", shell=True,
                                     capture_output=True, text=True).stdout.split()
                if "dev" in out:
                    return out[out.index("dev") + 1]
            except Exception:
                pass
            return "eth0"

        def wg_apply_nat(wan):
            # NAT/forwarding is applied here, OUTSIDE wg-quick's PostUp, on
            # purpose. wg-quick arms a `trap del_if EXIT` before it runs the PostUp
            # hooks and only clears it once every hook has succeeded, so a SINGLE
            # failing PostUp command tears the freshly-created interface back down
            # on its way out. That turned any iptables hiccup — a missing
            # nat/conntrack module, an nft-vs-legacy backend mismatch, a busy
            # xtables lock — into a tunnel clients could "connect" to while nothing
            # listened: no handshake, every packet into a black hole, no internet
            # and no admin sites. Run here instead, a NAT failure at worst costs
            # one rule (and is logged); it can never take the whole VPN down with
            # it. Forwarding itself is switched on by the compose file
            # (net.ipv4.ip_forward=1): /proc/sys is read-only in the container, so
            # that is the only way that works from here.
            #
            # Each rule is deleted first (failure ignored — the stale copy may not
            # exist) then re-added, so repeated wg_up calls stay idempotent and any
            # leftover PostUp-era rules are cleaned up. The FORWARD accepts are
            # explicit rather than trusting the namespace's default policy; MSS
            # clamping keeps large TCP segments from stalling on the doubly
            # encapsulated VPS+home path.
            # Forwarding is a container-start setting (compose `sysctls:`), not
            # something we can flip at runtime — /proc/sys is read-only here. If it
            # is off anyway (e.g. an OLD compose from before that fix is still
            # running), every routed packet is silently dropped: connected tunnel,
            # no internet, no admin sites. Surface it loudly so `docker logs`
            # names the cause instead of leaving a black hole to guess at.
            try:
                with open("/proc/sys/net/ipv4/ip_forward") as f:
                    if f.read().strip() != "1":
                        sys.stderr.write("ip_forward is 0: the container is not routing. "
                                         "Re-run setup so compose applies "
                                         "sysctls net.ipv4.ip_forward=1, then restart.\n")
                        sys.stderr.flush()
            except Exception:
                pass
            rules = [
                ("nat", ["POSTROUTING", "-s", SUBNET, "-o", wan, "-j", "MASQUERADE"]),
                ("filter", ["FORWARD", "-i", WG_IF, "-o", wan, "-j", "ACCEPT"]),
                ("filter", ["FORWARD", "-i", wan, "-o", WG_IF,
                            "-m", "conntrack", "--ctstate", "RELATED,ESTABLISHED", "-j", "ACCEPT"]),
                ("mangle", ["FORWARD", "-o", WG_IF, "-p", "tcp", "--tcp-flags", "SYN,RST", "SYN",
                            "-j", "TCPMSS", "--clamp-mss-to-pmtu"]),
            ]
            for table, spec in rules:
                subprocess.run(["iptables", "-t", table, "-D"] + spec, capture_output=True)
                r = subprocess.run(["iptables", "-t", table, "-A"] + spec, capture_output=True, text=True)
                if r.returncode != 0:
                    sys.stderr.write("iptables -t %s -A %s failed: %s\n"
                                     % (table, " ".join(spec), (r.stderr or "").strip()))
                    sys.stderr.flush()

        def wg_synced():
            # A running interface takes its new peers in place, so no client drops
            if subprocess.run(["ip", "link", "show", WG_IF], capture_output=True).returncode != 0:
                return False
            r = subprocess.run(["bash", "-c", f"wg syncconf {WG_IF} <(wg-quick strip {WG_IF})"], capture_output=True, text=True)
            if r.returncode != 0:
                sys.stderr.write(f"wg syncconf {WG_IF} failed ({r.returncode}): {(r.stderr or '').strip()}\n")
                sys.stderr.flush()
            return r.returncode == 0

        def wg_up(st):
            net = ipaddress.ip_network(SUBNET)
            server_ip = str(list(net.hosts())[0])
            wan = wan_if()
            peers = ""
            for c in load(CLIENTS, []):
                peers += f"\n[Peer]\nPublicKey = {c['pub']}\nAllowedIPs = {wg_addresses(c['ip'], 32, 128)}\n"
            # A BARE interface: no PostUp/PostDown firewall hooks. A failing hook
            # would make wg-quick trap-EXIT and delete the interface, so NAT and
            # forwarding are applied by wg_apply_nat AFTER the interface is
            # confirmed up (see there for the full rationale).
            conf = f""${'"'}[Interface]
        Address = {wg_addresses(server_ip, net.prefixlen, 64)}
        ListenPort = {WG_PORT}
        PrivateKey = {st['priv']}
        {peers}""${'"'}
            os.makedirs("/etc/wireguard", exist_ok=True)
            with open(WG_CONF, "w") as f: f.write(conf)
            os.chmod(WG_CONF, 0o600)
            if wg_synced():
                wg_apply_nat(wan)
                wg_refuse_ipv6()
                return True
            subprocess.run(f"wg-quick down {WG_IF}", shell=True, capture_output=True)
            r = subprocess.run(f"wg-quick up {WG_IF}", shell=True, capture_output=True, text=True)
            # The exit code used to be dropped on the floor, so an interface that
            # never came up looked exactly like a working one from in here. It is
            # the difference between "VPN is broken" and a line in `docker logs`.
            if r.returncode != 0:
                sys.stderr.write(f"wg-quick up {WG_IF} failed ({r.returncode}): "
                                 f"{(r.stderr or '').strip()}\n")
                sys.stderr.flush()
                return False
            wg_apply_nat(wan)
            wg_refuse_ipv6()
            return True

        def wg_refuse_ipv6():
            # Nothing routes IPv6 out; an instant refusal beats a silent drop
            if not TUNNEL_V6:
                return
            r = subprocess.run(["ip", "-6", "route", "replace", "unreachable", "default"], capture_output=True, text=True)
            if r.returncode != 0:
                sys.stderr.write(f"ip -6 route unreachable failed: {(r.stderr or '').strip()}\n")
                sys.stderr.flush()

        def next_ip():
            net = ipaddress.ip_network(SUBNET)
            used = {c["ip"] for c in load(CLIENTS, [])}
            used.add(str(list(net.hosts())[0]))
            for h in net.hosts():
                if str(h) not in used: return str(h)
            abort(507)

        def require_auth(f):
            @wraps(f)
            def w(*a, **k):
                if not logged_in():
                    # API callers get JSON they can act on; page requests are sent
                    # to the styled login form.
                    if request.path.startswith("/api/"):
                        return jsonify({"error": "Authentication required."}), 401
                    return redirect("/login")
                return f(*a, **k)
            return w

        def require_admin(f):
            @wraps(f)
            def w(*a, **k):
                if not logged_in():
                    if request.path.startswith("/api/"):
                        return jsonify({"error": "Authentication required."}), 401
                    return redirect("/login")
                if not is_admin():
                    return jsonify({"error": "Administrator access required."}), 403
                return f(*a, **k)
            return w

        def wg_clients():
            return [{"id": c["id"], "name": c["name"], "detail": c["ip"]} for c in load(CLIENTS, [])]

        def wg_add_client(name):
            st = ensure_server()
            priv = sh("wg genkey"); pub = sh("wg pubkey", inp=priv)
            clients = load(CLIENTS, [])
            cid = secrets.token_hex(6)
            clients.append({"id": cid, "name": name, "ip": next_ip(), "priv": priv, "pub": pub})
            save(CLIENTS, clients)
            wg_up(st)
            return cid

        def wg_del_client(cid):
            save(CLIENTS, [c for c in load(CLIENTS, []) if c["id"] != cid])
            wg_up(ensure_server())

        def wg_client_conf(cid):
            st = ensure_server()
            for c in load(CLIENTS, []):
                if c["id"] == cid:
                    return (f"[Interface]\nPrivateKey = {c['priv']}\nAddress = {wg_addresses(c['ip'], 32, 128)}\n"
                            f"DNS = {', '.join(dns_of('wireguard', cid))}\nMTU = {CLIENT_MTU}\n\n"
                            f"[Peer]\nPublicKey = {st['pub']}\nEndpoint = {WG_HOST}:{WG_PORT}\n"
                            f"AllowedIPs = {CLIENT_ALLOWED_IPS}\nPersistentKeepalive = 25\n")
            abort(404)

        # ---- Shadowsocks (edits the ss container's config.json, then restarts it) ----

        def ss_load():
            # ssserver reads per-client keys only inside a "servers" list
            conf = load(SS_CONF, {})
            return conf["servers"][0] if conf.get("servers") else conf

        def ss_save(conf):
            apply_config(SS_CONF, {"servers": [conf]}, "shadowsocks")

        def ss_clients():
            return [{"id": u["id"], "name": u["name"], "detail": "shadowsocks"} for u in ss_load().get("users", [])]

        def ss_add_client(name):
            conf = ss_load()
            users = conf.get("users", [])
            uid = secrets.token_hex(6)
            users.append({"id": uid, "name": name, "password": base64.b64encode(secrets.token_bytes(32)).decode()})
            conf["users"] = users
            ss_save(conf)
            return uid

        def ss_del_client(cid):
            conf = ss_load()
            conf["users"] = [u for u in conf.get("users", []) if u["id"] != cid]
            ss_save(conf)

        def ss_client_conf(cid):
            conf = ss_load(); meta = svc_meta("shadowsocks")
            method = conf.get("method", "2022-blake3-aes-256-gcm"); server_psk = conf.get("password", "")
            for u in conf.get("users", []):
                if u["id"] == cid:
                    # SIP022 multi-user: client password is server_psk:user_psk.
                    pw = urllib.parse.quote(f"{server_psk}:{u['password']}", safe=":")
                    # The label is a URI fragment, so it needs escaping just like
                    # xray's does — client names may contain spaces (api_add keeps
                    # them), and a raw space truncated the link in every importer
                    # that parses it as a URI.
                    label = urllib.parse.quote(u["name"])
                    return f"ss://{method}:{pw}@{meta['host']}:{meta['port']}#{label}"
            abort(404)

        # ---- Xray VLESS/Reality (adds client UUIDs to the inbound, then restarts) ----

        XR_CONF = "/protocols/xray/config/config.json"
        XR_LINK = "/protocols/xray/link.txt"

        def xr_inbound(conf):
            for i in conf.get("inbounds", []):
                if i.get("protocol") == "vless": return i
            abort(503)

        def xr_link_params():
            # pbk/sid/sni and the public host:port come from the link the setup
            # script wrote. Parsed with a regex (not parse_qsl) so the raw
            # percent-encoding of the values is preserved verbatim.
            try:
                with open(XR_LINK) as f: link = f.read().strip()
            except Exception:
                abort(503)
            m = re.match(r"vless://[^@]+@([^:/?#]+):(\d+)\?([^#]*)", link)
            if not m: abort(503)
            q = dict(p.split("=", 1) for p in m.group(3).split("&") if "=" in p)
            return m.group(1), m.group(2), q

        def xr_clients():
            out = []
            for i in load(XR_CONF, {}).get("inbounds", []):
                if i.get("protocol") == "vless":
                    out = i.get("settings", {}).get("clients", [])
            return [{"id": c["id"], "name": c.get("email") or "default", "detail": "vless"} for c in out]

        def xr_unique_names(clients):
            # Xray refuses to start at all when two clients share a name.
            taken, seen = {c.get("email") for c in clients}, set()
            for c in clients:
                base = c.get("email")
                if not base: continue
                name, n = base, 2
                while name in seen or (name != base and name in taken):
                    name = f"{base} {n}"; n += 1
                c["email"] = name; seen.add(name)

        def xr_add_client(name):
            conf = load(XR_CONF, {})
            ib = xr_inbound(conf)
            cid = str(uuid.uuid4())
            clients = ib.setdefault("settings", {}).setdefault("clients", [])
            clients.append({"id": cid, "flow": "xtls-rprx-vision", "email": name})
            xr_unique_names(clients)
            apply_config(XR_CONF, conf, "xray")
            return cid

        def xr_del_client(cid):
            conf = load(XR_CONF, {})
            ib = xr_inbound(conf)
            ib["settings"]["clients"] = [c for c in ib.get("settings", {}).get("clients", []) if c["id"] != cid]
            xr_unique_names(ib["settings"]["clients"])
            apply_config(XR_CONF, conf, "xray")

        def xr_client_conf(cid):
            host, port, q = xr_link_params()
            for c in xr_clients():
                if c["id"] == cid:
                    name = urllib.parse.quote(c["name"])
                    return (f"vless://{cid}@{host}:{port}?encryption=none&flow=xtls-rprx-vision"
                            f"&security=reality&sni={q.get('sni', '')}&fp=chrome"
                            f"&pbk={q.get('pbk', '')}&sid={q.get('sid', '')}&type=tcp#{name}")
            abort(404)

        # ---- OpenVPN (EasyRSA certificates via exec in the openvpn container) ----

        OV_DIR = "/protocols/openvpn"
        # Named so api_add can truncate to the same bound instead of guessing.
        OV_NAME_MAX = 32
        # \Z rather than a trailing ${SH}: in Python's re, ${SH} also matches right
        # before a final "\n", so "foo\n" would pass this and then interpolate
        # into a shell command (ov_write_profile) as three arguments instead of
        # one. \Z matches end-of-string only.
        OV_NAME = re.compile(r"^[A-Za-z0-9_][A-Za-z0-9_.-]{0,%d}\Z" % (OV_NAME_MAX - 1))

        def ov_server_cn():
            return svc_meta("openvpn").get("host", "")

        def ov_clients():
            # pki/index.txt is EasyRSA's authoritative state: V = valid, R = revoked.
            # The server's own certificate (CN = the VPN host) is not a client.
            try:
                with open(f"{OV_DIR}/pki/index.txt") as f: lines = f.readlines()
            except Exception:
                return []
            out = []
            for ln in lines:
                cols = ln.strip().split("\t")
                m = re.search(r"/CN=([^/\n]+)", cols[-1]) if cols else None
                if not m or cols[0] != "V": continue
                cn = m.group(1)
                if cn == ov_server_cn(): continue
                out.append({"id": cn, "name": cn, "detail": "certificate"})
            return out

        def ov_write_profile(cn):
            broker_ok("openvpn_profile", name=cn)

        def ov_add_client(name):
            name = name.replace(" ", "-")
            if not OV_NAME.match(name) or name == ov_server_cn(): abort(400)
            if any(c["id"] == name for c in ov_clients()): abort(409)
            broker_ok("openvpn_build", name=name)
            ov_write_profile(name)
            return name

        def ov_del_client(cid):
            if not OV_NAME.match(cid): abort(400)
            broker_ok("openvpn_revoke", name=cid)
            try: os.remove(f"{OV_DIR}/panel/{cid}.ovpn")
            except OSError: pass
            docker_restart("openvpn")

        def ov_client_conf(cid):
            if not OV_NAME.match(cid): abort(400)
            path = f"{OV_DIR}/panel/{cid}.ovpn"
            if not os.path.exists(path):
                # The initial client made by the setup script has no cached profile.
                if not any(c["id"] == cid for c in ov_clients()): abort(404)
                ov_write_profile(cid)
            with open(path) as f: text = f.read()
            dns = dns_recorded("openvpn", cid)
            return ov_with_dns(text, dns) if dns else text

        # ---- AmneziaWG (edits the awgvpn container's wg0.json, then restarts it) ----

        AWG_CONF = "/protocols/amneziawg/wg0.json"

        def awg_clients():
            return [{"id": k, "name": v.get("name", k), "detail": v.get("address", "")}
                    for k, v in load(AWG_CONF, {}).get("clients", {}).items()]

        def awg_next_ip(conf):
            server_ip = conf.get("server", {}).get("address", "10.10.0.1")
            net = ipaddress.ip_network(f"{server_ip}/24", strict=False)
            used = {server_ip} | {c.get("address") for c in conf.get("clients", {}).values()}
            for h in net.hosts():
                if str(h) not in used: return str(h)
            abort(507)

        def awg_add_client(name):
            conf = load(AWG_CONF, {})
            if "server" not in conf: abort(503)
            priv = sh("wg genkey"); pub = sh("wg pubkey", inp=priv); psk = sh("wg genpsk")
            cid = str(uuid.uuid4())
            now = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")
            conf.setdefault("clients", {})[cid] = {
                "name": name, "address": awg_next_ip(conf),
                "privateKey": priv, "publicKey": pub, "preSharedKey": psk,
                "createdAt": now, "updatedAt": now, "enabled": True,
            }
            apply_config(AWG_CONF, conf, "awgvpn")
            return cid

        def awg_del_client(cid):
            conf = load(AWG_CONF, {})
            conf.get("clients", {}).pop(cid, None)
            apply_config(AWG_CONF, conf, "awgvpn")

        def awg_client_conf(cid):
            conf = load(AWG_CONF, {}); meta = svc_meta("amneziawg")
            server = conf.get("server", {})
            c = conf.get("clients", {}).get(cid)
            if not c: abort(404)
            # The fork keeps the AmneziaWG obfuscation values with the server
            # config; the client [Interface] must carry the same ones.
            extra = ""
            for k in ("jc", "jmin", "jmax", "s1", "s2", "h1", "h2", "h3", "h4"):
                v = server.get(k)
                if v is not None:
                    extra += f"{k.capitalize() if k.startswith('j') else k.upper()} = {v}\n"
            awg_ip6 = ip6_of(c['address'], f"{c['address']}/24", AWG_SUBNET6)
            return (f"[Interface]\nPrivateKey = {c['privateKey']}\nAddress = {c['address']}/24, {awg_ip6}/128\n"
                    f"DNS = {', '.join(dns_of('amneziawg', cid))}\nMTU = {CLIENT_MTU}\n{extra}\n"
                    f"[Peer]\nPublicKey = {server.get('publicKey', '')}\nPresharedKey = {c['preSharedKey']}\n"
                    f"Endpoint = {meta.get('host', '')}:{meta.get('port', '')}\n"
                    f"AllowedIPs = {AWG_ALLOWED_IPS}\nPersistentKeepalive = 25\n")

        HANDLERS = {
            "wireguard": (wg_clients, wg_add_client, wg_del_client, wg_client_conf),
            "shadowsocks": (ss_clients, ss_add_client, ss_del_client, ss_client_conf),
            "xray": (xr_clients, xr_add_client, xr_del_client, xr_client_conf),
            "openvpn": (ov_clients, ov_add_client, ov_del_client, ov_client_conf),
            "amneziawg": (awg_clients, awg_add_client, awg_del_client, awg_client_conf),
        }

        # An .ovpn profile is several KB — far past what a phone camera scans.
        NO_QR = ["openvpn"]

        # Client-config download extension per protocol — what the VPN apps expect
        # to import (ss:// and vless:// links are plain text).
        EXT = {"wireguard": ".conf", "amneziawg": ".conf", "openvpn": ".ovpn",
               "shadowsocks": ".txt", "xray": ".txt"}

        from werkzeug.exceptions import HTTPException

        # API errors reach the frontend as JSON with a human message (abort() would
        # otherwise return an HTML page the SPA cannot show). 401 never lands here:
        # require_auth returns its JSON response / redirect directly.
        ERR = {400: "Invalid client name.", 403: "Request blocked.", 404: "Not found.",
               409: "A client with that name already exists.",
               502: "The protocol container could not be updated. It may be restarting — try again in a moment.",
               503: "This VPN service is not ready yet — wait a few seconds and retry.",
               422: "Invalid DNS address.",
               507: "No free addresses left in the VPN subnet."}

        @app.errorhandler(HTTPException)
        def on_http_error(e):
            return jsonify({"error": ERR.get(e.code, e.description or "Server error.")}), e.code

        # CSRF defence in depth: SameSite=Lax already keeps the session
        # cookie off cross-site POSTs; on top of that every state-changing request
        # must carry a custom header — a cross-origin page cannot attach one
        # without a CORS preflight, which this API never answers.
        @app.before_request
        def csrf_guard():
            # Every state-changing verb, not just the two the panel started with:
            # a route added later (PATCH /api/users/<id>) must not slip past this.
            if request.method not in ("GET", "HEAD", "OPTIONS") and request.headers.get("X-Gryonix-Auth") != "1":
                abort(403)

        # Baseline secure headers on every response, pages and API alike.
        # Everything the panel serves is sensitive, so nothing is cacheable; the
        # CSP pins all content to the page itself (both pages inline their CSS/JS).
        @app.after_request
        def secure_headers(resp):
            resp.headers["Content-Security-Policy"] = (
                "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; "
                "img-src 'self' data: blob:; connect-src 'self'; "
                "base-uri 'none'; form-action 'self'; frame-ancestors 'none'")
            resp.headers["X-Content-Type-Options"] = "nosniff"
            resp.headers["X-Frame-Options"] = "DENY"
            resp.headers["Referrer-Policy"] = "no-referrer"
            resp.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
            resp.headers["Cross-Origin-Opener-Policy"] = "same-origin"
            resp.headers["Cross-Origin-Resource-Policy"] = "same-origin"
            resp.headers["Strict-Transport-Security"] = "max-age=31536000"
            resp.headers["Cache-Control"] = "no-store"
            return resp

        @app.get("/login")
        def login_page():
            if logged_in(): return redirect("/")
            return send_file("/app/login.html")

        @app.post("/login")
        def login_submit():
            ip = client_ip()
            if rate_limited("login", ip):
                return jsonify({"error": "Too many attempts. Please wait a few minutes."}), 429
            data = request.get_json(silent=True) or request.form
            user = (data.get("username") or "").strip()
            pw = data.get("password") or ""
            # Both fields go through constant-time comparison, and both are always
            # evaluated — neither timing nor short-circuiting reveals which one
            # was wrong.
            record = find_user_by_name(user)
            # An unknown username is still checked against a throwaway hash so a
            # wrong name and a wrong password cost the same time.
            pw_ok = verify_pw(pw, record or hash_pw(secrets.token_hex(8)))
            if record and pw_ok:
                session.clear()          # a fresh session on every login
                session.permanent = True
                session["uid"] = record["id"]
                session["pv"] = record.get("pw_ver", 0)
                FAILS.pop(("login", ip), None); BANS.pop(("login", ip), None)
                return jsonify({"ok": True})
            note_fail("login", ip)
            time.sleep(0.4)              # flat cost per wrong guess
            return jsonify({"error": "Wrong username or password."}), 401

        @app.post("/logout")
        def logout():
            session.clear()
            return jsonify({"ok": True})

        @app.get("/")
        @require_auth
        def index():
            return send_file("/app/index.html")

        @app.get("/api/services")
        @require_auth
        def api_services():
            return jsonify({"services": services(), "manageable": list(HANDLERS.keys()), "noqr": NO_QR})

        @app.get("/api/<proto>/clients")
        @require_auth
        def api_list(proto):
            if proto not in HANDLERS: abort(404)
            found = HANDLERS[proto][0]()
            for c in found: c["dns"] = dns_of(proto, c["id"])
            # A plain user only ever sees the clients it created itself.
            return jsonify(found if is_admin() else [c for c in found if owns(proto, c["id"])])

        @app.post("/api/<proto>/clients")
        @require_auth
        @serialized
        def api_add(proto):
            if proto not in HANDLERS: abort(404)
            # 40 was this endpoint's own idea of "long enough"; openvpn turns the
            # name into an X.509 CN and rejects anything past OV_NAME's 32, so a
            # 33-character name got a bare "Invalid client name." after passing
            # the field's own validation. Truncate to what the strictest handler
            # accepts instead of handing it a name it will refuse.
            limit = OV_NAME_MAX if proto == "openvpn" else 40
            body = request.json or {}
            name = re.sub(r"[^A-Za-z0-9 _.-]", "", body.get("name", "").strip())[:limit] or "client"
            dns = dns_clean(body["dns"]) if body.get("dns") else dns_default()
            cid = HANDLERS[proto][1](name)
            note_owner(proto, cid, current_user()["id"])
            dns_set(proto, cid, dns)
            return jsonify({"id": cid})

        @app.put("/api/<proto>/clients/<cid>/dns")
        @require_auth
        @serialized
        def api_client_dns(proto, cid):
            if proto not in HANDLERS: abort(404)
            if not owns(proto, cid): abort(403)
            if not any(c["id"] == cid for c in HANDLERS[proto][0]()): abort(404)
            dns = dns_clean((request.json or {}).get("dns"))
            dns_set(proto, cid, dns)
            return jsonify({"dns": dns})

        @app.get("/api/dns")
        @require_auth
        def api_dns_default():
            return jsonify({"dns": dns_default()})

        @app.put("/api/dns")
        @require_admin
        @serialized
        def api_dns_default_set():
            dns = dns_clean((request.json or {}).get("dns"))
            store = load(CLIENT_DNS, {})
            store["default"] = dns
            save(CLIENT_DNS, store)
            return jsonify({"dns": dns})

        @app.delete("/api/<proto>/clients/<cid>")
        @require_auth
        @serialized
        def api_del(proto, cid):
            if proto not in HANDLERS: abort(404)
            if not owns(proto, cid): abort(403)
            HANDLERS[proto][2](cid)
            drop_owner(proto, cid)
            dns_set(proto, cid, None)
            return ("", 204)

        @app.get("/api/<proto>/clients/<cid>/config")
        @require_auth
        def api_conf(proto, cid):
            if proto not in HANDLERS: abort(404)
            if not owns(proto, cid): abort(403)
            resp = Response(HANDLERS[proto][3](cid), mimetype="text/plain")
            if request.args.get("dl"):
                # ?dl=1 turns the same URL into a real file download: an
                # attachment with the client's name survives mobile browsers that
                # ignore blob-anchor downloads.
                name = next((c["name"] for c in HANDLERS[proto][0]() if c["id"] == cid), cid)
                fname = re.sub(r"[^A-Za-z0-9._-]", "-", name).strip("-.") or "client"
                resp.headers["Content-Disposition"] = f'attachment; filename="{fname}{EXT.get(proto, ".txt")}"'
            return resp

        # ---- Accounts ----

        @app.get("/api/me")
        @require_auth
        def api_me():
            return jsonify(public_user(current_user()))

        @app.get("/api/users")
        @require_admin
        def api_users():
            return jsonify([public_user(u) for u in users()])

        @app.post("/api/users")
        @require_admin
        @serialized
        def api_user_add():
            data = request.json or {}
            name = re.sub(r"[^A-Za-z0-9_.-]", "", (data.get("username") or "").strip())[:32]
            password = data.get("password") or ""
            role = data.get("role") if data.get("role") in ("admin", "user") else "user"
            if not name or len(password) < 8:
                return jsonify({"error": "A username and a password of at least 8 characters are required."}), 400
            if find_user_by_name(name):
                return jsonify({"error": "That username is already taken."}), 409
            all_users = users()
            all_users.append({"id": secrets.token_hex(8), "username": name, "role": role,
                              "email": (data.get("email") or "").strip()[:120],
                              "pw_source": "panel", "pw_ver": 0, **hash_pw(password)})
            save(USERS, all_users)
            return jsonify({"ok": True})

        @app.patch("/api/users/<uid>")
        @require_admin
        @serialized
        def api_user_edit(uid):
            data = request.json or {}
            all_users = users()
            target = next((u for u in all_users if u["id"] == uid), None)
            if not target: abort(404)
            me = current_user()
            # The superadmin is the account that can always get back in: only it may
            # change itself, and its role is fixed.
            if target["role"] == "superadmin" and me["id"] != target["id"]:
                return jsonify({"error": "Only the main administrator can change this account."}), 403
            if target["role"] == "admin" and me["role"] != "superadmin" and me["id"] != target["id"]:
                return jsonify({"error": "Only the main administrator can change another administrator."}), 403
            if "role" in data and target["role"] != "superadmin":
                if data["role"] not in ("admin", "user"):
                    return jsonify({"error": "Unknown role."}), 400
                target["role"] = data["role"]
            if "email" in data:
                target["email"] = (data.get("email") or "").strip()[:120]
            if data.get("password"):
                if len(data["password"]) < 8:
                    return jsonify({"error": "The password must be at least 8 characters."}), 400
                set_password(target, data["password"])
            save(USERS, all_users)
            return jsonify({"ok": True})

        @app.delete("/api/users/<uid>")
        @require_admin
        @serialized
        def api_user_del(uid):
            all_users = users()
            target = next((u for u in all_users if u["id"] == uid), None)
            if not target: abort(404)
            if target["role"] == "superadmin":
                return jsonify({"error": "The main administrator cannot be removed."}), 403
            if target["id"] == session.get("uid"):
                return jsonify({"error": "You cannot remove your own account."}), 400
            if target["role"] == "admin" and current_user()["role"] != "superadmin":
                return jsonify({"error": "Only the main administrator can remove another administrator."}), 403
            save(USERS, [u for u in all_users if u["id"] != uid])
            return ("", 204)

        @app.get("/api/email")
        @require_admin
        def api_email_get():
            return jsonify({"smtp": public_smtp(smtp_conf()), "mailboxes": mailcow_mailboxes()})

        @app.put("/api/email")
        @require_admin
        @serialized
        def api_email_put():
            data = request.json or {}
            current = smtp_conf()
            conf = {
                "host": (data.get("host") or "").strip()[:200],
                "port": int(data.get("port") or 587),
                "security": data.get("security") if data.get("security") in ("starttls", "ssl", "none") else "starttls",
                "username": (data.get("username") or "").strip()[:200],
                "sender": (data.get("sender") or "").strip()[:200],
                # An omitted password keeps the stored one — the UI never sees it,
                # so it cannot send it back.
                "password": data.get("password") if data.get("password") else current.get("password", ""),
            }
            save(SMTP_CONF, conf)
            return jsonify({"ok": True, "smtp": public_smtp(conf)})

        @app.post("/api/email/test")
        @require_admin
        def api_email_test():
            me = current_user()
            target = (request.json or {}).get("to") or me.get("email")
            if not target:
                return jsonify({"error": "Add an e-mail address to your account first."}), 400
            if not send_mail(target, "Gryonix VPN test", "Your VPN panel can send e-mail."):
                return jsonify({"error": "Sending failed. Check the server, port and credentials."}), 502
            return jsonify({"ok": True})

        @app.post("/forgot")
        @serialized
        def forgot():
            ip = client_ip()
            # Throttled like the login form: this endpoint is unauthenticated.
            if rate_limited("forgot", ip):
                return jsonify({"error": "Too many attempts. Please wait a few minutes."}), 429
            note_fail("forgot", ip)
            wanted = ((request.json or {}).get("username") or "").strip()
            user = find_user_by_name(wanted) or next(
                (u for u in users() if u.get("email", "").lower() == wanted.lower() and u.get("email")), None)
            if user and user.get("email"):
                token = issue_reset(user)
                # The link is built from the panel's own configured hostname, never
                # from the Host header: a spoofed Host must not steer a valid reset
                # token to an attacker's domain. WG_HOST is the vhost Caddy serves
                # this panel on (and the upstream speaks plain HTTP behind the
                # proxy, so url_root would also get the scheme wrong).
                link = "https://" + WG_HOST + "/reset?token=" + token
                send_mail(user["email"], "Reset your VPN panel password",
                          "Someone asked to reset the password for your VPN panel account "
                          f"({user['username']}).\n\nOpen this link within the hour to choose a new one:\n"
                          f"{link}\n\nIf that was not you, ignore this message — nothing has changed.")
            # Always the same answer: whether an account or a mailbox exists is not
            # something a stranger gets to find out.
            return jsonify({"ok": True})

        @app.get("/reset")
        def reset_page():
            return send_file("/app/reset.html")

        @app.post("/reset")
        @serialized
        def reset_apply():
            data = request.json or {}
            password = data.get("password") or ""
            if len(password) < 8:
                return jsonify({"error": "The password must be at least 8 characters."}), 400
            user = consume_reset(data.get("token"))
            if not user:
                return jsonify({"error": "This link has expired. Ask for a new one."}), 400
            all_users = users()
            for u in all_users:
                if u["id"] == user["id"]:
                    set_password(u, password)
            save(USERS, all_users)
            # Whoever holds an older session for this account is signed out, which is
            # the point of a reset asked for by someone who lost the password.
            return jsonify({"ok": True})

        @app.post("/api/account/password")
        @require_auth
        @serialized
        def api_own_password():
            data = request.json or {}
            me = current_user()
            if not verify_pw(data.get("current") or "", me):
                return jsonify({"error": "The current password is wrong."}), 403
            new = data.get("password") or ""
            if len(new) < 8:
                return jsonify({"error": "The password must be at least 8 characters."}), 400
            all_users = users()
            for u in all_users:
                if u["id"] == me["id"]:
                    set_password(u, new)
                    # The session doing the changing carries on; every other one that
                    # was opened with the old password stops here.
                    session["pv"] = u["pw_ver"]
            save(USERS, all_users)
            return jsonify({"ok": True})

        @app.get("/api/<proto>/clients/<cid>/qr")
        @require_auth
        def api_qr(proto, cid):
            if proto not in HANDLERS: abort(404)
            if not owns(proto, cid): abort(403)
            png = subprocess.run(["qrencode", "-t", "PNG", "-m", "1", "-s", "6", "-o", "-"],
                                 input=HANDLERS[proto][3](cid).encode(), capture_output=True).stdout
            return Response(png, mimetype="image/png")

        if __name__ == "__main__":
            svc = load(f"{DATA}/services.json", {"services": []})
            if any(s.get("id") == "wireguard" for s in svc.get("services", [])):
                ensure_server(); wg_up(ensure_server())
            app.run(host="0.0.0.0", port=80)
        """.trimIndent()

    val loginHTML: String = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Gryonix VPN</title><style>
        @NEUTRALCSS@
        body{display:grid;place-items:center;padding:24px}
        .card{width:100%;max-width:360px;padding:34px 30px;margin:0;text-align:left}
        h1{margin-bottom:6px}
        p.sub{margin:6px 0 26px;font-size:13px;color:var(--t2)}
        p.sub:last-child{margin:18px 0 0}
        .tg{position:fixed;top:20px;right:20px}
        </style></head><body>
        <div class="tg" id="tg" role="button" tabindex="0" data-ic="theme"></div>
        <form class="card" id="f" autocomplete="on">
          <h1 class="wm"><i>Gryonix</i><b>VPN</b></h1><p class="sub" id="sub"></p>
          <input class="field" id="u" name="username" autocomplete="username" autocapitalize="none" autocorrect="off">
          <input class="field" id="p" name="password" type="password" autocomplete="current-password">
          <div class="err" id="err"></div>
          <button class="btn" id="go" type="submit"></button>
          <p class="sub"><a href="#" id="fp" style="color:inherit"></a></p>
        </form>
        <script>
        @I18NJS@
        @ICONSJS@
        icons();
        var root=document.documentElement;function dark(){var t=root.getAttribute('data-theme');return t?t==='dark':matchMedia('(prefers-color-scheme:dark)').matches}
        document.getElementById('tg').onclick=function(){root.setAttribute('data-theme',dark()?'light':'dark')};
        document.getElementById('sub').textContent=t('subtitle');
        document.getElementById('u').placeholder=t('user');
        document.getElementById('p').placeholder=t('pass');
        document.getElementById('go').textContent=t('signin');
        var f=document.getElementById('f'),go=document.getElementById('go'),err=document.getElementById('err');
        f.addEventListener('submit',function(e){e.preventDefault();err.textContent='';go.disabled=true;go.textContent=t('signingin');
          fetch('login',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},body:JSON.stringify({username:document.getElementById('u').value,password:document.getElementById('p').value})})
          .then(function(r){if(r.ok){location.href='.';return}go.disabled=false;go.textContent=t('signin');err.textContent=r.status===429?t('toomany'):t('wrong')},
                function(){go.disabled=false;go.textContent=t('signin');err.textContent=t('neterr')})});
        // Password recovery. The answer is deliberately the same whether
        // or not the account exists, so the message here is neutral too.
        document.getElementById('fp').textContent=t('forgot');
        document.getElementById('fp').onclick=function(e){e.preventDefault();
          var who=document.getElementById('u').value.trim();
          if(!who){err.textContent=t('entername');return}
          fetch('forgot',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},
            body:JSON.stringify({username:who})})
          .then(function(r){err.textContent=r.status===429?t('toomany'):t('resetsent')},
                function(){err.textContent=t('neterr')})};
        </script></body></html>
        """.trimIndent()
            .embedding("NEUTRALCSS" to neutralCSS, "I18NJS" to i18nJS, "ICONSJS" to iconsJS)

    val resetHTML: String = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Gryonix VPN</title><style>
        @NEUTRALCSS@
        body{display:grid;place-items:center;padding:24px}
        .card{width:100%;max-width:360px;padding:34px 30px;margin:0;text-align:left}
        h1{margin-bottom:6px}
        p.sub{margin:6px 0 26px;font-size:13px;color:var(--t2)}
        .tg{position:fixed;top:20px;right:20px}
        </style></head><body>
        <div class="tg" id="tg" role="button" tabindex="0" data-ic="theme"></div>
        <form class="card" id="f">
          <h1 class="wm"><i>Gryonix</i><b>VPN</b></h1><p class="sub" id="sub"></p>
          <input class="field" id="p" type="password" autocomplete="new-password">
          <input class="field" id="p2" type="password" autocomplete="new-password">
          <div class="err" id="err"></div>
          <button class="btn" id="go" type="submit"></button>
        </form>
        <script>
        @I18NJS@
        @ICONSJS@
        icons();
        var root=document.documentElement;function dark(){var t=root.getAttribute('data-theme');return t?t==='dark':matchMedia('(prefers-color-scheme:dark)').matches}
        document.getElementById('tg').onclick=function(){root.setAttribute('data-theme',dark()?'light':'dark')};
        document.getElementById('sub').textContent=t('newpass');
        document.getElementById('p').placeholder=t('pass');
        document.getElementById('p2').placeholder=t('passagain');
        document.getElementById('go').textContent=t('save');
        var f=document.getElementById('f'),go=document.getElementById('go'),err=document.getElementById('err');
        function token(){var m=location.search.match(/[?&]token=([^&]+)/);return m?decodeURIComponent(m[1]):''}
        f.addEventListener('submit',function(e){e.preventDefault();err.textContent='';
          var a=document.getElementById('p').value,b=document.getElementById('p2').value;
          if(a!==b){err.textContent=t('nomatch');return}
          if(a.length<8){err.textContent=t('tooshort');return}
          go.disabled=true;
          fetch('reset',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},
            body:JSON.stringify({token:token(),password:a})})
          .then(function(r){if(r.ok){location.href='login';return}go.disabled=false;
            r.json().then(function(d){err.textContent=(d&&d.error)||t('reqfail')},function(){err.textContent=t('reqfail')})},
            function(){go.disabled=false;err.textContent=t('neterr')})});
        </script></body></html>
        """.trimIndent()
            .embedding("NEUTRALCSS" to neutralCSS, "I18NJS" to i18nJS, "ICONSJS" to iconsJS)

    val indexHTML: String = """
        <!doctype html><html lang="en"><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1"><title>Gryonix VPN</title><style>
        @NEUTRALCSS@
        .wrap{max-width:920px;margin:0 auto;padding:0 22px 96px}
        header{display:flex;align-items:center;gap:14px;padding:22px 0;margin-bottom:10px;border-bottom:1px solid var(--bd)}
        header p{margin:3px 0 0;font-size:12px;color:var(--t2)}
        .sp{flex:1}
        .lbl{font-size:12px;font-weight:600;text-transform:uppercase;letter-spacing:.06em;color:var(--t2);margin:38px 2px 14px}
        .row{display:flex;align-items:center;gap:13px;padding:18px 20px;background:var(--sf2);border-bottom:1px solid var(--bd)}
        .ic{width:8px;height:8px;border-radius:50%;flex:none;background:var(--ok)}
        .row h3{margin:0;font-size:14px;font-weight:600}
        .row .ep{margin:4px 0 0;font-size:12px;color:var(--t2);font-variant-numeric:tabular-nums}
        .pill{margin-left:auto;font-size:11.5px;font-weight:500;color:var(--t2)}
        .cli{display:flex;align-items:center;gap:12px;padding:14px 20px;border-bottom:1px solid var(--bd);min-height:62px}
        .cli:last-child{border-bottom:0}
        .cli b{font-weight:530;font-size:13.5px}
        .cli span{color:var(--t2);font-size:12px;margin-left:10px;font-variant-numeric:tabular-nums}
        .cli .a{margin-left:auto;display:flex;gap:9px;align-items:center}
        .add{display:flex;align-items:center;gap:9px;width:100%;text-align:left;font:inherit;font-size:13.5px;font-weight:530;color:var(--t2);background:transparent;border:0;border-top:1px solid var(--bd);padding:16px 20px;cursor:pointer}
        .add svg{width:15px;height:15px}
        .add:hover{color:var(--tx);background:var(--sf2)}
        .ro{padding:16px 20px;font-size:12.5px;color:var(--t2);line-height:1.5}
        .nb{border-bottom:1px solid var(--bd)}
        .qr{width:200px;height:200px;display:block;margin:0 auto 18px;background:#fff;border-radius:12px;padding:11px}
        .empty{color:var(--t2);text-align:center;padding:48px 0;font-size:13.5px}
        </style></head><body><div class="wrap">
        <header><div><h1 class="wm"><i>Gryonix</i><b>VPN</b></h1><p id="host">protected</p></div><div class="sp"></div><div class="tg" id="out" role="button" tabindex="0" data-ic="exit"></div><div class="tg" id="tg" role="button" tabindex="0" data-ic="theme"></div></header>
        <div class="lbl" id="lbl">VPN services</div><div id="list"><div class="empty" id="loading">Loading…</div></div>
        <div id="usersec" style="display:none"><div class="lbl" id="ulbl">Accounts</div><div id="users"></div>
        <div class="lbl" id="mlbl">E-mail</div><div class="card" id="mailcard">
          <div class="cli"><b id="msender"></b><span id="mstate"></span><div class="a"><button class="mini" id="medit" data-ic="pencil"></button></div></div>
        </div></div></div>
        <div class="scrim" id="qr"><div class="sheet"><h2 id="qrn">client</h2><img class="qr" id="qri" alt="QR" width="200" height="200"><div class="conf" id="qrt"></div><button class="btn" id="qrdl"></button><button class="btn g" id="qrclose" onclick="hide()"></button></div></div>
        <div class="scrim" id="add"><div class="sheet"><h2 id="addt"></h2><input class="field" id="addn"><button class="btn" id="addgo"></button><button class="btn g" id="addcancel" onclick="hide()"></button></div></div>
        <div class="scrim" id="au"><div class="sheet"><h2 id="aut"></h2><input class="field" id="aun"><input class="field" id="aup" type="password"><select class="field" id="aur"><option value="user"></option><option value="admin"></option></select><button class="btn" id="augo"></button><button class="btn g" id="aucancel" onclick="hide()"></button></div></div>
        <div class="scrim" id="ms"><div class="sheet"><h2 id="mst"></h2>
          <select class="field" id="mbox" style="display:none"></select>
          <div id="mhint" class="conf" style="display:none"></div>
          <input class="field" id="mhost"><input class="field" id="mport" inputmode="numeric">
          <select class="field" id="msec"><option value="starttls">STARTTLS</option><option value="ssl">SSL/TLS</option><option value="none">—</option></select>
          <input class="field" id="muser"><input class="field" id="mpass" type="password"><input class="field" id="mfrom">
          <button class="btn" id="msgo"></button><button class="btn g" id="mstest"></button><button class="btn g" id="mscancel" onclick="hide()"></button></div></div>
        <script>
        @I18NJS@
        @ICONSJS@
        icons();
        var root=document.documentElement;function dark(){var t2=root.getAttribute('data-theme');return t2?t2==='dark':matchMedia('(prefers-color-scheme:dark)').matches}
        document.getElementById('tg').onclick=function(){root.setAttribute('data-theme',dark()?'light':'dark')};
        document.getElementById('out').onclick=function(){fetch('logout',{method:'POST',headers:{'X-Gryonix-Auth':'1'}}).then(function(){location.href='login'},function(){location.href='login'})};
        document.getElementById('host').textContent=location.hostname+' · '+t('protected');
        document.getElementById('lbl').textContent=t('services');
        document.getElementById('loading').textContent=t('loading');
        document.getElementById('qrdl').textContent=t('download');
        document.getElementById('qrclose').textContent=t('close');
        document.getElementById('addt').textContent=t('newc');
        document.getElementById('addn').placeholder=t('nameph');
        document.getElementById('addgo').textContent=t('create');
        document.getElementById('addcancel').textContent=t('cancel');
        // Quotes too, not just the three characters that matter in a text node:
        // nearly every use below is inside an ATTRIBUTE, where an unescaped quote ends
        // the attribute and the rest of the name is markup.
        function esc(s){return String(s).replace(/[&<>"']/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]})}
        function hide(){document.querySelectorAll('.scrim').forEach(function(s){s.classList.remove('show')})}
        document.querySelectorAll('.scrim').forEach(function(s){s.addEventListener('click',function(e){if(e.target===s)hide()})});
        var SVC=[],MAN=[],NOQR=[],addProto=null;
        function ext(p){return p==='openvpn'?'.ovpn':(p==='wireguard'||p==='amneziawg')?'.conf':'.txt'}
        function load(){fetch('api/services').then(function(r){return r.json()}).then(function(d){SVC=d.services||[];MAN=d.manageable||[];NOQR=d.noqr||[];render()})}
        // The client names the QR sheet shows, kept beside the markup rather than
        // inside it. An HTML attribute that carries a JS string literal is two nested
        // contexts, and escaping cannot serve both: the browser un-escapes the
        // attribute BEFORE JavaScript parses it, so an entity for a quote is a quote
        // again by the time it matters. The names never enter that context now — only
        // the ids do, and those are hex or a validated certificate name.
        var NAMES={};
        function render(){var el=document.getElementById('list');if(!SVC.length){el.innerHTML='<div class="empty">'+t('empty')+'</div>';return}
          Promise.all(SVC.map(function(s){return MAN.indexOf(s.id)>=0?fetch('api/'+s.id+'/clients').then(function(r){return r.json()}).catch(function(){return[]}):Promise.resolve(null)})).then(function(clis){
          el.innerHTML=SVC.map(function(s,i){var body='';
            if(MAN.indexOf(s.id)>=0){var cs=clis[i]||[];body=cs.map(function(c){NAMES[s.id+'/'+c.id]=c.name;return '<div class="cli"><b>'+esc(c.name)+'</b><span>'+esc(c.detail||'')+'</span><div class="a">'
              +'<button class="mini pri" title="QR" aria-label="QR" onclick="showQR(\''+s.id+'\',\''+c.id+'\')">'+ic('qr')+'</button>'
              +'<a class="mini" href="api/'+s.id+'/clients/'+c.id+'/config?dl=1" download title="'+t('download')+'" aria-label="'+t('download')+'">'+ic('dl')+'</a>'
              +'<button class="mini dgr" title="'+t('removeq')+'" aria-label="'+t('removeq')+'" onclick="del(\''+s.id+'\',\''+c.id+'\')">'+ic('trash')+'</button>'
              +'</div></div>'}).join('')+'<button class="add" onclick="openAdd(\''+s.id+'\')">'+ic('plus')+t('add')+'</button>';}
            else{body='<div class="ro">'+esc(s.endpoint||'')+' — '+t('soon')+'</div>';}
            // Every protocol but plain WireGuard says so on its own card: its
            // clients reach the internet but not the admin panels, and without
            // the line here that ends at a login form that just will not load.
            var note=s.id==='wireguard'?'':'<div class="ro nb">'+t('wgonly')+'</div>';
            return '<div class="card"><div class="row"><div class="ic"></div><div><h3>'+esc(s.name)+'</h3><p class="ep">'+esc(s.endpoint||'')+'</p></div><span class="pill">'+t('running')+'</span></div>'+note+body+'</div>'}).join('')})}
        function openAdd(proto){addProto=proto;document.getElementById('addn').value='';document.getElementById('add').classList.add('show');setTimeout(function(){document.getElementById('addn').focus()},60)}
        function showErr(r){return r.json().then(function(d){alert((d&&d.error)||t('reqfail'))},function(){alert(t('reqfail'))})}
        document.getElementById('addgo').onclick=function(){var n=document.getElementById('addn').value.trim()||'client';var b=this;b.disabled=true;
          fetch('api/'+addProto+'/clients',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},body:JSON.stringify({name:n})}).then(function(r){b.disabled=false;if(r.ok){hide();load()}else{showErr(r)}},function(){b.disabled=false;alert(t('neterr'))})}
        function del(proto,id){if(!confirm(t('removeq')))return;fetch('api/'+proto+'/clients/'+id,{method:'DELETE',headers:{'X-Gryonix-Auth':'1'}}).then(function(r){if(r.ok){load()}else{showErr(r)}},function(){alert(t('neterr'))})}
        function showQR(proto,id){var name=NAMES[proto+'/'+id]||id;fetch('api/'+proto+'/clients/'+id+'/config').then(function(r){if(!r.ok){return showErr(r).then(function(){throw 0})}return r.text()}).then(function(t){
          document.getElementById('qrn').textContent=name;document.getElementById('qrt').textContent=t;
          var img=document.getElementById('qri');
          if(NOQR.indexOf(proto)>=0){img.style.display='none';img.removeAttribute('src')}
          else{img.style.display='';img.src='api/'+proto+'/clients/'+id+'/qr'}
          document.getElementById('qrdl').onclick=function(){location.href='api/'+proto+'/clients/'+id+'/config?dl=1'};
          document.getElementById('qr').classList.add('show')}).catch(function(){})}
        // Accounts: only administrators get the section at all; the server
        // enforces the same rule, this just keeps the UI honest.
        var ME=null;
        function loadMe(){return fetch('api/me').then(function(r){return r.json()}).then(function(m){ME=m;
          if(m.role==='superadmin'||m.role==='admin'){document.getElementById('usersec').style.display='';loadUsers();loadMail()}})}
        function loadUsers(){fetch('api/users').then(function(r){return r.ok?r.json():[]}).then(function(us){
          var el=document.getElementById('users');var h='<div class="card">';
          us.forEach(function(u){
            h+='<div class="cli"><b>'+esc(u.username)+'</b><span>'+esc(roleName(u.role))+'</span><div class="a">';
            if(u.role!=='superadmin'&&u.id!==ME.id){h+='<button class="mini dgr" title="'+t('removeuserq')+'" aria-label="'+t('removeuserq')+'" onclick="delUser(\''+u.id+'\')">'+ic('trash')+'</button>'}
            h+='</div></div>'});
          h+='<button class="add" onclick="openAddUser()">'+ic('plus')+t('adduser')+'</button></div>';
          el.innerHTML=h})}
        function roleName(r){return r==='superadmin'?t('rsuper'):r==='admin'?t('radmin'):t('ruser')}
        function openAddUser(){document.getElementById('aun').value='';document.getElementById('aup').value='';
          document.getElementById('au').classList.add('show')}
        function delUser(id){if(!confirm(t('removeuserq')))return;
          fetch('api/users/'+id,{method:'DELETE',headers:{'X-Gryonix-Auth':'1'}}).then(function(r){
            if(r.ok){loadUsers()}else{showErr(r)}},function(){alert(t('neterr'))})}
        document.getElementById('aut').textContent=t('newuser');
        document.getElementById('aun').placeholder=t('user');
        document.getElementById('aup').placeholder=t('pass');
        document.getElementById('aur').options[0].textContent=t('ruser');
        document.getElementById('aur').options[1].textContent=t('radmin');
        document.getElementById('augo').textContent=t('create');
        document.getElementById('aucancel').textContent=t('cancel');
        document.getElementById('augo').onclick=function(){var b=this;b.disabled=true;
          fetch('api/users',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},
            body:JSON.stringify({username:document.getElementById('aun').value,
                                 password:document.getElementById('aup').value,
                                 role:document.getElementById('aur').value})})
            .then(function(r){b.disabled=false;if(r.ok){hide();loadUsers()}else{showErr(r)}},
                  function(){b.disabled=false;alert(t('neterr'))})};
        document.getElementById('ulbl').textContent=t('accounts');
        // Mail settings: the sender can be picked from mailcow's mailboxes
        // when mailcow runs here; its password is still typed, because mailcow
        // stores only hashes.
        document.getElementById('mlbl').textContent=t('email');
        document.getElementById('mst').textContent=t('emailsetup');
        document.getElementById('mhost').placeholder=t('smtphost');
        document.getElementById('mport').placeholder=t('smtpport');
        document.getElementById('muser').placeholder=t('user');
        document.getElementById('mpass').placeholder=t('pass');
        document.getElementById('mfrom').placeholder=t('sender');
        document.getElementById('msgo').textContent=t('save');
        document.getElementById('mstest').textContent=t('sendtest');
        document.getElementById('mscancel').textContent=t('cancel');
        function loadMail(){fetch('api/email').then(function(r){return r.ok?r.json():null}).then(function(d){
          if(!d)return;MAIL=d;var s=d.smtp||{};
          document.getElementById('msender').textContent=s.sender||t('notset');
          document.getElementById('mstate').textContent=s.host?s.host+':'+s.port:t('nosmtp');
          document.getElementById('mhost').value=s.host||'';document.getElementById('mport').value=s.port||587;
          document.getElementById('msec').value=s.security||'starttls';
          document.getElementById('muser').value=s.username||'';document.getElementById('mfrom').value=s.sender||'';
          var sel=document.getElementById('mbox'),hint=document.getElementById('mhint');
          if(d.mailboxes&&d.mailboxes.length){sel.style.display='';hint.style.display='none';
            sel.innerHTML='<option value="">'+t('pickbox')+'</option>'+d.mailboxes.map(function(m){
              return '<option value="'+esc(m)+'">'+esc(m)+'</option>'}).join('');
            sel.onchange=function(){if(!sel.value)return;
              document.getElementById('mfrom').value=sel.value;document.getElementById('muser').value=sel.value;
              if(!document.getElementById('mhost').value){document.getElementById('mhost').value='host.docker.internal';
                document.getElementById('mport').value=587}}}
          else{sel.style.display='none';hint.style.display='';hint.textContent=t('nomailboxes')}})}
        var MAIL=null;
        document.getElementById('medit').onclick=function(){document.getElementById('mpass').value='';
          document.getElementById('ms').classList.add('show')};
        function mailBody(){var b={host:document.getElementById('mhost').value,port:document.getElementById('mport').value,
          security:document.getElementById('msec').value,username:document.getElementById('muser').value,
          sender:document.getElementById('mfrom').value};
          var pw=document.getElementById('mpass').value;if(pw)b.password=pw;return b}
        document.getElementById('msgo').onclick=function(){var b=this;b.disabled=true;
          fetch('api/email',{method:'PUT',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},
            body:JSON.stringify(mailBody())}).then(function(r){b.disabled=false;
              if(r.ok){hide();loadMail()}else{showErr(r)}},function(){b.disabled=false;alert(t('neterr'))})};
        document.getElementById('mstest').onclick=function(){var b=this;b.disabled=true;
          fetch('api/email',{method:'PUT',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},
            body:JSON.stringify(mailBody())})
          .then(function(){return fetch('api/email/test',{method:'POST',headers:{'Content-Type':'application/json','X-Gryonix-Auth':'1'},body:'{}'})})
          .then(function(r){b.disabled=false;if(r.ok){alert(t('testsent'))}else{showErr(r)}},
                function(){b.disabled=false;alert(t('neterr'))})};
        load();loadMe();
        </script></body></html>
        """.trimIndent()
            .embedding("NEUTRALCSS" to neutralCSS, "I18NJS" to i18nJS, "ICONSJS" to iconsJS)
}

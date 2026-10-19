package com.skaymer.gryonixnexus.recipe

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

object L10nScripts {
    // ---------------------------------------------- Script header
    fun headerRunLine(l: AppLanguage, script: String): String = l.pick(mapOf(
        EN to "Run: sudo bash $script",
        DE to "Start: sudo bash $script",
        FR to "Lancement : sudo bash $script",
        ES to "Ejecución: sudo bash $script",
        RU to "Запуск: sudo bash $script",
        UK to "Запуск: sudo bash $script",
        IT to "Avvio: sudo bash $script",
        JA to "実行方法: sudo bash $script",
        ZH to "运行：sudo bash $script"
    ))
    fun headerSelfContained(l: AppLanguage): String = l.pick(mapOf(
        EN to "The script is self-contained and idempotent: packages, configs (with backups), firewall, services — all in one run; re-running it is safe.",
        DE to "Das Skript ist eigenständig und idempotent: Pakete, Konfigurationen (mit Backup), Firewall, Dienste — alles in einem Lauf; ein erneuter Lauf ist sicher.",
        FR to "Le script est autonome et idempotent : paquets, configurations (avec sauvegarde), firewall, services — tout en une seule exécution ; le relancer est sans risque.",
        ES to "El script es autónomo e idempotente: paquetes, configuraciones (con copia de seguridad), firewall, servicios — todo en una sola ejecución; volver a ejecutarlo es seguro.",
        RU to "Скрипт самодостаточен и идемпотентен: пакеты, конфиги (с бэкапом), firewall, сервисы — всё в одном запуске; повторный запуск безопасен.",
        UK to "Скрипт самодостатній та ідемпотентний: пакети, конфіги (з бекапом), firewall, сервіси — все за один запуск; повторний запуск безпечний.",
        IT to "Lo script è autonomo e idempotente: pacchetti, configurazioni (con backup), firewall, servizi — tutto in un unico avvio; rieseguirlo è sicuro.",
        JA to "このスクリプトは自己完結型かつ冪等です: パッケージ、設定 (バックアップ付き)、firewall、サービスを一度の実行で構成し、再実行しても安全です。",
        ZH to "该脚本自包含且幂等：软件包、配置（含备份）、firewall、服务一次运行全部完成；重复运行是安全的。"
    ))
    fun headerDistributionPinned(l: AppLanguage): String = l.pick(mapOf(
        EN to "The distribution was pinned at generation time in the app — here it is only verified.",
        DE to "Die Distribution wurde bei der Generierung in der App festgelegt — hier wird sie nur überprüft.",
        FR to "La distribution a été fixée lors de la génération dans l'application — ici elle est seulement vérifiée.",
        ES to "La distribución se fijó al generar el script en la aplicación — aquí solo se verifica.",
        RU to "Дистрибутив зафиксирован при генерации в приложении — только сверяем.",
        UK to "Дистрибутив зафіксовано під час генерації в застосунку — тут лише звіряємо.",
        IT to "La distribuzione è stata fissata alla generazione nell'app — qui viene solo verificata.",
        JA to "ディストリビューションはアプリでの生成時に固定済みです — ここでは照合のみ行います。",
        ZH to "发行版已在应用生成脚本时固定 — 此处仅做核对。"
    ))

    fun errorPrefix(l: AppLanguage): String = l.pick(mapOf(
        EN to "ERROR",
        DE to "FEHLER",
        FR to "ERREUR",
        ES to "ERROR",
        RU to "ОШИБКА",
        UK to "ПОМИЛКА",
        IT to "ERRORE",
        JA to "エラー",
        ZH to "错误"
    ))
    fun rootRequired(l: AppLanguage, script: String): String = l.pick(mapOf(
        EN to "root privileges required: sudo bash $script",
        DE to "Root-Rechte erforderlich: sudo bash $script",
        FR to "droits root requis : sudo bash $script",
        ES to "se requieren privilegios de root: sudo bash $script",
        RU to "нужны права root: sudo bash $script",
        UK to "потрібні права root: sudo bash $script",
        IT to "servono privilegi root: sudo bash $script",
        JA to "root 権限が必要です: sudo bash $script",
        ZH to "需要 root 权限：sudo bash $script"
    ))
    fun osReleaseMissing(l: AppLanguage): String = l.pick(mapOf(
        EN to "/etc/os-release not found — unsupported OS",
        DE to "/etc/os-release nicht gefunden — nicht unterstütztes Betriebssystem",
        FR to "/etc/os-release introuvable — OS non pris en charge",
        ES to "/etc/os-release no encontrado — sistema operativo no compatible",
        RU to "не найден /etc/os-release — неподдерживаемая ОС",
        UK to "не знайдено /etc/os-release — непідтримувана ОС",
        IT to "/etc/os-release non trovato — sistema operativo non supportato",
        JA to "/etc/os-release が見つかりません — サポートされていない OS です",
        ZH to "未找到 /etc/os-release — 不受支持的操作系统"
    ))

    /** Default value inside a bash `${VAR:-…}` expansion */
    fun unknownValue(l: AppLanguage): String = l.pick(mapOf(
        EN to "unknown",
        DE to "unbekannt",
        FR to "inconnu",
        ES to "desconocido",
        RU to "неизвестно",
        UK to "невідомо",
        IT to "sconosciuto",
        JA to "不明",
        ZH to "未知"
    ))

    /** `detected` is a bash fragment (e.g */
    fun wrongDistribution(l: AppLanguage, expected: String, detected: String): String = l.pick(mapOf(
        EN to "the script was generated for $expected, detected: $detected",
        DE to "das Skript wurde für $expected generiert, erkannt: $detected",
        FR to "le script a été généré pour $expected, détecté : $detected",
        ES to "el script se generó para $expected, detectado: $detected",
        RU to "скрипт сгенерирован для $expected, обнаружено: $detected",
        UK to "скрипт згенеровано для $expected, виявлено: $detected",
        IT to "lo script è stato generato per $expected, rilevato: $detected",
        JA to "スクリプトは $expected 向けに生成されています。検出: $detected",
        ZH to "脚本为 $expected 生成，检测到：$detected"
    ))
    fun distributionDerivative(l: AppLanguage, detected: String, base: String): String = l.pick(mapOf(
        EN to "$detected is a $base derivative — continuing",
        DE to "$detected ist eine $base-Ableitung — wird fortgesetzt",
        FR to "$detected est un dérivé de $base — poursuite",
        ES to "$detected es un derivado de $base: continuando",
        RU to "$detected — производная от $base, продолжаем",
        UK to "$detected — похідна від $base, продовжуємо",
        IT to "$detected è un derivato di $base — si continua",
        JA to "$detected は $base 派生のため続行します",
        ZH to "$detected 是 $base 衍生版，继续执行"
    ))

    // ---------------------------------------------- DNS pre-check
    fun dnsCheckLog(l: AppLanguage, hostname: String, expectedIP: String): String = l.pick(mapOf(
        EN to "DNS check: $hostname must point to $expectedIP",
        DE to "DNS-Prüfung: $hostname muss auf $expectedIP zeigen",
        FR to "Vérification DNS : $hostname doit pointer vers $expectedIP",
        ES to "Comprobación de DNS: $hostname debe apuntar a $expectedIP",
        RU to "Проверка DNS: $hostname должен указывать на $expectedIP",
        UK to "Перевірка DNS: $hostname має вказувати на $expectedIP",
        IT to "Controllo DNS: $hostname deve puntare a $expectedIP",
        JA to "DNS チェック: $hostname は $expectedIP を指している必要があります",
        ZH to "DNS 检查：$hostname 必须指向 $expectedIP"
    ))

    /** Default value inside a bash `${resolved:-…}` expansion */
    fun nothingValue(l: AppLanguage): String = l.pick(mapOf(
        EN to "nothing",
        DE to "nichts",
        FR to "rien",
        ES to "nada",
        RU to "ничего",
        UK to "нічого",
        IT to "niente",
        JA to "なし",
        ZH to "无"
    ))

    /** `resolved` and `script` are bash fragments passed through verbatim */
    fun dnsMismatch(l: AppLanguage, hostname: String, resolved: String, expectedIP: String, script: String): String = l.pick(mapOf(
        EN to "the A record for $hostname currently points to «$resolved», expected $expectedIP.\nAdd the records from dns-records.txt, wait for DNS to update, and run the script again\n(skip this check: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        DE to "der A-Eintrag für $hostname zeigt derzeit auf «$resolved», erwartet wird $expectedIP.\nFügen Sie die Einträge aus dns-records.txt hinzu, warten Sie auf die DNS-Aktualisierung und starten Sie das Skript erneut\n(Prüfung überspringen: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        FR to "l'enregistrement A de $hostname pointe actuellement vers «$resolved», attendu : $expectedIP.\nAjoutez les enregistrements de dns-records.txt, attendez la mise à jour du DNS et relancez le script\n(ignorer la vérification : GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        ES to "el registro A de $hostname apunta actualmente a «$resolved», se esperaba $expectedIP.\nAñada los registros de dns-records.txt, espere a que el DNS se actualice y vuelva a ejecutar el script\n(omitir la comprobación: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        RU to "A-запись $hostname сейчас указывает на «$resolved», ожидается $expectedIP.\nДобавьте записи из dns-records.txt, дождитесь обновления DNS и запустите скрипт снова\n(пропустить проверку: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        UK to "A-запис $hostname зараз вказує на «$resolved», очікується $expectedIP.\nДодайте записи з dns-records.txt, дочекайтеся оновлення DNS і запустіть скрипт знову\n(пропустити перевірку: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        IT to "il record A di $hostname attualmente punta a «$resolved», atteso $expectedIP.\nAggiungete i record da dns-records.txt, attendete la propagazione del DNS e rieseguite lo script\n(per saltare il controllo: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script).",
        JA to "$hostname の A レコードは現在「$resolved」を指しています。期待値: $expectedIP。\ndns-records.txt のレコードを追加し、DNS の更新を待ってからスクリプトを再実行してください\n(チェックをスキップ: GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script)。",
        ZH to "$hostname 的 A 记录当前指向「$resolved」，期望值为 $expectedIP。\n请添加 dns-records.txt 中的记录，等待 DNS 更新后重新运行脚本\n（跳过检查：GRYONIXNEXUS_SKIP_DNS_CHECK=1 sudo bash $script）。"
    ))

    // ---------------------------------------------- Port pre-flight
    fun portPreflightLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Checking that the ports these services need are free",
        DE to "Prüfen, ob die von diesen Diensten benötigten Ports frei sind",
        FR to "Vérification que les ports requis par ces services sont libres",
        ES to "Comprobando que los puertos que necesitan estos servicios están libres",
        RU to "Проверяем, свободны ли порты, которые нужны этим сервисам",
        UK to "Перевіряємо, чи вільні порти, потрібні цим сервісам",
        IT to "Verifica che le porte richieste da questi servizi siano libere",
        JA to "これらのサービスに必要なポートが空いているか確認しています",
        ZH to "正在检查这些服务所需的端口是否空闲"
    ))

    /** One conflict whose holder docker can name */
    fun portHeldByContainer(l: AppLanguage, service: String, port: String, container: String, project: String): String = l.pick(mapOf(
        EN to "$service: port $port is already used by the container «$container» (compose project «$project»)",
        DE to "$service: Port $port wird bereits vom Container «$container» belegt (Compose-Projekt «$project»)",
        FR to "$service : le port $port est déjà utilisé par le conteneur «$container» (projet compose «$project»)",
        ES to "$service: el puerto $port ya lo usa el contenedor «$container» (proyecto compose «$project»)",
        RU to "$service: порт $port уже занят контейнером «$container» (compose-проект «$project»)",
        UK to "$service: порт $port вже зайнятий контейнером «$container» (compose-проєкт «$project»)",
        IT to "$service: la porta $port è già usata dal container «$container» (progetto compose «$project»)",
        JA to "$service: ポート $port はコンテナ「$container」が使用中です (compose プロジェクト「$project」)",
        ZH to "$service：端口 $port 已被容器「$container」占用（compose 项目「$project」）"
    ))

    fun portHeldByUnknown(l: AppLanguage, service: String, port: String): String = l.pick(mapOf(
        EN to "$service: port $port is already used by something else on this server",
        DE to "$service: Port $port wird bereits von etwas anderem auf diesem Server belegt",
        FR to "$service : le port $port est déjà utilisé par autre chose sur ce serveur",
        ES to "$service: el puerto $port ya lo usa otra cosa en este servidor",
        RU to "$service: порт $port уже занят чем-то другим на этом сервере",
        UK to "$service: порт $port вже зайнятий чимось іншим на цьому сервері",
        IT to "$service: la porta $port è già usata da qualcos'altro su questo server",
        JA to "$service: ポート $port はこのサーバー上の別のものが使用中です",
        ZH to "$service：端口 $port 已被此服务器上的其他程序占用"
    ))

    /** The refusal itself */
    fun portsInUseFail(l: AppLanguage, conflicts: String): String = l.pick(mapOf(
        EN to "these ports are already in use on this server, so nothing was installed:$conflicts\n\nFree them — or remove the service that holds them — and run the script again.\n\nIf one of these is the service itself, already installed on this machine by hand: gryonixNexus does not take over an install it did not make. Back its data up, remove it, and install it again from the app.",
        DE to "diese Ports sind auf diesem Server bereits belegt, deshalb wurde nichts installiert:$conflicts\n\nGeben Sie sie frei — oder entfernen Sie den Dienst, der sie hält — und starten Sie das Skript erneut.\n\nWenn einer davon der Dienst selbst ist, bereits von Hand auf dieser Maschine installiert: gryonixNexus übernimmt keine Installation, die es nicht selbst gemacht hat. Sichern Sie die Daten, entfernen Sie ihn und installieren Sie ihn erneut aus der App.",
        FR to "ces ports sont déjà utilisés sur ce serveur, rien n'a donc été installé :$conflicts\n\nLibérez-les — ou supprimez le service qui les occupe — puis relancez le script.\n\nSi l'un d'eux est le service lui-même, déjà installé à la main sur cette machine : gryonixNexus ne reprend pas une installation qu'il n'a pas faite. Sauvegardez ses données, supprimez-le, puis réinstallez-le depuis l'application.",
        ES to "estos puertos ya están en uso en este servidor, así que no se instaló nada:$conflicts\n\nLibérelos — o elimine el servicio que los ocupa — y vuelva a ejecutar el script.\n\nSi uno de ellos es el propio servicio, ya instalado a mano en esta máquina: gryonixNexus no se hace cargo de una instalación que no hizo. Haga una copia de sus datos, elimínelo e instálelo de nuevo desde la aplicación.",
        RU to "эти порты уже заняты на этом сервере, поэтому ничего не установлено:$conflicts\n\nОсвободите их — или удалите сервис, который их держит — и запустите скрипт снова.\n\nЕсли один из них — сам сервис, уже поставленный на эту машину вручную: gryonixNexus не подхватывает установку, которую делал не он. Сделайте бэкап его данных, удалите его и поставьте заново из приложения.",
        UK to "ці порти вже зайняті на цьому сервері, тому нічого не встановлено:$conflicts\n\nЗвільніть їх — або видаліть сервіс, який їх тримає — і запустіть скрипт знову.\n\nЯкщо один із них — сам сервіс, уже встановлений на цю машину вручну: gryonixNexus не підхоплює встановлення, яке робив не він. Зробіть резервну копію його даних, видаліть його і встановіть заново з застосунку.",
        IT to "queste porte sono già occupate su questo server, quindi non è stato installato nulla:$conflicts\n\nLiberatele — o rimuovete il servizio che le occupa — e rieseguite lo script.\n\nSe uno di questi è il servizio stesso, già installato a mano su questa macchina: gryonixNexus non eredita un'installazione che non ha fatto. Fate un backup dei suoi dati, rimuovetelo e installatelo di nuovo dall'app.",
        JA to "これらのポートはこのサーバーで既に使用されているため、何もインストールされていません:$conflicts\n\n解放するか、占有しているサービスを削除してから、スクリプトを再実行してください。\n\nそのうちの一つがこのマシンに手作業で入れた当のサービスである場合: gryonixNexus は自分が行っていないインストールを引き継ぎません。データをバックアップし、削除してから、アプリから改めてインストールしてください。",
        ZH to "这些端口在此服务器上已被占用，因此未安装任何内容：$conflicts\n\n请释放这些端口，或删除占用它们的服务，然后重新运行脚本。\n\n如果其中之一就是本机上手动安装的该服务：gryonixNexus 不会接管并非由它安装的部署。请备份其数据、将其删除，然后从应用中重新安装。"
    ))

    fun serviceCrashLoopFail(l: AppLanguage, service: String, seconds: Int): String = l.pick(mapOf(
        EN to "$service never held still: over $seconds seconds it kept restarting rather than staying up. Its ports are published, so nothing else would have noticed; the installation stopped here rather than describe a service that never ran.",
        DE to "$service kam nie zur Ruhe: Über $seconds Sekunden startete es immer wieder neu, statt oben zu bleiben. Seine Ports sind veröffentlicht, sonst wäre es niemandem aufgefallen; die Installation wurde hier gestoppt, statt einen Dienst zu beschreiben, der nie lief.",
        FR to "$service ne s'est jamais stabilisé : pendant $seconds secondes il n'a cessé de redémarrer au lieu de rester en place. Ses ports sont publiés, donc rien d'autre ne l'aurait remarqué ; l'installation s'est arrêtée ici plutôt que de décrire un service qui n'a jamais tourné.",
        ES to "$service nunca se quedó quieto: durante $seconds segundos siguió reiniciándose en lugar de mantenerse en marcha. Sus puertos están publicados, así que nada más lo habría notado; la instalación se detuvo aquí en lugar de describir un servicio que nunca funcionó.",
        RU to "$service так и не успокоился: за $seconds секунд он перезапускался снова и снова вместо того, чтобы остаться поднятым. Порты при этом опубликованы, поэтому больше ничто этого бы не заметило; установка остановлена здесь, чтобы не описывать сервис, который ни разу не работал.",
        UK to "$service так і не заспокоївся: за $seconds секунд він перезапускався знову і знову замість того, щоб лишитися піднятим. Порти при цьому опубліковані, тож більше ніщо цього б не помітило; встановлення зупинено тут, щоб не описувати сервіс, який жодного разу не працював.",
        IT to "$service non si è mai fermato: per $seconds secondi ha continuato a riavviarsi invece di restare su. Le sue porte sono pubblicate, quindi nient'altro se ne sarebbe accorto; l'installazione si è fermata qui invece di descrivere un servizio che non ha mai funzionato.",
        JA to "$service は一度も落ち着きませんでした: $seconds 秒にわたり、起動したままにならず再起動を繰り返しました。ポートは公開されているため、他の何もこれに気づきません。一度も動かなかったサービスを説明する代わりに、インストールはここで停止しました。",
        ZH to "$service 从未稳定下来：在 $seconds 秒里它不断重启，而不是保持运行。它的端口已发布，因此其他检查都不会察觉；安装在此停止，而不是去描述一个从未运行过的服务。"
    ))

    fun portsNotPublishedFail(l: AppLanguage, service: String, ports: String): String = l.pick(mapOf(
        EN to "$service started, but without the ports it needs ($ports) — something else on this server took them. The installation stopped here: everything after this point would describe a service that cannot answer.",
        DE to "$service wurde gestartet, aber ohne die benötigten Ports ($ports) — etwas anderes auf diesem Server hat sie belegt. Die Installation wurde hier gestoppt: Alles Weitere würde einen Dienst beschreiben, der nicht antworten kann.",
        FR to "$service a démarré, mais sans les ports dont il a besoin ($ports) — autre chose sur ce serveur les a pris. L'installation s'est arrêtée ici : la suite décrirait un service incapable de répondre.",
        ES to "$service se inició, pero sin los puertos que necesita ($ports): otra cosa en este servidor los ocupó. La instalación se detuvo aquí: todo lo demás describiría un servicio que no puede responder.",
        RU to "$service запустился, но без нужных ему портов ($ports) — их занял кто-то другой на этом сервере. Установка остановлена здесь: всё дальнейшее описывало бы сервис, который не может ответить.",
        UK to "$service запустився, але без потрібних йому портів ($ports) — їх зайняв хтось інший на цьому сервері. Встановлення зупинено тут: усе подальше описувало б сервіс, який не може відповісти.",
        IT to "$service è partito, ma senza le porte che gli servono ($ports): qualcos'altro su questo server le ha occupate. L'installazione si è fermata qui: tutto il resto descriverebbe un servizio che non può rispondere.",
        JA to "$service は起動しましたが、必要なポート ($ports) がありません — このサーバー上の別のものが占有しています。インストールはここで停止しました。これ以降は応答できないサービスの説明になってしまいます。",
        ZH to "$service 已启动，但没有它需要的端口（$ports）——被此服务器上的其他程序占用。安装在此停止：继续下去只会描述一个无法响应的服务。"
    ))

    // ---------------------------------------------- Packages, TLS, configs, DKIM, services
    fun installingPackages(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing packages (non-interactive)",
        DE to "Paketinstallation (nicht interaktiv)",
        FR to "Installation des paquets (non interactive)",
        ES to "Instalación de paquetes (no interactiva)",
        RU to "Установка пакетов (неинтерактивно)",
        UK to "Встановлення пакетів (неінтерактивно)",
        IT to "Installazione dei pacchetti (non interattiva)",
        JA to "パッケージのインストール (非対話)",
        ZH to "安装软件包（非交互式）"
    ))
    fun containerControlWrapperLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing the container control helper for the Server Dashboard",
        DE to "Installation des Container-Steuerungshelfers für das Server-Dashboard",
        FR to "Installation de l’assistant de contrôle des conteneurs pour le tableau de bord du serveur",
        ES to "Instalando el asistente de control de contenedores para el panel del servidor",
        RU to "Установка помощника управления контейнерами для панели сервера",
        UK to "Встановлення помічника керування контейнерами для панелі сервера",
        IT to "Installazione dell’helper di controllo dei container per il pannello del server",
        JA to "サーバーダッシュボード用のコンテナ制御ヘルパーをインストールしています",
        ZH to "正在为服务器仪表板安装容器控制助手"
    ))
    fun backupControlWrapperLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing the backup helper for the Server Dashboard",
        DE to "Installation des Backup-Helfers für das Server-Dashboard",
        FR to "Installation de l’assistant de sauvegarde pour le tableau de bord du serveur",
        ES to "Instalando el asistente de copias de seguridad para el panel del servidor",
        RU to "Установка помощника резервного копирования для панели сервера",
        UK to "Встановлення помічника резервного копіювання для панелі сервера",
        IT to "Installazione dell’helper di backup per il pannello del server",
        JA to "サーバーダッシュボード用のバックアップヘルパーをインストールしています",
        ZH to "正在为服务器仪表板安装备份助手"
    ))
    fun updateControlWrapperLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing the update helper for the Server Dashboard",
        DE to "Installation des Update-Helfers für das Server-Dashboard",
        FR to "Installation de l’assistant de mise à jour pour le tableau de bord du serveur",
        ES to "Instalando el asistente de actualizaciones para el panel del servidor",
        RU to "Установка помощника обновлений для панели сервера",
        UK to "Встановлення помічника оновлень для панелі сервера",
        IT to "Installazione dell’helper di aggiornamento per il pannello del server",
        JA to "サーバーダッシュボード用のアップデートヘルパーをインストールしています",
        ZH to "正在为服务器仪表板安装更新助手"
    ))
    fun uninstallWrapperLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing the uninstall helper for the Server Dashboard",
        DE to "Installation des Deinstallationshelfers für das Server-Dashboard",
        FR to "Installation de l’assistant de désinstallation pour le tableau de bord du serveur",
        ES to "Instalando el asistente de desinstalación para el panel del servidor",
        RU to "Установка помощника удаления для панели сервера",
        UK to "Встановлення помічника видалення для панелі сервера",
        IT to "Installazione dell’helper di disinstallazione per il pannello del server",
        JA to "サーバーダッシュボード用のアンインストールヘルパーをインストールしています",
        ZH to "正在为服务器仪表板安装卸载助手"
    ))
    fun restoreWrapperLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing the restore helper for the Server Dashboard",
        DE to "Installation des Wiederherstellungshelfers für das Server-Dashboard",
        FR to "Installation de l’assistant de restauration pour le tableau de bord du serveur",
        ES to "Instalando el asistente de restauración para el panel del servidor",
        RU to "Установка помощника восстановления для панели сервера",
        UK to "Встановлення помічника відновлення для панелі сервера",
        IT to "Installazione dell’helper di ripristino per il pannello del server",
        JA to "サーバーダッシュボード用の復元ヘルパーをインストールしています",
        ZH to "正在为服务器仪表板安装恢复助手"
    ))
    fun restoreDone(l: AppLanguage): String = l.pick(mapOf(
        EN to "Restore finished.",
        DE to "Wiederherstellung abgeschlossen.",
        FR to "Restauration terminée.",
        ES to "Restauración finalizada.",
        RU to "Восстановление завершено.",
        UK to "Відновлення завершено.",
        IT to "Ripristino completato.",
        JA to "復元が完了しました。",
        ZH to "恢复完成。"
    ))

    fun reportTitle(l: AppLanguage): String = l.pick(mapOf(
        EN to "REPORT",
        DE to "BERICHT",
        FR to "RAPPORT",
        ES to "INFORME",
        RU to "ОТЧЁТ",
        UK to "ЗВІТ",
        IT to "RAPPORTO",
        JA to "レポート",
        ZH to "报告"
    ))
    fun serviceStatusHeader(l: AppLanguage): String = l.pick(mapOf(
        EN to "Service status:",
        DE to "Dienststatus:",
        FR to "État des services :",
        ES to "Estado de los servicios:",
        RU to "Статус сервисов:",
        UK to "Статус сервісів:",
        IT to "Stato dei servizi:",
        JA to "サービスの状態:",
        ZH to "服务状态:"
    ))
    fun ptrReminder(l: AppLanguage, ip: String, hostname: String): String = l.pick(mapOf(
        EN to "PTR at your provider: $ip -> $hostname (critical for deliverability).",
        DE to "PTR beim Provider: $ip -> $hostname (entscheidend für die Zustellbarkeit).",
        FR to "PTR chez votre hébergeur : $ip -> $hostname (crucial pour la délivrabilité).",
        ES to "PTR en su proveedor: $ip -> $hostname (crítico para la entregabilidad).",
        RU to "PTR у провайдера: $ip -> $hostname (критично для доставляемости).",
        UK to "PTR у провайдера: $ip -> $hostname (критично для доставлюваності).",
        IT to "PTR presso il provider: $ip -> $hostname (fondamentale per la deliverability).",
        JA to "プロバイダーで PTR を設定: $ip -> $hostname (到達性に必須)。",
        ZH to "在服务商处设置 PTR：$ip -> $hostname（对送达率至关重要）。"
    ))

    fun purposeMailServer(l: AppLanguage, hostname: String): String = l.pick(mapOf(
        EN to "mail server $hostname in a single run.",
        DE to "Mailserver $hostname in einem Lauf.",
        FR to "serveur mail $hostname en une seule exécution.",
        ES to "servidor de correo $hostname en una sola ejecución.",
        RU to "почтовый сервер $hostname одним запуском.",
        UK to "поштовий сервер $hostname одним запуском.",
        IT to "server di posta $hostname in un unico avvio.",
        JA to "メールサーバー $hostname を一度の実行で構築。",
        ZH to "一次运行完成邮件服务器 $hostname 的搭建。"
    ))
    fun purposeServicesServer(l: AppLanguage, domain: String): String = l.pick(mapOf(
        EN to "self-hosted services for $domain in a single run.",
        DE to "Self-hosted-Dienste für $domain in einem Lauf.",
        FR to "services auto-hébergés pour $domain en une seule exécution.",
        ES to "servicios autoalojados para $domain en una sola ejecución.",
        RU to "self-hosted сервисы для $domain одним запуском.",
        UK to "self-hosted сервіси для $domain одним запуском.",
        IT to "servizi self-hosted per $domain in un unico avvio.",
        JA to "$domain の self-hosted サービスを一度の実行で構築。",
        ZH to "一次运行完成 $domain 的 self-hosted 服务搭建。"
    ))
    fun purposeVPS(l: AppLanguage): String = l.pick(mapOf(
        EN to "VPS — entry point: WireGuard tunnel and mail forwarding to the home server.",
        DE to "VPS — Einstiegspunkt: WireGuard-Tunnel und Mail-Weiterleitung zum Heimserver.",
        FR to "VPS — point d'entrée : tunnel WireGuard et redirection du courrier vers le serveur domestique.",
        ES to "VPS — punto de entrada: túnel WireGuard y reenvío del correo al servidor doméstico.",
        RU to "VPS — точка входа: WireGuard-туннель и проброс почты на домашний сервер.",
        UK to "VPS — точка входу: WireGuard-тунель і прокидання пошти на домашній сервер.",
        IT to "VPS — punto di ingresso: tunnel WireGuard e inoltro della posta al server domestico.",
        JA to "VPS — エントリーポイント: WireGuard トンネルとホームサーバーへのメール転送。",
        ZH to "VPS — 入口节点：WireGuard 隧道并将邮件转发到家庭服务器。"
    ))
    fun purposeHomeMail(l: AppLanguage): String = l.pick(mapOf(
        EN to "home server: WireGuard client + mail.",
        DE to "Heimserver: WireGuard-Client + Mail.",
        FR to "serveur domestique : client WireGuard + mail.",
        ES to "servidor doméstico: cliente WireGuard + correo.",
        RU to "домашний сервер: WireGuard-клиент + почта.",
        UK to "домашній сервер: WireGuard-клієнт + пошта.",
        IT to "server domestico: client WireGuard + posta.",
        JA to "ホームサーバー: WireGuard クライアント + メール。",
        ZH to "家庭服务器：WireGuard 客户端 + 邮件。"
    ))
    fun purposeHomeServices(l: AppLanguage): String = l.pick(mapOf(
        EN to "home server: WireGuard client + self-hosted services.",
        DE to "Heimserver: WireGuard-Client + Self-hosted-Dienste.",
        FR to "serveur domestique : client WireGuard + services auto-hébergés.",
        ES to "servidor doméstico: cliente WireGuard + servicios autoalojados.",
        RU to "домашний сервер: WireGuard-клиент + self-hosted сервисы.",
        UK to "домашній сервер: WireGuard-клієнт + self-hosted сервіси.",
        IT to "server domestico: client WireGuard + servizi self-hosted.",
        JA to "ホームサーバー: WireGuard クライアント + self-hosted サービス。",
        ZH to "家庭服务器：WireGuard 客户端 + self-hosted 服务。"
    ))

    // ---------------------------------------------- Artifact summaries
    fun summarySingleHost(l: AppLanguage): String = l.pick(mapOf(
        EN to "Full server setup in one run: firewall, TLS, the selected services; ends with a report containing all credentials.",
        DE to "Komplette Servereinrichtung in einem Lauf: Firewall, TLS, die gewählten Dienste; am Ende ein Bericht mit allen Zugangsdaten.",
        FR to "Configuration complète du serveur en une seule exécution : firewall, TLS, les services choisis ; se termine par un rapport avec tous les accès.",
        ES to "Configuración completa del servidor en una sola ejecución: firewall, TLS, los servicios seleccionados; al final, un informe con todas las credenciales.",
        RU to "Полная настройка сервера одним запуском: firewall, TLS, выбранные сервисы; в конце — отчёт со всеми доступами.",
        UK to "Повне налаштування сервера одним запуском: firewall, TLS, обрані сервіси; наприкінці — звіт з усіма доступами.",
        IT to "Configurazione completa del server in un unico avvio: firewall, TLS, i servizi scelti; al termine un rapporto con tutte le credenziali.",
        JA to "一度の実行でサーバーを完全構築: firewall、TLS、選択したサービス。最後にすべての認証情報を含むレポートを出力します。",
        ZH to "一次运行完成服务器全部配置：firewall、TLS、所选服务；最后输出包含全部访问凭据的报告。"
    ))
    fun summaryVPS(l: AppLanguage): String = l.pick(mapOf(
        EN to "VPS in one run: WireGuard server, IPv4 forwarding, firewall with DNAT of the mail ports into the tunnel. Contains this machine's WireGuard private key.",
        DE to "VPS in einem Lauf: WireGuard-Server, IPv4-Forwarding, Firewall mit DNAT der Mail-Ports in den Tunnel. Enthält den privaten WireGuard-Schlüssel dieser Maschine.",
        FR to "VPS en une seule exécution : serveur WireGuard, forwarding IPv4, firewall avec DNAT des ports mail vers le tunnel. Contient la clé privée WireGuard de cette machine.",
        ES to "VPS en una sola ejecución: servidor WireGuard, reenvío IPv4, firewall con DNAT de los puertos de correo hacia el túnel. Contiene la clave privada WireGuard de esta máquina.",
        RU to "VPS одним запуском: WireGuard-сервер, IPv4-форвардинг, firewall с DNAT почтовых портов в туннель. Содержит приватный ключ WireGuard этой машины.",
        UK to "VPS одним запуском: WireGuard-сервер, IPv4-форвардинг, firewall з DNAT поштових портів у тунель. Містить приватний ключ WireGuard цієї машини.",
        IT to "VPS in un unico avvio: server WireGuard, forwarding IPv4, firewall con DNAT delle porte di posta nel tunnel. Contiene la chiave privata WireGuard di questa macchina.",
        JA to "一度の実行で VPS を構築: WireGuard サーバー、IPv4 フォワーディング、メールポートをトンネルへ DNAT する firewall。このマシンの WireGuard 秘密鍵を含みます。",
        ZH to "一次运行完成 VPS 配置：WireGuard 服务端、IPv4 转发、将邮件端口 DNAT 进隧道的 firewall。包含本机的 WireGuard 私钥。"
    ))
    fun summaryHome(l: AppLanguage): String = l.pick(mapOf(
        EN to "Home server in one run: WireGuard client (waits for the VPS handshake), firewall and the selected services. Contains this machine's WireGuard private key.",
        DE to "Heimserver in einem Lauf: WireGuard-Client (wartet auf den VPS-Handshake), Firewall und die gewählten Dienste. Enthält den privaten WireGuard-Schlüssel dieser Maschine.",
        FR to "Serveur domestique en une seule exécution : client WireGuard (attend le handshake du VPS), firewall et les services choisis. Contient la clé privée WireGuard de cette machine.",
        ES to "Servidor doméstico en una sola ejecución: cliente WireGuard (espera el handshake del VPS), firewall y los servicios seleccionados. Contiene la clave privada WireGuard de esta máquina.",
        RU to "Домашний сервер одним запуском: WireGuard-клиент (ждёт рукопожатия с VPS), firewall и выбранные сервисы. Содержит приватный ключ WireGuard этой машины.",
        UK to "Домашній сервер одним запуском: WireGuard-клієнт (чекає на рукостискання з VPS), firewall і обрані сервіси. Містить приватний ключ WireGuard цієї машини.",
        IT to "Server domestico in un unico avvio: client WireGuard (attende l'handshake del VPS), firewall e i servizi scelti. Contiene la chiave privata WireGuard di questa macchina.",
        JA to "一度の実行でホームサーバーを構築: WireGuard クライアント (VPS とのハンドシェイクを待機)、firewall、選択したサービス。このマシンの WireGuard 秘密鍵を含みます。",
        ZH to "一次运行完成家庭服务器配置：WireGuard 客户端（等待与 VPS 的握手）、firewall 及所选服务。包含本机的 WireGuard 私钥。"
    ))

    // ---------------------------------------------- VPS sections
    fun enableForwardingLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Enabling IPv4 forwarding (needed for DNAT into the tunnel)",
        DE to "IPv4-Forwarding wird aktiviert (nötig für DNAT in den Tunnel)",
        FR to "Activation du forwarding IPv4 (nécessaire pour le DNAT vers le tunnel)",
        ES to "Activación del reenvío IPv4 (necesario para el DNAT hacia el túnel)",
        RU to "Включение IPv4-форвардинга (нужен для DNAT в туннель)",
        UK to "Увімкнення IPv4-форвардингу (потрібен для DNAT у тунель)",
        IT to "Attivazione del forwarding IPv4 (necessario per il DNAT nel tunnel)",
        JA to "IPv4 フォワーディングを有効化 (トンネルへの DNAT に必要)",
        ZH to "启用 IPv4 转发（DNAT 进隧道所需）"
    ))
    fun detectPublicInterfaceLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Detecting the public network interface",
        DE to "Ermittlung der öffentlichen Netzwerkschnittstelle",
        FR to "Détection de l'interface réseau publique",
        ES to "Detección de la interfaz de red pública",
        RU to "Определение публичного интерфейса",
        UK to "Визначення публічного інтерфейсу",
        IT to "Rilevamento dell'interfaccia di rete pubblica",
        JA to "公開ネットワークインターフェースの検出",
        ZH to "检测公网网络接口"
    ))
    fun publicInterfaceFail(l: AppLanguage): String = l.pick(mapOf(
        EN to "could not determine the public network interface (ip route get)",
        DE to "die öffentliche Netzwerkschnittstelle konnte nicht ermittelt werden (ip route get)",
        FR to "impossible de déterminer l'interface réseau publique (ip route get)",
        ES to "no se pudo determinar la interfaz de red pública (ip route get)",
        RU to "не удалось определить публичный сетевой интерфейс (ip route get)",
        UK to "не вдалося визначити публічний мережевий інтерфейс (ip route get)",
        IT to "impossibile determinare l'interfaccia di rete pubblica (ip route get)",
        JA to "公開ネットワークインターフェースを特定できませんでした (ip route get)",
        ZH to "无法确定公网网络接口（ip route get）"
    ))

    /** `interface` is a bash fragment (e.g */
    fun publicInterfaceIs(l: AppLanguage, `interface`: String): String = l.pick(mapOf(
        EN to "Public interface: ${`interface`}",
        DE to "Öffentliche Schnittstelle: ${`interface`}",
        FR to "Interface publique : ${`interface`}",
        ES to "Interfaz pública: ${`interface`}",
        RU to "Публичный интерфейс: ${`interface`}",
        UK to "Публічний інтерфейс: ${`interface`}",
        IT to "Interfaccia pubblica: ${`interface`}",
        JA to "公開インターフェース: ${`interface`}",
        ZH to "公网接口：${`interface`}"
    ))
    fun startingTunnel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Starting the tunnel",
        DE to "Tunnel wird gestartet",
        FR to "Démarrage du tunnel",
        ES to "Inicio del túnel",
        RU to "Запуск туннеля",
        UK to "Запуск тунелю",
        IT to "Avvio del tunnel",
        JA to "トンネルの起動",
        ZH to "启动隧道"
    ))
    fun vpsReportWireGuard(l: AppLanguage, port: Int): String = l.pick(mapOf(
        EN to "WireGuard:   /etc/wireguard/wg0.conf — tunnel server, port UDP/$port",
        DE to "WireGuard:   /etc/wireguard/wg0.conf — Tunnel-Server, Port UDP/$port",
        FR to "WireGuard :  /etc/wireguard/wg0.conf — serveur du tunnel, port UDP/$port",
        ES to "WireGuard:   /etc/wireguard/wg0.conf — servidor del túnel, puerto UDP/$port",
        RU to "WireGuard:   /etc/wireguard/wg0.conf — сервер туннеля, порт UDP/$port",
        UK to "WireGuard:   /etc/wireguard/wg0.conf — сервер тунелю, порт UDP/$port",
        IT to "WireGuard:   /etc/wireguard/wg0.conf — server del tunnel, porta UDP/$port",
        JA to "WireGuard:   /etc/wireguard/wg0.conf — トンネルサーバー、ポート UDP/$port",
        ZH to "WireGuard:   /etc/wireguard/wg0.conf — 隧道服务端，端口 UDP/$port"
    ))
    fun vpsReportFirewall(l: AppLanguage, ports: String, target: String): String = l.pick(mapOf(
        EN to "Firewall:    /etc/nftables.conf — DNAT of ports $ports -> $target",
        DE to "Firewall:    /etc/nftables.conf — DNAT der Ports $ports -> $target",
        FR to "Firewall :   /etc/nftables.conf — DNAT des ports $ports -> $target",
        ES to "Firewall:    /etc/nftables.conf — DNAT de los puertos $ports -> $target",
        RU to "Firewall:    /etc/nftables.conf — DNAT портов $ports -> $target",
        UK to "Firewall:    /etc/nftables.conf — DNAT портів $ports -> $target",
        IT to "Firewall:    /etc/nftables.conf — DNAT delle porte $ports -> $target",
        JA to "Firewall:    /etc/nftables.conf — ポート $ports を $target へ DNAT",
        ZH to "Firewall:    /etc/nftables.conf — 端口 $ports DNAT 至 $target"
    ))
    fun vpsReportForwarding(l: AppLanguage): String = l.pick(mapOf(
        EN to "Forwarding:  /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        DE to "Forwarding:  /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        FR to "Forwarding : /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        ES to "Reenvío:     /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        RU to "Форвардинг:  /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        UK to "Форвардинг:  /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        IT to "Forwarding:  /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        JA to "フォワーディング: /etc/sysctl.d/99-gryonixnexus-forwarding.conf",
        ZH to "转发:        /etc/sysctl.d/99-gryonixnexus-forwarding.conf"
    ))
    fun vpsHandshakeNote(l: AppLanguage): String = l.pick(mapOf(
        EN to "Tunnel (the handshake will appear after setup-home-server.sh runs on the home server):",
        DE to "Tunnel (der Handshake erscheint, nachdem setup-home-server.sh auf dem Heimserver gelaufen ist):",
        FR to "Tunnel (le handshake apparaîtra après l'exécution de setup-home-server.sh sur le serveur domestique) :",
        ES to "Túnel (el handshake aparecerá tras ejecutar setup-home-server.sh en el servidor doméstico):",
        RU to "Туннель (рукопожатие появится после setup-home-server.sh на домашнем сервере):",
        UK to "Тунель (рукостискання зʼявиться після setup-home-server.sh на домашньому сервері):",
        IT to "Tunnel (l'handshake apparirà dopo l'esecuzione di setup-home-server.sh sul server domestico):",
        JA to "トンネル (ハンドシェイクはホームサーバーで setup-home-server.sh を実行すると表示されます):",
        ZH to "隧道（在家庭服务器上运行 setup-home-server.sh 后握手才会出现）："
    ))
    fun nextStepsHeader(l: AppLanguage): String = l.pick(mapOf(
        EN to "Next steps:",
        DE to "Weiter geht es so:",
        FR to "Étapes suivantes :",
        ES to "Próximos pasos:",
        RU to "Дальше:",
        UK to "Далі:",
        IT to "Prossimi passi:",
        JA to "次の手順:",
        ZH to "后续步骤:"
    ))
    fun vpsNextStepHome(l: AppLanguage): String = l.pick(mapOf(
        EN to "1) Run setup-home-server.sh on the HOME server.",
        DE to "1) Führen Sie setup-home-server.sh auf dem HEIM-Server aus.",
        FR to "1) Lancez setup-home-server.sh sur le serveur DOMESTIQUE.",
        ES to "1) Ejecute setup-home-server.sh en el servidor DOMÉSTICO.",
        RU to "1) Запустите setup-home-server.sh на ДОМАШНЕМ сервере.",
        UK to "1) Запустіть setup-home-server.sh на ДОМАШНЬОМУ сервері.",
        IT to "1) Eseguite setup-home-server.sh sul server DOMESTICO.",
        JA to "1) ホームサーバーで setup-home-server.sh を実行してください。",
        ZH to "1) 在家庭服务器上运行 setup-home-server.sh。"
    ))
    fun vpsNextStepPTR(l: AppLanguage, hostname: String): String = l.pick(mapOf(
        EN to "2) PTR at the VPS provider: public IP -> $hostname.",
        DE to "2) PTR beim VPS-Provider: öffentliche IP -> $hostname.",
        FR to "2) PTR chez le fournisseur du VPS : IP publique -> $hostname.",
        ES to "2) PTR en el proveedor del VPS: IP pública -> $hostname.",
        RU to "2) PTR у провайдера VPS: публичный IP -> $hostname.",
        UK to "2) PTR у провайдера VPS: публічний IP -> $hostname.",
        IT to "2) PTR presso il provider del VPS: IP pubblico -> $hostname.",
        JA to "2) VPS プロバイダーで PTR を設定: 公開 IP -> $hostname。",
        ZH to "2) 在 VPS 服务商处设置 PTR：公网 IP -> $hostname。"
    ))

    // ---------------------------------------------- Home server sections
    fun wgFullTunnelLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "WireGuard: /etc/wireguard/wg0.conf (full tunnel via the VPS)",
        DE to "WireGuard: /etc/wireguard/wg0.conf (voller Tunnel über den VPS)",
        FR to "WireGuard : /etc/wireguard/wg0.conf (tunnel complet via le VPS)",
        ES to "WireGuard: /etc/wireguard/wg0.conf (túnel completo a través del VPS)",
        RU to "WireGuard: /etc/wireguard/wg0.conf (полный туннель через VPS)",
        UK to "WireGuard: /etc/wireguard/wg0.conf (повний тунель через VPS)",
        IT to "WireGuard: /etc/wireguard/wg0.conf (tunnel completo tramite il VPS)",
        JA to "WireGuard: /etc/wireguard/wg0.conf (VPS 経由のフルトンネル)",
        ZH to "WireGuard: /etc/wireguard/wg0.conf（经 VPS 的全隧道）"
    ))
    fun startingTunnelToVPS(l: AppLanguage, endpoint: String): String = l.pick(mapOf(
        EN to "Starting the tunnel to the VPS ($endpoint)",
        DE to "Tunnel zum VPS wird gestartet ($endpoint)",
        FR to "Démarrage du tunnel vers le VPS ($endpoint)",
        ES to "Inicio del túnel hacia el VPS ($endpoint)",
        RU to "Запуск туннеля до VPS ($endpoint)",
        UK to "Запуск тунелю до VPS ($endpoint)",
        IT to "Avvio del tunnel verso il VPS ($endpoint)",
        JA to "VPS へのトンネルを起動 ($endpoint)",
        ZH to "启动到 VPS 的隧道（$endpoint）"
    ))
    fun waitingForHandshake(l: AppLanguage): String = l.pick(mapOf(
        EN to "Waiting for the WireGuard handshake",
        DE to "Warten auf den WireGuard-Handshake",
        FR to "Attente du handshake WireGuard",
        ES to "Esperando el handshake de WireGuard",
        RU to "Ожидание рукопожатия WireGuard",
        UK to "Очікування рукостискання WireGuard",
        IT to "In attesa dell'handshake WireGuard",
        JA to "WireGuard のハンドシェイクを待機中",
        ZH to "等待 WireGuard 握手"
    ))
    fun noHandshake(l: AppLanguage, endpoint: String, port: Int): String = l.pick(mapOf(
        EN to "no handshake with the VPS ($endpoint).\nMake sure setup-vps.sh has already been run on the VPS and UDP/$port is not blocked.",
        DE to "kein Handshake mit dem VPS ($endpoint).\nStellen Sie sicher, dass setup-vps.sh bereits auf dem VPS gelaufen ist und UDP/$port nicht blockiert wird.",
        FR to "pas de handshake avec le VPS ($endpoint).\nVérifiez que setup-vps.sh a déjà été exécuté sur le VPS et que UDP/$port n'est pas bloqué.",
        ES to "sin handshake con el VPS ($endpoint).\nAsegúrese de que setup-vps.sh ya se ejecutó en el VPS y de que UDP/$port no está bloqueado.",
        RU to "нет рукопожатия с VPS ($endpoint).\nУбедитесь, что setup-vps.sh уже выполнен на VPS и UDP/$port не блокируется.",
        UK to "немає рукостискання з VPS ($endpoint).\nПереконайтеся, що setup-vps.sh уже виконано на VPS і UDP/$port не блокується.",
        IT to "nessun handshake con il VPS ($endpoint).\nAssicuratevi che setup-vps.sh sia già stato eseguito sul VPS e che UDP/$port non sia bloccato.",
        JA to "VPS とのハンドシェイクがありません ($endpoint)。\nVPS で setup-vps.sh が実行済みであること、UDP/$port がブロックされていないことを確認してください。",
        ZH to "与 VPS 未建立握手（$endpoint）。\n请确认已在 VPS 上运行 setup-vps.sh，且 UDP/$port 未被拦截。"
    ))
    fun tunnelUp(l: AppLanguage): String = l.pick(mapOf(
        EN to "The tunnel is up.",
        DE to "Der Tunnel läuft.",
        FR to "Le tunnel fonctionne.",
        ES to "El túnel funciona.",
        RU to "Туннель работает.",
        UK to "Тунель працює.",
        IT to "Il tunnel funziona.",
        JA to "トンネルは稼働中です。",
        ZH to "隧道已正常工作。"
    ))

    // ---------------------------------------------- Service infrastructure
    fun installingDocker(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing Docker",
        DE to "Installation von Docker",
        FR to "Installation de Docker",
        ES to "Instalación de Docker",
        RU to "Установка Docker",
        UK to "Встановлення Docker",
        IT to "Installazione di Docker",
        JA to "Docker のインストール",
        ZH to "安装 Docker"
    ))
    fun installingMetricsCollector(l: AppLanguage): String = l.pick(mapOf(
        EN to "Metrics history collector (gryonixnexus-metrics)",
        DE to "Metrikverlauf-Kollektor (gryonixnexus-metrics)",
        FR to "Collecteur d’historique des métriques (gryonixnexus-metrics)",
        ES to "Recolector de historial de métricas (gryonixnexus-metrics)",
        RU to "Коллектор истории метрик (gryonixnexus-metrics)",
        UK to "Колектор історії метрик (gryonixnexus-metrics)",
        IT to "Raccoglitore dello storico delle metriche (gryonixnexus-metrics)",
        JA to "メトリクス履歴コレクター（gryonixnexus-metrics）",
        ZH to "指标历史收集器（gryonixnexus-metrics）"
    ))
    fun installingCaddy(l: AppLanguage): String = l.pick(mapOf(
        EN to "Installing Caddy",
        DE to "Installation von Caddy",
        FR to "Installation de Caddy",
        ES to "Instalación de Caddy",
        RU to "Установка Caddy",
        UK to "Встановлення Caddy",
        IT to "Installazione di Caddy",
        JA to "Caddy のインストール",
        ZH to "安装 Caddy"
    ))
    fun caddyReverseProxyLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Caddy: reverse proxy for the web services",
        DE to "Caddy: Reverse-Proxy für die Webdienste",
        FR to "Caddy : reverse proxy pour les services web",
        ES to "Caddy: proxy inverso para los servicios web",
        RU to "Caddy: обратный прокси для веб-сервисов",
        UK to "Caddy: зворотний проксі для веб-сервісів",
        IT to "Caddy: reverse proxy per i servizi web",
        JA to "Caddy: Web サービス用のリバースプロキシ",
        ZH to "Caddy：Web 服务的反向代理"
    ))
    fun caddyDidNotStart(l: AppLanguage): String = l.pick(mapOf(
        EN to "Caddy did not start; its log and whatever holds ports 80/443 are above",
        DE to "Caddy ist nicht gestartet; sein Log und die Belegung der Ports 80/443 stehen oben",
        FR to "Caddy n'a pas démarré ; son journal et ce qui occupe les ports 80/443 sont ci-dessus",
        ES to "Caddy no arrancó; su registro y lo que ocupa los puertos 80/443 están arriba",
        RU to "Caddy не запустился; выше его журнал и то, что занимает порты 80/443",
        UK to "Caddy не запустився; вище його журнал і те, що займає порти 80/443",
        IT to "Caddy non si è avviato; il suo log e ciò che occupa le porte 80/443 sono sopra",
        JA to "Caddy が起動しませんでした。ログとポート 80/443 を使用中のプロセスを上に表示しています",
        ZH to "Caddy 未能启动；上方是它的日志以及占用 80/443 端口的进程"
    ))

    fun caddyNameAlreadyServed(l: AppLanguage): String = l.pick(mapOf(
        EN to ("another site on this server already answers on these names, " +
            "and two blocks on one name make Caddy refuse the whole file"),
        DE to ("eine andere Website auf diesem Server antwortet bereits auf diese Namen; " +
            "zwei Blöcke für einen Namen lassen Caddy die gesamte Datei ablehnen"),
        FR to ("un autre site de ce serveur répond déjà sur ces noms, " +
            "et deux blocs pour un même nom font rejeter tout le fichier par Caddy"),
        ES to ("otro sitio de este servidor ya responde en estos nombres, " +
            "y dos bloques con un mismo nombre hacen que Caddy rechace todo el archivo"),
        RU to ("на этом сервере эти имена уже обслуживает другой сайт, " +
            "а два блока на одно имя заставляют Caddy отвергнуть весь файл"),
        UK to ("на цьому сервері ці імена вже обслуговує інший сайт, " +
            "а два блоки на одне ім'я змушують Caddy відхилити весь файл"),
        IT to ("un altro sito su questo server risponde già su questi nomi, " +
            "e due blocchi per lo stesso nome fanno rifiutare a Caddy l'intero file"),
        JA to ("このサーバーの別のサイトがすでにこれらの名前で応答しています。" +
            "1 つの名前に 2 つのブロックがあると Caddy はファイル全体を拒否します"),
        ZH to ("此服务器上已有其他站点在这些名称上响应；" +
            "同一名称出现两个块会让 Caddy 拒绝整个文件")
    ))
    fun caddyDNSReminder(l: AppLanguage): String = l.pick(mapOf(
        EN to "Remember the DNS records from dns-records.txt — without them Caddy cannot issue certificates.",
        DE to "Denken Sie an die DNS-Einträge aus dns-records.txt — ohne sie kann Caddy keine Zertifikate ausstellen.",
        FR to "N'oubliez pas les enregistrements DNS de dns-records.txt — sans eux, Caddy ne pourra pas émettre de certificats.",
        ES to "No olvide los registros DNS de dns-records.txt — sin ellos Caddy no podrá emitir certificados.",
        RU to "Не забудьте DNS-записи из dns-records.txt — без них Caddy не выпустит сертификаты.",
        UK to "Не забудьте DNS-записи з dns-records.txt — без них Caddy не випустить сертифікати.",
        IT to "Non dimenticate i record DNS da dns-records.txt — senza di essi Caddy non potrà emettere certificati.",
        JA to "dns-records.txt の DNS レコードを忘れずに — ないと Caddy は証明書を発行できません。",
        ZH to "别忘了 dns-records.txt 中的 DNS 记录 — 没有它们 Caddy 无法签发证书。"
    ))
    fun serviceCredentialsHeader(l: AppLanguage): String = l.pick(mapOf(
        EN to "=== SERVICE CREDENTIALS (save these) ===",
        DE to "=== ZUGANGSDATEN DER DIENSTE (bitte speichern) ===",
        FR to "=== ACCÈS AUX SERVICES (à conserver) ===",
        ES to "=== CREDENCIALES DE LOS SERVICIOS (guárdelas) ===",
        RU to "=== ДОСТУПЫ СЕРВИСОВ (сохраните) ===",
        UK to "=== ДОСТУПИ СЕРВІСІВ (збережіть) ===",
        IT to "=== CREDENZIALI DEI SERVIZI (da conservare) ===",
        JA to "=== サービスの認証情報 (保存してください) ===",
        ZH to "=== 服务访问凭据（请保存）==="
    ))

    /** The generated passphrase that encrypts this host's automatic backups */
    fun backupPassphraseLabel(l: AppLanguage): String = l.pick(mapOf(
        EN to "Backup passphrase (keep it — encrypted backups need it): ",
        DE to "Backup-Passphrase (aufbewahren — verschlüsselte Backups brauchen sie): ",
        FR to "Phrase secrète de sauvegarde (à conserver — les sauvegardes chiffrées en ont besoin) : ",
        ES to "Frase de contraseña de copia (guárdela — las copias cifradas la necesitan): ",
        RU to "Пароль бэкапов (сохраните — без него не восстановить шифрованный бэкап): ",
        UK to "Пароль резервних копій (збережіть — без нього не відновити шифровану копію): ",
        IT to "Passphrase dei backup (conservala — i backup cifrati la richiedono): ",
        JA to "バックアップのパスフレーズ (暗号化バックアップの復元に必要です): ",
        ZH to "备份口令（请保存 — 恢复加密备份时需要）："
    ))

    // ---------------------------------------------- Dashboard access
    fun dashboardSSHKeyLog(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "Dashboard: the app SSH key for user $user",
        DE to "Dashboard: SSH-Schlüssel der App für den Benutzer $user",
        FR to "Dashboard : clé SSH de l'application pour l'utilisateur $user",
        ES to "Dashboard: clave SSH de la aplicación para el usuario $user",
        RU to "Панель управления: SSH-ключ приложения для пользователя $user",
        UK to "Панель керування: SSH-ключ застосунку для користувача $user",
        IT to "Dashboard: chiave SSH dell'app per l'utente $user",
        JA to "ダッシュボード: ユーザー $user 用アプリの SSH 鍵",
        ZH to "管理面板：用户 $user 的应用 SSH 密钥"
    ))
    fun userNotFound(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "user «$user» not found — create it (adduser $user) and run the script again",
        DE to "Benutzer «$user» nicht gefunden — legen Sie ihn an (adduser $user) und starten Sie das Skript erneut",
        FR to "utilisateur «$user» introuvable — créez-le (adduser $user) et relancez le script",
        ES to "usuario «$user» no encontrado — créelo (adduser $user) y vuelva a ejecutar el script",
        RU to "пользователь «$user» не найден — создайте его (adduser $user) и запустите скрипт снова",
        UK to "користувача «$user» не знайдено — створіть його (adduser $user) і запустіть скрипт знову",
        IT to "utente «$user» non trovato — createlo (adduser $user) e rieseguite lo script",
        JA to "ユーザー「$user」が見つかりません — 作成して (adduser $user) スクリプトを再実行してください",
        ZH to "未找到用户「$user」— 请创建（adduser $user）后重新运行脚本"
    ))
    fun homeDirectoryFail(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "could not determine the home directory of user «$user»",
        DE to "das Home-Verzeichnis des Benutzers «$user» konnte nicht ermittelt werden",
        FR to "impossible de déterminer le répertoire personnel de l'utilisateur «$user»",
        ES to "no se pudo determinar el directorio de inicio del usuario «$user»",
        RU to "не удалось определить домашнюю директорию пользователя «$user»",
        UK to "не вдалося визначити домашню директорію користувача «$user»",
        IT to "impossibile determinare la home directory dell'utente «$user»",
        JA to "ユーザー「$user」のホームディレクトリを特定できませんでした",
        ZH to "无法确定用户「$user」的主目录"
    ))
    fun dashboardCreateUserLog(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "Dashboard: dedicated control user «$user» (SSH key only, rights limited by sudoers)",
        DE to "Panel: dedizierter Steuerbenutzer «$user» (nur SSH-Schlüssel, Rechte durch sudoers begrenzt)",
        FR to "Panneau : utilisateur de contrôle dédié «$user» (clé SSH uniquement, droits limités par sudoers)",
        ES to "Panel: usuario de control dedicado «$user» (solo clave SSH, permisos limitados por sudoers)",
        RU to "Панель управления: выделенный пользователь «$user» (вход только по SSH-ключу, права ограничены sudoers)",
        UK to "Панель керування: виділений користувач «$user» (вхід лише за SSH-ключем, права обмежені sudoers)",
        IT to "Pannello: utente di controllo dedicato «$user» (solo chiave SSH, permessi limitati da sudoers)",
        JA to "パネル: 専用の管理ユーザー «$user» (SSH キーのみ、権限は sudoers で制限)",
        ZH to "面板：专用管理用户 «$user»（仅 SSH 密钥登录，权限由 sudoers 限制）"
    ))
    fun dashboardExistingUserLog(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "Dashboard: using the existing user «$user» (account untouched, only sudoers installed)",
        DE to "Panel: bestehender Benutzer «$user» wird verwendet (Konto unangetastet, nur sudoers installiert)",
        FR to "Panneau : utilisation de l'utilisateur existant «$user» (compte intact, seul sudoers est installé)",
        ES to "Panel: se usa el usuario existente «$user» (cuenta intacta, solo se instala sudoers)",
        RU to "Панель управления: используется существующий пользователь «$user» (аккаунт не меняется, ставится только sudoers)",
        UK to "Панель керування: використовується наявний користувач «$user» (обліковий запис не змінюється, ставиться лише sudoers)",
        IT to "Pannello: uso dell'utente esistente «$user» (account intatto, viene installato solo sudoers)",
        JA to "パネル: 既存ユーザー «$user» を使用（アカウントは変更せず、sudoers のみ設定）",
        ZH to "面板：使用现有用户 «$user»（不修改账户，仅安装 sudoers）"
    ))
    fun existingUserMissing(l: AppLanguage, user: String): String = l.pick(mapOf(
        EN to "user «$user» does not exist on this server — create it first or switch off 'existing user' in the app",
        DE to "Benutzer «$user» existiert auf diesem Server nicht — legen Sie ihn zuerst an oder deaktivieren Sie «bestehender Benutzer» in der App",
        FR to "l'utilisateur «$user» n'existe pas sur ce serveur — créez-le d'abord ou désactivez « utilisateur existant » dans l'app",
        ES to "el usuario «$user» no existe en este servidor: créelo primero o desactive «usuario existente» en la app",
        RU to "пользователь «$user» не существует на этом сервере — сначала создайте его или выключите «существующий пользователь» в приложении",
        UK to "користувач «$user» не існує на цьому сервері — спершу створіть його або вимкніть «наявний користувач» у застосунку",
        IT to "l'utente «$user» non esiste su questo server: crealo prima o disattiva «utente esistente» nell'app",
        JA to "ユーザー «$user» はこのサーバーに存在しません。先に作成するか、アプリで「既存ユーザー」をオフにしてください",
        ZH to "此服务器上不存在用户 «$user»——请先创建该用户，或在应用中关闭“现有用户”"
    ))
    fun revokeInstallKeyLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Revoking the temporary root access of the app (install key)",
        DE to "Temporärer Root-Zugang der App wird entzogen (Installationsschlüssel)",
        FR to "Révocation de l'accès root temporaire de l'application (clé d'installation)",
        ES to "Revocando el acceso root temporal de la aplicación (clave de instalación)",
        RU to "Отзыв временного root-доступа приложения (ключ установки)",
        UK to "Відкликання тимчасового root-доступу застосунку (ключ встановлення)",
        IT to "Revoca dell'accesso root temporaneo dell'app (chiave di installazione)",
        JA to "アプリの一時的な root アクセスを取り消しています (インストール用キー)",
        ZH to "正在撤销应用的临时 root 访问权限（安装密钥）"
    ))
    fun revokeInstallKeyDone(l: AppLanguage): String = l.pick(mapOf(
        EN to "app key removed from the install account's authorized_keys; the app now connects as the control user only",
        DE to "App-Schlüssel aus authorized_keys des Installationskontos entfernt; die App verbindet sich nur noch als Steuerbenutzer",
        FR to "clé de l'application retirée de authorized_keys du compte d'installation ; l'application se connecte désormais uniquement en tant qu'utilisateur de contrôle",
        ES to "clave de la aplicación eliminada de authorized_keys de la cuenta de instalación; la aplicación ahora se conecta solo como usuario de control",
        RU to "ключ приложения удалён из authorized_keys установочной учётной записи; теперь приложение подключается только под управляющим пользователем",
        UK to "ключ застосунку видалено з authorized_keys встановлювального облікового запису; тепер застосунок підключається лише під керуючим користувачем",
        IT to "chiave dell'app rimossa da authorized_keys dell'account di installazione; l'app ora si connette solo come utente di controllo",
        JA to "インストールに使ったアカウントの authorized_keys からアプリの鍵を削除しました。以後アプリは管理ユーザーとしてのみ接続します",
        ZH to "已从安装账户的 authorized_keys 中移除应用密钥；应用此后仅以管理用户身份连接"
    ))
    fun dashboardSudoersLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Dashboard: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        DE to "Dashboard: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        FR to "Dashboard : sudoers (/etc/sudoers.d/gryonixnexus-control)",
        ES to "Dashboard: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        RU to "Панель управления: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        UK to "Панель керування: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        IT to "Dashboard: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        JA to "ダッシュボード: sudoers (/etc/sudoers.d/gryonixnexus-control)",
        ZH to "管理面板：sudoers（/etc/sudoers.d/gryonixnexus-control）"
    ))
    fun sshdPenaltyExemptLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH: exempting the tunnel address from sshd per-source penalties",
        DE to "SSH: Tunnel-Adresse von sshd-Per-Source-Penalties ausgenommen",
        FR to "SSH : exemption de l'adresse du tunnel des pénalités par source de sshd",
        ES to "SSH: eximiendo la dirección del túnel de las penalizaciones por origen de sshd",
        RU to "SSH: адрес туннеля исключается из per-source-штрафов sshd",
        UK to "SSH: адресу тунелю виключено з per-source-штрафів sshd",
        IT to "SSH: esenzione dell'indirizzo del tunnel dalle penalità per origine di sshd",
        JA to "SSH: トンネルアドレスを sshd のソース別ペナルティから除外します",
        ZH to "SSH：将隧道地址从 sshd 的按源惩罚中豁免"
    ))
    fun sshdPasswordCloseLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH: closing password login now that this host has the app key",
        DE to "SSH: Passwort-Login wird geschlossen, da dieser Host den App-Schlüssel hat",
        FR to "SSH : fermeture de la connexion par mot de passe, cet hôte a maintenant la clé de l app",
        ES to "SSH: cerrando el acceso por contraseña, este host ya tiene la clave de la app",
        RU to "SSH: закрываем вход по паролю — ключ приложения уже на этом хосте",
        UK to "SSH: закриваємо вхід за паролем — ключ застосунку вже на цьому хості",
        IT to "SSH: chiusura dell accesso con password, questo host ha ora la chiave dell app",
        JA to "SSH: アプリの鍵が入ったので、パスワードログインを閉じます",
        ZH to "SSH：本机已有应用密钥，正在关闭密码登录"
    ))

    fun sshdPasswordCloseSkipped(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH password login stays ON: the app key is not on the control user, and closing the door before the key is proven is how a host is lost",
        DE to "SSH-Passwort-Login bleibt AN: der App-Schlüssel liegt nicht beim Steuerbenutzer, und die Tür vor dem Nachweis zu schließen kostet den Host",
        FR to "La connexion SSH par mot de passe reste ACTIVE : la clé de l app n est pas sur le compte de contrôle, et fermer la porte avant de prouver la clé fait perdre l hôte",
        ES to "El acceso SSH por contraseña sigue ACTIVO: la clave de la app no está en el usuario de control, y cerrar la puerta antes de probar la clave hace perder el host",
        RU to "Вход по паролю SSH ОСТАЁТСЯ включённым: ключа приложения нет у управляющего пользователя, а закрывать дверь до подтверждения ключа — потерять хост",
        UK to "Вхід за паролем SSH ЗАЛИШАЄТЬСЯ увімкненим: ключа застосунку немає в керуючого користувача, а закривати двері до підтвердження ключа — втратити хост",
        IT to "L accesso SSH con password resta ATTIVO: la chiave dell app non è sull utente di controllo, e chiudere la porta prima di provare la chiave fa perdere l host",
        JA to "SSH のパスワードログインは有効なままです: 管理ユーザーにアプリの鍵がなく、鍵を確認する前に扉を閉じるとホストを失います",
        ZH to "SSH 密码登录保持开启：控制账户上没有应用密钥，在密钥未确认前关门会失去这台主机"
    ))

    fun sshdPasswordCloseNotWritten(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH password login stays ON: the configuration file could not be written to this host at all",
        DE to "SSH-Passwort-Login bleibt AN: die Konfigurationsdatei konnte auf diesem Host gar nicht geschrieben werden",
        FR to "La connexion SSH par mot de passe reste ACTIVE : le fichier de configuration n a pas pu être écrit sur cet hôte",
        ES to "El acceso SSH por contraseña sigue ACTIVO: no se pudo escribir el archivo de configuración en este host",
        RU to "Вход по паролю SSH ОСТАЁТСЯ включённым: файл конфигурации вообще не удалось записать на этот хост",
        UK to "Вхід за паролем SSH ЗАЛИШАЄТЬСЯ увімкненим: файл конфігурації взагалі не вдалося записати на цей хост",
        IT to "L accesso SSH con password resta ATTIVO: il file di configurazione non è stato scritto su questo host",
        JA to "SSH のパスワードログインは有効なままです: 設定ファイルをこのホストにまったく書き込めませんでした",
        ZH to "SSH 密码登录保持开启：配置文件根本无法写入这台主机"
    ))

    fun sshdPasswordCloseNotEffective(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH password login stays ON: sshd still accepts passwords with the file in place, so something earlier in its configuration wins — a cloud image's own sshd_config.d file is the usual one",
        DE to "SSH-Passwort-Login bleibt AN: sshd akzeptiert weiterhin Passwörter, obwohl die Datei liegt — etwas Früheres in seiner Konfiguration gewinnt, meist eine eigene sshd_config.d-Datei des Cloud-Images",
        ES to "El acceso SSH por contraseña sigue ACTIVO: sshd sigue aceptando contraseñas con el archivo puesto, así que gana algo anterior en su configuración — normalmente un archivo sshd_config.d de la propia imagen en la nube",
        FR to "La connexion SSH par mot de passe reste ACTIVE : sshd accepte encore les mots de passe alors que le fichier est en place, donc quelque chose de plus tôt dans sa configuration l emporte — en général un fichier sshd_config.d de l image cloud",
        RU to "Вход по паролю SSH ОСТАЁТСЯ включённым: sshd всё ещё принимает пароли, хотя файл на месте — значит побеждает что-то более раннее в его конфигурации, обычно собственный файл sshd_config.d облачного образа",
        UK to "Вхід за паролем SSH ЗАЛИШАЄТЬСЯ увімкненим: sshd досі приймає паролі, хоча файл на місці — отже перемагає щось раніше в його конфігурації, зазвичай власний файл sshd_config.d хмарного образу",
        IT to "L accesso SSH con password resta ATTIVO: sshd accetta ancora le password con il file al suo posto, quindi vince qualcosa di precedente nella sua configurazione — di solito un file sshd_config.d della stessa immagine cloud",
        JA to "SSH のパスワードログインは有効なままです: ファイルを置いても sshd はまだパスワードを受け付けます。設定のより前にあるもの — たいていはクラウドイメージ自身の sshd_config.d ファイル — が勝っています",
        ZH to "SSH 密码登录保持开启：文件已就位但 sshd 仍接受密码，说明其配置中更靠前的内容取胜——通常是云镜像自带的 sshd_config.d 文件"
    ))

    fun sshdPasswordCloseRefused(l: AppLanguage): String = l.pick(mapOf(
        EN to "SSH password login stays ON: sshd rejected the configuration with the drop-in in place, so it was removed again",
        DE to "SSH-Passwort-Login bleibt AN: sshd hat die Konfiguration mit dem Drop-in abgelehnt, es wurde wieder entfernt",
        FR to "La connexion SSH par mot de passe reste ACTIVE : sshd a rejeté la configuration avec le fichier en place, il a été retiré",
        ES to "El acceso SSH por contraseña sigue ACTIVO: sshd rechazó la configuración con el archivo puesto, así que se retiró de nuevo",
        RU to "Вход по паролю SSH ОСТАЁТСЯ включённым: sshd отверг конфигурацию с этим файлом, и файл убран обратно",
        UK to "Вхід за паролем SSH ЗАЛИШАЄТЬСЯ увімкненим: sshd відхилив конфігурацію з цим файлом, і файл прибрано назад",
        IT to "L accesso SSH con password resta ATTIVO: sshd ha rifiutato la configurazione con il file presente, quindi è stato rimosso",
        JA to "SSH のパスワードログインは有効なままです: この設定ファイルを置いた状態で sshd が構成を拒否したため、ファイルを取り除きました",
        ZH to "SSH 密码登录保持开启：放入该配置片段后 sshd 拒绝了配置，因此已将其移除"
    ))

    fun sudoersRejected(l: AppLanguage): String = l.pick(mapOf(
        EN to "sudoers failed the visudo check — the file was not installed",
        DE to "sudoers hat die visudo-Prüfung nicht bestanden — die Datei wurde nicht installiert",
        FR to "sudoers a échoué à la vérification visudo — le fichier n'a pas été installé",
        ES to "sudoers no pasó la comprobación de visudo — el archivo no se instaló",
        RU to "sudoers не прошёл проверку visudo — файл не установлен",
        UK to "sudoers не пройшов перевірку visudo — файл не встановлено",
        IT to "sudoers non ha superato il controllo visudo — il file non è stato installato",
        JA to "sudoers が visudo の検証に失敗しました — ファイルはインストールされていません",
        ZH to "sudoers 未通过 visudo 校验 — 文件未安装"
    ))
    fun mailcowNotFound(l: AppLanguage, path: String): String = l.pick(mapOf(
        EN to "mailcow not found in $path",
        DE to "mailcow nicht gefunden in $path",
        FR to "mailcow introuvable dans $path",
        ES to "mailcow no encontrado en $path",
        RU to "mailcow не найден в $path",
        UK to "mailcow не знайдено в $path",
        IT to "mailcow non trovato in $path",
        JA to "$path に mailcow が見つかりません",
        ZH to "在 $path 中未找到 mailcow"
    ))
    fun mailcowBackupWrapperLog(l: AppLanguage, path: String): String = l.pick(mapOf(
        EN to "Dashboard: Mailcow backup wrapper ($path/bot-backup.sh)",
        DE to "Dashboard: Mailcow-Backup-Wrapper ($path/bot-backup.sh)",
        FR to "Dashboard : wrapper de sauvegarde Mailcow ($path/bot-backup.sh)",
        ES to "Dashboard: wrapper de copia de seguridad de Mailcow ($path/bot-backup.sh)",
        RU to "Панель управления: обёртка бэкапа Mailcow ($path/bot-backup.sh)",
        UK to "Панель керування: обгортка бекапу Mailcow ($path/bot-backup.sh)",
        IT to "Dashboard: wrapper di backup Mailcow ($path/bot-backup.sh)",
        JA to "ダッシュボード: Mailcow バックアップラッパー ($path/bot-backup.sh)",
        ZH to "管理面板：Mailcow 备份包装脚本（$path/bot-backup.sh）"
    ))
    fun vaultwardenUpdateLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Dashboard: Vaultwarden update script (/opt/vaultwarden-update.sh)",
        DE to "Dashboard: Vaultwarden-Update-Skript (/opt/vaultwarden-update.sh)",
        FR to "Dashboard : script de mise à jour de Vaultwarden (/opt/vaultwarden-update.sh)",
        ES to "Dashboard: script de actualización de Vaultwarden (/opt/vaultwarden-update.sh)",
        RU to "Панель управления: скрипт обновления Vaultwarden (/opt/vaultwarden-update.sh)",
        UK to "Панель керування: скрипт оновлення Vaultwarden (/opt/vaultwarden-update.sh)",
        IT to "Dashboard: script di aggiornamento Vaultwarden (/opt/vaultwarden-update.sh)",
        JA to "ダッシュボード: Vaultwarden 更新スクリプト (/opt/vaultwarden-update.sh)",
        ZH to "管理面板：Vaultwarden 更新脚本（/opt/vaultwarden-update.sh）"
    ))
    fun mailcowBackupDirLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Dashboard: Mailcow backup directory",
        DE to "Dashboard: Mailcow-Backup-Verzeichnis",
        FR to "Dashboard : répertoire des sauvegardes Mailcow",
        ES to "Dashboard: directorio de copias de seguridad de Mailcow",
        RU to "Панель управления: директория бэкапов Mailcow",
        UK to "Панель керування: директорія бекапів Mailcow",
        IT to "Dashboard: directory dei backup di Mailcow",
        JA to "ダッシュボード: Mailcow バックアップディレクトリ",
        ZH to "管理面板：Mailcow 备份目录"
    ))

    fun serviceBackupDirLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Dashboard: service backup directories",
        DE to "Dashboard: Backup-Verzeichnisse der Dienste",
        FR to "Dashboard : répertoires de sauvegarde des services",
        ES to "Dashboard: directorios de copias de seguridad de los servicios",
        RU to "Панель управления: директории бэкапов сервисов",
        UK to "Панель керування: директорії бекапів сервісів",
        IT to "Dashboard: directory dei backup dei servizi",
        JA to "ダッシュボード: サービスのバックアップディレクトリ",
        ZH to "管理面板：服务备份目录"
    ))
    fun vaultwardenBackupDirLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Dashboard: Vaultwarden backup directory",
        DE to "Dashboard: Vaultwarden-Backup-Verzeichnis",
        FR to "Dashboard : répertoire des sauvegardes Vaultwarden",
        ES to "Dashboard: directorio de copias de seguridad de Vaultwarden",
        RU to "Панель управления: директория бэкапов Vaultwarden",
        UK to "Панель керування: директорія бекапів Vaultwarden",
        IT to "Dashboard: directory dei backup di Vaultwarden",
        JA to "ダッシュボード: Vaultwarden バックアップディレクトリ",
        ZH to "管理面板：Vaultwarden 备份目录"
    ))

    private fun pad(label: String, width: Int = 16): String =
        if (label.length >= width) "$label " else label + " ".repeat(width - label.length)

    fun domainLabel(l: AppLanguage): String = pad(l.pick(mapOf(
        EN to "Domain:",
        DE to "Domain:",
        FR to "Domaine :",
        ES to "Dominio:",
        RU to "Домен:",
        UK to "Домен:",
        IT to "Dominio:",
        JA to "ドメイン:",
        ZH to "域名:"
    )))

    fun mailHostLabel(l: AppLanguage): String = pad(l.pick(mapOf(
        EN to "Mail host:",
        DE to "Mailhost:",
        FR to "Hôte mail :",
        ES to "Host de correo:",
        RU to "Почтовый хост:",
        UK to "Поштовий хост:",
        IT to "Host di posta:",
        JA to "メールホスト:",
        ZH to "邮件主机:"
    )))

    fun tunnelReportLine(l: AppLanguage, endpoint: String): String {
        val label = l.pick(mapOf(
            EN to "Tunnel:",
            DE to "Tunnel:",
            FR to "Tunnel :",
            ES to "Túnel:",
            RU to "Туннель:",
            UK to "Тунель:",
            IT to "Tunnel:",
            JA to "トンネル:",
            ZH to "隧道:"
        ))
        val note = l.pick(mapOf(
            EN to "(full tunnel — outgoing traffic uses the VPS IP)",
            DE to "(voller Tunnel — ausgehender Verkehr nutzt die VPS-IP)",
            FR to "(tunnel complet — le trafic sortant utilise l'IP du VPS)",
            ES to "(túnel completo — el tráfico saliente usa la IP del VPS)",
            RU to "(полный туннель — исходящий трафик с IP VPS)",
            UK to "(повний тунель — вихідний трафік з IP VPS)",
            IT to "(tunnel completo — il traffico in uscita usa l'IP del VPS)",
            JA to "(フルトンネル — 送信トラフィックは VPS の IP を使用)",
            ZH to "（全隧道 — 出站流量使用 VPS 的 IP）"
        ))
        return pad(label) + "wg0 -> $endpoint " + note
    }

    fun crowdsecInstallingLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Intrusion defence: CrowdSec (watches ssh and Caddy, bans on the firewall)",
        DE to "Angriffserkennung: CrowdSec (überwacht ssh und Caddy, sperrt über die Firewall)",
        FR to "Défense contre les intrusions : CrowdSec (surveille ssh et Caddy, bannit via le pare-feu)",
        ES to "Defensa contra intrusiones: CrowdSec (vigila ssh y Caddy, bloquea mediante el cortafuegos)",
        RU to "Защита от вторжений: CrowdSec (следит за ssh и Caddy, блокирует через firewall)",
        UK to "Захист від вторгнень: CrowdSec (стежить за ssh і Caddy, блокує через firewall)",
        IT to "Difesa dalle intrusioni: CrowdSec (osserva ssh e Caddy, blocca tramite il firewall)",
        JA to "侵入防御: CrowdSec (ssh と Caddy を監視し、ファイアウォールで遮断します)",
        ZH to "入侵防御：CrowdSec（监视 ssh 与 Caddy，通过防火墙封禁）"
    ))

    fun crowdsecDisabledLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Intrusion defence: off for this deployment (recommended, not required)",
        DE to "Angriffserkennung: für diese Bereitstellung deaktiviert (empfohlen, aber nicht erforderlich)",
        FR to "Défense contre les intrusions : désactivée pour ce déploiement (recommandée, non obligatoire)",
        ES to "Defensa contra intrusiones: desactivada para este despliegue (recomendada, no obligatoria)",
        RU to "Защита от вторжений: отключена для этого развёртывания (рекомендуется, но не обязательна)",
        UK to "Захист від вторгнень: вимкнено для цього розгортання (рекомендовано, але не обов'язково)",
        IT to "Difesa dalle intrusioni: disattivata per questa distribuzione (consigliata, non obbligatoria)",
        JA to "侵入防御: このデプロイでは無効です (推奨ですが必須ではありません)",
        ZH to "入侵防御：本次部署已关闭（建议开启，但非必需）"
    ))

    fun crowdsecFailedLog(l: AppLanguage): String = l.pick(mapOf(
        EN to "Intrusion defence (CrowdSec) did not finish installing — continuing without it. Everything else on this server is unaffected.",
        DE to "Die Angriffserkennung (CrowdSec) wurde nicht vollständig installiert — es wird ohne sie fortgefahren. Alles andere auf diesem Server ist davon nicht betroffen.",
        FR to "La défense contre les intrusions (CrowdSec) ne s’est pas installée entièrement — la suite continue sans elle. Le reste de ce serveur n’est pas concerné.",
        ES to "La defensa contra intrusiones (CrowdSec) no terminó de instalarse — se continúa sin ella. El resto de este servidor no se ve afectado.",
        RU to "Защита от вторжений (CrowdSec) не установилась до конца — установка продолжается без неё. На остальную часть сервера это не влияет.",
        UK to "Захист від вторгнень (CrowdSec) не встановився повністю — встановлення триває без нього. На решту сервера це не впливає.",
        IT to "La difesa dalle intrusioni (CrowdSec) non ha completato l’installazione — si continua senza di essa. Il resto di questo server non ne risente.",
        JA to "侵入防御 (CrowdSec) のインストールが完了しませんでした — それなしで続行します。このサーバーの他の部分には影響しません。",
        ZH to "入侵防御（CrowdSec）未能完成安装——将继续而不使用它。此服务器上的其他部分不受影响。"
    ))
}

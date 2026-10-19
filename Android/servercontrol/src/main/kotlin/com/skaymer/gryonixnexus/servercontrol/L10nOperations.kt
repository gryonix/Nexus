package com.skaymer.gryonixnexus.servercontrol

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

/** Compiled-in translations for messages the dashboard shows the user */
object L10nOperations {
    fun restartNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support restart",
        DE to "Dienst $service unterstützt keinen Neustart",
        FR to "le service $service ne prend pas en charge le redémarrage",
        ES to "el servicio $service no admite el reinicio",
        RU to "сервис $service не поддерживает перезапуск",
        UK to "сервіс $service не підтримує перезапуск",
        IT to "il servizio $service non supporta il riavvio",
        JA to "サービス $service は再起動をサポートしていません",
        ZH to "服务 $service 不支持重启"
    ))
    fun startNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support being started",
        DE to "Dienst $service unterstützt kein Starten",
        FR to "le service $service ne prend pas en charge le démarrage",
        ES to "el servicio $service no admite el inicio",
        RU to "сервис $service не поддерживает запуск",
        UK to "сервіс $service не підтримує запуск",
        IT to "il servizio $service non supporta l’avvio",
        JA to "サービス $service は起動をサポートしていません",
        ZH to "服务 $service 不支持启动"
    ))
    fun stopNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support being stopped",
        DE to "Dienst $service unterstützt kein Stoppen",
        FR to "le service $service ne prend pas en charge l’arrêt",
        ES to "el servicio $service no admite la detención",
        RU to "сервис $service не поддерживает остановку",
        UK to "сервіс $service не підтримує зупинку",
        IT to "il servizio $service non supporta l’arresto",
        JA to "サービス $service は停止をサポートしていません",
        ZH to "服务 $service 不支持停止"
    ))
    fun logsNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not expose a log to read",
        DE to "Dienst $service stellt kein lesbares Protokoll bereit",
        FR to "le service $service n’expose aucun journal à lire",
        ES to "el servicio $service no expone un registro que se pueda leer",
        RU to "сервис $service не отдаёт лог для чтения",
        UK to "сервіс $service не віддає лог для читання",
        IT to "il servizio $service non espone un registro da leggere",
        JA to "サービス $service は読み取れるログを提供していません",
        ZH to "服务 $service 未提供可读取的日志"
    ))
    fun restoreNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service cannot be restored from a backup",
        DE to "Dienst $service kann nicht aus einem Backup wiederhergestellt werden",
        FR to "le service $service ne peut pas être restauré à partir d’une sauvegarde",
        ES to "el servicio $service no se puede restaurar desde una copia de seguridad",
        RU to "сервис $service нельзя восстановить из резервной копии",
        UK to "сервіс $service не можна відновити з резервної копії",
        IT to "il servizio $service non può essere ripristinato da un backup",
        JA to "サービス $service はバックアップから復元できません",
        ZH to "服务 $service 无法从备份恢复"
    ))
    fun restoreNeedsPassphrase(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "the $service backup is encrypted — its passphrase is required",
        DE to "das $service-Backup ist verschlüsselt — die Passphrase wird benötigt",
        FR to "la sauvegarde $service est chiffrée — sa phrase secrète est requise",
        ES to "la copia de $service está cifrada: se necesita su frase de contraseña",
        RU to "резервная копия $service зашифрована — нужна её парольная фраза",
        UK to "резервна копія $service зашифрована — потрібна її парольна фраза",
        IT to "il backup di $service è cifrato: serve la sua passphrase",
        JA to "$service のバックアップは暗号化されています。パスフレーズが必要です",
        ZH to "$service 备份已加密 — 需要其密码短语"
    ))
    fun restoreBadPath(l: AppLanguage, path: String): String = l.pick(mapOf(
        EN to "$path is not inside this service's backup directory",
        DE to "$path liegt nicht im Backup-Verzeichnis dieses Dienstes",
        FR to "$path ne se trouve pas dans le répertoire de sauvegarde de ce service",
        ES to "$path no está dentro del directorio de copias de este servicio",
        RU to "$path находится вне каталога резервных копий этого сервиса",
        UK to "$path розташовано поза каталогом резервних копій цього сервісу",
        IT to "$path non si trova nella cartella di backup di questo servizio",
        JA to "$path はこのサービスのバックアップディレクトリ内にありません",
        ZH to "$path 不在此服务的备份目录中"
    ))
    fun updateNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support update",
        DE to "Dienst $service unterstützt keine Aktualisierung",
        FR to "le service $service ne prend pas en charge la mise à jour",
        ES to "el servicio $service no admite la actualización",
        RU to "сервис $service не поддерживает обновление",
        UK to "сервіс $service не підтримує оновлення",
        IT to "il servizio $service non supporta l'aggiornamento",
        JA to "サービス $service は更新をサポートしていません",
        ZH to "服务 $service 不支持更新"
    ))
    fun backupKindNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support this kind of backup",
        DE to "Dienst $service unterstützt diese Art von Backup nicht",
        FR to "le service $service ne prend pas en charge ce type de sauvegarde",
        ES to "el servicio $service no admite este tipo de copia de seguridad",
        RU to "сервис $service не поддерживает такой бэкап",
        UK to "сервіс $service не підтримує такий бекап",
        IT to "il servizio $service non supporta questo tipo di backup",
        JA to "サービス $service はこの種類のバックアップをサポートしていません",
        ZH to "服务 $service 不支持此类备份"
    ))

    fun mailboxInvalidAddress(l: AppLanguage, address: String): String = l.pick(mapOf(
        EN to "$address is not a usable mailbox address: one name, one domain, latin letters, digits and . _ + - only",
        DE to "$address ist keine verwendbare Postfachadresse: ein Name, eine Domain, nur lateinische Buchstaben, Ziffern und . _ + -",
        FR to "$address n’est pas une adresse de boîte utilisable : un nom, un domaine, uniquement lettres latines, chiffres et . _ + -",
        ES to "$address no es una dirección de buzón utilizable: un nombre, un dominio, solo letras latinas, dígitos y . _ + -",
        RU to "$address — недопустимый адрес ящика: одно имя, один домен, только латинские буквы, цифры и . _ + -",
        UK to "$address — неприпустима адреса скриньки: одне ім’я, один домен, лише латинські літери, цифри та . _ + -",
        IT to "$address non è un indirizzo di casella utilizzabile: un nome, un dominio, solo lettere latine, cifre e . _ + -",
        JA to "$address は使用できないメールボックスアドレスです。名前とドメインは各1つ、使えるのはラテン文字・数字と . _ + - のみです",
        ZH to "$address 不是可用的邮箱地址：一个名称、一个域名，仅限拉丁字母、数字和 . _ + -"
    ))
    fun mailboxPasswordEmpty(l: AppLanguage): String = l.pick(mapOf(
        EN to "a mailbox password is required",
        DE to "ein Postfach-Passwort wird benötigt",
        FR to "un mot de passe de boîte est requis",
        ES to "se necesita una contraseña del buzón",
        RU to "нужен пароль для ящика",
        UK to "потрібен пароль для скриньки",
        IT to "serve una password della casella",
        JA to "メールボックスのパスワードが必要です",
        ZH to "需要邮箱密码"
    ))
    fun mailboxesNotAvailable(l: AppLanguage): String = l.pick(mapOf(
        EN to "this server has no Docker Mailserver installed",
        DE to "auf diesem Server ist kein Docker Mailserver installiert",
        FR to "aucun Docker Mailserver n’est installé sur ce serveur",
        ES to "este servidor no tiene Docker Mailserver instalado",
        RU to "на этом сервере не установлен Docker Mailserver",
        UK to "на цьому сервері не встановлено Docker Mailserver",
        IT to "su questo server non è installato Docker Mailserver",
        JA to "このサーバーには Docker Mailserver がインストールされていません",
        ZH to "此服务器未安装 Docker Mailserver"
    ))
    fun encryptedBackupNotSupported(l: AppLanguage, service: String): String = l.pick(mapOf(
        EN to "service $service does not support encrypted backup",
        DE to "Dienst $service unterstützt kein verschlüsseltes Backup",
        FR to "le service $service ne prend pas en charge la sauvegarde chiffrée",
        ES to "el servicio $service no admite la copia de seguridad cifrada",
        RU to "сервис $service не поддерживает шифрованный бэкап",
        UK to "сервіс $service не підтримує шифрований бекап",
        IT to "il servizio $service non supporta il backup cifrato",
        JA to "サービス $service は暗号化バックアップをサポートしていません",
        ZH to "服务 $service 不支持加密备份"
    ))
}

package com.skaymer.gryonixnexus.core

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

/** Compiled-in translation tables for [ValidationError] messages */
internal object L10nValidation {
    fun invalidDomain(l: AppLanguage, value: String): String = l.pick(mapOf(
        EN to "Invalid domain: \"$value\". Expected a format like example.com.",
        DE to "Ungültige Domain: „$value“. Erwartet wird ein Format wie example.com.",
        FR to "Domaine invalide : « $value ». Format attendu : example.com.",
        ES to "Dominio no válido: «$value». Se espera un formato como example.com.",
        RU to "Некорректный домен: «$value». Ожидается формат вида example.com.",
        UK to "Некоректний домен: «$value». Очікується формат на кшталт example.com.",
        IT to "Dominio non valido: \"$value\". È atteso un formato come example.com.",
        JA to "ドメインが正しくありません: 「$value」。example.com のような形式が必要です。",
        ZH to "域名无效：“$value”。应为类似 example.com 的格式。"
    ))

    fun invalidHostname(l: AppLanguage, value: String): String = l.pick(mapOf(
        EN to "Invalid hostname: \"$value\". Expected a format like mail.example.com.",
        DE to "Ungültiger Hostname: „$value“. Erwartet wird ein Format wie mail.example.com.",
        FR to "Nom d'hôte invalide : « $value ». Format attendu : mail.example.com.",
        ES to "Nombre de host no válido: «$value». Se espera un formato como mail.example.com.",
        RU to "Некорректное имя хоста: «$value». Ожидается формат вида mail.example.com.",
        UK to "Некоректне ім'я хоста: «$value». Очікується формат на кшталт mail.example.com.",
        IT to "Nome host non valido: \"$value\". È atteso un formato come mail.example.com.",
        JA to "ホスト名が正しくありません: 「$value」。mail.example.com のような形式が必要です。",
        ZH to "主机名无效：“$value”。应为类似 mail.example.com 的格式。"
    ))

    fun invalidAddress(l: AppLanguage, value: String): String = l.pick(mapOf(
        EN to "Invalid IP address: \"$value\".",
        DE to "Ungültige IP-Adresse: „$value“.",
        FR to "Adresse IP invalide : « $value ».",
        ES to "Dirección IP no válida: «$value».",
        RU to "Некорректный IP-адрес: «$value».",
        UK to "Некоректна IP-адреса: «$value».",
        IT to "Indirizzo IP non valido: \"$value\".",
        JA to "IP アドレスが正しくありません: 「$value」。",
        ZH to "IP 地址无效：“$value”。"
    ))

    fun missingPublicIP(l: AppLanguage, role: String): String = l.pick(mapOf(
        EN to "No public IP address specified for node \"$role\".",
        DE to "Für den Knoten „$role“ ist keine öffentliche IP-Adresse angegeben.",
        FR to "Aucune adresse IP publique indiquée pour le nœud « $role ».",
        ES to "No se ha indicado una dirección IP pública para el nodo «$role».",
        RU to "Для узла «$role» не указан публичный IP-адрес.",
        UK to "Для вузла «$role» не вказано публічну IP-адресу.",
        IT to "Nessun indirizzo IP pubblico specificato per il nodo \"$role\".",
        JA to "ノード「$role」のパブリック IP アドレスが指定されていません。",
        ZH to "未为节点“$role”指定公网 IP 地址。"
    ))

    fun missingVPNAddress(l: AppLanguage, role: String): String = l.pick(mapOf(
        EN to "No WireGuard-internal address specified for node \"$role\".",
        DE to "Für den Knoten „$role“ ist keine Adresse innerhalb von WireGuard angegeben.",
        FR to "Aucune adresse interne WireGuard indiquée pour le nœud « $role ».",
        ES to "No se ha indicado una dirección interna de WireGuard para el nodo «$role».",
        RU to "Для узла «$role» не указан адрес внутри WireGuard.",
        UK to "Для вузла «$role» не вказано адресу всередині WireGuard.",
        IT to "Nessun indirizzo interno a WireGuard specificato per il nodo \"$role\".",
        JA to "ノード「$role」の WireGuard 内アドレスが指定されていません。",
        ZH to "未为节点“$role”指定 WireGuard 内部地址。"
    ))
}

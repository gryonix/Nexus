import Foundation
import SwiftUI

enum CountryRegion: String, CaseIterable, Codable, Sendable, Identifiable {
    case australiaNewZealand
    case caribbean
    case centralAmerica
    case centralAsia
    case centralEurope
    case easternAfrica
    case easternAsia
    case easternEurope
    case melanesia
    case micronesia
    case middleAfrica
    case northAmerica
    case northernAfrica
    case northernAsia
    case northernEurope
    case polynesia
    case southAmerica
    case southEasternAsia
    case southeastEurope
    case southernAfrica
    case southernAsia
    case southernEurope
    case westernAfrica
    case westernAsia
    case westernEurope

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .australiaNewZealand: return "Australia and New Zealand"
        case .caribbean: return "Caribbean"
        case .centralAmerica: return "Central America"
        case .centralAsia: return "Central Asia"
        case .centralEurope: return "Central Europe"
        case .easternAfrica: return "Eastern Africa"
        case .easternAsia: return "East Asia"
        case .easternEurope: return "Eastern Europe"
        case .melanesia: return "Melanesia"
        case .micronesia: return "Micronesia"
        case .middleAfrica: return "Middle Africa"
        case .northAmerica: return "North America"
        case .northernAfrica: return "Northern Africa"
        case .northernAsia: return "Northern Asia"
        case .northernEurope: return "Northern Europe"
        case .polynesia: return "Polynesia"
        case .southAmerica: return "South America"
        case .southEasternAsia: return "Southeast Asia"
        case .southeastEurope: return "Southeast Europe"
        case .southernAfrica: return "Southern Africa"
        case .southernAsia: return "South Asia"
        case .southernEurope: return "Southern Europe"
        case .westernAfrica: return "Western Africa"
        case .westernAsia: return "Western Asia"
        case .westernEurope: return "Western Europe"
        }
    }

    var continent: Continent {
        switch self {
        case .australiaNewZealand: return .oceania
        case .caribbean: return .americas
        case .centralAmerica: return .americas
        case .centralAsia: return .asia
        case .centralEurope: return .europe
        case .easternAfrica: return .africa
        case .easternAsia: return .asia
        case .easternEurope: return .europe
        case .melanesia: return .oceania
        case .micronesia: return .oceania
        case .middleAfrica: return .africa
        case .northAmerica: return .americas
        case .northernAfrica: return .africa
        case .northernAsia: return .asia
        case .northernEurope: return .europe
        case .polynesia: return .oceania
        case .southAmerica: return .americas
        case .southEasternAsia: return .asia
        case .southeastEurope: return .europe
        case .southernAfrica: return .africa
        case .southernAsia: return .asia
        case .southernEurope: return .europe
        case .westernAfrica: return .africa
        case .westernAsia: return .asia
        case .westernEurope: return .europe
        }
    }
}

enum Continent: String, CaseIterable, Identifiable, Sendable {
    case africa
    case americas
    case asia
    case europe
    case oceania

    var id: String { rawValue }

    var displayName: LocalizedStringKey {
        switch self {
        case .africa: return "Africa"
        case .americas: return "Americas"
        case .asia: return "Asia"
        case .europe: return "Europe"
        case .oceania: return "Oceania"
        }
    }

    var regions: [CountryRegion] {
        CountryRegion.allCases.filter { $0.continent == self }
    }
}

enum CountryCatalog {
    /// Generated — see `CountryRegion`'s header
    static let regionByCode: [String: CountryRegion] = [
        "AD": .southernEurope,
        "AE": .westernAsia,
        "AF": .southernAsia,
        "AG": .caribbean,
        "AI": .caribbean,
        "AL": .southeastEurope,
        "AM": .westernAsia,
        "AO": .middleAfrica,
        "AR": .southAmerica,
        "AS": .polynesia,
        "AT": .centralEurope,
        "AU": .australiaNewZealand,
        "AW": .caribbean,
        "AX": .northernEurope,
        "AZ": .westernAsia,
        "BA": .southeastEurope,
        "BB": .caribbean,
        "BD": .southernAsia,
        "BE": .westernEurope,
        "BF": .westernAfrica,
        "BG": .southeastEurope,
        "BH": .westernAsia,
        "BI": .easternAfrica,
        "BJ": .westernAfrica,
        "BL": .caribbean,
        "BM": .northAmerica,
        "BN": .southEasternAsia,
        "BO": .southAmerica,
        "BQ": .caribbean,
        "BR": .southAmerica,
        "BS": .caribbean,
        "BT": .southernAsia,
        "BW": .southernAfrica,
        "BY": .easternEurope,
        "BZ": .centralAmerica,
        "CA": .northAmerica,
        "CC": .australiaNewZealand,
        "CD": .middleAfrica,
        "CF": .middleAfrica,
        "CG": .middleAfrica,
        "CH": .westernEurope,
        "CI": .westernAfrica,
        "CK": .polynesia,
        "CL": .southAmerica,
        "CM": .middleAfrica,
        "CN": .easternAsia,
        "CO": .southAmerica,
        "CR": .centralAmerica,
        "CU": .caribbean,
        "CV": .westernAfrica,
        "CW": .caribbean,
        "CX": .australiaNewZealand,
        "CY": .southernEurope,
        "CZ": .centralEurope,
        "DE": .westernEurope,
        "DJ": .easternAfrica,
        "DK": .northernEurope,
        "DM": .caribbean,
        "DO": .caribbean,
        "DZ": .northernAfrica,
        "EC": .southAmerica,
        "EE": .northernEurope,
        "EG": .northernAfrica,
        "EH": .northernAfrica,
        "ER": .easternAfrica,
        "ES": .southernEurope,
        "ET": .easternAfrica,
        "FI": .northernEurope,
        "FJ": .melanesia,
        "FK": .southAmerica,
        "FM": .micronesia,
        "FO": .northernEurope,
        "FR": .westernEurope,
        "GA": .middleAfrica,
        "GB": .northernEurope,
        "GD": .caribbean,
        "GE": .westernAsia,
        "GF": .southAmerica,
        "GG": .northernEurope,
        "GH": .westernAfrica,
        "GI": .southernEurope,
        "GL": .northAmerica,
        "GM": .westernAfrica,
        "GN": .westernAfrica,
        "GP": .caribbean,
        "GQ": .middleAfrica,
        "GR": .southernEurope,
        "GT": .centralAmerica,
        "GU": .micronesia,
        "GW": .westernAfrica,
        "GY": .southAmerica,
        "HK": .easternAsia,
        "HN": .centralAmerica,
        "HR": .southeastEurope,
        "HT": .caribbean,
        "HU": .centralEurope,
        "ID": .southEasternAsia,
        "IE": .northernEurope,
        "IL": .westernAsia,
        "IM": .northernEurope,
        "IN": .southernAsia,
        "IO": .easternAfrica,
        "IQ": .westernAsia,
        "IR": .southernAsia,
        "IS": .northernEurope,
        "IT": .southernEurope,
        "JE": .northernEurope,
        "JM": .caribbean,
        "JO": .westernAsia,
        "JP": .easternAsia,
        "KE": .easternAfrica,
        "KG": .centralAsia,
        "KH": .southEasternAsia,
        "KI": .micronesia,
        "KM": .easternAfrica,
        "KN": .caribbean,
        "KP": .easternAsia,
        "KR": .easternAsia,
        "KW": .westernAsia,
        "KY": .caribbean,
        "KZ": .centralAsia,
        "LA": .southEasternAsia,
        "LB": .westernAsia,
        "LC": .caribbean,
        "LI": .westernEurope,
        "LK": .southernAsia,
        "LR": .westernAfrica,
        "LS": .southernAfrica,
        "LT": .northernEurope,
        "LU": .westernEurope,
        "LV": .northernEurope,
        "LY": .northernAfrica,
        "MA": .northernAfrica,
        "MC": .westernEurope,
        "MD": .easternEurope,
        "ME": .southeastEurope,
        "MF": .caribbean,
        "MG": .easternAfrica,
        "MH": .micronesia,
        "MK": .southeastEurope,
        "ML": .westernAfrica,
        "MM": .southEasternAsia,
        "MN": .easternAsia,
        "MO": .easternAsia,
        "MP": .micronesia,
        "MQ": .caribbean,
        "MR": .westernAfrica,
        "MS": .caribbean,
        "MT": .southernEurope,
        "MU": .easternAfrica,
        "MV": .southernAsia,
        "MW": .easternAfrica,
        "MX": .northAmerica,
        "MY": .southEasternAsia,
        "MZ": .easternAfrica,
        "NA": .southernAfrica,
        "NC": .melanesia,
        "NE": .westernAfrica,
        "NF": .australiaNewZealand,
        "NG": .westernAfrica,
        "NI": .centralAmerica,
        "NL": .westernEurope,
        "NO": .northernEurope,
        "NP": .southernAsia,
        "NR": .micronesia,
        "NU": .polynesia,
        "NZ": .australiaNewZealand,
        "OM": .westernAsia,
        "PA": .centralAmerica,
        "PE": .southAmerica,
        "PF": .polynesia,
        "PG": .melanesia,
        "PH": .southEasternAsia,
        "PK": .southernAsia,
        "PL": .centralEurope,
        "PM": .northAmerica,
        "PN": .polynesia,
        "PR": .caribbean,
        "PS": .westernAsia,
        "PT": .southernEurope,
        "PW": .micronesia,
        "PY": .southAmerica,
        "QA": .westernAsia,
        "RE": .easternAfrica,
        "RO": .southeastEurope,
        "RS": .southeastEurope,
        "RU": .northernAsia,
        "RW": .easternAfrica,
        "SA": .westernAsia,
        "SB": .melanesia,
        "SC": .easternAfrica,
        "SD": .northernAfrica,
        "SE": .northernEurope,
        "SG": .southEasternAsia,
        "SH": .westernAfrica,
        "SI": .centralEurope,
        "SJ": .northernEurope,
        "SK": .centralEurope,
        "SL": .westernAfrica,
        "SM": .southernEurope,
        "SN": .westernAfrica,
        "SO": .easternAfrica,
        "SR": .southAmerica,
        "SS": .middleAfrica,
        "ST": .middleAfrica,
        "SV": .centralAmerica,
        "SX": .caribbean,
        "SY": .westernAsia,
        "SZ": .southernAfrica,
        "TC": .caribbean,
        "TD": .middleAfrica,
        "TG": .westernAfrica,
        "TH": .southEasternAsia,
        "TJ": .centralAsia,
        "TK": .polynesia,
        "TL": .southEasternAsia,
        "TM": .centralAsia,
        "TN": .northernAfrica,
        "TO": .polynesia,
        "TR": .westernAsia,
        "TT": .caribbean,
        "TV": .polynesia,
        "TW": .easternAsia,
        "TZ": .easternAfrica,
        "UA": .easternEurope,
        "UG": .easternAfrica,
        "UM": .northAmerica,
        "US": .northAmerica,
        "UY": .southAmerica,
        "UZ": .centralAsia,
        "VA": .southernEurope,
        "VC": .caribbean,
        "VE": .southAmerica,
        "VG": .caribbean,
        "VI": .caribbean,
        "VN": .southEasternAsia,
        "VU": .melanesia,
        "WF": .polynesia,
        "WS": .polynesia,
        "XK": .southeastEurope,
        "YE": .westernAsia,
        "YT": .easternAfrica,
        "ZA": .southernAfrica,
        "ZM": .easternAfrica,
        "ZW": .easternAfrica,
    ]

    static func codes(in region: CountryRegion) -> [String] {
        regionByCode.compactMap { $0.value == region ? $0.key : nil }.sorted()
    }

    static func codes(in continent: Continent) -> [String] {
        regionByCode.compactMap { $0.value.continent == continent ? $0.key : nil }.sorted()
    }

    static let allCodes: [String] = regionByCode.keys.sorted()

    static func name(for code: String, locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: code) ?? code
    }

    static func flag(_ code: String) -> String {
        let upper = code.uppercased()
        guard upper.count == 2, upper.allSatisfy({ $0.isLetter && $0.isASCII }) else { return "" }
        return String(upper.unicodeScalars.compactMap {
            Unicode.Scalar(127_397 + $0.value)
        }.map(Character.init))
    }
}

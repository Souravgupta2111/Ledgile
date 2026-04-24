// IndianStates.swift
// All 37 Indian States/UTs with GST codes

import Foundation

struct IndianState {
    let name: String
    let code: String      // 2-digit GST state code
    let shortCode: String // e.g., "MH", "DL"
}

enum IndianStates {

    /// All 37 states/UTs recognized by GST
    static let all: [IndianState] = [
        IndianState(name: "Jammu & Kashmir",          code: "01", shortCode: "JK"),
        IndianState(name: "Himachal Pradesh",          code: "02", shortCode: "HP"),
        IndianState(name: "Punjab",                    code: "03", shortCode: "PB"),
        IndianState(name: "Chandigarh",                code: "04", shortCode: "CH"),
        IndianState(name: "Uttarakhand",               code: "05", shortCode: "UK"),
        IndianState(name: "Haryana",                   code: "06", shortCode: "HR"),
        IndianState(name: "Delhi",                     code: "07", shortCode: "DL"),
        IndianState(name: "Rajasthan",                 code: "08", shortCode: "RJ"),
        IndianState(name: "Uttar Pradesh",             code: "09", shortCode: "UP"),
        IndianState(name: "Bihar",                     code: "10", shortCode: "BR"),
        IndianState(name: "Sikkim",                    code: "11", shortCode: "SK"),
        IndianState(name: "Arunachal Pradesh",         code: "12", shortCode: "AR"),
        IndianState(name: "Nagaland",                  code: "13", shortCode: "NL"),
        IndianState(name: "Manipur",                   code: "14", shortCode: "MN"),
        IndianState(name: "Mizoram",                   code: "15", shortCode: "MZ"),
        IndianState(name: "Tripura",                   code: "16", shortCode: "TR"),
        IndianState(name: "Meghalaya",                 code: "17", shortCode: "ML"),
        IndianState(name: "Assam",                     code: "18", shortCode: "AS"),
        IndianState(name: "West Bengal",               code: "19", shortCode: "WB"),
        IndianState(name: "Jharkhand",                 code: "20", shortCode: "JH"),
        IndianState(name: "Odisha",                    code: "21", shortCode: "OD"),
        IndianState(name: "Chhattisgarh",              code: "22", shortCode: "CG"),
        IndianState(name: "Madhya Pradesh",            code: "23", shortCode: "MP"),
        IndianState(name: "Gujarat",                   code: "24", shortCode: "GJ"),
        IndianState(name: "Dadra & Nagar Haveli and Daman & Diu", code: "26", shortCode: "DD"),
        IndianState(name: "Maharashtra",               code: "27", shortCode: "MH"),
        IndianState(name: "Andhra Pradesh",            code: "28", shortCode: "AP"),  // Old code (pre-bifurcation)
        IndianState(name: "Karnataka",                 code: "29", shortCode: "KA"),
        IndianState(name: "Goa",                       code: "30", shortCode: "GA"),
        IndianState(name: "Lakshadweep",               code: "31", shortCode: "LD"),
        IndianState(name: "Kerala",                    code: "32", shortCode: "KL"),
        IndianState(name: "Tamil Nadu",                code: "33", shortCode: "TN"),
        IndianState(name: "Puducherry",                code: "34", shortCode: "PY"),
        IndianState(name: "Andaman & Nicobar Islands", code: "35", shortCode: "AN"),
        IndianState(name: "Telangana",                 code: "36", shortCode: "TS"),
        IndianState(name: "Andhra Pradesh (New)",      code: "37", shortCode: "AP"),
        IndianState(name: "Ladakh",                    code: "38", shortCode: "LA"),
    ]

    /// State names sorted alphabetically for picker display
    static let sortedNames: [String] = all.map { $0.name }.sorted()

    /// Lookup by name (case-insensitive)
    static func stateByName(_ name: String) -> IndianState? {
        all.first { $0.name.lowercased() == name.lowercased() }
    }

    /// Lookup by 2-digit code
    static func stateByCode(_ code: String) -> IndianState? {
        all.first { $0.code == code }
    }

    /// Extract state code from GSTIN (first 2 characters)
    static func stateFromGSTIN(_ gstin: String) -> IndianState? {
        guard gstin.count >= 2 else { return nil }
        let code = String(gstin.prefix(2))
        return stateByCode(code)
    }

    /// Check if two state codes are the same (intra-state)
    static func isIntraState(_ code1: String, _ code2: String) -> Bool {
        code1 == code2
    }

    /// Valid GST rates in India
    static let validGSTRates: [Double] = [0, 0.25, 3, 5, 12, 18, 28]
}

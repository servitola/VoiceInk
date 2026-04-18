import Foundation
import SQLite3

// MARK: - JSON Model (matches DictionaryImportExportService.swift)

struct DictionaryExportData: Codable {
    let version: String
    let vocabularyWords: [String]
    let wordReplacements: [String: String]
    let exportDate: Date
}

// MARK: - Constants

let databasePath: String = {
    let home = FileManager.default.homeDirectoryForCurrentUser
    return home
        .appendingPathComponent("Library/Application Support/com.prakashjoshipax.VoiceInk/dictionary.store")
        .path
}()

// MARK: - SQLite Helpers

func openDatabase(readonly: Bool) -> OpaquePointer? {
    var db: OpaquePointer?
    let flags = readonly ? SQLITE_OPEN_READONLY : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
    let rc = sqlite3_open_v2(databasePath, &db, flags | SQLITE_OPEN_FULLMUTEX, nil)
    guard rc == SQLITE_OK else {
        if let db = db {
            let msg = String(cString: sqlite3_errmsg(db))
            sqlite3_close(db)
            fputs("Error opening database: \(msg)\n", stderr)
        } else {
            fputs("Error opening database at \(databasePath)\n", stderr)
        }
        return nil
    }
    sqlite3_busy_timeout(db, 5000)
    return db
}

func queryString(_ db: OpaquePointer, _ sql: String) -> [[String: Any]] {
    var stmt: OpaquePointer?
    guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
        let msg = String(cString: sqlite3_errmsg(db))
        fputs("SQL error: \(msg)\n", stderr)
        return []
    }
    defer { sqlite3_finalize(stmt) }

    var rows: [[String: Any]] = []
    let colCount = sqlite3_column_count(stmt)

    while sqlite3_step(stmt) == SQLITE_ROW {
        var row: [String: Any] = [:]
        for i in 0..<colCount {
            let name = String(cString: sqlite3_column_name(stmt, i))
            switch sqlite3_column_type(stmt, i) {
            case SQLITE_INTEGER:
                row[name] = sqlite3_column_int64(stmt, i)
            case SQLITE_FLOAT:
                row[name] = sqlite3_column_double(stmt, i)
            case SQLITE_TEXT:
                row[name] = String(cString: sqlite3_column_text(stmt, i))
            case SQLITE_NULL:
                row[name] = nil as Any?
            default:
                break
            }
        }
        rows.append(row)
    }
    return rows
}

func exec(_ db: OpaquePointer, _ sql: String) -> Bool {
    var errMsg: UnsafeMutablePointer<CChar>?
    let rc = sqlite3_exec(db, sql, nil, nil, &errMsg)
    if rc != SQLITE_OK {
        if let errMsg = errMsg {
            fputs("SQL error: \(String(cString: errMsg))\n", stderr)
            sqlite3_free(errMsg)
        }
        return false
    }
    return true
}

// MARK: - Export

func exportDictionary(to path: String) {
    guard FileManager.default.fileExists(atPath: databasePath) else {
        fputs("Database not found at \(databasePath)\nHas VoiceInk been run at least once?\n", stderr)
        exit(1)
    }

    guard let db = openDatabase(readonly: true) else { exit(1) }
    defer { sqlite3_close(db) }

    // Fetch vocabulary words
    let wordRows = queryString(db, "SELECT ZWORD FROM ZVOCABULARYWORD ORDER BY ZWORD")
    let words = wordRows.compactMap { $0["ZWORD"] as? String }

    // Fetch word replacements
    let replRows = queryString(db, "SELECT ZORIGINALTEXT, ZREPLACEMENTTEXT FROM ZWORDREPLACEMENT")
    var replacements: [String: String] = [:]
    for row in replRows {
        if let orig = row["ZORIGINALTEXT"] as? String,
           let repl = row["ZREPLACEMENTTEXT"] as? String {
            replacements[orig] = repl
        }
    }

    let exportData = DictionaryExportData(
        version: "1.0",
        vocabularyWords: words,
        wordReplacements: replacements,
        exportDate: Date()
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601

    do {
        let jsonData = try encoder.encode(exportData)

        // Create intermediate directories if needed
        let dir = (path as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        try jsonData.write(to: URL(fileURLWithPath: path))
        print("Exported \(words.count) vocabulary words and \(replacements.count) replacements to \(path)")
    } catch {
        fputs("Export failed: \(error.localizedDescription)\n", stderr)
        exit(1)
    }
}

// MARK: - Import

func importDictionary(from path: String) {
    guard FileManager.default.fileExists(atPath: databasePath) else {
        fputs("Database not found at \(databasePath)\nHas VoiceInk been run at least once?\n", stderr)
        exit(1)
    }

    // Read and decode JSON
    let importData: DictionaryExportData
    do {
        let jsonData = try Data(contentsOf: URL(fileURLWithPath: path))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        importData = try decoder.decode(DictionaryExportData.self, from: jsonData)
    } catch {
        fputs("Failed to read \(path): \(error.localizedDescription)\n", stderr)
        exit(1)
    }

    guard let db = openDatabase(readonly: false) else { exit(1) }
    defer { sqlite3_close(db) }

    guard exec(db, "BEGIN IMMEDIATE") else {
        fputs("Could not begin transaction (database may be locked)\n", stderr)
        exit(1)
    }

    // Read entity numbers from Z_PRIMARYKEY
    let pkRows = queryString(db, "SELECT Z_ENT, Z_NAME, Z_MAX FROM Z_PRIMARYKEY WHERE Z_NAME IN ('VocabularyWord', 'WordReplacement')")
    var entVocab: Int64 = 2
    var entRepl: Int64 = 3
    var maxPkVocab: Int64 = 0
    var maxPkRepl: Int64 = 0
    for row in pkRows {
        let name = row["Z_NAME"] as? String ?? ""
        let ent = row["Z_ENT"] as? Int64 ?? 0
        let max = row["Z_MAX"] as? Int64 ?? 0
        if name == "VocabularyWord" { entVocab = ent; maxPkVocab = max }
        if name == "WordReplacement" { entRepl = ent; maxPkRepl = max }
    }

    let now = Date().timeIntervalSinceReferenceDate

    // Import vocabulary words
    let existingWords = Set(
        queryString(db, "SELECT ZWORD FROM ZVOCABULARYWORD")
            .compactMap { ($0["ZWORD"] as? String)?.lowercased() }
    )

    var wordsAdded = 0
    for word in importData.vocabularyWords {
        if existingWords.contains(word.lowercased()) { continue }
        maxPkVocab += 1
        var stmt: OpaquePointer?
        let sql = "INSERT INTO ZVOCABULARYWORD (Z_PK, Z_ENT, Z_OPT, ZDATEADDED, ZWORD) VALUES (?, ?, 1, ?, ?)"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, maxPkVocab)
            sqlite3_bind_int64(stmt, 2, entVocab)
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_bind_text(stmt, 4, (word as NSString).utf8String, -1, nil)
            if sqlite3_step(stmt) == SQLITE_DONE { wordsAdded += 1 }
            sqlite3_finalize(stmt)
        }
    }

    // Import word replacements
    let existingOriginals = Set(
        queryString(db, "SELECT ZORIGINALTEXT FROM ZWORDREPLACEMENT")
            .compactMap { ($0["ZORIGINALTEXT"] as? String)?.lowercased() }
    )

    var replAdded = 0
    for (original, replacement) in importData.wordReplacements {
        if existingOriginals.contains(original.lowercased()) { continue }
        maxPkRepl += 1
        var stmt: OpaquePointer?
        let sql = "INSERT INTO ZWORDREPLACEMENT (Z_PK, Z_ENT, Z_OPT, ZISENABLED, ZDATEADDED, ZORIGINALTEXT, ZREPLACEMENTTEXT, ZID) VALUES (?, ?, 1, 1, ?, ?, ?, ?)"
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK {
            sqlite3_bind_int64(stmt, 1, maxPkRepl)
            sqlite3_bind_int64(stmt, 2, entRepl)
            sqlite3_bind_double(stmt, 3, now)
            sqlite3_bind_text(stmt, 4, (original as NSString).utf8String, -1, nil)
            sqlite3_bind_text(stmt, 5, (replacement as NSString).utf8String, -1, nil)
            // UUID as 16-byte blob
            let uuid = UUID()
            _ = withUnsafeBytes(of: uuid.uuid) { buffer in
                sqlite3_bind_blob(stmt, 6, buffer.baseAddress, Int32(buffer.count), nil)
            }
            if sqlite3_step(stmt) == SQLITE_DONE { replAdded += 1 }
            sqlite3_finalize(stmt)
        }
    }

    // Update Z_PRIMARYKEY max values
    _ = exec(db, "UPDATE Z_PRIMARYKEY SET Z_MAX = \(maxPkVocab) WHERE Z_NAME = 'VocabularyWord'")
    _ = exec(db, "UPDATE Z_PRIMARYKEY SET Z_MAX = \(maxPkRepl) WHERE Z_NAME = 'WordReplacement'")

    guard exec(db, "COMMIT") else {
        fputs("Failed to commit transaction\n", stderr)
        _ = exec(db, "ROLLBACK")
        exit(1)
    }

    print("Imported \(wordsAdded) new vocabulary words and \(replAdded) new replacements from \(path)")
    if wordsAdded > 0 || replAdded > 0 {
        print("Note: Restart VoiceInk or re-open Dictionary settings to see changes.")
    }
}

// MARK: - Main

func printUsage() {
    let name = (CommandLine.arguments[0] as NSString).lastPathComponent
    fputs("""
    Usage: \(name) <command> <path>

    Commands:
      export <path>  Export dictionary to JSON file
      import <path>  Import dictionary from JSON file

    Examples:
      \(name) export ~/dotfiles/voiceink/dictionary.json
      \(name) import ~/dotfiles/voiceink/dictionary.json

    """, stderr)
}

let args = CommandLine.arguments
guard args.count == 3 else {
    printUsage()
    exit(1)
}

let command = args[1]
let path = (args[2] as NSString).expandingTildeInPath

switch command {
case "export":
    exportDictionary(to: path)
case "import":
    importDictionary(from: path)
default:
    fputs("Unknown command: \(command)\n\n", stderr)
    printUsage()
    exit(1)
}

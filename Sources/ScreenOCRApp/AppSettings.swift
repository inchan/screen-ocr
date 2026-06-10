import AppKit
import Carbon.HIToolbox
import Foundation

/// OCR engine to use for text recognition.
enum OCREngineChoice: String, Codable, CaseIterable {
    case paddleOCR = "paddleocr"
    case vision = "vision"
}

/// A user-configurable global hotkey, stored as Carbon virtual key code + Carbon modifier mask
/// (the same values `RegisterEventHotKey` expects), plus a cached human-readable label.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayString: String

    /// Default capture shortcut: ⇧⌘0.
    static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_0),
        modifiers: UInt32(cmdKey | shiftKey),
        displayString: "⇧⌘0"
    )
}

/// Persisted user preferences. Codable so the whole struct round-trips through settings.json;
/// every field has a default so older/partial files still decode.
struct AppSettings: Codable, Equatable {
    var saveScreenshots: Bool
    var saveTextResults: Bool
    var saveDirectoryPath: String
    /// Days to keep saved files before the retention sweep deletes them. 0 disables cleanup.
    var retentionDays: Int
    var launchAtLogin: Bool
    var hotkey: HotkeyConfig
    /// When on, the step-by-step OCR progress popup (per-stage timings) is shown. Off by default:
    /// ordinary users only see a single-line completion toast.
    var showDebugProgress: Bool
    /// OCR engine used for text recognition. Defaults to PaddleOCR for backward compatibility.
    var ocrEngine: OCREngineChoice

    init(
        saveScreenshots: Bool = true,
        saveTextResults: Bool = true,
        saveDirectoryPath: String = AppSettings.defaultSaveDirectory().path,
        retentionDays: Int = 1,
        launchAtLogin: Bool = false,
        hotkey: HotkeyConfig = .default,
        showDebugProgress: Bool = false,
        ocrEngine: OCREngineChoice = .paddleOCR
    ) {
        self.saveScreenshots = saveScreenshots
        self.saveTextResults = saveTextResults
        self.saveDirectoryPath = saveDirectoryPath
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
        self.showDebugProgress = showDebugProgress
        self.ocrEngine = ocrEngine
    }

    // Decode defensively: a missing key falls back to its default rather than failing the load.
    enum CodingKeys: String, CodingKey {
        case saveScreenshots, saveTextResults, saveDirectoryPath, retentionDays, launchAtLogin, hotkey, showDebugProgress, ocrEngine
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppSettings()
        saveScreenshots = try container.decodeIfPresent(Bool.self, forKey: .saveScreenshots) ?? defaults.saveScreenshots
        saveTextResults = try container.decodeIfPresent(Bool.self, forKey: .saveTextResults) ?? defaults.saveTextResults
        saveDirectoryPath = try container.decodeIfPresent(String.self, forKey: .saveDirectoryPath) ?? defaults.saveDirectoryPath
        retentionDays = try container.decodeIfPresent(Int.self, forKey: .retentionDays) ?? defaults.retentionDays
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? defaults.launchAtLogin
        hotkey = try container.decodeIfPresent(HotkeyConfig.self, forKey: .hotkey) ?? defaults.hotkey
        showDebugProgress = try container.decodeIfPresent(Bool.self, forKey: .showDebugProgress) ?? defaults.showDebugProgress
        ocrEngine = try container.decodeIfPresent(OCREngineChoice.self, forKey: .ocrEngine) ?? defaults.ocrEngine
    }

    var saveDirectoryURL: URL {
        URL(fileURLWithPath: saveDirectoryPath, isDirectory: true)
    }

    static func defaultSaveDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        return base
            .appendingPathComponent("Screen OCR", isDirectory: true)
            .appendingPathComponent("captures", isDirectory: true)
    }
}

/// Loads, persists, and broadcasts `AppSettings`. The single source of truth for preferences;
/// every mutation writes settings.json atomically and notifies observers on the main actor.
@MainActor
final class SettingsStore {
    private(set) var settings: AppSettings
    private let fileURL: URL
    private var observers: [(AppSettings) -> Void] = []

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        fileURL = base
            .appendingPathComponent("Screen OCR", isDirectory: true)
            .appendingPathComponent("settings.json")
        settings = SettingsStore.load(from: fileURL) ?? AppSettings()
    }

    /// Registers an observer and immediately invokes it with the current settings.
    func observe(_ handler: @escaping (AppSettings) -> Void) {
        observers.append(handler)
        handler(settings)
    }

    /// Mutates settings through a closure, persists, and notifies observers. Returns the new value.
    @discardableResult
    func update(_ mutate: (inout AppSettings) -> Void) -> AppSettings {
        var next = settings
        mutate(&next)
        guard next != settings else { return settings }
        settings = next
        persist()
        for observer in observers {
            observer(next)
        }
        return next
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(settings)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            NSLog("[ScreenOCR] failed to persist settings: \(error.localizedDescription)")
        }
    }

    private static func load(from url: URL) -> AppSettings? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(AppSettings.self, from: data)
    }
}

import AppKit
import Carbon.HIToolbox
import Foundation

/// OCR engine to use for text recognition.
enum OCREngineChoice: String, Codable, CaseIterable {
    case paddleOCR = "paddleocr"
    case vision = "vision"

    var isAvailableOnCurrentPlatform: Bool {
        switch self {
        case .paddleOCR:
            return true
        case .vision:
            #if os(macOS) && canImport(Vision)
            return true
            #else
            return false
            #endif
        }
    }

    static func normalizedForCurrentPlatform(_ engine: OCREngineChoice) -> OCREngineChoice {
        engine.isAvailableOnCurrentPlatform ? engine : .paddleOCR
    }
}

/// A user-configurable global hotkey, stored as Carbon virtual key code + Carbon modifier mask
/// (the same values `RegisterEventHotKey` expects), plus a cached human-readable label.
struct HotkeyConfig: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32
    var displayString: String

    /// Default capture shortcut: ⇧⌘2.
    static let `default` = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_2),
        modifiers: UInt32(cmdKey | shiftKey),
        displayString: "⇧⌘2"
    )

    /// Fallback used only when the first-launch default shortcut is unavailable.
    static let fallback = HotkeyConfig(
        keyCode: UInt32(kVK_ANSI_0),
        modifiers: UInt32(cmdKey | shiftKey),
        displayString: "⇧⌘0"
    )

    static func fallbackCandidate(afterRegistrationFailureOf config: HotkeyConfig) -> HotkeyConfig? {
        config == .default ? .fallback : nil
    }

    static func startupPreferredCandidate(for storedConfig: HotkeyConfig, autoFallback: Bool) -> HotkeyConfig {
        autoFallback && storedConfig == .fallback ? .default : storedConfig
    }
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
    /// True only when the app persisted `hotkey` as an automatic fallback from the default.
    var hotkeyAutoFallback: Bool
    /// When on, the step-by-step OCR progress popup (per-stage timings) is shown. Off by default:
    /// ordinary users only see a single-line completion toast.
    var showDebugProgress: Bool
    /// OCR engine used for text recognition. Defaults to Apple Vision when the platform supports it.
    var ocrEngine: OCREngineChoice
    /// PaddleOCR recognizer worker count. `nil` means Auto: use the Python sidecar's safe
    /// single-process default. Numeric values opt into recognizer parallelism.
    var paddleOCRWorkerCount: Int?
    /// Sparkle automatic update checks. Off by default because this unsigned build may still
    /// require Gatekeeper approval or Screen Recording permission re-approval after updating.
    var automaticUpdateChecks: Bool

    static let paddleOCRWorkerCountRange = 1...10

    init(
        saveScreenshots: Bool = true,
        saveTextResults: Bool = true,
        saveDirectoryPath: String = AppSettings.defaultSaveDirectory().path,
        retentionDays: Int = 1,
        launchAtLogin: Bool = false,
        hotkey: HotkeyConfig = .default,
        hotkeyAutoFallback: Bool = false,
        showDebugProgress: Bool = false,
        ocrEngine: OCREngineChoice = .vision,
        paddleOCRWorkerCount: Int? = nil,
        automaticUpdateChecks: Bool = false
    ) {
        self.saveScreenshots = saveScreenshots
        self.saveTextResults = saveTextResults
        self.saveDirectoryPath = saveDirectoryPath
        self.retentionDays = retentionDays
        self.launchAtLogin = launchAtLogin
        self.hotkey = hotkey
        self.hotkeyAutoFallback = hotkeyAutoFallback
        self.showDebugProgress = showDebugProgress
        self.ocrEngine = OCREngineChoice.normalizedForCurrentPlatform(ocrEngine)
        self.paddleOCRWorkerCount = Self.normalizedPaddleOCRWorkerCount(paddleOCRWorkerCount)
        self.automaticUpdateChecks = automaticUpdateChecks
    }

    // Decode defensively: a missing key falls back to its default rather than failing the load.
    enum CodingKeys: String, CodingKey {
        case saveScreenshots, saveTextResults, saveDirectoryPath, retentionDays, launchAtLogin, hotkey, hotkeyAutoFallback, showDebugProgress, ocrEngine, paddleOCRWorkerCount, automaticUpdateChecks
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
        hotkeyAutoFallback = try container.decodeIfPresent(Bool.self, forKey: .hotkeyAutoFallback) ?? (hotkey == .fallback)
        showDebugProgress = try container.decodeIfPresent(Bool.self, forKey: .showDebugProgress) ?? defaults.showDebugProgress
        let decodedEngine = try container.decodeIfPresent(OCREngineChoice.self, forKey: .ocrEngine) ?? defaults.ocrEngine
        ocrEngine = OCREngineChoice.normalizedForCurrentPlatform(decodedEngine)
        let decodedWorkerCount = try container.decodeIfPresent(Int.self, forKey: .paddleOCRWorkerCount)
        paddleOCRWorkerCount = Self.normalizedPaddleOCRWorkerCount(decodedWorkerCount)
        automaticUpdateChecks = try container.decodeIfPresent(Bool.self, forKey: .automaticUpdateChecks) ?? defaults.automaticUpdateChecks
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

    static func normalizedPaddleOCRWorkerCount(_ count: Int?) -> Int? {
        guard let count, paddleOCRWorkerCountRange.contains(count) else { return nil }
        return count
    }

    mutating func normalizeForCurrentPlatform() {
        ocrEngine = OCREngineChoice.normalizedForCurrentPlatform(ocrEngine)
        paddleOCRWorkerCount = Self.normalizedPaddleOCRWorkerCount(paddleOCRWorkerCount)
    }
}

/// Loads, persists, and broadcasts `AppSettings`. The single source of truth for preferences;
/// every mutation writes settings.json atomically and notifies observers on the main actor.
@MainActor
final class SettingsStore {
    private(set) var settings: AppSettings
    private let fileURL: URL
    private var observers: [(AppSettings) -> Void] = []

    init(fileURL overrideFileURL: URL? = nil) {
        if let overrideFileURL {
            fileURL = overrideFileURL
        } else {
            let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            fileURL = base
                .appendingPathComponent("Screen OCR", isDirectory: true)
                .appendingPathComponent("settings.json")
        }
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
        next.normalizeForCurrentPlatform()
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

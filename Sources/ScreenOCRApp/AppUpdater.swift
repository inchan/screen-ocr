import Foundation
import Sparkle

@MainActor
final class AppUpdater: NSObject {
    var onStatusChange: ((AppUpdateStatus) -> Void)?
    var onPreparedUpdateChanged: ((Bool, String?) -> Void)?

    private lazy var updaterController: SPUStandardUpdaterController = {
        SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()
    private var preparedInstallHandler: (() -> Void)?
    private var preparedVersion: String?
    private var didStart = false
    private var launchCheckTask: Task<Void, Never>?

    deinit {
        launchCheckTask?.cancel()
    }

    var currentVersion: String {
        SettingsWindowController.currentVersionString()
    }

    var status: AppUpdateStatus {
        guard isConfigured else {
            return .unavailable(currentVersion: currentVersion, message: copy.updateUnavailable)
        }
        guard isInstalledInApplications else {
            return .unavailable(currentVersion: currentVersion, message: copy.moveToApplications)
        }
        if let preparedVersion {
            return AppUpdateStatus(
                currentVersion: currentVersion,
                message: copy.updateReady(preparedVersion),
                availableVersion: preparedVersion,
                isChecking: false,
                canCheck: true,
                canInstall: preparedInstallHandler != nil
            )
        }
        return .idle(currentVersion: currentVersion)
    }

    func start(automaticChecksEnabled: Bool) {
        guard isConfigured, isInstalledInApplications else {
            publish(status)
            return
        }

        updaterController.updater.automaticallyChecksForUpdates = automaticChecksEnabled
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.updateCheckInterval = 86_400

        if !didStart {
            updaterController.startUpdater()
            didStart = true
        }

        publish(status)
        scheduleLaunchCheckIfNeeded(automaticChecksEnabled)
    }

    func setAutomaticChecksEnabled(_ enabled: Bool) {
        guard isConfigured, isInstalledInApplications else {
            publish(status)
            return
        }
        updaterController.updater.automaticallyChecksForUpdates = enabled
        updaterController.updater.automaticallyDownloadsUpdates = false
        publish(status)
        scheduleLaunchCheckIfNeeded(enabled)
    }

    func checkForUpdates() {
        guard isConfigured, isInstalledInApplications else {
            publish(status)
            return
        }
        publish(AppUpdateStatus(
            currentVersion: currentVersion,
            message: copy.checking,
            availableVersion: nil,
            isChecking: true,
            canCheck: true,
            canInstall: false
        ))
        updaterController.checkForUpdates(nil)
    }

    func installPreparedUpdateAndRelaunch() {
        preparedInstallHandler?()
    }

    private var isConfigured: Bool {
        guard let feed = Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              let publicKey = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String else {
            return false
        }
        return URL(string: feed) != nil && !publicKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var isInstalledInApplications: Bool {
        let applicationsPath = URL(fileURLWithPath: "/Applications", isDirectory: true)
            .standardizedFileURL
            .path
        return Bundle.main.bundleURL.standardizedFileURL.path.hasPrefix(applicationsPath + "/")
    }

    private func scheduleLaunchCheckIfNeeded(_ enabled: Bool) {
        launchCheckTask?.cancel()
        guard enabled else { return }
        launchCheckTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            guard !Task.isCancelled, let self else { return }
            self.updaterController.updater.checkForUpdatesInBackground()
        }
    }

    private func publish(_ next: AppUpdateStatus) {
        onStatusChange?(next)
        onPreparedUpdateChanged?(next.canInstall, next.availableVersion)
    }

    private var copy: AppUpdaterCopy {
        AppUpdaterCopy.current
    }
}

extension AppUpdater: SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        publish(AppUpdateStatus(
            currentVersion: currentVersion,
            message: copy.updateAvailable(item.displayVersionString),
            availableVersion: item.displayVersionString,
            isChecking: false,
            canCheck: true,
            canInstall: false
        ))
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        publish(AppUpdateStatus(
            currentVersion: currentVersion,
            message: copy.latest,
            availableVersion: nil,
            isChecking: false,
            canCheck: true,
            canInstall: false
        ))
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: any Error) {
        publish(AppUpdateStatus(
            currentVersion: currentVersion,
            message: copy.failed,
            availableVersion: nil,
            isChecking: false,
            canCheck: true,
            canInstall: false
        ))
    }

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        preparedVersion = item.displayVersionString
        preparedInstallHandler = immediateInstallHandler
        publish(status)
        return true
    }
}

private struct AppUpdaterCopy: Sendable {
    let updateUnavailable: String
    let moveToApplications: String
    let checking: String
    let latest: String
    let failed: String
    let updateAvailable: @Sendable (String) -> String
    let updateReady: @Sendable (String) -> String

    static var current: AppUpdaterCopy {
        let preferred = Locale.preferredLanguages.first?.lowercased()
        return preferred?.hasPrefix("ko") == true ? .korean : .english
    }

    private static let korean = AppUpdaterCopy(
        updateUnavailable: "업데이트 설정 필요",
        moveToApplications: "업데이트하려면 앱을 Applications 폴더로 이동하세요",
        checking: "업데이트 확인 중...",
        latest: "최신 버전입니다",
        failed: "마지막 확인 실패",
        updateAvailable: { "v\($0) 사용 가능" },
        updateReady: { "업데이트 준비됨: v\($0)" }
    )

    private static let english = AppUpdaterCopy(
        updateUnavailable: "Update setup required",
        moveToApplications: "Move the app to Applications to update",
        checking: "Checking for updates...",
        latest: "Up to date",
        failed: "Last check failed",
        updateAvailable: { "v\($0) available" },
        updateReady: { "Update ready: v\($0)" }
    )
}

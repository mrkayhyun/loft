import LoftKit
import Observation
import SwiftUI

/// Root state: navigation plus one model per section. All models share the
/// same engine client.
@Observable
@MainActor
final class AppModel {
    var section: AppSection = .overview
    let engine: EngineClient?
    let cleanup: CleanupModel
    let uninstaller: UninstallerModel
    let space: SpaceLensModel
    let monitor: MonitorModel
    private(set) var volume: VolumeInfo? = VolumeInfo.current()

    init() {
        let engine = EngineClient.locate()
        self.engine = engine
        cleanup = CleanupModel(engine: engine)
        uninstaller = UninstallerModel(engine: engine)
        space = SpaceLensModel(engine: engine)
        monitor = MonitorModel(engine: engine)
    }

    func refreshVolume() {
        volume = VolumeInfo.current()
    }

    func startSmartScan() {
        withAnimation(.smooth) { section = .cleanup }
        cleanup.scan()
    }
}

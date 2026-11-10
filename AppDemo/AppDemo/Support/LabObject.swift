/// Base class of the pure Swift non-screen objects: logs its deinit.
class LabObject {
    let logTag: String

    init(logTag: String) {
        self.logTag = logTag
    }

    deinit {
        LabLog.log("deinit \(logTag)")
    }
}

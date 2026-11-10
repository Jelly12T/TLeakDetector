//
//  TaskRegistry.swift
//  TLeakDetector
//
//  Created by thachlh on 10/11/26.
//

#if LEAK_DETECTOR_ENABLED
import Foundation
import MachO
import LeakCore
import LeakGraph
import LeakHeap

/// Unstructured tasks the app starts, seen as they are created: calls to `swift_task_create` from the
/// app's images are rebound to a hook. Structured child tasks (`async let`, task groups) cannot outlive
/// their parent and are not recorded.
///
/// Nothing here keeps a task or what it captured alive: the task is held through a native weak reference,
/// its operation's context through a weak or an unowned one, checked before every read (ADR 005).
package enum TaskRegistry {
    /// A task still running, kept alive with its operation's context for as long as this value lives.
    package struct LiveTask {
        package let address: UInt
        /// What it runs: `closure #1 in ProfileVC.viewDidLoad()`.
        package let operation: String
        /// The task in a retain graph: holds its operation, and through it what the operation captured.
        package let root: LiveHeap.Object
        package let createdAt: TimeInterval
        /// Keeps the task itself alive while this value lives.
        fileprivate let task: Retained

        package var holder: LeakHolder { LeakHolder(.task, detail: operation) }
    }

    // Two words, returned in registers like the runtime's AsyncTaskAndContext (x0/x1, rax/rdx).
    private typealias TaskAndContext = ldiv_t
    private typealias TaskCreate = @convention(c) (Int, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?, UnsafeRawPointer?) -> TaskAndContext

    nonisolated(unsafe) private static var original: TaskCreate?
    nonisolated(unsafe) private static var records: [Record] = []
    nonisolated(unsafe) private static var created = 0
    private static let lock = NSLock()
    /// TaskCreateFlags.Task_IsChildTask (swift/ABI/MetadataValues.h).
    private static let isChildTask = 1 << 8

    package static var isInstalled: Bool { original != nil }

    /// Records tasks created from now on by code in images whose path `includeImage` accepts. Called again,
    /// accepts the images either filter accepts.
    package static func install(includeImage: @escaping @Sendable (String) -> Bool) {
        lock.lock()
        defer { lock.unlock() }
        guard Runtime.shared != nil, let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "swift_task_create") else { return }
        guard original == nil else {
            let previous = Filter.includeImage ?? { _ in false }
            Filter.includeImage = { previous($0) || includeImage($0) }
            for index in 0..<_dyld_image_count() {
                guard let header = _dyld_get_image_header(index), let path = _dyld_get_image_name(index),
                      !previous(String(cString: path)), includeImage(String(cString: path)) else { continue }
                rebind(header, slide: _dyld_get_image_vmaddr_slide(index))
            }
            return
        }
        original = unsafeBitCast(symbol, to: TaskCreate.self)
        Filter.includeImage = includeImage
        _dyld_register_func_for_add_image { header, slide in
            guard let header, let filter = Filter.includeImage else { return }
            var info = Dl_info()
            guard dladdr(header, &info) != 0, let path = info.dli_fname, filter(String(cString: path)) else { return }
            TaskRegistry.rebind(header, slide: slide)
        }
    }

    private static func rebind(_ header: UnsafePointer<mach_header>, slide: Int) {
        SymbolRebinder.rebind("swift_task_create", to: unsafeBitCast(TaskRegistry.hook, to: UnsafeRawPointer.self),
                              in: header, slide: slide)
    }

    private enum Filter {
        nonisolated(unsafe) static var includeImage: (@Sendable (String) -> Bool)?
    }

    private static let hook: TaskCreate = { flags, options, resultType, entry, context in
        // Read before the task can start: the caller keeps the context alive during this call only.
        guard flags & TaskRegistry.isChildTask == 0, let context, let runtime = Runtime.shared,
              let operation = LiveHeap.taskOperation(ofContext: context),
              let operationContext = UnretainedHeapReference(address: operation.context) else {
            return TaskRegistry.original!(flags, options, resultType, entry, context)
        }
        let created = TaskRegistry.original!(flags, options, resultType, entry, context)
        TaskRegistry.record(task: UInt(bitPattern: created.quot), operation: operation, operationContext: operationContext,
                            runtime: runtime)
        return created
    }

    private static func record(task: UInt, operation: LiveHeap.TaskOperation, operationContext: UnretainedHeapReference,
                               runtime: Runtime) {
        guard let pointer = UnsafeRawPointer(bitPattern: task) else { return }
        let record = Record(task: pointer, operation: operation, operationContext: operationContext, runtime: runtime)
        lock.lock()
        records.append(record)
        created += 1
        let prune = created % 64 == 0
        lock.unlock()
        if prune { _ = liveTasks() }
    }

    /// Tasks not finished yet, oldest first. Each keeps its context alive while it is held.
    package static func liveTasks() -> [LiveTask] {
        guard let runtime = Runtime.shared else { return [] }
        lock.lock()
        let current = records
        lock.unlock()
        var live: [LiveTask] = []
        var finished: Set<ObjectIdentifier> = []
        for record in current {
            guard let task = record.retainedContext(runtime) else {
                finished.insert(ObjectIdentifier(record))
                continue
            }
            live.append(task)
        }
        if !finished.isEmpty {
            lock.lock()
            records.removeAll { finished.contains(ObjectIdentifier($0)) }
            lock.unlock()
        }
        return live
    }

    /// A native weak reference to a task: `weak var` cannot hold one, a task is not a class instance.
    private final class WeakTask: @unchecked Sendable {
        private let slot = UnsafeMutableRawPointer.allocate(byteCount: 8, alignment: 8)
        private let runtime: Runtime

        init(_ task: UnsafeRawPointer, _ runtime: Runtime) {
            self.runtime = runtime
            runtime.weakInit(slot, task)
        }

        deinit {
            runtime.weakDestroy(slot)
            slot.deallocate()
        }

        var isAlive: Bool { retained().map { _ in true } ?? false }

        fileprivate func retained() -> Retained? {
            runtime.weakLoadStrong(slot).map { Retained($0, runtime) }
        }
    }

    /// One created task. Released when the task is found finished.
    private final class Record: @unchecked Sendable {
        let address: UInt
        let createdAt = ProcessInfo.processInfo.systemUptime
        private let task: WeakTask
        private let operation: LiveHeap.TaskOperation
        private let operationContext: UnretainedHeapReference

        init(task: UnsafeRawPointer, operation: LiveHeap.TaskOperation, operationContext: UnretainedHeapReference, runtime: Runtime) {
            address = UInt(bitPattern: task)
            self.task = WeakTask(task, runtime)
            self.operation = operation
            self.operationContext = operationContext
        }

        var isRunning: Bool { task.isAlive && operationContext.retained() != nil }

        /// The task while it runs, its operation's context retained: `nil` once either is gone.
        func retainedContext(_ runtime: Runtime) -> LiveTask? {
            guard let retainedTask = task.retained(), let keepAlive = operationContext.retained() else { return nil }
            return LiveTask(address: address, operation: operation.name,
                            root: .task(address, operation: operation, keepAlive: keepAlive), createdAt: createdAt,
                            task: retainedTask)
        }
    }

    /// `true` while the task at `address` has not returned: alive, its operation still holding its context.
    /// A task that returned can stay alive while a handle to it is kept; its operation is gone.
    static func isRunning(_ address: UInt) -> Bool {
        lock.lock()
        let record = records.first { $0.address == address }
        lock.unlock()
        return record?.isRunning ?? false
    }

    /// Running tasks whose operation points to one of `objects`, strongly or weakly: the tasks working for them.
    package static func tasks(pointingTo objects: [AnyObject], depth: Int = 4) -> [LiveTask] {
        let ids = Set(objects.map(ObjectIdentifier.init))
        guard !ids.isEmpty else { return [] }
        return liveTasks().filter { task in
            LiveHeap().pointees(of: task.root, depth: depth).contains { ids.contains(ObjectIdentifier($0)) }
        }
    }

    /// A strong reference already taken, released with this value.
    fileprivate final class Retained: @unchecked Sendable {
        let pointer: UnsafeRawPointer
        private let runtime: Runtime

        init(_ pointer: UnsafeRawPointer, _ runtime: Runtime) {
            self.pointer = pointer
            self.runtime = runtime
        }

        deinit { runtime.release(pointer) }
    }

    /// Reference counting entry points of the Swift runtime, by name. All take and return plain pointers.
    final class Runtime: @unchecked Sendable {
        private typealias Unary = @convention(c) (UnsafeRawPointer) -> Void
        private typealias WeakInit = @convention(c) (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
        private typealias WeakLoad = @convention(c) (UnsafeMutableRawPointer) -> UnsafeRawPointer?
        private typealias WeakDestroy = @convention(c) (UnsafeMutableRawPointer) -> Void

        static let shared = Runtime()

        let release: (UnsafeRawPointer) -> Void
        let weakInit: (UnsafeMutableRawPointer, UnsafeRawPointer) -> Void
        let weakLoadStrong: (UnsafeMutableRawPointer) -> UnsafeRawPointer?
        let weakDestroy: (UnsafeMutableRawPointer) -> Void

        private init?() {
            let handle = UnsafeMutableRawPointer(bitPattern: -2)
            func load<T>(_ name: String, as _: T.Type) -> T? { dlsym(handle, name).map { unsafeBitCast($0, to: T.self) } }
            guard let release = load("swift_release", as: Unary.self),
                  let weakInit = load("swift_weakInit", as: WeakInit.self),
                  let weakLoadStrong = load("swift_weakLoadStrong", as: WeakLoad.self),
                  let weakDestroy = load("swift_weakDestroy", as: WeakDestroy.self) else { return nil }
            self.release = release
            self.weakInit = weakInit
            self.weakLoadStrong = weakLoadStrong
            self.weakDestroy = weakDestroy
        }
    }
}

/// A running task watched like an object: alive until the task returns. Holds it through a weak reference.
@MainActor
package final class TaskProbe: LeakProbe {
    package nonisolated let holder: LeakHolder
    private let address: UInt

    package init(_ live: TaskRegistry.LiveTask) {
        holder = live.holder
        address = live.address
    }

    package nonisolated var typeName: String { "Task" }

    package var isAlive: Bool { TaskRegistry.isRunning(address) }
}

#endif

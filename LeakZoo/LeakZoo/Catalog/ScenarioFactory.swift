//
//  ScenarioFactory.swift
//  LeakZoo
//
//  Created by thachlh on 5/11/26.
//

import UIKit

/// Maps a scenario id to the first screen it opens. Returns a maker, so the id
/// can be checked at launch without creating (and deinit-logging) a screen.
enum ScenarioFactory {
    static func maker(for id: String) -> (() -> UIViewController)? {
        switch id {
        // Leak: cycle
        case "Z01": return { Z01ClosurePropertyViewController(logTag: "Z01") }
        case "Z02": return { Z02StrongDelegateViewController(logTag: "Z02") }
        case "Z03": return { Z03ButtonActionViewController(logTag: "Z03") }
        case "Z04": return { ChildHostViewController(logTag: "Z04.host",
                                                   child: Z04ChildClosureViewController(logTag: "Z04")) }
        case "Z05": return { Z05Level1ViewController(logTag: "Z05.1") }
        case "Z06": return { Z06CombineSinkViewController(logTag: "Z06") }
        // Leak: rooted
        case "Z07": return { Z07TimerViewController(logTag: "Z07") }
        case "Z08": return { Z08NotificationObserverViewController(logTag: "Z08") }
        case "Z09": return { Z09StreamTaskViewController(logTag: "Z09") }
        case "Z10": return { Z10StaticRegistryViewController(logTag: "Z10") }
        // No leak
        case "Z11": return { Z11WeakClosureViewController(logTag: "Z11") }
        case "Z12": return { Z12CancelledTaskViewController(logTag: "Z12") }
        case "Z13": return { Z13InvalidatedTimerViewController(logTag: "Z13") }
        case "Z14": return { Z14AsyncAfterViewController(logTag: "Z14") }
        case "Z15": return { ChildHostViewController(logTag: "Z15.host",
                                                   child: Z15PlainChildViewController(logTag: "Z15")) }
        case "Z16": return { Z16LevelViewController(level: 1) }
        // Allowed to outlive the screen, or a known leak
        case "Z17": return { Z17CachedViewController.cached() }
        case "Z18": return { Z18OptedOutViewController(logTag: "Z18") }
        case "Z19": return { Z19SuppressedLeakViewController(logTag: "Z19") }
        case "Z20": return { ChildHostViewController(logTag: "Z20.host",
                                                   child: Z20CarelessChildViewController(logTag: "Z20"),
                                                   callsWillMove: false) }
        case "Z21": return { Z21AssociatedObjectViewController(logTag: "Z21") }
        // Concurrency and classic patterns
        case "Z22": return { Z22TaskOutlivesScreenViewController(logTag: "Z22") }
        case "Z23": return { Z23DisplayLinkViewController(logTag: "Z23") }
        case "Z24": return { Z24SessionDelegateViewController(logTag: "Z24") }
        case "Z25": return { Z25ScriptMessageHandlerViewController(logTag: "Z25") }
        case "Z26": return { Z26StrongDelegateNoLeakViewController(logTag: "Z26") }
        case "Z27": return { Z27ObserverTokenViewController(logTag: "Z27") }
        default: return nil
        }
    }
}

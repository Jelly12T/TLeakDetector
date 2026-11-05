//
//  SpikeHostApp.swift
//  FieldOwnershipSpike
//
//  Created by thachlh on 5/11/26.
//
//  SPIKE CODE — runs the report on a real device, prints SPIKE| lines to stdout, then exits.
//  Package tests cannot run tool-hosted on a device, hence this app.
//

import SpikeReport
import UIKit

@main
final class SpikeHostApp: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        SpikeReport.run()
        print("SPIKE|DONE")
        fflush(stdout)
        exit(0)
    }
}

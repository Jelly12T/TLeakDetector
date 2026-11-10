//
//  Z25ScriptMessageHandlerViewController.swift
//  LeakZoo
//
//  Created by thachlh on 10/11/26.
//

import UIKit
import WebKit

/// Z25 — LEAK (cycle). self → webView → userContentController → script message handler self.
/// WKUserContentController retains its handlers; WebKit keeps them where no ivar shows it.
final class Z25ScriptMessageHandlerViewController: ZooViewController, WKScriptMessageHandler {
    private let webView = WKWebView()

    override func viewDidLoad() {
        super.viewDidLoad()
        webView.configuration.userContentController.add(self, name: "zoo")
        stack.addArrangedSubview(webView)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {}
}

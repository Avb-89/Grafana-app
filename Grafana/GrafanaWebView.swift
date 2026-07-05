//
//  GrafanaWebView.swift
//  Grafana
//
//  Created by SITIS on 7/3/26.
//

import SwiftUI
import WebKit

struct GrafanaWebView: NSViewRepresentable {
    let url: URL
    let username: String
    let password: String

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        configuration.userContentController.addUserScript(
            WKUserScript(
                source: autologinScript(),
                injectionTime: .atDocumentEnd,
                forMainFrameOnly: true
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.customUserAgent = "Grafana macOS Workspace"
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url == nil {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            print("Grafana WebView navigation failed: \(error.localizedDescription)")
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            print("Grafana WebView provisional navigation failed: \(error.localizedDescription)")
        }
    }


    private func autologinScript() -> String {
        let escapedUsername = javascriptEscaped(username)
        let escapedPassword = javascriptEscaped(password)

        return """
        (function() {
            const username = '\(escapedUsername)';
            const password = '\(escapedPassword)';

            function setNativeValue(element, value) {
                const valueSetter = Object.getOwnPropertyDescriptor(element, 'value')?.set;
                const prototype = Object.getPrototypeOf(element);
                const prototypeValueSetter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;

                if (prototypeValueSetter && valueSetter !== prototypeValueSetter) {
                    prototypeValueSetter.call(element, value);
                } else if (valueSetter) {
                    valueSetter.call(element, value);
                } else {
                    element.value = value;
                }

                element.dispatchEvent(new Event('input', { bubbles: true }));
                element.dispatchEvent(new Event('change', { bubbles: true }));
            }

            function findButtonByText(text) {
                const buttons = Array.from(document.querySelectorAll('button'));
                return buttons.find(function(button) {
                    return (button.innerText || '').trim().toLowerCase().includes(text);
                });
            }

            function tryLogin() {
                if (!username || !password) {
                    return false;
                }

                const userInput = document.querySelector('input[name="user"], input[name="username"], input[autocomplete="username"], input[type="text"]');
                const passwordInput = document.querySelector('input[name="password"], input[type="password"], input[autocomplete="current-password"]');
                const button = document.querySelector('button[type="submit"], button[aria-label="Login button"]') || findButtonByText('log in') || findButtonByText('login');

                if (!userInput || !passwordInput || !button) {
                    return false;
                }

                setNativeValue(userInput, username);
                setNativeValue(passwordInput, password);
                setTimeout(function() { button.click(); }, 300);
                return true;
            }

            if (!tryLogin()) {
                const timer = setInterval(function() {
                    if (tryLogin()) {
                        clearInterval(timer);
                    }
                }, 500);
                setTimeout(function() { clearInterval(timer); }, 15000);
            }
        })();
        """
    }

    private func javascriptEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "'", with: "\\'")
            .replacingOccurrences(of: "\n", with: "\\n")
            .replacingOccurrences(of: "\r", with: "\\r")
    }
}

struct GrafanaWindowView: View {
    let username: String
    let password: String
    let preferredSize: CGSize
    let onClose: () -> Void

    private let grafanaURL = URL(string: "http://127.0.0.1:3000/login")!

    var body: some View {
        ZStack(alignment: .topTrailing) {
            GrafanaWebView(
                url: grafanaURL,
                username: username,
                password: password
            )

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.primary)
                    .frame(width: 34, height: 34)
                    .background(.regularMaterial)
                    .clipShape(Circle())
                    .overlay(
                        Circle()
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
                    .shadow(radius: 8, y: 2)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .padding(14)
            .help("Закрыть окно Grafana")
        }
        .frame(
            width: preferredSize.width,
            height: preferredSize.height
        )
    }
}

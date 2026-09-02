import SwiftUI
import WebKit

#if os(iOS)
import UIKit
public typealias ViewRepresentable = UIViewRepresentable
#elseif os(macOS)
import AppKit
public typealias ViewRepresentable = NSViewRepresentable
#endif

/// Native WKWebView Wrapper loading local web calendar with instant response & native haptics
public struct CalendarWebView: ViewRepresentable {
    public init() {}
    
    #if os(iOS)
    public func makeUIView(context: Context) -> WKWebView {
        return createConfiguredWebView(context: context)
    }
    public func updateUIView(_ uiView: WKWebView, context: Context) {}
    #elseif os(macOS)
    public func makeNSView(context: Context) -> WKWebView {
        return createConfiguredWebView(context: context)
    }
    public func updateNSView(_ nsView: WKWebView, context: Context) {}
    #endif
    
    private func createConfiguredWebView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        #if os(iOS)
        config.allowsInlineMediaPlayback = true
        #endif
        
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        
        #if os(iOS)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        #endif
        
        if let htmlPath = Bundle.main.path(forResource: "index", ofType: "html") {
            let htmlUrl = URL(fileURLWithPath: htmlPath)
            webView.loadFileURL(htmlUrl, allowingReadAccessTo: htmlUrl.deletingLastPathComponent())
        } else {
            let req = URLRequest(url: URL(string: "http://localhost:8080")!)
            webView.load(req)
        }
        
        return webView
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    public class Coordinator: NSObject, WKNavigationDelegate {
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Inject haptic bridge listener into WebView
            let js = """
            document.addEventListener('click', function(e) {
                if (e.target.closest('.haptic-tap, button, select, input, .day-cell, .event-chip')) {
                    window.webkit.messageHandlers.haptic.postMessage('light');
                }
            });
            """
            webView.evaluateJavaScript(js, completionHandler: nil)
        }
    }
}

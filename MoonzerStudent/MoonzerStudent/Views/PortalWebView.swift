import SwiftUI
import WebKit
import UIKit

struct PortalWebView: UIViewRepresentable {
    @ObservedObject var session: AppSession

    func makeCoordinator() -> Coordinator {
        Coordinator(session: session)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = [.all]
        config.applicationNameForUserAgent = "MoonzerStudent-iOS/1.1"

        let userController = WKUserContentController()
        userController.add(context.coordinator, name: "exam")
        userController.addUserScript(
            WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
        config.userContentController = userController

        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = !session.isLocked
        web.allowsLinkPreview = !session.isLocked
        web.scrollView.keyboardDismissMode = .interactive
        web.scrollView.alwaysBounceVertical = true

        let refresh = UIRefreshControl()
        refresh.addTarget(context.coordinator, action: #selector(Coordinator.refreshTriggered(_:)), for: .valueChanged)
        web.scrollView.refreshControl = refresh

        context.coordinator.webView = web
        session.webController = context.coordinator

        CookieStore.restore(into: web) {
            guard session.screen == .web else { return }
            context.coordinator.load(session.currentURL)
        }
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        uiView.allowsBackForwardNavigationGestures = !session.isLocked
        uiView.allowsLinkPreview = !session.isLocked
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.navigationDelegate = nil
        uiView.uiDelegate = nil
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "exam")
        if coordinator.session.webController === coordinator {
            coordinator.session.webController = nil
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        let session: AppSession
        weak var webView: WKWebView?
        private var lastRequestedURL: URL?

        init(session: AppSession) {
            self.session = session
        }

        func load(_ url: URL) {
            guard let webView else { return }
            guard shouldAllowProgrammaticLoad(url) else {
                session.toast = "Alamat layanan tidak diizinkan."
                return
            }

            if webView.url == url, !webView.isLoading {
                return
            }
            lastRequestedURL = url
            var request = URLRequest(url: url)
            request.cachePolicy = .useProtocolCachePolicy
            request.timeoutInterval = 45
            webView.load(request)
        }

        func reload() {
            session.showError = false
            if webView?.url != nil {
                webView?.reload()
            } else {
                load(session.currentURL)
            }
        }

        func goBack() -> Bool {
            guard !session.isLocked, webView?.canGoBack == true else { return false }
            webView?.goBack()
            return true
        }

        func zoom(in increase: Bool) {
            let js = increase
                ? "document.documentElement.style.zoom=(Math.min(1.75,parseFloat(document.documentElement.style.zoom||1)*1.12)).toFixed(2)"
                : "document.documentElement.style.zoom=(Math.max(0.70,parseFloat(document.documentElement.style.zoom||1)*0.90)).toFixed(2)"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }

        func cookieHeader(_ completion: @escaping (String) -> Void) {
            guard let webView else {
                completion("")
                return
            }
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                let header = cookies.filter { $0.domain.lowercased().hasSuffix("emoonzer.com") }
                    .map { "\($0.name)=\($0.value)" }
                    .joined(separator: "; ")
                DispatchQueue.main.async { completion(header) }
            }
        }

        func setCopyPasteBlocked(_ blocked: Bool) {
            webView?.evaluateJavaScript(blocked ? PortalWebView.blockClipboardJS : PortalWebView.unblockClipboardJS, completionHandler: nil)
        }

        func clearWebViewState() {
            webView?.stopLoading()
            webView?.loadHTMLString("", baseURL: nil)
        }

        @objc func refreshTriggered(_ sender: UIRefreshControl) {
            guard !session.isLocked else {
                sender.endRefreshing()
                session.toast = "Tarik untuk memuat ulang dinonaktifkan selama ujian."
                return
            }
            reload()
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "exam",
                  let body = message.body as? [String: Any],
                  let action = body["action"] as? String else { return }

            let uuid = body["uuid"] as? String ?? ""
            DispatchQueue.main.async {
                if action == "startExam" || action == "startExamWithToken" {
                    self.session.startExamFromBridge(uuid: uuid)
                } else if action == "setUuid", AppUrls.isTrusted(self.webView?.url) {
                    self.session.updateUuid(uuid)
                }
            }
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }

            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "about" && url.absoluteString == "about:blank" {
                decisionHandler(.allow)
                return
            }

            if scheme == "http",
               AppUrls.isTrustedHost(url.host) || (session.isQrSession && AppUrls.isAllowedQrHost(url, allowedHost: session.qrAllowedHost)) {
                if var comps = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                    comps.scheme = "https"
                    if let https = comps.url {
                        webView.load(URLRequest(url: https, cachePolicy: .useProtocolCachePolicy, timeoutInterval: 45))
                    }
                }
                decisionHandler(.cancel)
                return
            }

            if AppUrls.isTrusted(url) || (session.isQrSession && AppUrls.isAllowedQrHost(url, allowedHost: session.qrAllowedHost)) {
                if !session.isLocked, navigationAction.targetFrame?.isMainFrame != false,
                   AppUrls.isAttemptUrl(url.absoluteString) || AppUrls.isTryoutExamStartUrl(url.absoluteString) {
                    DispatchQueue.main.async { self.session.inspect(url: url.absoluteString) }
                }
                decisionHandler(.allow)
                return
            }

            if session.isLocked {
                DispatchQueue.main.async {
                    self.session.toast = "Tautan di luar layanan ujian diblokir selama mode ujian."
                }
                decisionHandler(.cancel)
                return
            }

            if ["https", "mailto", "tel"].contains(scheme) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                self.session.showError = false
                if let url = webView.url?.absoluteString {
                    self.session.inspect(url: url)
                }
            }
        }

        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            if session.isLocked { setCopyPasteBlocked(true) }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            webView.scrollView.refreshControl?.endRefreshing()
            CookieStore.persist(from: webView)
            if session.isLocked { setCopyPasteBlocked(true) }
            if let url = webView.url?.absoluteString {
                DispatchQueue.main.async {
                    self.session.showError = false
                    self.session.inspect(url: url)
                }
            }
        }

        func webView(_ webView: WKWebView,
                     didFailProvisionalNavigation navigation: WKNavigation!,
                     withError error: Error) {
            handleNavigationError(error, webView: webView)
        }

        func webView(_ webView: WKWebView,
                     didFail navigation: WKNavigation!,
                     withError error: Error) {
            handleNavigationError(error, webView: webView)
        }

        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            DispatchQueue.main.async {
                self.session.toast = "Halaman dimuat ulang karena proses WebView berhenti."
                webView.reload()
            }
        }

        func webView(_ webView: WKWebView,
                     createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            guard !session.isLocked else {
                session.toast = "Jendela baru diblokir selama mode ujian."
                return nil
            }
            if let url = navigationAction.request.url {
                load(url)
            }
            return nil
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptAlertPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping () -> Void) {
            presentJavaScriptAlert(message: message, completionHandler: completionHandler)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptConfirmPanelWithMessage message: String,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (Bool) -> Void) {
            guard let presenter = Self.topViewController() else {
                completionHandler(false)
                return
            }
            let alert = UIAlertController(title: "Moonzer Student", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Batal", style: .cancel) { _ in completionHandler(false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler(true) })
            presenter.present(alert, animated: true)
        }

        func webView(_ webView: WKWebView,
                     runJavaScriptTextInputPanelWithPrompt prompt: String,
                     defaultText: String?,
                     initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping (String?) -> Void) {
            guard let presenter = Self.topViewController() else {
                completionHandler(nil)
                return
            }
            let alert = UIAlertController(title: "Moonzer Student", message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Batal", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            presenter.present(alert, animated: true)
        }

        private func shouldAllowProgrammaticLoad(_ url: URL) -> Bool {
            AppUrls.isTrusted(url) || (session.isQrSession && AppUrls.isAllowedQrHost(url, allowedHost: session.qrAllowedHost))
        }

        private func handleNavigationError(_ error: Error, webView: WKWebView) {
            webView.scrollView.refreshControl?.endRefreshing()
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }

            DispatchQueue.main.async {
                self.session.errorMessage = self.session.isOnline
                    ? "Halaman gagal dimuat. Silakan coba kembali."
                    : "Perangkat sedang offline. Periksa Wi-Fi atau data seluler."
                self.session.showError = true
            }
        }

        private func presentJavaScriptAlert(message: String, completionHandler: @escaping () -> Void) {
            guard let presenter = Self.topViewController() else {
                completionHandler()
                return
            }
            let alert = UIAlertController(title: "Moonzer Student", message: message, preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in completionHandler() })
            presenter.present(alert, animated: true)
        }

        private static func topViewController(base: UIViewController? = nil) -> UIViewController? {
            let root: UIViewController? = {
                if let base { return base }
                return UIApplication.shared.connectedScenes
                    .compactMap { $0 as? UIWindowScene }
                    .flatMap { $0.windows }
                    .first(where: { $0.isKeyWindow })?
                    .rootViewController
            }()

            if let nav = root as? UINavigationController {
                return topViewController(base: nav.visibleViewController)
            }
            if let tab = root as? UITabBarController, let selected = tab.selectedViewController {
                return topViewController(base: selected)
            }
            if let presented = root?.presentedViewController {
                return topViewController(base: presented)
            }
            return root
        }
    }

    private static let bridgeJS = """
    (function(){
      window.Android = window.Android || {};
      window.Android.startExam = function(uuid){
        window.webkit.messageHandlers.exam.postMessage({action:'startExam', uuid:String(uuid||'')});
      };
      window.Android.startExamWithToken = function(uuid, token){
        window.webkit.messageHandlers.exam.postMessage({action:'startExamWithToken', uuid:String(uuid||'')});
      };
      window.Android.setUuid = function(uuid){
        window.webkit.messageHandlers.exam.postMessage({action:'setUuid', uuid:String(uuid||'')});
      };
    })();
    """

    static let blockClipboardJS = """
    (function(){
      try{
        if(!document.getElementById('moonzer-cp-block')){
          var s=document.createElement('style');
          s.id='moonzer-cp-block';
          s.textContent='*,*::before,*::after{-webkit-user-select:none!important;user-select:none!important;-webkit-touch-callout:none!important;}';
          document.documentElement.appendChild(s);
        }
        if(!window.__moonzerBlockClipboard){
          window.__moonzerBlockClipboard=function(e){e.preventDefault();e.stopPropagation();return false;};
          document.addEventListener('copy',window.__moonzerBlockClipboard,true);
          document.addEventListener('cut',window.__moonzerBlockClipboard,true);
          document.addEventListener('paste',window.__moonzerBlockClipboard,true);
          document.addEventListener('contextmenu',window.__moonzerBlockClipboard,true);
          document.addEventListener('dragstart',window.__moonzerBlockClipboard,true);
        }
      }catch(e){}
    })();
    """

    static let unblockClipboardJS = """
    (function(){
      try{
        var s=document.getElementById('moonzer-cp-block'); if(s) s.remove();
        if(window.__moonzerBlockClipboard){
          document.removeEventListener('copy',window.__moonzerBlockClipboard,true);
          document.removeEventListener('cut',window.__moonzerBlockClipboard,true);
          document.removeEventListener('paste',window.__moonzerBlockClipboard,true);
          document.removeEventListener('contextmenu',window.__moonzerBlockClipboard,true);
          document.removeEventListener('dragstart',window.__moonzerBlockClipboard,true);
          window.__moonzerBlockClipboard=null;
        }
      }catch(e){}
    })();
    """
}

//
//  Browser.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import WebKit
import UIKit
import PinLayout
import Combine

let showWebNotification = NotificationPublisher<Bool>()

class Browser: UIViewController {
    
    static let shared = Browser()
    
    let screenshotManager = ScreenshotManager()
    
    let keyboardManager = KeyboardManager()
    
    var webView: WKWebView?
    var completionHandler: ((String?) -> Void)?
    
    var urlInputText: String = "https://google.com"
    
    var viewModel = BrowserViewModel()
    
    var cancellables = Set<AnyCancellable>()
    
    let browserBar: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
        return view
    }()
    
    let browserBarTopBorder = {
        let view = UIView()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.1)
        return view
    }()
    
    let progressBar = UIProgressView(progressViewStyle: .bar)
    
    let browserInput = BrowserTextField()
    
    let browserMenuButton = BrowserButton()
    
    // MARK: CREATE WEBVIEW FUNCTION
    
    func createWebView(parentView: UIView) {
        if webView != nil {
            return
        }
        
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = WKWebsiteDataStore.default()

        view.frame = parentView.frame
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView?.navigationDelegate = self
        webView?.allowsBackForwardNavigationGestures = true
        view.insertSubview(webView!, belowSubview: browserBar)
        
        viewModel.browserUrl = URL(string: urlInputText)
        
        keyboardManager.observeKeyboardChanges { (height, animation) in
            var bottomOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
            
            if bottomOffset == 0 {
                bottomOffset = 12
            }
            
            let yTranslate: CGFloat = height != 0 ? -height + bottomOffset - 12 : 0
            let transform = CGAffineTransform(translationX: 0, y:  yTranslate)
            
            if let animation = animation {
                UIView.animate(withDuration: animation.duration, delay: 0, options: [.beginFromCurrentState, animation.options], animations: {
                    self.browserBar.transform = transform
                })
            } else {
                self.browserBar.transform = transform
            }
        }
        
        webView!.publisher(for: \.estimatedProgress)
            .map { Float($0) }
            .receive(on: DispatchQueue.main)
            .assign(to: \.progress, on: progressBar)
            .store(in: &cancellables)
        
        webView!.publisher(for: \.estimatedProgress)
            .map { $0 == 1 }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .assign(to: \.isHidden, on: progressBar)
            .store(in: &cancellables)
        
//        webView!.publisher(for: \.estimatedProgress)
//            .sink { progress in
//                print("Progress: \(progress)")
//            }
//            .store(in: &cancellables)

        webView!.publisher(for: \.url)
            .sink { url in
                print("URL: \(url)")
                DispatchQueue.main.async {
                    self.viewModel.inputText = url?.absoluteString
                }
                
            }
            .store(in: &cancellables)

        webView!.publisher(for: \.title)
            .sink { title in
                print("Title: \(title)")
            }
            .store(in: &cancellables)
    }
    
    // MARK: VIEW DID LAYOUT SUBVIEWS
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var topOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
        
        #if targetEnvironment(macCatalyst)
        topOffset += 28
        #endif
        
        var bottomOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
        
        if bottomOffset == 0 {
            bottomOffset = 12
        }
        
        webView?.pin.all()
        
        webView?.scrollView.contentInset.top = topOffset
        
        webView?.scrollView.contentInset.bottom = bottomOffset + 54 + 12
        
        webView?.scrollView.verticalScrollIndicatorInsets = .init(top: topOffset, left: 0, bottom: bottomOffset + 54 + 12, right: 0)
        
        browserBar.pin.bottom().horizontally().height(bottomOffset + 12 + 54)
        
        browserBar.contentView.pin.all()
        
        browserBarTopBorder.pin.top().horizontally().height(1)
        
        browserMenuButton.pin.top(12).right(16).height(54).width(54)
        
        browserInput.pin.top(12).left(16).height(54).before(of: browserMenuButton).marginRight(12)
        
        progressBar.pin.top().left().right().height(2)
    }
    
    private func updateColors() {
        if traitCollection.userInterfaceStyle == .light {
            browserBar.effect = UIBlurEffect(style: .light)
        } else {
            browserBar.effect = UIBlurEffect(style: .dark)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColors()
        }
    }
    
    let inputDelegate = InputTextCoordinator()
    
    // MARK: VIEW DID LOAD
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateColors()
        view.addSubview(browserBar)
        
        browserBar.contentView.addSubview(browserMenuButton)
        browserBar.contentView.addSubview(browserInput)
        browserBar.contentView.addSubview(browserBarTopBorder)
        
        browserInput.returnKeyType = .go
        browserInput.delegate = inputDelegate
        browserInput.clearButtonMode = .always
        browserInput.keyboardType = .webSearch
        browserInput.enablesReturnKeyAutomatically = true
        browserInput.spellCheckingType = .no
        browserInput.autocorrectionType = .no
        browserInput.autocapitalizationType = .none
        inputDelegate.parent = self
        
        progressBar.trackTintColor = UIColor.clear
        progressBar.progressTintColor = UIColor.blue
        progressBar.layer.cornerRadius = 0
        progressBar.clipsToBounds = true

        browserBar.contentView.addSubview(self.progressBar)
        
        viewModel.$inputText
            .assign(to: \.text, on: browserInput)
            .store(in: &cancellables)
        
        // Bind TextField's text to View`Model's text
        NotificationCenter.default.publisher(for: UITextField.textDidChangeNotification, object: browserInput)
            .compactMap { $0.object as? UITextField }
            .map { $0.text ?? "" }
            .assign(to: \.text, on: browserInput)
            .store(in: &cancellables)
        
        viewModel.onURLLoad = { url in
            DispatchQueue.main.async {
                self.webView?.load(URLRequest(url: url))
            }
        }
    }
    
    func fetchHTML(from url: URL, completionHandler: @escaping (String?) -> Void) {
        guard let w = webView else {
            print("WebView has not been setup")
            return
        }
        self.completionHandler = completionHandler
        self.viewModel.browserUrl = url
    }
    
    func dumpHTML(completionHandler: @escaping (String?) -> Void) {
        
        webView?.evaluateJavaScript("document.documentElement.outerHTML.toString()", completionHandler: { (html: Any?, error: Error?) in
            
            let image = self.webView?.screenshot()
            
            if let htmlString = html as? String {
                self.completionHandler?(htmlString)
            } else {
                self.completionHandler?(nil)
            }
            
        })
    }
    
    func findURLs(input: String) -> [URL] {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: input, options: [], range: NSRange(location: 0, length: input.utf16.count))
        
        var urls = [URL]()
        
        for match in matches ?? [] {
            if let url = match.url {
                urls.append(url)
            }
        }
        
        return urls
    }
    
    func loadURLString(_ string: String) {
        let searchString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        print("search string", searchString)
        
        let urls = findURLs(input: searchString)
        
        if let url = urls.first, searchString.split(separator: " ").count == 1 {
            print(url)
            self.viewModel.browserUrl = url
        } else {
            if let url = URL(string: "https://www.google.com/search?q=\(searchString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "")") {
                print(url)
                self.viewModel.browserUrl = url
            }
        }
    }
    
    class InputTextCoordinator: NSObject, UITextFieldDelegate {
        weak var parent: Browser?
        
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            if let text = textField.text {
                parent?.loadURLString(text)
            }
            textField.resignFirstResponder()
            return true
        }
    }
}

extension Browser: WKNavigationDelegate {
    
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        
        print("url loaded", webView.url)
        print("view model url", viewModel.browserUrl)
        
        let url = viewModel.browserUrl
        
        if let handler = self.completionHandler {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if let url = url {
                    self.takeScreenshot(url: url)
                }
                
                webView.evaluateJavaScript("document.documentElement.outerHTML.toString()",
                                           completionHandler: { (html: Any?, error: Error?) in
                    if let htmlString = html as? String {
                        handler(htmlString)
                    } else {
                        handler(nil)
                    }
                    self.completionHandler = nil
                })
            }
        }
    }
    
    private func takeScreenshot(url: URL) {
        let cachePath = ImageCache.getCachePath(url: url)
        if let image = self.webView?.screenshot()  {
            Task {
                try? await self.screenshotManager.storeScreenshot(image, for: url, at: cachePath)
           }
        }
    }

    func onScreenshotReady(for url: URL) async -> URL? {
        return await screenshotManager.onScreenshotReady(for: url)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if let url = viewModel.browserUrl {
            self.takeScreenshot(url: url)
        }
        completionHandler?(nil)
    }
}

class BrowserTextField: UITextField {
    
    let padding = UIEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupTextField()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupTextField()
    }
    
    private func setupTextField() {
        layer.cornerRadius = 12
        layer.masksToBounds = true
        layer.cornerCurve = .continuous

        if traitCollection.userInterfaceStyle == .light {
            backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.1)
        } else {
            backgroundColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.1)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            setupTextField()
        }
    }
    
    // Add padding
    override func textRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }

    override func placeholderRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }

    override func editingRect(forBounds bounds: CGRect) -> CGRect {
        return bounds.inset(by: padding)
    }
    
    override func clearButtonRect(forBounds bounds: CGRect) -> CGRect {
        let originalRect = super.clearButtonRect(forBounds: bounds)
        return originalRect.offsetBy(dx: -8, dy: 0)
    }
}

class BrowserButton: UIButton {
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupButton()
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        setupButton()
    }
    
    private func setupButton() {
        showsMenuAsPrimaryAction = true
        
        layer.cornerRadius = 12
        layer.cornerCurve = .continuous
        layer.masksToBounds = true

        setImage(UIImage(systemName: "ellipsis"), for: .normal)
        setImage(UIImage(systemName: "ellipsis"), for: .highlighted)

        updateColors()
        
//        let cancelAction = UIAction(title: "Cancel", attributes: .destructive, handler: { _ in
//                // handle cancel action
//                print("Cancel tapped")
//            })
        
        let chatAction = UIAction(title: "Back to Chat", image: UIImage(systemName: "message"), handler: { _ in
            // handle chat action
            print("Chat tapped")
            showWebNotification.send(false)
            UIApplication.shared.endEditing()
        })

        let crawlSiteAction = UIAction(title: "Import Site", image: UIImage(systemName: "doc.on.doc"), handler: { _ in
            // handle crawl site action
            print("Crawl Site tapped")
        })

        let indexPageAction = UIAction(title: "Import Page", image: UIImage(systemName: "doc.richtext"), handler: { _ in
            // handle index page action
            print("Index Page tapped")
            
            Browser.shared.dumpHTML { html in
                print(html)
            }
        })
        
        let refreshAction = UIAction(title: "Refresh", image: UIImage(systemName: "arrow.clockwise"), handler: { _ in
            // handle crawl site action
            print("Crawl Site tapped")
        })
        
        var elements: [UIMenuElement] = [crawlSiteAction, indexPageAction, refreshAction, chatAction]
        
        #if targetEnvironment(macCatalyst)
        elements.remove(at: 0)
        #endif

        let menu = UIMenu(title: "", children: elements)
        self.menu = menu
    }
    
    private func updateColors() {
        if traitCollection.userInterfaceStyle == .light {
            backgroundColor = UIColor(red: 0, green: 0, blue: 0, alpha: 0.1)
        } else {
            backgroundColor = UIColor(red: 1, green: 1, blue: 1, alpha: 0.1)
        }
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColors()
        }
    }
}


// Actor to manage screenshot file URLs
actor ScreenshotManager {
    private var screenshotURLs: [URL: URL] = [:]
    private var screenshotReadyContinuations: [URL: [CheckedContinuation<URL?, Never>]] = [:]

    func storeScreenshot(_ screenshot: UIImage, for pageURL: URL, at cacheURL: URL) async throws {
        try await saveImage(screenshot, at: cacheURL)
        screenshotURLs[pageURL] = cacheURL
        screenshotReadyContinuations[pageURL]?.forEach { continuation in
            continuation.resume(returning: cacheURL)
        }
        screenshotReadyContinuations[pageURL] = nil
    }

    func screenshotURL(for pageURL: URL) -> URL? {
        return screenshotURLs[pageURL]
    }

    func onScreenshotReady(for pageURL: URL) async -> URL? {
        if let fileURL = screenshotURLs[pageURL] {
            return fileURL
        } else {
            return await withCheckedContinuation { continuation in
                screenshotReadyContinuations[pageURL, default: []].append(continuation)
            }
        }
    }

    private func saveImage(_ image: UIImage, at cacheURL: URL) async throws {

        guard let imageData = image.pngData() else {
            throw NSError(domain: "ScreenshotManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to convert UIImage to PNG data"])
        }

        try imageData.write(to: cacheURL)
    }
}

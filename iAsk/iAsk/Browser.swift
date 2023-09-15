//
//  Browser.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/8/23.
//

import WebKit
import UIKit
import PinLayout

let showWebNotification = NotificationPublisher<Bool>()

class Browser: UIViewController {
    
    static let shared = Browser()
    
    let keyboardManager = KeyboardManager()
    
    var webView: WKWebView?
    var completionHandler: ((String?) -> Void)?
    var snapshotHandler: ((UIImage?) -> Void)?
    
    var urlInputText: String = "https://google.com"
    
    var browserUrl: URL? {
        didSet {
            if let url = browserUrl {
                let request = URLRequest(url: url)
                webView?.load(request)
            }
        }
    }
    
    let browserBar: UIVisualEffectView = {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .extraLight))
        return view
    }()
    
    let browserInput = BrowserTextField()
    
    let browserMenuButton = BrowserButton()
    
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
        
        browserUrl = URL(string: urlInputText)
        
        keyboardManager.observeKeyboardChanges { (height, animation) in
            var bottomOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
            
            if bottomOffset == 0 {
                bottomOffset = 8
            }
            
            let yTranslate: CGFloat = height != 0 ? -height + bottomOffset - 16 : 0
            let transform = CGAffineTransform(translationX: 0, y:  yTranslate)
            
            if let animation = animation {
                UIView.animate(withDuration: animation.duration, delay: 0, options: [.beginFromCurrentState, animation.options], animations: {
                    self.browserBar.transform = transform
                })
            } else {
                self.browserBar.transform = transform
            }
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        var topOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
        
        #if targetEnvironment(macCatalyst)
        topOffset += 28
        #endif
        
        var bottomOffset = UIApplication.shared.windows.first!.safeAreaInsets.bottom
        
        if bottomOffset == 0 {
            bottomOffset = 8
        }
        
        webView?.pin.all()
        
        webView?.scrollView.contentInset.top = topOffset
        
        webView?.scrollView.contentInset.bottom = bottomOffset + 44 + 8
        
        webView?.scrollView.verticalScrollIndicatorInsets = .init(top: 0, left: 0, bottom: bottomOffset + 44 + 8, right: 0)
        
        browserBar.pin.bottom().horizontally().height(bottomOffset + 8 + 44)
        
        browserBar.contentView.pin.all()
        
        browserMenuButton.pin.top(8).right(8).height(44).width(44)
        
        browserInput.pin.top(8).left(8).height(44).before(of: browserMenuButton).marginRight(8)
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
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        updateColors()
        view.addSubview(browserBar)
        
        browserBar.contentView.addSubview(browserMenuButton)
        browserBar.contentView.addSubview(browserInput)
        
        browserInput.returnKeyType = .go
        browserInput.delegate = inputDelegate
    }
    
    func fetchHTML(from url: URL, completionHandler: @escaping (String?) -> Void) {
        guard let w = webView else {
            print("WebView has not been setup")
            return
        }
        self.completionHandler = completionHandler
        let request = URLRequest(url: url)
        w.load(request)
    }
    
    func dumpHTML(completionHandler: @escaping (String?) -> Void) {
        webView?.evaluateJavaScript("document.documentElement.outerHTML.toString()",
                                   completionHandler: { (html: Any?, error: Error?) in
            if let htmlString = html as? String {
                self.completionHandler?(htmlString)
            } else {
                self.completionHandler?(nil) // handle error as needed
            }
        })
    }
    
    func takeURLSnapshot(_ url: URL, handler: @escaping (UIImage?) -> Void) {
        self.snapshotHandler = handler
        
        webView?.load(URLRequest(url: url))
    }
    
    func loadURLString(_ string: String) {
        let searchString = string.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if searchString.contains("://") || searchString.hasPrefix("www.") {
            if let url = URL(string: searchString) {
                webView?.load(URLRequest(url: url))
            }
        } else {
            if let url = URL(string: "https://www.google.com/search?q=\(searchString.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? "")") {
                webView?.load(URLRequest(url: url))
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
        
        if let handler = self.snapshotHandler {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let configuration = WKSnapshotConfiguration()
                configuration.rect = CGRect(origin: .zero, size: webView.scrollView.contentSize)
                
                webView.takeSnapshot(with: configuration) {image, error in
                    if let error = error {
                        print(error)
                    }
                    handler(image)
                    self.snapshotHandler = nil
                }
            }
        }
        else if let handler = self.completionHandler {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                webView.evaluateJavaScript("document.documentElement.outerHTML.toString()",
                                           completionHandler: { (html: Any?, error: Error?) in
                    if let htmlString = html as? String {
                        self.completionHandler?(htmlString)
                    } else {
                        self.completionHandler?(nil) // handle error as needed
                    }
                    self.completionHandler = nil
                })
            }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        // Handle the error as needed
        completionHandler?(nil)
    }
}

class BrowserTextField: UITextField {
    
    let padding = UIEdgeInsets(top: 0, left: 8, bottom: 0, right: 8)
    
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
        
        let cancelAction = UIAction(title: "Cancel", attributes: .destructive, handler: { _ in
                // handle cancel action
                print("Cancel tapped")
            })
        
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
        
        var elements: [UIMenuElement] = [cancelAction, crawlSiteAction, indexPageAction, refreshAction, chatAction]
        
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

//
//  ViewController.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/7/23.
//

import UIKit
import PinLayout
import SwiftUI
import Combine
import WebKit
import MobileCoreServices

let scrollToPageNotification = NotificationPublisher<(page: Int, animated: Bool)>()

class ViewController: UIViewController {
    
    let scrollView = UIScrollView()
    
    let pageOne = UIView()
    
    let pageTwo = UIView()
    
    var currentPage: Int = 1
    
    var currentChat = ChatViewModel()
    
    var currentHistory = HistoryViewModel()
    
    lazy var chatViewController: UIHostingController = {
        let view = ChatViewWrapper(chat: currentChat)
        return UIHostingController(rootView: view)
    }()
    
    lazy var historyViewController: UIHostingController = {
        let view = HistoryView(history: self.currentHistory)
        return UIHostingController(rootView: view)
    }()
    
    lazy var documentPicker: DocumentPickerPresenter =  {
        DocumentPickerPresenter(parentViewController: self)
    }()
    
    lazy var cameraPresenter: CameraPresenter = {
        CameraPresenter(parentViewController: self)
    }()
    
    lazy var photoPresenter: PhotoPickerPresenter = {
        PhotoPickerPresenter(parentViewController: self)
    }()
    
    var cancellables: Set<AnyCancellable> = []
    
    weak var webView: WKWebView?

    override func viewDidLoad() {
        super.viewDidLoad()
        
        Browser.shared.createWebView(parentView: self.view)
        
        view.addSubview(Browser.shared.view)
        
        view.addSubview(scrollView)
        
        scrollView.delegate = self
        
        scrollView.addSubview(pageOne)
        
        scrollView.addSubview(pageTwo)
        
        scrollView.isPagingEnabled = true
        
        scrollView.showsHorizontalScrollIndicator = false
        
        scrollView.keyboardDismissMode = .onDrag
        
        addChild(historyViewController)
        
        pageOne.addSubview(historyViewController.view)
        
        historyViewController.didMove(toParent: self)

        addChild(chatViewController)
        
        pageTwo.addSubview(chatViewController.view)
        
        chatViewController.didMove(toParent: self)
        
        setupShowDocumentsListener()
        
        setupShowWebListener()
        
        setupSelectChatListener()
        
        setupGoogleSigninListener()
        
        setupShowSaveListener()
        
        setupScrollToPageListener()
        
        setupShowCameraListener()
        
        setupShowPhotoPickerListener()
        
        let dropInteraction = UIDropInteraction(delegate: self)
        view.addInteraction(dropInteraction)
        
        updateColors()
    }
    
    func setupShowCameraListener() {
        let cancel = showCameraNotification.publisher.sink { [weak self] value in
            // Handle the received value here
            print("show documents: \(value)")
            
            self?.cameraPresenter.present()
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupShowPhotoPickerListener() {
        let cancel = showPhotoPickerNotification.publisher.sink { [weak self] value in
            // Handle the received value here
            print("show documents: \(value)")
            
            self?.photoPresenter.present()
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupShowDocumentsListener() {
        let showDocumentsCancel = showDocumentsNotification.publisher.sink { [weak self] value in
            // Handle the received value here
            print("show documents: \(value)")
            
            self?.documentPicker.presentDocumentPicker()
            
        }
        
        showDocumentsCancel.store(in: &cancellables)
    }
    
    func setupShowSaveListener() {
        let cancel = showSaveNotification.publisher.sink { [weak self] value in
            // Handle the received value here
            print("show save dialog: \(value)")
            
            self?.documentPicker.presentSaveDialog(urls: value)
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupShowWebListener() {
        let cancel = showWebNotification.publisher.sink { [weak self] value in
            print("show web: \(value)")
            
            let transform = CGAffineTransform(translationX: 0, y: value ? UIScreen.main.bounds.height : 0)
            
            UIView.animate(withDuration: 0.2) {
                self?.scrollView.transform = transform
            }
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupScrollToPageListener() {
        let cancel = scrollToPageNotification.publisher.sink { [weak self] value in
            
            guard let self = self else {
                return
            }
            
            print("scroll to page: \(value)")
            
            DispatchQueue.main.async {
                self.scrollView.setContentOffset(.init(x: 0, y: CGFloat(value.page) * self.scrollView.frame.width), animated: value.animated)
            }
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupSelectChatListener() {
        let cancel = selectChatNotification.publisher.sink { [weak self] value in

            Task {
                let messages = await Message.loadForChatId(value.id) ?? []
                DispatchQueue.main.async {
                    self?.currentChat.id = value.id
                    self?.currentChat.messages = messages
                    self?.currentChat.transcript = ""
                    self?.scrollView.setContentOffset(.init(x: self?.view.frame.width ?? 0, y: 0), animated: true)
                    self?.currentChat.scrollProxy?.scrollTo("top", anchor: .top)
                }
            }
            
        }
        
        cancel.store(in: &cancellables)
    }
    
    func setupGoogleSigninListener() {
        let cancel = startGoogleSignInNotification.publisher.sink { [weak self] value in
            print("start google signin: \(value)")
            
            Task {
                guard let `self` = self else { return }
                try? await Google.shared.signIn(controller: self)
            }
            
        }
        
        cancel.store(in: &cancellables)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        scrollView.pin.all()
        
        pageOne.pin.topLeft().bottom().width(of: scrollView)
        
        pageTwo.pin.after(of: pageOne).vertically().width(of: pageOne)
        
        chatViewController.view.pin.all()
        
        historyViewController.view.pin.all()
        
        scrollView.contentSize = .init(width: scrollView.frame.width * 2, height: scrollView.frame.height)
        
        Browser.shared.view.pin.all()
        
        Browser.shared.view.setNeedsLayout()
        Browser.shared.view.layoutIfNeeded()
        
        if !documentPicker.isSaving {
            scrollView.contentOffset.x = scrollView.frame.width * CGFloat(currentPage)
        }
    }
    
    private func updateColors() {
        view.backgroundColor = .backgroundColor
        pageOne.backgroundColor = .backgroundColor
        pageTwo.backgroundColor = .backgroundColor
        scrollView.backgroundColor = .backgroundColor
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        if traitCollection.userInterfaceStyle != previousTraitCollection?.userInterfaceStyle {
            updateColors()
        }
    }
    
    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: "b", modifierFlags: [.command], action: #selector(showWeb)),
            UIKeyCommand(input: "o", modifierFlags: [.command], action: #selector(openFile)),
            UIKeyCommand(input: "\r", modifierFlags: [.command], action: #selector(send)),
            UIKeyCommand(input: "n", modifierFlags: [.command], action: #selector(resetChat)),
            UIKeyCommand(input: "f", modifierFlags: [.command], action: #selector(search)),
            UIKeyCommand(input: "s", modifierFlags: [.command], action: #selector(saveChat)),
            UIKeyCommand(input: "4", modifierFlags: [.command], action: #selector(togglePro))
        ]
    }
    
    @objc func togglePro() {
        currentChat.proMode.toggle()
    }
    
    @objc func saveChat() {
        currentChat.saveDialog()
    }
    
    @objc func showWeb() {
        showWebNotification.send(!(showWebNotification.value ?? false))
    }
    
    @objc func openFile() {
        showDocumentsNotification.send(true)
    }
    
    @objc func send() {
        currentChat.send()
    }
    
    @objc func resetChat() {
        Task {
            await currentChat.resetChat()
        }
    }
    
    @objc func search() {
        scrollToPageNotification.send((0, true))
    }
}

extension ViewController: UIScrollViewDelegate {
    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        let pageWidth = scrollView.frame.size.width
        currentPage = Int(scrollView.contentOffset.x / pageWidth)
    }
}

struct MySwiftUIView: View {
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading) {
                    HStack {
                        Button("Hello from SwiftUI!") {
                            showDocumentsNotification.send(true)
                        }
                        Spacer()
                    }
                    .padding()
                    
                    Spacer()
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .background(Rectangle().fill(.red))
            }
        }
    }
}

extension ViewController: UIDropInteractionDelegate {
    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        let documentTypes: [String] = [
            kUTTypeFolder as String,
            kUTTypePDF as String,
            kUTTypePlainText as String,
            "com.microsoft.word.doc",
            "org.openxmlformats.wordprocessingml.document",
            "com.microsoft.excel.xls",
            "org.openxmlformats.spreadsheetml.sheet",
            "com.microsoft.powerpoint.ppt",
            "org.openxmlformats.presentationml.presentation",
            kUTTypeJSON as String,
            kUTTypeImage as String,
            kUTTypeMovie as String,
            kUTTypeSourceCode as String
        ]
        return session.hasItemsConforming(toTypeIdentifiers: documentTypes)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        return UIDropProposal(operation: .copy)
    }
    
    func dropInteraction(_ interaction: UIDropInteraction, performDrop session: UIDropSession) {
        var providers = [NSItemProvider]()
        for item in session.items {
            providers.append(item.itemProvider)
        }
        Task {
            let urls = try? await withThrowingTaskGroup(of: URL?.self) { group -> [URL] in
                
                var vals = [URL]()

                for provider in providers {
                    if let fileType = provider.registeredTypeIdentifiers.first {
                        group.addTask {
                            func loadInPlaceFileRepresentationAsync(forTypeIdentifier typeIdentifier: String) async throws -> URL? {
                                return try await withCheckedThrowingContinuation { continuation in
                                    provider.loadFileRepresentation(forTypeIdentifier: typeIdentifier) { url, error in
                                        guard let url = url else {
                                            return
                                        }
                                        let fileManager = FileManager.default
                                        let cacheDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
                                        let tempURL = cacheDirectory.appending(component: url.lastPathComponent)
                                        
                                        do {
                                            try? fileManager.removeItem(at: tempURL)
                                            try fileManager.copyItem(at: url, to: tempURL)
                                        }
                                        catch {
                                            print(error)
                                            continuation.resume(throwing: error)
                                            return
                                        }
                                        
                                        
                                        if let error = error {
                                            continuation.resume(throwing: error)
                                        } else {
                                            continuation.resume(returning: tempURL)
                                        }
                                    }
                                }
                            }
                            
                            return try await loadInPlaceFileRepresentationAsync(forTypeIdentifier: fileType)
                        }
                    }
                }
                
                for try await url in group {
                    if let url = url {
                        vals.append(url)
                    }
                }

                return vals
            }
            
            if let urls = urls {
                await self.currentChat.importURLs(urls: urls)
            }
        }
    }
}

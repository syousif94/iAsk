//
//  SceneDelegate.swift
//  iAsk
//
//  Created by Sammy Yousif on 8/7/23.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?


    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        /// 1. Capture the scene
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        /// 2. Create a new UIWindow using the windowScene constructor which takes in a window scene.
        let window = UIWindow(windowScene: windowScene)
        
        /// 3. Create a view hierarchy programmatically
        let viewController = ViewController()

        /// 4. Set the root view controller of the window with your view controller
        window.rootViewController = viewController
        
        /// 5. Set the window and call makeKeyAndVisible()
        self.window = window
        
        #if targetEnvironment(macCatalyst)
        if let titlebar = windowScene.titlebar {
            titlebar.titleVisibility = .hidden
            titlebar.toolbar = nil
        }
        #endif
        
        handleUrls(urlContexts: connectionOptions.urlContexts)
        
        window.makeKeyAndVisible()
    }
    
    func handleUrls(urlContexts: Set<UIOpenURLContext>) {
        var importedUrls = [URL]()
        
        for urlContext in urlContexts {
            let url = urlContext.url
            
            if let shareExtUrls = getShareUrls(from: url.absoluteString), !shareExtUrls.isEmpty {
                importedUrls += shareExtUrls
            }
            else if let newUrl = Disk.support.getPath(for: "imports/\(url.lastPathComponent)") {
                let _ = url.startAccessingSecurityScopedResource()
                copyFile(from: url, to: newUrl)
                url.stopAccessingSecurityScopedResource()
                importedUrls.append(newUrl)
            }
        }
        
        DispatchQueue.main.async {
            importedDocumentNotification.send(importedUrls)
        }
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // Called as the scene is being released by the system.
        // This occurs shortly after the scene enters the background, or when its session is discarded.
        // Release any resources associated with this scene that can be re-created the next time the scene connects.
        // The scene may re-connect later, as its session was not necessarily discarded (see `application:didDiscardSceneSessions` instead).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Called when the scene has moved from an inactive state to an active state.
        // Use this method to restart any tasks that were paused (or not yet started) when the scene was inactive.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Called when the scene will move from an active state to an inactive state.
        // This may occur due to temporary interruptions (ex. an incoming phone call).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        let pasteboard = UIPasteboard.general
        if pasteboard.hasStrings || pasteboard.hasImages || pasteboard.hasURLs {
            print("show paste option")
        }
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Called as the scene transitions from the foreground to the background.
        // Use this method to save data, release shared resources, and store enough scene-specific state information
        // to restore the scene back to its current state.
    }
    
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        
        handleUrls(urlContexts: URLContexts)
    }
    
    
}

func getShareUrls(from urlString: String) -> [URL]? {
    guard let url = URL(string: urlString),
          let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
          let queryItems = components.queryItems else {
        return nil
    }
    
    var urls = [URL]()
    
    for item in queryItems where item.name == "share_url" {
        if let urlText = item.value?.removingPercentEncoding,
            let url = URL(string: urlText) {
            urls.append(url)
        }
    }
    
    return urls
}

import UIKit
import Flutter
import GoogleMaps // 導入 GoogleMaps 模組

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 初始化 Google Maps SDK，使用 Info.plist 中的 API Key
    GMSServices.provideAPIKey("AIzaSyBnAEpz4kQpMA94u8Iy1GPrHVNZeeBBhwM")
    
    // 註冊 Flutter 插件
    GeneratedPluginRegistrant.register(with: self)
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
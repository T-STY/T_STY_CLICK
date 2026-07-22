import UIKit
import Flutter
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // Maps SDK key is now in Info.plist under `GoogleMapsApiKey`
    // (matches the Android `secrets.xml` pattern — single source
    // per platform, easier to swap for staging vs production via
    // xcconfig in a later pass). Falls back to empty if the key is
    // missing so a misconfigured build fails loudly at the Maps
    // SDK level instead of crashing on startup with `nil`.
    let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GoogleMapsApiKey") as? String ?? ""
    GMSServices.provideAPIKey(mapsKey)

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}


import Cocoa
import FlutterMacOS

public class JustGamepadsPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private let controller = GamepadController()

  public static func register(with registrar: FlutterPluginRegistrar) {
    let instance = JustGamepadsPlugin()
    let channel = FlutterEventChannel(
      name: "just_gamepads/events", binaryMessenger: registrar.messenger)
    channel.setStreamHandler(instance)
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    controller.start { event in events(event) }
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    controller.stop()
    return nil
  }
}

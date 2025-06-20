import UIKit

enum Haptics {
  private static let impact = UIImpactFeedbackGenerator(style: .heavy)   // heavier pop
  private static let notify = UINotificationFeedbackGenerator()

  /// Prime the Taptic Engine so the first tap never misses.
  static func prime() {
    impact.prepare()
    notify.prepare()
  }

  static func tap()   { impact.impactOccurred() }
  static func ok()    { notify.notificationOccurred(.success) }
  static func error() { notify.notificationOccurred(.error) }
}

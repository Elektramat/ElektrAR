import Combine
import Foundation

/// A value that changes many times a second (the crosshair position, about 15 times a second).
/// It lives outside the session's @Published properties, so a screen that observes the
/// session does not redraw at that rate. Only the small views that draw the crosshair, the
/// height label or the live cable length observe this object.
@MainActor
final class LiveValue<Value>: ObservableObject {
    @Published var value: Value?
}

import Foundation
import SwiftUI

@MainActor
final class FlowTabStore: ObservableObject {
    @Published var showFlow: Bool = false
}

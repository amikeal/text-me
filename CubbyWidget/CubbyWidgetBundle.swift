import SwiftUI
import WidgetKit

@main
struct CubbyWidgetBundle: WidgetBundle {
    var body: some Widget {
        CaptureWidget()
        CaptureControl()
    }
}

import SwiftUI

struct TestView: View {
    var body: some View {
        Text("Hello")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Spacer()
                }
            }
    }
}

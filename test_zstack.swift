import SwiftUI

struct TestView: View {
    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.clear
            VStack {
                Spacer(minLength: 470)
                Text("Content")
            }
        }
        .frame(height: 820)
    }
}

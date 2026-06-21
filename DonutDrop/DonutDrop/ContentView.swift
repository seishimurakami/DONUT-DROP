import SwiftUI

struct ContentView: View {
    var body: some View {
        GameWebView()
            .ignoresSafeArea()
            .statusBar(hidden: true)
            .background(Color(red: 10/255, green: 0/255, blue: 21/255))
    }
}

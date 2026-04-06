import SwiftUI
import TipKit

struct SetDefaultBrowserTip: Tip {
    var title: Text { Text("Set Yojam as your default browser") }
    var message: Text? { Text("Once Yojam is your default, every link you click goes through your rules and the picker.") }
    var image: Image? { Image(systemName: "globe") }

    var rules: [Rule] {
        #Rule(Self.$hasSetDefault) { $0.donations.count == 0 }
    }

    @Parameter
    static var hasSetDefault: Bool = false
}

struct ActivationModeTip: Tip {
    var title: Text { Text("Pick when the chooser appears") }
    var message: Text? { Text("Auto-pick learns your habits and only asks when it hasn't seen the domain before.") }
    var image: Image? { Image(systemName: "cursorarrow.click.2") }

    var rules: [Rule] {
        #Rule(Self.$hasChangedMode) { $0.donations.count == 0 }
    }

    @Parameter
    static var hasChangedMode: Bool = false
}

struct BrowserOrderTip: Tip {
    var title: Text { Text("Drag to set your preferred order") }
    var message: Text? { Text("The first browser in the list is your default. Drag the handles to rearrange.") }
    var image: Image? { Image(systemName: "arrow.up.arrow.down") }

    var rules: [Rule] {
        #Rule(Self.$hasReordered) { $0.donations.count == 0 }
    }

    @Parameter
    static var hasReordered: Bool = false
}

struct URLTesterTip: Tip {
    var title: Text { Text("Test your link handling") }
    var message: Text? { Text("Paste any URL here to see how Yojam would process and route it.") }
    var image: Image? { Image(systemName: "testtube.2") }

    var rules: [Rule] {
        #Rule(Self.$hasTestedURL) { $0.donations.count == 0 }
    }

    @Parameter
    static var hasTestedURL: Bool = false
}

struct CustomLaunchArgsTip: Tip {
    var title: Text { Text("Custom launch arguments") }
    var message: Text? { Text("Pass command-line flags like --app=$URL to control how a browser opens links.") }
    var image: Image? { Image(systemName: "terminal") }

    var rules: [Rule] {
        #Rule(Self.$hasEditedArgs) { $0.donations.count == 0 }
    }

    @Parameter
    static var hasEditedArgs: Bool = false
}

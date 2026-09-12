import Cocoa

func test(toolbar: NSToolbar) {
    if let index = toolbar.items.firstIndex(where: { $0.itemIdentifier.rawValue.contains("Search") }) {
        if index > 0, toolbar.items[index - 1].itemIdentifier != .flexibleSpace {
            toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: index)
        }
    }
}

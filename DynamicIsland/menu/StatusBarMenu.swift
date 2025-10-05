import Cocoa

class StatusBarMenu: NSMenu {
    
    var statusItem: NSStatusItem!
    
    override init(title: String) {
        super.init(title: title)
        setupStatusItem()
    }
    
    convenience init() {
        self.init(title: "DynamicIsland")
    }
    
    required init(coder: NSCoder) {
        super.init(coder: coder)
        setupStatusItem()
    }
    
    private func setupStatusItem() {
        // Initialize the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        // Set the menu bar icon
        if let button = statusItem.button {
            button.image = NSImage(named: "logo")
        }
        
        // Set up the menu
        self.addItem(NSMenuItem(title: "Quit", action: #selector(NSApp.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = self
    }

}

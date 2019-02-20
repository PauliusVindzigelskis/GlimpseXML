//
//  AppDelegate.swift
//  XML Example
//
//  Created by venj on 1/19/18.
//  Copyright © 2018 glimpse.io. All rights reserved.
//

import Cocoa
import GlimpseXML

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    @IBOutlet weak var window: NSWindow!


    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Insert code here to initialize your application
        let book = Bundle.main.path(forResource: "books", ofType: "xml")!
        guard let doc = try? GlimpseXML.Document.parseFile(book) else { return }
        let rootNodeName = doc.rootElement.name ?? "failed."
        print("Library Type: \(rootNodeName)")
        let trackCount = (try? doc.xpath("//books/book/title"))?.first?.text ?? "failed."
            
        print("First book: \(trackCount)")

        //let _ = try? Document.parseString("")

        let node = Node(name: "library", attributes: [("url", "glimpse.io")], children: [
            Node(name: "inventory", children: [
                Node(name: "book", attributes: [("checkout", "true")], children: [
                    Node(name: "title", text: "I am a Bunny" ),
                    Node(name: "author", text: "Richard Scarry"),
                    ]),
                Node(name: "book", attributes: [("checkout", "false")], children: [
                    Node(name: "title", text: "You were a Bunny" ),
                    Node(name: "author", text: "Scarry Richard"),
                    ]),
                ]),
            ])
        let xml = Document(root: node)
        print(xml.serialize(true))
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }


}


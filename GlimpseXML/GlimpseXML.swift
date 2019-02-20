//
//  GlimpseXML.swift
//  GlimpseXML
//
//  Created by Marc Prud'hommeaux on 10/13/14.
//  Copyright (c) 2014 glimpse.io. All rights reserved.
//

//import libxmlGlimpse
import libxml2

private typealias DocumentPtr = UnsafePointer<xmlDoc>
private typealias NodePtr = UnsafePointer<xmlNode>
private typealias NamespacePtr = UnsafePointer<xmlNs>

private func castDoc(_ doc: DocumentPtr)->xmlDocPtr { return UnsafeMutablePointer<xmlDoc>(mutating: doc) }
private func castNode(_ node: NodePtr)->xmlNodePtr { return UnsafeMutablePointer<xmlNode>(mutating: node) }
private func castNs(_ ns: NamespacePtr)->xmlNsPtr { return UnsafeMutablePointer<xmlNs>(mutating: ns) }


/// The root of an XML Document, containing a single root element
public final class Document: Equatable, Hashable, CustomDebugStringConvertible {
    fileprivate let docPtr: DocumentPtr
    fileprivate var ownsDoc: Bool


    /// Creates a new Document with the given version string and root node
    public init(version: String? = nil, root: Node? = nil) {
        xmlInitParser()
        precondition(xmlHasFeature(XML_WITH_THREAD) != 0)
        xmlSetStructuredErrorFunc(nil) { ctx, err in } // squelch errors going to stdout
        defer { xmlSetStructuredErrorFunc(nil, nil) }

        self.ownsDoc = true
        self.docPtr = version != nil ? DocumentPtr(xmlNewDoc(version!)) : DocumentPtr(xmlNewDoc(nil))

        if let root = root {
            root.detach()
            xmlDocSetRootElement(castDoc(self.docPtr), castNode(root.nodePtr))
            root.ownsNode = false // ownership transfers to document
        }
    }

    /// Create a new Document by performing a deep copy of the doc parameter
    public required convenience init(copy: Document) {
        self.init(doc: DocumentPtr(xmlCopyDoc(castDoc(copy.docPtr), 1 /* 1 => recursive */)), owns: true)
    }

    fileprivate init(doc: DocumentPtr, owns: Bool) {
        self.ownsDoc = owns
        self.docPtr = doc
    }

    deinit {
        if ownsDoc {
            xmlFreeDoc(castDoc(docPtr))
        }
    }

    public var hashValue: Int { return 0 }

    /// Create a curried xpath finder with the given namespaces
    public func xpath(_ ns: [String:String]? = nil, _ path: String) throws -> [Node] {
        return try rootElement.xpath(path, namespaces: ns)
    }

    public func xpath(_ path: String, namespaces: [String:String]? = nil) throws -> [Node] {
        return try rootElement.xpath(path, namespaces: namespaces)
    }
    
    public func serialize(_ indent: Bool = false, encoding: String? = "utf8") -> String {
        var buf: UnsafeMutablePointer<xmlChar>? = nil
        var buflen: Int32 = 0
        let format: Int32 = indent ? 1 : 0

        if let encoding = encoding {
            xmlDocDumpFormatMemoryEnc(castDoc(self.docPtr), &buf, &buflen, encoding, format)
        } else {
            xmlDocDumpFormatMemory(castDoc(self.docPtr), &buf, &buflen, format)
        }

        var string: String = ""
        if buflen >= 0 {
            string = String(cString: buf!)
            buf?.deallocate()
        }

        return string
    }

    public var debugDescription: String { return serialize() }

    public var rootElement: Node {
        get { return Node(node: NodePtr(xmlDocGetRootElement(castDoc(docPtr))), owns: false) }
    }

    /// Parses the XML contained in the given string, returning the Document or an Error
    public class func parseString(_ xmlString: String, encoding: String? = nil, html: Bool = false) throws -> Document {
        var doc: Document?
        var err: Error?
        // FIXME: withCString doesn't declare rethrows, so we need to hold value & error in bogus optionals
        let _: Void = xmlString.withCString { str in
            do {
                doc = try self.parseData(str, length: Int(strlen(str)), html: html)
            } catch {
                err = error
            }
        }
        if let err = err { throw err }
        return doc!
    }

    /// Parses the XML contained in the given data, returning the Document or an Error
    public class func parseData(_ xmlData: UnsafePointer<CChar>, length: Int, encoding: String? = nil, html: Bool = false) throws -> Document {
        return try parse(.data(data: xmlData, length: Int32(length)), encoding: encoding, html: html)
    }

    /// Parses the XML contained at the given filename, returning the Document or an Error
    public class func parseFile(_ fileName: String, encoding: String? = nil, html: Bool = false) throws -> Document {
        return try parse(.file(fileName: fileName), encoding: encoding, html: html)
    }

    /// The source of the loading for the XML data
    enum XMLLoadSource {
        case file(fileName: String)
        case data(data: UnsafePointer<CChar>, length: Int32)
    }

    fileprivate class func parse(_ source: XMLLoadSource, encoding: String?, html: Bool) throws -> Document {
        xmlInitParser()
        precondition(xmlHasFeature(XML_WITH_THREAD) != 0)
        xmlSetStructuredErrorFunc(nil) { ctx, err in } // squelch errors going to stdout
        defer { xmlSetStructuredErrorFunc(nil, nil) }

        let opts : Int32 = Int32(XML_PARSE_NONET.rawValue)

        if html {
            precondition(xmlHasFeature(XML_WITH_HTML) != 0)
        }

        let ctx = html ? htmlNewParserCtxt() : xmlNewParserCtxt()
        defer {
            if html {
                htmlFreeParserCtxt(ctx)
            } else {
                xmlFreeParserCtxt(ctx)
            }
        }

        var doc: xmlDocPtr? // also htmlDocPtr: “Most of the back-end structures from XML and HTML are shared.”

        switch (html, source) {
        case (false, .file(let fileName)):
            if let encoding = encoding {
                doc = xmlCtxtReadFile(ctx, fileName, encoding, opts)
            } else {
                doc = xmlCtxtReadFile(ctx, fileName, nil, opts)
            }
        case (false, .data(let data, let length)):
            if let encoding = encoding {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, encoding, opts)
            } else {
                doc = xmlCtxtReadMemory(ctx, data, length, nil, nil, opts)
            }
        case (true, .file(let fileName)):
            if let encoding = encoding {
                doc = htmlCtxtReadFile(ctx, fileName, encoding, opts)
            } else {
                doc = htmlCtxtReadFile(ctx, fileName, nil, opts)
            }
        case (true, .data(let data, let length)):
            if let encoding = encoding {
                doc = htmlCtxtReadMemory(ctx, data, length, nil, encoding, opts)
            } else {
                doc = htmlCtxtReadMemory(ctx, data, length, nil, nil, opts)
            }
        }
        
        let err = errorFromXmlError((ctx?.pointee.lastError)!)
        
        if let doc = doc {
            //if doc != nil { // unwrapped pointer can still be nil
            let document = Document(doc: DocumentPtr(doc), owns: true)
            return document
            //}
        }
        
        throw err
    }
}

/// Equality is defined by whether the underlying document pointer is the same
public func ==(lhs: Document, rhs: Document) -> Bool {
    return castDoc(lhs.docPtr) == castDoc(rhs.docPtr)
}


/// A Node in an Document
public final class Node: Equatable, Hashable, CustomDebugStringConvertible {
    fileprivate let nodePtr: NodePtr
    fileprivate var ownsNode: Bool

    fileprivate init(node: NodePtr, owns: Bool) {
        self.ownsNode = owns
        self.nodePtr = node
    }

    public init(doc: Document? = nil, cdata: String) {
        self.ownsNode = doc == nil
        self.nodePtr = NodePtr(xmlNewCDataBlock(doc == nil ? nil : castDoc(doc!.docPtr), cdata, Int32(cdata.utf8CString.count)))
    }

    public init(doc: Document? = nil, text: String) {
        self.ownsNode = doc == nil
        self.nodePtr = NodePtr(xmlNewText(text))
    }

    public init(doc: Document? = nil, name: String? = nil, namespace: Namespace? = nil, attributes: [(name: String, value: String)]? = nil, text: String? = nil, children: [Node]? = nil) {
        self.ownsNode = doc == nil
        
        
        self.nodePtr = NodePtr(xmlNewDocNode(doc == nil ? nil : castDoc(doc!.docPtr), namespace == nil ? nil : castNs(namespace!.nsPtr), name ?? "", text ?? ""))
        
        let _ = attributes?.map { self.updateAttribute($0, value: $1, namespace: namespace) }

        if let children = children {
            self.children = children
        }
    }

    public required convenience init(copy: Node) {
        self.init(node: NodePtr(xmlCopyNode(castNode(copy.nodePtr), 1 /* 1 => recursive */)), owns: true)
    }

    deinit {
        if ownsNode {
            xmlFreeNode(castNode(nodePtr))
        }
    }

    public var hashValue: Int { return name?.hashValue ?? 0 }

    /// Returns a deep copy of the current node
    public func copy() -> Node {
        return Node(copy: self)
    }

    /// The name of the node
    public var name: String? {
        get { return stringFromXMLString(castNode(nodePtr).pointee.name) }
        set(value) {
            if let value = value {
                xmlNodeSetName(castNode(nodePtr), value)
            } else {
                xmlNodeSetName(castNode(nodePtr), nil)
            }
        }
    }

    /// The text content of the node
    public var text: String? {
        get { return stringFromXMLString(xmlNodeGetContent(castNode(nodePtr)), free: true) }

        set(value) {
            if let value = value {
                xmlNodeSetContent(castNode(nodePtr), value)
            } else {
                xmlNodeSetContent(castNode(nodePtr), nil)
            }
        }
    }

    /// The parent node of the node
    public var parent: Node? {
        let parentPtr = castNode(nodePtr).pointee.parent
        if parentPtr == nil {
            return nil
        } else {
            return Node(node: NodePtr(parentPtr!), owns: false)
        }
    }

    /// The next sibling of the node
    public var next: Node? {
        get {
            let nextPtr = castNode(nodePtr).pointee.next
            if nextPtr == nil {
                return nil
            } else {
                return Node(node: NodePtr(nextPtr!), owns: false)
            }
        }

        set(node) {
            if let node = node {
                node.detach()
                xmlAddNextSibling(castNode(nodePtr), castNode(node.nodePtr))
                node.ownsNode = false
            }
        }
    }

    /// The previous sibling of the node
    public var prev: Node? {
        get {
            let prevPtr = castNode(nodePtr).pointee.prev
            if prevPtr == nil {
                return nil
            } else {
                return Node(node: NodePtr(prevPtr!), owns: false)
            }
        }

        set(node) {
            if let node = node {
                node.detach()
                xmlAddPrevSibling(castNode(nodePtr), castNode(node.nodePtr))
                node.ownsNode = false
            }
        }

    }

    /// The child nodes of the current node
    public var children: [Node] {
        get {
            var nodes = [Node]()
            var child = castNode(nodePtr).pointee.children
            while child != nil {
                defer { child = child?.pointee.next }
                nodes += [Node(node: NodePtr(child!), owns: false)]
            }
            return nodes
        }

        set(newChildren) {
            for child in children { child.detach() } // remove existing children from parent
            for child in newChildren { addChild(child) }
        }
    }

    /// Adds the given node to the end of the child node list; if the child is already in a node tree then a copy will be added and the copy will be returned
    @discardableResult
    public func addChild(_ child: Node) -> Node {
        if child.ownsNode {
            // we don't have enough information to transfer ownership directly, do copy instead?
            child.ownsNode = false // ownership transfers to the new parent
            xmlAddChild(castNode(nodePtr), castNode(child.nodePtr))
            return child
        } else {
            let childCopy = Node(copy: child)
            xmlAddChild(castNode(nodePtr), castNode(childCopy.nodePtr))
            return childCopy
        }
    }

    /// Removes the node from a parent
    public func detach() {
        xmlUnlinkNode(castNode(nodePtr))
        self.ownsNode = true // ownership goes to self
    }

    /// Returns the value for the given attribute name with the optional namespace
    public func attributeValue(_ name: String, namespace: Namespace? = nil) -> String? {
        if let href = namespace?.href {
            return stringFromXMLString(xmlGetNsProp(castNode(nodePtr), name, href))
        } else {
            return stringFromXMLString(xmlGetNoNsProp(castNode(nodePtr), name))
        }
    }

    /// Updates the value for the given attribute
    public func updateAttribute(_ name: String, value: String, namespace: Namespace? = nil) {
        if let namespace = namespace {
            xmlSetNsProp(castNode(nodePtr), castNs(namespace.nsPtr), name, value)
        } else {
            xmlSetProp(castNode(nodePtr), name, value)
        }
    }

    /// Removes the given attribute
    @discardableResult
    public func removeAttribute(_ name: String, namespace: Namespace? = nil) -> Bool {
        var attr: xmlAttrPtr?
        if let href = namespace?.href {
            attr = xmlHasNsProp(castNode(nodePtr), name, href)
        } else {
            attr = xmlHasProp(castNode(nodePtr), name)
        }

        if attr != nil {
            xmlRemoveProp(attr)
            return true
        } else {
            return false
        }
    }

    /// Node subscripts get and set namespace-less attributes on the element
    public subscript(attribute: String) -> String? {
        get {
            return attributeValue(attribute)
        }

        set(value) {
            if let value = value {
                updateAttribute(attribute, value: value)
            } else {
                removeAttribute(attribute)
            }
        }
    }

    /// The name of the type of node
    public var nodeType: String {
        switch castNode(nodePtr).pointee.type.rawValue {
        case XML_ELEMENT_NODE.rawValue: return "Element"
        case XML_ATTRIBUTE_NODE.rawValue: return "Attribute"
        case XML_TEXT_NODE.rawValue: return "Text"
        case XML_CDATA_SECTION_NODE.rawValue: return "CDATA"
        case XML_ENTITY_REF_NODE.rawValue: return "EntityRef"
        case XML_ENTITY_NODE.rawValue: return "Entity"
        case XML_PI_NODE.rawValue: return "PI"
        case XML_COMMENT_NODE.rawValue: return "Comment"
        case XML_DOCUMENT_NODE.rawValue: return "Document"
        case XML_DOCUMENT_TYPE_NODE.rawValue: return "DocumentType"
        case XML_DOCUMENT_FRAG_NODE.rawValue: return "DocumentFrag"
        case XML_NOTATION_NODE.rawValue: return "Notation"
        case XML_HTML_DOCUMENT_NODE.rawValue: return "HTMLDocument"
        case XML_DTD_NODE.rawValue: return "DTD"
        case XML_ELEMENT_DECL.rawValue: return "ElementDecl"
        case XML_ATTRIBUTE_DECL.rawValue: return "AttributeDecl"
        case XML_ENTITY_DECL.rawValue: return "EntityDecl"
        case XML_NAMESPACE_DECL.rawValue: return "NamespaceDecl"
        case XML_XINCLUDE_START.rawValue: return "XIncludeStart"
        case XML_XINCLUDE_END.rawValue: return "XIncludeEnd"
        case XML_DOCB_DOCUMENT_NODE.rawValue: return "Document"
        default: return "Unknown"
        }
    }

    /// Returns this node as an XML string with optional indentation
    public func serialize(_ indent: Bool = false) -> String {
        let buf = xmlBufferCreate()
        let level: Int32 = 0
        let format: Int32 = indent ? 1 : 0

        let result = xmlNodeDump(buf, castNode(nodePtr).pointee.doc, castNode(nodePtr), level, format)

        var string: String = ""
        if result >= 0 {
            let buflen: Int32 = xmlBufferLength(buf)
            let str: UnsafePointer<CUnsignedChar> = xmlBufferContent(buf)
            if buflen >= 0 {
                string = String(cString: UnsafePointer(str))
            }
        }

        xmlBufferFree(buf)
        return string
    }

    /// The owning document for the node, if any
    public var document: Document? {
        let docPtr = castNode(nodePtr).pointee.doc
        return docPtr == nil ? nil : Document(doc: DocumentPtr(docPtr!), owns: false)
    }

    public var debugDescription: String {
        return "[\(nodeType)]: \(serialize())"
    }

    /// Evaluates the given xpath and returns matching nodes
    public func xpath(_ path: String, namespaces: [String:String]? = nil) throws -> [Node] {

        // xmlXPathNewContext requires that a node be part of a document; host it inside a temporary one if it is standalone
        var nodeDoc = castNode(nodePtr).pointee.doc
        if nodeDoc == nil {
            nodeDoc = xmlNewDoc(nil)
            var topParent = castNode(nodePtr)
            while topParent.pointee.parent != nil {
                topParent = topParent.pointee.parent
            }
            xmlDocSetRootElement(nodeDoc, topParent)

            // release our temporary document when we are done
            defer {
                xmlUnlinkNode(topParent)
                xmlSetTreeDoc(topParent, nil)
                xmlFreeDoc(nodeDoc)
            }
        }

        let xpathCtx = xmlXPathNewContext(nodeDoc)
        defer { xmlXPathFreeContext(xpathCtx) }

        if xpathCtx == nil {
            throw XMLError(message: "Could not create XPath context")
        }

        if let namespaces = namespaces {
            for (prefix, uri) in namespaces {
                xmlXPathRegisterNs(xpathCtx, prefix, uri)
            }
        }

        let xpathObj = xmlXPathNodeEval(castNode(nodePtr), path, xpathCtx)
        if xpathObj == nil {
            let lastError = xpathCtx?.pointee.lastError
            let error = errorFromXmlError(lastError!)
            throw error
        }
        defer { xmlXPathFreeObject(xpathObj) }

        var results = [Node]()
        let nodeSet = xpathObj?.pointee.nodesetval
        if nodeSet != nil {
            let count = Int((nodeSet?.pointee.nodeNr)!)
            var index = 0
            while index < count {
                defer { index += 1 }
                let node = nodeSet?.pointee.nodeTab[index]
                if node != nil {
                    results += [Node(node: NodePtr(node!), owns: false)]
                }
            }
        }
        return results
    }
}


/// Equality is defined by whether the underlying node pointer is identical
public func ==(lhs: Node, rhs: Node) -> Bool {
    return castNode(lhs.nodePtr) == castNode(rhs.nodePtr)
}

/// Appends the right node as a child of the left node
public func +=(lhs: Node, rhs: Node) -> Node {
    lhs.addChild(rhs)
    return rhs
}


private func errorFromXmlError(_ error: xmlError)->XMLError {
    let level = errorLevelFromXmlErrorLevel(error.level)
    var message:String = ""
    var file:String = ""
    var str1:String = ""
    var str2:String = ""
    var str3:String = ""
    if error.message != nil {
        message = String(cString: error.message)
    }
    
    if error.file != nil {
        file = String(cString: error.file)
    }
    
    if error.str1 != nil {
        str1 = String(cString: error.str1)
    }
    
    if error.str2 != nil {
        str2 = String(cString: error.str2)
    }
    
    if error.str3 != nil {
        str3 = String(cString: error.str3)
    }
    
    return XMLError(domain: XMLError.ErrorDomain.fromErrorDomain(error.domain), code: error.code, message: message, level: level, file: file, line: error.line, str1: str1, str2: str2, str3: str3, int1: error.int1, column: error.int2)
}

private func errorLevelFromXmlErrorLevel(_ level: xmlErrorLevel) -> XMLError.ErrorLevel {
    switch level.rawValue {
    case XML_ERR_NONE.rawValue: return .none
    case XML_ERR_WARNING.rawValue: return .warning
    case XML_ERR_ERROR.rawValue: return .error
    case XML_ERR_FATAL.rawValue: return .fatal
    default: return .none
    }
}

/// A namespace for a document, node, or attribute
open class Namespace {
    fileprivate let nsPtr: NamespacePtr
    fileprivate let ownsNode: Bool

    fileprivate init(ns: NamespacePtr, owns: Bool) {
        self.ownsNode = owns
        self.nsPtr = ns
    }

    public init(href: String, prefix: String, node: Node? = nil) {
        self.ownsNode = node == nil
        self.nsPtr = NamespacePtr(xmlNewNs(node == nil ? nil : castNode(node!.nodePtr), href, prefix))
    }

    public required convenience init(copy: Namespace) {
        self.init(ns: NamespacePtr(xmlCopyNamespace(castNs(copy.nsPtr))), owns: true)
    }

    deinit {
        if ownsNode {
            xmlFreeNs(castNs(nsPtr))
        }
    }

    fileprivate var href: String? { return stringFromXMLString(castNs(nsPtr).pointee.href) }
    fileprivate var prefix: String? { return stringFromXMLString(castNs(nsPtr).pointee.prefix) }
    
}


/// MARK: General Utilities

/// The result of an XML operation, which may be a T or an Error condition
public enum XMLResult<T>: CustomDebugStringConvertible {
    case value(XMLValue<T>)
    case error(XMLError)

    public var debugDescription: String {
        switch self {
        case .value(let v): return "value: \(v)"
        case .error(let e): return "error: \(e)"
        }
    }

    public var value: T? {
        switch self {
        case .value(let v): return v.value
        case .error: return nil
        }
    }

    public var error: XMLError? {
        switch self {
        case .value: return nil
        case .error(let e): return e
        }
    }

}

/// Wrapper for a generic value; workaround for Swift enum generic deficiency
open class XMLValue<T> {
    public let value: T
    public init(_ value: T) { self.value = value }
}

extension XMLError: Error {
    public var _domain: String { return domain.debugDescription }
    public var _code: Int { return Int(code) }
}

// A stuctured XML parse of processing error
public struct XMLError: CustomDebugStringConvertible {
    
    public enum ErrorLevel: CustomDebugStringConvertible {
        case none, warning, error, fatal

        public var debugDescription: String {
            switch self {
            case .none: return "None"
            case .warning: return "Warning"
            case .error: return "Error"
            case .fatal: return "Fatal"
            }
        }
    }

    /// The domain (type) of error that occurred
    public enum ErrorDomain: UInt, CustomDebugStringConvertible {
        case none, parser, tree, namespace, dtd, html, memory, output, io, ftp, http, xInclude, xPath, xPointer, regexp, datatype, schemasP, schemasV, relaxNGP, relaxNGV, catalog, c14N, xslt, valid, check, writer, module, i18N, schematronV, buffer, uri

        public var debugDescription: String {
            switch self {
            case .none: return "None"
            case .parser: return "Parser"
            case .tree: return "Tree"
            case .namespace: return "Namespace"
            case .dtd: return "DTD"
            case .html: return "HTML"
            case .memory: return "Memory"
            case .output: return "Output"
            case .io: return "IO"
            case .ftp: return "FTP"
            case .http: return "HTTP"
            case .xInclude: return "XInclude"
            case .xPath: return "XPath"
            case .xPointer: return "XPointer"
            case .regexp: return "Regexp"
            case .datatype: return "Datatype"
            case .schemasP: return "SchemasP"
            case .schemasV: return "SchemasV"
            case .relaxNGP: return "RelaxNGP"
            case .relaxNGV: return "RelaxNGV"
            case .catalog: return "Catalog"
            case .c14N: return "C14N"
            case .xslt: return "XSLT"
            case .valid: return "Valid"
            case .check: return "Check"
            case .writer: return "Writer"
            case .module: return "Module"
            case .i18N: return "I18N"
            case .schematronV: return "SchematronV"
            case .buffer: return "Buffer"
            case .uri: return "URI"
            }
        }

        public static func fromErrorDomain(_ domain: Int32) -> ErrorDomain {
            return ErrorDomain(rawValue: UInt(domain)) ?? .none
        }
    }

    /// What part of the library raised this error
    public let domain: ErrorDomain

    /// The error code.level: return XXX
    public let code: Int32

    /// human-readable informative error message
    public let message: String

    /// how consequent is the error
    public let level: ErrorLevel

    /// the filename
    public let file: String

    /// the line number if available
    public let line: Int32

    /// column number of the error or 0 if N/A
    public let column: Int32

    /// extra string information
    public let str1: String

    /// extra string information
    public let str2: String

    /// extra string information
    public let str3: String

    /// extra number information
    public let int1: Int32

    public init(domain: ErrorDomain, code: Int32, message: String, level: ErrorLevel, file: String, line: Int32, str1: String, str2: String, str3: String, int1: Int32, column: Int32) {
        self.domain = domain
        self.code = code
        self.message = message
        self.level = level
        self.file = file
        self.line = line
        self.str1 = str1
        self.str2 = str2
        self.str3 = str3
        self.int1 = int1
        self.column = column
    }

    public init(message: String) {
        self.init(domain: ErrorDomain.none, code: 0, message: message, level: ErrorLevel.fatal, file: "", line: 0, str1: "", str2: "", str3: "", int1: 0, column: 0)
    }

    public var debugDescription: String {
        return "\(domain) \(level) [\(line):\(column)]: \(message)"
    }
}

private func stringFromXMLString(_ string: UnsafePointer<xmlChar>, free: Bool = false) -> String? {
    let str = String(cString: UnsafePointer(string))
    if free {
        xmlFree(UnsafeMutableRawPointer(mutating: string))
    }
    return str
}


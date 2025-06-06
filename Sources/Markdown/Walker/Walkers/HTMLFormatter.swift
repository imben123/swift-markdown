/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2023 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See https://swift.org/LICENSE.txt for license information
 See https://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Foundation

/// Options given to the ``HTMLFormatter``.
public struct HTMLFormatterOptions: OptionSet {
    public var rawValue: UInt
    public init(rawValue: UInt) {
        self.rawValue = rawValue
    }

    /// Attempt to parse blockquotes as asides.
    ///
    /// If a blockquote is found to begin with an aside marker, e.g. "`Remark:`" then the
    /// corresponding HTML will be an `<aside>` tag instead of a `<blockquote>` tag, with the aside
    /// kind given in the `data-kind` attribute.
    ///
    /// - Note: To prevent false positives, the aside checking will only look for a single-word
    ///   aside marker, i.e. the following blockquote will not parse as an aside:
    ///
    ///   ```markdown
    ///   > This is a compound sentence: It contains two clauses separated by a colon.
    ///   ```
    public static let parseAsides = HTMLFormatterOptions(rawValue: 1 << 0)

    /// Parse inline attributes as JSON and use the `"class"` property as the resulting span's `class`.
    public static let parseInlineAttributeClass = HTMLFormatterOptions(rawValue: 1 << 1)
}

/// A ``MarkupWalker`` that prints rendered HTML for a given ``Markup`` tree.
public struct HTMLFormatter: MarkupWalker {
    /// The resulting HTML built up after printing.
    public private(set) var result = ""

    let options: HTMLFormatterOptions

    var inTableHead = false
    var tableColumnAlignments: [Table.ColumnAlignment?]? = nil
    var currentTableColumn = 0

    public init(options: HTMLFormatterOptions = []) {
        self.options = options
    }

    /// Format HTML for the given markup tree.
    public static func format(_ markup: Markup, options: HTMLFormatterOptions = []) -> String {
        var walker = HTMLFormatter(options: options)
        walker.visit(markup)
        return walker.result
    }

    /// Format HTML for the given input text.
    public static func format(_ inputString: String, options: HTMLFormatterOptions = []) -> String {
        let document = Document(parsing: inputString)
        return format(document, options: options)
    }

    // MARK: Block elements

    public mutating func visitBlockQuote(_ blockQuote: BlockQuote) -> () {
        if self.options.contains(.parseAsides), let aside = Aside(blockQuote, tagRequirement: .requireSingleWordTag) {
            result += "<aside data-kind=\"\(aside.kind.rawValue)\">\n"
            for child in aside.content {
                visit(child)
            }
            result += "</aside>\n"
        } else {
            result += "<blockquote>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }
    }

    public mutating func visitCodeBlock(_ codeBlock: CodeBlock) -> () {
        let languageAttr: String
        if let language = codeBlock.language {
            languageAttr = " class=\"language-\(language)\""
        } else {
            languageAttr = ""
        }
        result += "<pre><code\(languageAttr)>\(codeBlock.code)</code></pre>\n"
    }

    public mutating func visitHeading(_ heading: Heading) -> () {
        result += "<h\(heading.level)>\(heading.plainText)</h\(heading.level)>\n"
    }

    public mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) -> () {
        result += "<hr />\n"
    }

    public mutating func visitHTMLBlock(_ html: HTMLBlock) -> () {
        result += html.rawHTML
    }

    public mutating func visitListItem(_ listItem: ListItem) -> () {
        result += "<li>"
        if let checkbox = listItem.checkbox {
            result += "<input type=\"checkbox\" disabled=\"\""
            if checkbox == .checked {
                result += " checked=\"\""
            }
            result += " /> "
        }
        descendInto(listItem)
        result += "</li>\n"
    }

    public mutating func visitOrderedList(_ orderedList: OrderedList) -> () {
        let start: String
        if orderedList.startIndex != 1 {
            start = " start=\"\(orderedList.startIndex)\""
        } else {
            start = ""
        }
        result += "<ol\(start)>\n"
        descendInto(orderedList)
        result += "</ol>\n"
    }

    public mutating func visitUnorderedList(_ unorderedList: UnorderedList) -> () {
        result += "<ul>\n"
        descendInto(unorderedList)
        result += "</ul>\n"
    }

    public mutating func visitParagraph(_ paragraph: Paragraph) -> () {
        result += "<p>"
        descendInto(paragraph)
        result += "</p>\n"
    }

    public mutating func visitTable(_ table: Table) -> () {
        result += "<table>\n"
        tableColumnAlignments = table.columnAlignments
        descendInto(table)
        tableColumnAlignments = nil
        result += "</table>\n"
    }

    public mutating func visitTableHead(_ tableHead: Table.Head) -> () {
        result += "<thead>\n"
        result += "<tr>\n"

        inTableHead = true
        currentTableColumn = 0
        descendInto(tableHead)
        inTableHead = false

        result += "</tr>\n"
        result += "</thead>\n"
    }

    public mutating func visitTableBody(_ tableBody: Table.Body) -> () {
        if !tableBody.isEmpty {
            result += "<tbody>\n"
            descendInto(tableBody)
            result += "</tbody>\n"
        }
    }

    public mutating func visitTableRow(_ tableRow: Table.Row) -> () {
        result += "<tr>\n"

        currentTableColumn = 0
        descendInto(tableRow)

        result += "</tr>\n"
    }

    public mutating func visitTableCell(_ tableCell: Table.Cell) -> () {
        guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count else { return }

        guard tableCell.colspan > 0 && tableCell.rowspan > 0 else { return }

        let element: String
        if inTableHead {
            element = "th"
        } else {
            element = "td"
        }

        if inTableHead {
            result += "<\(element)"
        } else {
            result += "<\(element)"
        }

        if let alignment = alignments[currentTableColumn] {
            result += " align=\"\(alignment)\""
        }
        currentTableColumn += 1

        if tableCell.rowspan > 1 {
            result += " rowspan=\"\(tableCell.rowspan)\""
        }
        if tableCell.colspan > 1 {
            result += " colspan=\"\(tableCell.colspan)\""
        }

        result += ">"

        descendInto(tableCell)

        result += "</\(element)>\n"
    }

    // MARK: Inline elements

    mutating func printInline(tag: String, _ content: Markup) {
        result += "<\(tag)>"
        descendInto(content)
        result += "</\(tag)>"
    }

    public mutating func visitInlineCode(_ inlineCode: InlineCode) -> () {
        result += "<code>\(inlineCode.code)</code>"
    }

    public mutating func visitEmphasis(_ emphasis: Emphasis) -> () {
        printInline(tag: "em", emphasis)
    }

    public mutating func visitStrong(_ strong: Strong) -> () {
        printInline(tag: "strong", strong)
    }

    public mutating func visitImage(_ image: Image) -> () {
        result += "<img"

        if let source = image.source, !source.isEmpty {
            result += " src=\"\(source)\""
        }

        if let title = image.title, !title.isEmpty {
            result += " title=\"\(title)\""
        }

        result += " />"
    }

    public mutating func visitInlineHTML(_ inlineHTML: InlineHTML) -> () {
        result += inlineHTML.rawHTML
    }

    public mutating func visitLineBreak(_ lineBreak: LineBreak) -> () {
        result += "<br />\n"
    }

    public mutating func visitSoftBreak(_ softBreak: SoftBreak) -> () {
        result += "\n"
    }

    public mutating func visitLink(_ link: Link) -> () {
        result += "<a"
        if let destination = link.destination {
            result += " href=\"\(destination)\""
        }
        result += ">"

        descendInto(link)

        result += "</a>"
    }

    public mutating func visitText(_ text: Text) -> () {
        result += text.string
    }

    public mutating func visitStrikethrough(_ strikethrough: Strikethrough) -> () {
        printInline(tag: "del", strikethrough)
    }

    public mutating func visitHighlight(_ highlight: Highlight) -> () {
        printInline(tag: "mark", highlight)
    }

    public mutating func visitSymbolLink(_ symbolLink: SymbolLink) -> () {
        if let destination = symbolLink.destination {
            result += "<code>\(destination)</code>"
        }
    }

    public mutating func visitInlineAttributes(_ attributes: InlineAttributes) -> () {
        result += "<span data-attributes=\"\(attributes.attributes.replacingOccurrences(of: "\"", with: "\\\""))\""

        let wrappedAttributes = "{\(attributes.attributes)}"
        if options.contains(.parseInlineAttributeClass),
           let attributesData = wrappedAttributes.data(using: .utf8)
        {
            struct ParsedAttributes: Decodable {
                var `class`: String
            }

            let decoder = JSONDecoder()
            // JSON5 parsing is available in Apple Foundation as of macOS 12 et al, or in Swift
            // Foundation as of Swift 6.0
            // Note: We don't turn on `.assumesTopLevelDictionary` to allow parsing to work on older
            // compilers and OSs. If/when Swift-Markdown assumes a minimum Swift version of 6.0, we
            // can clean this up to always use JSON5 and top-level dictionaries.
            #if os(macOS) || os(iOS) || os(tvOS) || os(watchOS) || os(visionOS)
            if #available(macOS 12, iOS 15, tvOS 15, watchOS 8, *) {
                decoder.allowsJSON5 = true
            }
            #elseif compiler(>=6.0)
            decoder.allowsJSON5 = true
            #endif

            let parsedAttributes = try? decoder.decode(ParsedAttributes.self, from: attributesData)
            if let parsedAttributes = parsedAttributes {
                result += " class=\"\(parsedAttributes.class)\""
            }
        }

        result += ">"
        descendInto(attributes)
        result += "</span>"
    }
}

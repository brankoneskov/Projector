//
//  ExportHelpers.swift
//  Projector
//
//  Drop-in helper for printing & PDF export (macOS 12+).
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers
import PDFKit

// MARK: - Core PDF / Print helper
enum PDFExporter {
    /// A4 at 72 dpi (AppKit points)
    static let a4: NSSize = NSSize(width: 595, height: 842)

    // MARK: - Internals (replace these three in ExportHelpers.swift)

    private static func savePDF(
        of view: NSView,
        to url: URL,
        pageSize: NSSize,
        margins: NSEdgeInsets,
        virtualPageCount: Int? = nil
    ) throws {
        let info = configuredPrintInfo(pageSize: pageSize, margins: margins)
        info.jobDisposition = NSPrintInfo.JobDisposition.save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url

        // 🔧 Make the view as tall as the total number of virtual pages
        if let pages = virtualPageCount {
            let h = pageSize.height * CGFloat(max(pages, 1))
            view.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: h)
        }

        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else {
            throw NSError(
                domain: "Projector.PDF",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Print operation failed"]
            )
        }
    }

    static func runSavePanelAndExport<V: View>(
        root: V,
        filename: String,
        pageSize: NSSize = PDFExporter.a4,
        margins: NSEdgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18),
        virtualPageCount: Int? = nil
    ) throws {
        let host = NSHostingView(rootView: root)

        // 🔧 Make the host tall enough for all pages
        if let pages = virtualPageCount {
            host.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height * CGFloat(max(pages, 1)))
        } else {
            host.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = filename

        if panel.runModal() == .OK, let url = panel.url {
            try savePDF(
                of: host,
                to: url,
                pageSize: pageSize,
                margins: margins,
                virtualPageCount: virtualPageCount
            )
        }
    }

    static func printView<V: View>(
        root: V,
        pageSize: NSSize = PDFExporter.a4,
        margins: NSEdgeInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18),
        virtualPageCount: Int? = nil
    ) {
        let host = NSHostingView(rootView: root)

        // 🔧 Make the host tall enough for all pages
        if let pages = virtualPageCount {
            host.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height * CGFloat(max(pages, 1)))
        } else {
            host.frame = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        }

        let info = configuredPrintInfo(pageSize: pageSize, margins: margins)
        let op = NSPrintOperation(view: host, printInfo: info)
        op.showsPrintPanel = true
        op.showsProgressPanel = true
        op.run()
    }
    // MARK: - Default filename
    private static func defaultQuoteFilename(project: Project, budget: ProjectBudget) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        let date = df.string(from: Date())

        func clean(_ s: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            return s.components(separatedBy: invalid).joined(separator: "_")
        }

        return "\(clean(project.name))_\(clean(budget.quoteNumber ?? budget.title))_\(date).pdf"
    }

    private static func configuredPrintInfo(pageSize: NSSize, margins: NSEdgeInsets) -> NSPrintInfo {
        let pi = (NSPrintInfo.shared.copy() as! NSPrintInfo)
        pi.horizontalPagination = .automatic
        pi.verticalPagination   = .automatic
        pi.paperSize = pageSize
        pi.leftMargin = 0
        pi.rightMargin = 0
        pi.topMargin = 0
        pi.bottomMargin = 0
        pi.scalingFactor = 1.0
        pi.isHorizontallyCentered = false
        pi.isVerticallyCentered   = false
        return pi
    }
}

// MARK: - Pagination utilities
private func rowsPerPageForCurrentLayout() -> Int {
    let header: CGFloat = 90
    let footer: CGFloat = 36
    let verticalMargins: CGFloat = A4_MARGIN * 2
    let rowHeight: CGFloat = 18
    let usable = A4_SIZE.height - verticalMargins - header - footer
    return max(10, Int(floor(usable / rowHeight)))
}

private func paginateLines(_ all: [BudgetLine], rowsPerPage: Int) -> [[BudgetLine]] {
    let lines = all.filter { $0.isActive }
    guard !lines.isEmpty else { return [[]] }
    var pages: [[BudgetLine]] = []
    var i = 0
    while i < lines.count {
        let end = min(i + rowsPerPage, lines.count)
        pages.append(Array(lines[i..<end]))
        i = end
    }
    return pages
}

// MARK: - Totals footer
// Use the legacy signature everywhere so it compiles on all SDKs.
@inline(__always)
private func pdfData(from view: NSView) -> Data {
    // dataWithPDF performs the required off-screen NSHostingView display pass.
    // Do not force layoutSubtreeIfNeeded() here: on recent macOS versions that
    // can commit the AppKit-backed logo before SwiftUI's text display list is
    // ready, producing a logo-only PDF.
    return view.dataWithPDF(inside: view.bounds)
}

// MARK: - Quote page height estimates
//
// QuoteExportPageView uses fixed-size A4 pages. Pagination therefore has to
// reserve the real rendered height of totals, notes and footers; otherwise an
// oversized SwiftUI VStack is clipped at both the top and bottom of the page.
private func estimatedTextHeight(
    _ text: String,
    font: NSFont,
    width: CGFloat
) -> CGFloat {
    guard !text.isEmpty, width > 0 else { return 0 }

    let bounds = (text as NSString).boundingRect(
        with: NSSize(width: width, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading],
        attributes: [.font: font]
    )
    return ceil(bounds.height)
}

private func estimatedLastPageFooterHeight(for budget: ProjectBudget) -> CGFloat {
    let printableWidth = A4_SIZE.width - (A4_MARGIN * 2)
    let notes = budget.generalNotes
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let legalNotes = localizedExportFooterNotes(language: budget.exportLanguage)

    // Totals divider + three total rows.
    var height: CGFloat = 58

    if !notes.isEmpty {
        // Divider, "Notes" heading, spacing and the user-entered text.
        height += 29
        height += estimatedTextHeight(
            notes,
            font: .systemFont(ofSize: 9),
            width: printableWidth
        )
    }

    if !legalNotes.isEmpty {
        // The legal/export notes use a VStack with four points between rows.
        height += 12
        for line in legalNotes {
            height += estimatedTextHeight(
                line,
                font: .systemFont(ofSize: 8),
                width: printableWidth
            )
        }
        height += CGFloat(max(legalNotes.count - 1, 0)) * 4
        height += 8
    }

    // Studio details, page number and a little tolerance for font metrics.
    height += 52

    // Keep the usual short quote compact while providing a safe minimum when
    // user notes are present. The cap guarantees that table pagination always
    // retains usable space on an A4 page.
    let minimum: CGFloat = notes.isEmpty ? 170 : 260
    return min(max(ceil(height), minimum), 400)
}

private func estimatedSectionsHeight(
    _ sections: [PrintSection],
    sectionHeaderH: CGFloat,
    tableHeaderH: CGFloat,
    rowH: CGFloat,
    interSectionSpacing: CGFloat
) -> CGFloat {
    sections.enumerated().reduce(CGFloat.zero) { height, element in
        let (index, section) = element
        let spacing = index == 0 ? 0 : interSectionSpacing
        return height
            + spacing
            + sectionHeaderH
            + tableHeaderH
            + (CGFloat(section.lines.count) * rowH)
    }
}
// MARK: - Render all pages (section-aware pagination; totals on last page)
private func renderQuotePages(project: Project, budget: ProjectBudget) -> [PDFPage] {
    // 1) Build sections from the budget, preserving your section order
    let sections: [PrintSection] =
        BudgetSection.allCases.compactMap { sec in
            let ls = budget.lines.filter { $0.isActive && $0.section == sec }
            guard !ls.isEmpty else { return nil }
            let title = localizedSectionLabel(sec, language: budget.exportLanguage)
            return PrintSection(title: title, lines: ls)
        }

    // ...rest stays the same...

    // 2) Split safely across pages (reserves space for section + table headers)
    // Reserve enough space for: totals + (optional) user notes + legal notes + footer branding
    let headerHeight: CGFloat = 170
    let sectionHeaderHeight: CGFloat = 28
    let tableHeaderHeight: CGFloat = 23
    let rowHeight: CGFloat = 22
    let interSectionSpacing: CGFloat = 8
    let regularFooterHeight: CGFloat = 42
    let reservedLastPageFooterHeight = estimatedLastPageFooterHeight(for: budget)

    // First paginate table content using only the studio/page-number footer
    // shown on every page. We then check whether the final table page also has
    // room for totals and notes. If not, those blocks get a clean summary page
    // instead of forcing every table page to reserve the large final footer.
    var pagesOfSections = paginate(
        sections: sections,
        pageHeight: A4_SIZE.height,
        top: A4_MARGIN,
        bottom: A4_MARGIN,
        // These values mirror QuoteExportPageView, including its VStack
        // spacing and vertical padding. Conservative estimates are preferable
        // to clipping; a quote may gain a page, but no content is lost.
        headerHeight: headerHeight,
        footerHeight: regularFooterHeight,
        sectionHeaderH: sectionHeaderHeight,
        tableHeaderH: tableHeaderHeight,
        rowH: rowHeight,
        interSectionSpacing: interSectionSpacing
    )

    if pagesOfSections.isEmpty {
        pagesOfSections = [[]]
    } else if let lastSections = pagesOfSections.last {
        let lastTableHeight = estimatedSectionsHeight(
            lastSections,
            sectionHeaderH: sectionHeaderHeight,
            tableHeaderH: tableHeaderHeight,
            rowH: rowHeight,
            interSectionSpacing: interSectionSpacing
        )
        let availableForLastTable = A4_SIZE.height
            - (A4_MARGIN * 2)
            - headerHeight
            - reservedLastPageFooterHeight

        if lastTableHeight > availableForLastTable {
            pagesOfSections.append([])
        }
    }

    // 3) Render one NSHostingView per PDF page
    var pages: [PDFPage] = []
    let totalPages = pagesOfSections.count

    for (i, secPage) in pagesOfSections.enumerated() {
        let matchedClient = ClientsStore.shared.clients.first(where: {
            $0.name.trimmingCharacters(in: .whitespacesAndNewlines)
                .caseInsensitiveCompare(project.client.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
        })

        let view = QuoteExportPageView(
            project: project,
            budget: budget,
            pageIndex: i,
            totalPages: totalPages,
            sections: secPage,
            client: matchedClient
        )


        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: A4_SIZE)

        let data = pdfData(from: host)
        if let doc = PDFDocument(data: data), let page = doc.page(at: 0) {
            pages.append(page)
        }
    }
    return pages
}


// Each logical section you print (e.g. "SOUND MIXING")
struct PrintSection {
    var title: String
    var lines: [BudgetLine]
}


// A single page contains a list of sections, but a section may be split across pages.
// When split, we append " (cont.)" to the title on the continued chunk.
private func paginate(
    sections: [PrintSection],
    pageHeight: CGFloat = 842,      // A4 = 595x842pt at 72 dpi
    top: CGFloat = 72,              // top page margin
    bottom: CGFloat = 72,           // bottom page margin
    headerHeight: CGFloat = 140,    // your page header block area
    footerHeight: CGFloat = 72,     // totals/footer area
    sectionHeaderH: CGFloat = 20,   // "SOUND MIXING" label
    tableHeaderH: CGFloat = 16,     // "Item | Unit | Qty | Price | Total"
    rowH: CGFloat = 16,             // one table row height
    interSectionSpacing: CGFloat = 8
) -> [[PrintSection]] {

    let usable = max(
        sectionHeaderH + tableHeaderH + rowH,
        pageHeight - top - bottom - headerHeight - footerHeight
    )
    
    var pages: [[PrintSection]] = []
    var currentPage: [PrintSection] = []
    var remaining = usable

    func newPage() {
        if !currentPage.isEmpty { pages.append(currentPage) }
        currentPage = []
        remaining = usable
    }

    for s in sections {
        // how many rows fit after we print the section+table header?
        var i = 0
        var chunkTitle = s.title
        while i < s.lines.count {
            let headerCost = sectionHeaderH + tableHeaderH + (currentPage.isEmpty ? 0 : interSectionSpacing)
            // if headers don't fit, start a new page first
            if headerCost + rowH > remaining {
                newPage()
            }
            let roomForRows = max(0, Int(floor((remaining - headerCost) / rowH)))
            if roomForRows == 0 {
                newPage()
                continue
            }
            let end = min(i + roomForRows, s.lines.count)
            let slice = Array(s.lines[i..<end])
            currentPage.append(PrintSection(title: chunkTitle, lines: slice))

            // Update remaining height
            let consumed = headerCost + CGFloat(slice.count) * rowH
            remaining -= consumed

            i = end
            if i < s.lines.count {
                // We'll continue this section on the next page
                chunkTitle = s.title + " (cont.)"
                newPage()
            }
        }
    }

    if !currentPage.isEmpty { pages.append(currentPage) }
    return pages
}




// MARK: - Save or print via PDFKit
extension PDFExporter {
    static func presentSaveAndExport(
        budget: ProjectBudget,
        project: Project,
        filename: String? = nil
    ) throws {
        let pages = renderQuotePages(project: project, budget: budget)
        let doc = PDFDocument()
        for (i, page) in pages.enumerated() { doc.insert(page, at: i) }
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType.pdf]
        panel.nameFieldStringValue = filename ?? defaultQuoteFilename(project: project, budget: budget)
        if panel.runModal() == .OK, let url = panel.url {
            doc.write(to: url)
        }
    }
    
    static func print(budget: ProjectBudget, project: Project) {
        // Build the PDF from your existing render function
        let pages = renderQuotePages(project: project, budget: budget)
        let doc = PDFDocument()
        for (i, page) in pages.enumerated() { doc.insert(page, at: i) }

        // Write to a temporary file so Print service can use it
        guard let data = doc.dataRepresentation() else {
            NSSound.beep()
            Swift.print("Failed to create PDF data for printing.")
            return
        }

        // Clean filename (avoid slashes etc.)
        func clean(_ s: String) -> String {
            let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            return s.components(separatedBy: invalid).joined(separator: "_")
        }

        let fn = "Quote_\(clean(project.name))_\(clean(budget.quoteNumber ?? budget.title)).pdf"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(fn)

        do {
            try data.write(to: url, options: .atomic)
        } catch {
            NSSound.beep()
            Swift.print("Failed to write temp PDF:", error)
            return
        }

        // Prefer system Print service — avoids printer-session crash
        NSWorkspace.shared.open(url)
    }

}


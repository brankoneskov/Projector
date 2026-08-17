import SwiftUI
import AppKit

let A4_SIZE = CGSize(width: 595, height: 842)
let A4_MARGIN: CGFloat = 36
// Column widths (print-optimised; adjust as you like)
private let COL_ITEM:  CGFloat = 150    // Item name
private let COL_NOTES: CGFloat = 120    // NEW: Notes column
private let COL_UNIT:  CGFloat = 42
private let COL_QTY:   CGFloat = 44
private let COL_SELL:  CGFloat = 72
private let COL_AMNT:  CGFloat = 84
private struct GroupHeaderRow: View {
    let title: String
    var body: some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(0.18))
        )
    }
}

struct QuoteExportPageView: View {
    let project: Project
    let budget: ProjectBudget
    let pageIndex: Int
    let totalPages: Int
    let sections: [PrintSection]   // ← IMPORTANT
    let client: Client?
    private var resolvedVAT: String {
        let vat = client?.vatNumber.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return vat
    }

    var body: some View {
        VStack(spacing: 0) {
            
            // ======= LOGO ROW (top-left) =======
            HStack(spacing: 0) {
                LogoView(width: 120, height: 40)
                    .padding(.bottom, 20)
                Spacer(minLength: 0)
            }
            
                        // ========== ROW 1: Client (left) vs Project (right) ==========
            HStack(alignment: .top, spacing: 16) {
                // Client block (left) – gets all remaining width
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(localizedExportLabel("Client", language: budget.exportLanguage)): \(project.client)")
                        .font(.system(size: 10, weight: .semibold))

                    Text("\(localizedExportLabel("Address", language: budget.exportLanguage)): \(project.address ?? "—")")
                        .font(.system(size: 9))

                    Text("\(localizedExportLabel("Email", language: budget.exportLanguage)): \(project.email.isEmpty ? "—" : project.email)")
                        .font(.system(size: 9))

                    Text("\(localizedExportLabel("Phone", language: budget.exportLanguage)): \(project.phone.isEmpty ? "—" : project.phone)")
                        .font(.system(size: 9))
                    Text("\(localizedExportLabel("VAT Nº", language: budget.exportLanguage)): \(resolvedVAT.isEmpty ? "—" : resolvedVAT)")
                        .font(.system(size: 9))
                    // NEW: Attention line (only if filled)
                    if let att = budget.attentionTo, !att.isEmpty {
                        Text("\(localizedExportLabel("Attention", language: budget.exportLanguage)): \(att)")
                            .font(.system(size: 9))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)  // 👈 let this grow

                // Project/budget block (right) – fixed width
                VStack(alignment: .trailing, spacing: 3) {
                    Text("\(localizedExportLabel("Title", language: budget.exportLanguage)): \(project.name)")
                        .font(.system(size: 10, weight: .semibold))

                    Text("\(localizedExportLabel("Budget nº", language: budget.exportLanguage)): \(budget.quoteNumber ?? budget.title)")
                        .font(.system(size: 10))
                        .font(.system(size: 10))
                    Text(Date.now.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
                .frame(width: 220, alignment: .trailing)          // 👈 fixed width right column
            }
            .padding(.bottom, 40)

            Divider()
            
            // ========== LINES (grouped by section) ==========
            VStack(spacing: 8) {
                ForEach(sections, id: \.title) { sec in
                    if !sec.lines.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            // Section header with guaranteed background height
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(Color(nsColor: NSColor(calibratedWhite: 0.50, alpha: 1.0)))
                                    .frame(height: 18)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                                
                                Text(sec.title.uppercased())
                                    .font(.system(size: 10, weight: .semibold))
                                    .padding(.horizontal, 6)
                                    .frame(height: 18, alignment: .center)
                            }
                            .padding(.top, 6)
                            
                            // Column headers
                            HStack(spacing: 0) {
                                Text(localizedExportLabel("Item", language: budget.exportLanguage))
                                    .frame(width: COL_ITEM, alignment: .leading)

                                Text(localizedExportLabel("Notes", language: budget.exportLanguage))
                                    .frame(width: COL_NOTES, alignment: .leading)

                                Text(localizedExportLabel("Unit", language: budget.exportLanguage))
                                    .frame(width: COL_UNIT, alignment: .trailing)

                                Text(localizedExportLabel("Qty", language: budget.exportLanguage))
                                    .frame(width: COL_QTY, alignment: .trailing)

                                Text(localizedExportLabel("Price", language: budget.exportLanguage))
                                    .frame(width: COL_SELL, alignment: .trailing)

                                Text(localizedExportLabel("Total", language: budget.exportLanguage))
                                    .frame(width: COL_AMNT, alignment: .trailing)
                            }
                            .font(.system(size: 9, weight: .bold))
                            .padding(.vertical, 4)
                            .overlay(
                                Rectangle().frame(height: 1).foregroundColor(.secondary),
                                alignment: .bottom
                            )

                            
                            // Lines that FIT on THIS PAGE (already paginated)
                            ForEach(sec.lines) { line in
                                HStack(spacing: 0) {
                                    // Item name
                                    Text(localizedBudgetLineName(line, language: budget.exportLanguage))
                                        .font(.system(size: 9))
                                        .frame(width: COL_ITEM, alignment: .leading)

                                    // 🔹 NEW: Notes cell (between Item and Unit)
                                    Text(line.notes)
                                        .font(.system(size: 8))
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                        .truncationMode(.tail)
                                        .frame(width: COL_NOTES, alignment: .leading)

                                    // Unit — user-configured Translation dictionary link.
                                    Text(localizedBudgetLineUnit(line, language: budget.exportLanguage))
                                        .font(.system(size: 9))
                                        .frame(width: COL_UNIT, alignment: .trailing)

                                    // Qty
                                    Text(line.quantity, format: .number.precision(.fractionLength(2)))
                                        .font(.system(size: 9))
                                        .frame(width: COL_QTY, alignment: .trailing)

                                    // Price (unit sell)
                                    Text(line.rateSell, format: .number.precision(.fractionLength(2)))
                                        .font(.system(size: 9))
                                        .frame(width: COL_SELL, alignment: .trailing)

                                    // Total
                                    Text("€ " + String(format: "%.2f", line.amountSell))
                                        .font(.system(size: 9))
                                        .frame(width: COL_AMNT, alignment: .trailing)
                                }
                            }
                        }
                    }
                }
            }
            
            
            .padding(.vertical, 4)
            .compositingGroup()
            
            Spacer(minLength: 8)
            
            // ========== Last-page totals ONLY ==========
            if pageIndex == totalPages - 1 {
                Divider().padding(.vertical, 6)
                
                HStack {
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(localizedExportLabel("Subtotal", language: budget.exportLanguage)): € " +
                             String(format: "%.2f", budget.subtotalSell))

                        let discountLabel = localizedExportLabel("Discount", language: budget.exportLanguage)
                        Text(String(format: "\(discountLabel) (%.2f%%): € %.2f",
                                    budget.discountPercent,
                                    budget.discountValue))

                        Text("\(localizedExportLabel("Total", language: budget.exportLanguage)): € " +
                             String(format: "%.2f", budget.totalSell))

                            .bold()
                    }
                    .font(.system(size: 9))
                }
            }
            // ========== Notes (last page only) ==========
            if pageIndex == totalPages - 1 {
                let note = budget.generalNotes
                    .trimmingCharacters(in: .whitespacesAndNewlines)

                if !note.isEmpty {
                    Divider().padding(.vertical, 6)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizedExportLabel("Notes", language: budget.exportLanguage))
                            .font(.system(size: 9, weight: .semibold))

                        Text(note)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                           // .lineLimit(5) // ✅ allow for 5 lines
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)   // ✅ ADD THIS LINE
                }
            }


            // ========== Footer (page/branding) ==========
            Spacer()
            // ========== Export notes (LAST PAGE ONLY) ==========
            if pageIndex == totalPages - 1 {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(
                        localizedExportFooterNotes(language: budget.exportLanguage),
                        id: \.self
                    ) { line in
                        Text(line)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 8)
            }
            // Studio info footer — dynamic, no VAT, two-row safe
            let s = StudioInfoStore.shared.info
            let footerLine1Parts: [String] = [s.name, s.address].filter { !$0.isEmpty }
            let footerLine2Parts: [String] = [s.phone, s.email, s.website].filter { !$0.isEmpty }
            let footerLine1 = footerLine1Parts.joined(separator: " • ")
            let footerLine2 = footerLine2Parts.joined(separator: " • ")

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 1) {
                    if !footerLine1.isEmpty {
                        Text(footerLine1)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    if !footerLine2.isEmpty {
                        Text(footerLine2)
                            .font(.system(size: 8))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Text("\(localizedExportLabel("Page", language: budget.exportLanguage)) \(pageIndex + 1)/\(totalPages)")
                    .font(.system(size: 8))
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }
        .padding(A4_MARGIN)
        .frame(width: A4_SIZE.width, height: A4_SIZE.height)
        .background(Color.white)
    }
    
    struct LogoView: NSViewRepresentable {
        let width: CGFloat
        let height: CGFloat?      // pass nil to keep aspect ratio from image
        let resourceName: String = "logo"
        let resourceExt: String   = "png"

        func makeNSView(context: Context) -> NSView {
            let container = NSView()
            container.translatesAutoresizingMaskIntoConstraints = false

            let imageView = NSImageView()
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.imageScaling = .scaleProportionallyDown  // never upscale
            imageView.imageAlignment = .alignTopLeft
            imageView.isEditable = false
            imageView.wantsLayer = true
            imageView.canDrawSubviewsIntoLayer = true

            // Load image: custom logo in data folder takes priority over bundle
            var img: NSImage? = nil
            if let customURL = StudioInfoStore.customLogoURL,
               let customImg = NSImage(contentsOf: customURL) {
                img = customImg
                print("✅ logo loaded from data folder: \(customURL.lastPathComponent)")
            } else if let url = Bundle.main.url(forResource: resourceName, withExtension: resourceExt),
               let fileImg = NSImage(contentsOf: url) {
                img = fileImg
                print("✅ logo loaded from bundle")
            } else if let namedImg = NSImage(named: resourceName) {
                img = namedImg
                print("✅ logo loaded from asset catalog as \(resourceName)")
            } else {
                print("❌ logo not found — no custom logo and no bundle fallback")
            }
            imageView.image = img

            container.addSubview(imageView)

            // Size constraints for the container itself
            let targetHeight: CGFloat = {
                if let h = height { return h }
                guard let img = img, img.size.width > 0 else { return width * 0.45 }
                let ratio = img.size.height / img.size.width
                return width * ratio
            }()

            NSLayoutConstraint.activate([
                container.widthAnchor.constraint(equalToConstant: width),
                container.heightAnchor.constraint(equalToConstant: targetHeight),
                imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                imageView.topAnchor.constraint(equalTo: container.topAnchor),
                imageView.widthAnchor.constraint(equalTo: container.widthAnchor),
                imageView.heightAnchor.constraint(equalTo: container.heightAnchor),
            ])

            return container
        }

        func updateNSView(_ nsView: NSView, context: Context) { }
    }
}


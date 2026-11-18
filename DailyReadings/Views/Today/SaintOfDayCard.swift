//
//  SaintOfDayCard.swift
//  DailyReadings
//
//  Created for DailyReadings Catholic Daily Readings App.
//  iOS 17+ | Swift 6+
//

import SwiftUI

/// A contemplative card displaying the Saint of the Day.
///
/// Features a liturgical candle icon, feast title, biography with smooth "Read more" expansion,
/// and patronage badges.
public struct SaintOfDayCard: View {
    
    // MARK: - Properties
    
    public let saint: Saint
    public var liturgicalColor: LiturgicalColor = .green
    
    @State private var isExpanded: Bool = true
    
    // MARK: - Initialization
    
    public init(saint: Saint, liturgicalColor: LiturgicalColor = .green) {
        self.saint = saint
        self.liturgicalColor = liturgicalColor
    }
    
    // MARK: - Body
    
    public var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.medium) {
            // Header: Icon + Name + Title
            headerSection

            // Life facts: years, birthplace, order, canonization
            if !lifeFacts.isEmpty {
                lifeFactsSection
            }

            // Biography Section (with Truncation / Expansion)
            biographySection

            if let quote = saint.quote {
                quoteSection(quote)
            }
            
            // Patronages (if available)
            if let patronages = saint.patronages, !patronages.isEmpty {
                patronagesSection(patronages: patronages)
            }
        }
        .cardStyle(
            backgroundColor: AppTheme.Colors.cardBackground,
            cornerRadius: AppTheme.CornerRadius.large,
            padding: AppTheme.Spacing.medium
        )
    }
    
    // MARK: - Header
    
    private var headerSection: some View {
        HStack(alignment: .top, spacing: AppTheme.Spacing.medium) {
            // Sacred Candle Icon
            ZStack {
                Circle()
                    .fill(liturgicalColor.swiftUIColor.opacity(0.12))
                    .frame(width: 44, height: 44)
                
                Image(systemName: "flame.fill")
                    .font(.scaled(size: 20))
                    .foregroundStyle(AppTheme.Colors.solemnGold)
            }
            
            VStack(alignment: .leading, spacing: 3) {
                Text(headerBadgeTitle)
                    .readingTitleStyle(tintColor: liturgicalColor.swiftUIColor)
                
                Text(saint.name)
                    .font(.scaled(size: 19, weight: .bold, design: .serif))
                    .foregroundStyle(Color.primary)
                
                if let title = saint.title, !title.isEmpty {
                    Text(title)
                        .font(.scaled(size: 14, weight: .medium, design: .serif).italic())
                        .foregroundStyle(Color.secondary)
                }
            }
            
            Spacer()
        }
    }
    
    // MARK: - Dynamic Badge Title
    
    private var headerBadgeTitle: String {
        let nameLower = saint.name.lowercased()
        let titleLower = (saint.title ?? "").lowercased()
        
        // Respect the classic "SAINT OF THE DAY" specifically for All Saints
        if nameLower.contains("all saints") {
            return "SAINT OF THE DAY"
        } else if nameLower.contains("solemnity") || titleLower.contains("solemnity") {
            return "SOLEMNITY OF THE DAY"
        } else if nameLower.contains("feast") || titleLower.contains("feast") || nameLower.contains("dedication") || nameLower.contains("presentation") || nameLower.contains("transfiguration") || nameLower.contains("exaltation") || nameLower.contains("baptism") {
            return "FEAST OF THE DAY"
        } else if nameLower.contains("commemoration") || nameLower.contains("ash wednesday") || nameLower.contains("good friday") || nameLower.contains("holy saturday") || nameLower.contains("holy thursday") {
            return "COMMEMORATION OF THE DAY"
        } else {
            return "SAINT OF THE DAY"
        }
    }
    
    // MARK: - Biography Section
    
    private var biographySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(saint.biography.trimmingCharacters(in: .whitespacesAndNewlines))
                .saintBioStyle()
                .lineLimit(isExpanded ? nil : 4)
                .fixedSize(horizontal: false, vertical: isExpanded)
                .animation(.easeInOut(duration: 0.25), value: isExpanded)
            
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 4) {
                    Text(isExpanded ? "Show Less" : "Read More")
                        .font(.scaled(size: 13, weight: .semibold))
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.scaled(size: 11, weight: .semibold))
                }
                .foregroundStyle(liturgicalColor.swiftUIColor)
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            if !saint.sources.isEmpty {
                sourceCredit
            }
        }
    }

    /// Credit for the description: Wikipedia text is CC BY-SA 4.0, which asks for attribution.
    private var sourceCredit: some View {
        var credit = AttributedString("From Wikipedia: ")
        for (index, source) in saint.sources.enumerated() {
            var link = AttributedString(source.title)
            link.link = URL(string: source.url)
            link.underlineStyle = .single
            credit += link
            if index < saint.sources.count - 1 { credit += AttributedString(" · ") }
        }
        credit += AttributedString(" (CC BY-SA 4.0)")
        return Text(credit)
            .font(.scaled(size: 11))
            .foregroundStyle(Color.secondary)
            .tint(Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
    
    // MARK: - Life Facts

    private var lifeFacts: [(label: String, value: String)] {
        var facts: [(String, String)] = []
        if let lived = saint.livedLine { facts.append(("LIVED", lived)) }
        if let place = saint.birthplace { facts.append(("BORN IN", place)) }
        if let order = saint.religiousOrder { facts.append(("ORDER", order)) }
        if let canonized = saint.canonized { facts.append(("CANONIZED", canonized)) }
        if let day = saint.martyrologyDay { facts.append(("MARTYROLOGY", day)) }
        return facts
    }

    private var lifeFactsSection: some View {
        Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 4) {
            ForEach(lifeFacts, id: \.label) { fact in
                GridRow {
                    Text(fact.label)
                        .font(.scaled(size: 11, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.8))
                        .tracking(1.0)
                    Text(fact.value)
                        .font(.scaled(size: 14, weight: .medium, design: .serif))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: - Quote

    private func quoteSection(_ quote: SaintQuote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\u{201C}\(quote.text)\u{201D}")
                .font(.scaled(size: 16, design: .serif).italic())
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Text("\u{2014} \(quote.source)")
                .font(.scaled(size: 12, weight: .medium))
                .foregroundStyle(Color.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.leading, 13)
        // The gold rule follows the quote's height.
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(AppTheme.Colors.solemnGold.opacity(0.7))
                .frame(width: 3)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Patronages
    
    private func patronagesSection(patronages: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("PATRON OF")
                .font(.scaled(size: 11, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.8))
                .tracking(1.0)
            
            FlowLayout(spacing: 6) {
                ForEach(patronages, id: \.self) { patronage in
                    Text(patronage)
                        .font(.scaled(size: 12, weight: .medium))
                        .foregroundStyle(Color.primary.opacity(0.85))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(Capsule())
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Flow Layout Helper for Patronage Tags

fileprivate struct FlowLayout: Layout {
    var spacing: CGFloat = 6
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var height: CGFloat = 0
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > width && currentX > 0 {
                currentX = 0
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height = currentY + rowHeight
        return CGSize(width: width, height: height)
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var currentX = bounds.minX
        var currentY = bounds.minY
        var rowHeight: CGFloat = 0
        
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > bounds.maxX && currentX > bounds.minX {
                currentX = bounds.minX
                currentY += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: currentX, y: currentY), proposal: .unspecified)
            currentX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

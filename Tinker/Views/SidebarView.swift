//
//  SidebarView.swift
//  Tinker
//

import SwiftUI

struct SidebarView: View {
    let sections: [SidebarSection]
    @Binding var selection: SidebarDestination?

    var body: some View {
        List(selection: $selection) {
            Section {
                SidebarLabel(title: "Dashboard", symbol: "rectangle.3.group.fill", color: .blue)
                    .tag(SidebarDestination.dashboard)
                SidebarLabel(title: "All Settings", symbol: "list.bullet", color: .gray)
                    .tag(SidebarDestination.allSettings)
            }
            ForEach(sections) { section in
                Section(section.title) {
                    ForEach(section.categories) { category in
                        SidebarLabel(
                            title: Text(category.title),
                            symbol: category.symbol,
                            color: Color(catalogName: category.color)
                        )
                        .tag(SidebarDestination.category(category.id))
                    }
                }
            }
            Section("Tinker") {
                SidebarLabel(title: "Settings", symbol: "gearshape.fill", color: .gray)
                    .tag(SidebarDestination.appSettings)
            }
        }
    }
}

/// A name beside its symbol on a colored tile, like System Settings.
struct SidebarLabel: View {
    let title: Text
    let symbol: String
    let color: Color

    init(title: Text, symbol: String, color: Color) {
        self.title = title
        self.symbol = symbol
        self.color = color
    }

    init(title: LocalizedStringKey, symbol: String, color: Color) {
        self.init(title: Text(title), symbol: symbol, color: color)
    }

    var body: some View {
        Label {
            title
        } icon: {
            SymbolTile(symbol: symbol, color: color, size: 22)
        }
    }
}

struct SymbolTile: View {
    let symbol: String
    let color: Color
    let size: CGFloat

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: .rect(cornerRadius: size * 0.27))
    }
}

extension Color {
    /// Maps the color names used in Catalog.json to system colors.
    init(catalogName: String) {
        self = switch catalogName {
        case "blue": .blue
        case "brown": .brown
        case "cyan": .cyan
        case "green": .green
        case "indigo": .indigo
        case "orange": .orange
        case "pink": .pink
        case "purple": .purple
        case "red": .red
        case "teal": .teal
        default: .gray
        }
    }
}

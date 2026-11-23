import SwiftUI

/// Every other kind of business: pick an area, then a kind.
struct KindsSheet: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    let pick: (Kind) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(L("%lld סוגים, %lld מקומות. בוחרים תחום, ואז סוג.", store.kindCount, store.near.count))
                        .font(.darb(.subheadline, .medium)).foregroundStyle(.secondary)
                    // a ruled index, like the one on the home screen: the area, and how many places it has
                    LazyVStack(spacing: 0) {
                        ForEach(store.sectorCounts(), id: \.sector.slug) { item in
                            NavigationLink(value: item.sector) { SectorTile(sector: item.sector, count: item.count) }
                                .buttonStyle(RowStyle())
                            Color.ink.opacity(0.12).frame(height: 1)
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
            }
            .background(Color.canvas)
            .navigationTitle(L("כל השאר"))
            .navigationBarTitleDisplayMode(.large)
            .navigationDestination(for: Sector.self) { s in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(store.kindCounts(sector: s.slug), id: \.kind.slug) { item in
                            Button { pick(item.kind) } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: s.symbol).font(.symbol(.footnote)).foregroundStyle(Color.onColor.opacity(0.75))
                                        .frame(width: 36, height: 36)
                                        .background(s.color, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
                                    Text(item.kind.title).font(.darb(.body, .bold))
                                    Spacer()
                                    Text(verbatim: "\(item.count)").font(.figure(.body)).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.forward").font(.symbol(.caption)).foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 12)
                                .frame(minHeight: 58)
                                .background(Color.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                            }
                            .buttonStyle(PressStyle(scale: 0.98))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    .padding(.horizontal, 16).padding(.bottom, 24)
                }
                .background(Color.canvas)
                .navigationTitle(s.title)
                .navigationBarTitleDisplayMode(.large)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button { dismiss() } label: { Text(L("סגירה")).font(.darb(.body, .semibold)) } } }
        }
        .tint(Color.ink)
        .foregroundStyle(Color.ink)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(30)
        .onAppear { Perf.shown("kinds") }
    }
}

/// A sector as a row of the index: its name, its symbol, and how many places it has, as a figure.
struct SectorTile: View {
    let sector: Sector
    let count: Int
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: sector.symbol).font(.symbol(.body)).opacity(0.55).frame(width: 26)
            Text(sector.title).font(.darb(size: 18, .bold, relativeTo: .body)).lineLimit(2).multilineTextAlignment(.leading)
            Spacer(minLength: 8)
            Text(verbatim: "\(count)").font(.darb(size: 24, .black, relativeTo: .title2)).monospacedDigit()
            Image(systemName: "chevron.forward").font(.symbol(.caption)).opacity(0.4)
        }
        .padding(.horizontal, 4)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("%@, %lld מקומות", sector.title, count))
    }
}

import SwiftUI

struct CablePickerSheet: View {
    let cables: [Cable]
    @Binding var selectedId: String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filtered: [Cable] {
        guard !query.isEmpty else { return cables }
        return cables.filter {
            $0.name.localizedCaseInsensitiveContains(query)
                || $0.crossSection.localizedCaseInsensitiveContains(query)
                || $0.use.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { cable in
                Button {
                    selectedId = cable.id
                    dismiss()
                } label: {
                    CableRow(cable: cable, selected: cable.id == selectedId)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if filtered.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "Zoek kabel")
            .navigationTitle("Kies een kabel")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Sluit") { dismiss() } }
            }
        }
    }
}

private struct CableRow: View {
    let cable: Cable
    let selected: Bool

    var body: some View {
        HStack(spacing: Theme.spacing) {
            CablePhoto(cable: cable)
            VStack(alignment: .leading, spacing: 2) {
                Text(cable.name).font(.headline)
                Text("\(cable.crossSection) · \(cable.use)").font(.subheadline).foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    Text("\(Format.euro(cable.pricePerMeter)) per meter").font(.subheadline)
                    Text("· \(salesText)").font(.subheadline).foregroundStyle(.secondary)
                }
                Text(cable.stock).font(.caption).foregroundStyle(.secondary)
                if cable.isSample { SampleBadge() }
            }
            Spacer()
            if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 4)
    }

    private var salesText: String {
        switch cable.sales {
        case .perMeter: "op lengte"
        case let .fixedLengths(lengths): "rol " + lengths.sorted().map { Format.orderLength($0) }.joined(separator: ", ")
        }
    }
}

struct CablePhoto: View {
    let cable: Cable

    var body: some View {
        Group {
            if let image = bundledImage {
                Image(uiImage: image).resizable().scaledToFit().background(.white)
            } else if let url = cable.imageUrl {
                AsyncImage(url: url) { image in image.resizable().scaledToFit() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: 52, height: 52)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// Photos fetched by scripts/scrape_elektramat.py ship in the bundle as <sku>.jpg,
    /// so the picker works without a network connection.
    private var bundledImage: UIImage? {
        guard let path = Bundle.main.path(forResource: cable.sku, ofType: "jpg") else { return nil }
        return UIImage(contentsOfFile: path)
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(.quaternary)
            .overlay(Image(systemName: "cable.connector").foregroundStyle(.secondary))
    }
}

struct SampleBadge: View {
    var body: some View {
        Text("Voorbeelddata")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.sampleBadge.opacity(0.85), in: Capsule())
            .foregroundStyle(.white)
    }
}

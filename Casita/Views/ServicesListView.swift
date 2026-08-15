import SwiftUI

struct ServicesListView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openURL) private var openURL
    @State private var query = ""
    @State private var selectedCategory: ServiceCategory?
    @State private var showingForm = false
    @State private var showingHousehold = false
    @State private var showingSettings = false

    private var filteredServices: [Service] {
        model.services.filter { service in
            if let selectedCategory, service.category != selectedCategory { return false }
            let trimmed = query.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return true }
            return service.name.localizedCaseInsensitiveContains(trimmed)
                || service.category.label.localizedCaseInsensitiveContains(trimmed)
                || service.phone.localizedCaseInsensitiveContains(trimmed)
                || service.notes.localizedCaseInsensitiveContains(trimmed)
        }
    }

    /// Only categories that actually have services, for the filter chips.
    private var presentCategories: [ServiceCategory] {
        var seen = Set<ServiceCategory>()
        var result: [ServiceCategory] = []
        for category in ServiceCategory.allCases where model.services.contains(where: { $0.category == category }) {
            if seen.insert(category).inserted { result.append(category) }
        }
        return result
    }

    var body: some View {
        Group {
            if model.services.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .background(Theme.background)
        // The nav bar caps item height (~36pt of glass), which crops the
        // symbols. Own header instead, so the glass circles are ours to size.
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .overlay(alignment: .bottom) {
            addServiceIsland
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $showingForm) { ServiceFormView(mode: .add) }
        .sheet(isPresented: $showingHousehold) { HouseholdView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .refreshable { await model.refreshQuietly() }
    }

    /// Household name plus the two round glass buttons, sized by us rather
    /// than by the navigation bar.
    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                glassCircleButton(
                    "person.2.fill", label: "Household and members"
                ) { showingHousehold = true }
                Spacer()
                glassCircleButton(
                    "gearshape.fill", label: "Settings"
                ) { showingSettings = true }
            }
            Text(model.household?.name ?? "Casita")
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.background)
    }

    @ViewBuilder
    private func glassCircleButton(
        _ symbol: String, label: LocalizedStringKey, action: @escaping () -> Void
    ) -> some View {
        // 20pt glyph inside a 54pt circle keeps even the wide person.2.fill
        // clear of the edge.
        let icon = Image(systemName: symbol)
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(Theme.terracotta)
            .frame(width: 54, height: 54)

        if #available(iOS 26.0, *) {
            Button(action: action) { icon }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(Text(label))
        } else {
            Button(action: action) {
                icon.background(Circle().fill(Theme.card))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(label))
        }
    }

    private var listContent: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 10)

            if presentCategories.count > 1 {
                categoryChips
                    .padding(.bottom, 6)
            }

            List {
                if model.isDemo {
                    DemoBanner()
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(filteredServices) { service in
                    NavigationLink(value: service) {
                        ServiceRow(service: service)
                    }
                    .listRowBackground(Theme.card)
                }
                if filteredServices.isEmpty {
                    Text("Nothing matches your search")
                        .font(.body)
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .listRowBackground(Color.clear)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .contentMargins(.bottom, 92, for: .scrollContent)
        }
    }

    /// Floating island CTA: Liquid Glass on iOS 26, solid terracotta before.
    private var addServiceIsland: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button {
                    showingForm = true
                } label: {
                    islandLabel
                }
                .buttonStyle(.glassProminent)
                .buttonBorderShape(.capsule)
                .tint(Theme.terracottaFill)
            } else {
                Button {
                    showingForm = true
                } label: {
                    islandLabel
                        .foregroundStyle(.white)
                        .background(Theme.terracottaFill, in: Capsule())
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var islandLabel: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus")
                .font(.headline)
                .accessibilityHidden(true)
            Text("Add service")
                .font(.system(.headline, design: .rounded))
        }
        .padding(.horizontal, 22)
        .frame(minHeight: 52)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(Theme.inkSecondary)
            TextField("Search by name or trade", text: $query)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.inkSecondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Clear search"))
            }
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 50)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.ink.opacity(0.08))
        )
    }

    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(label: Text("All"), symbol: nil, isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(presentCategories) { category in
                    chip(
                        label: Text(category.label),
                        symbol: category.symbol,
                        isSelected: selectedCategory == category
                    ) {
                        selectedCategory = selectedCategory == category ? nil : category
                    }
                }
            }
            .padding(.horizontal, 20)
        }
    }

    private func chip(label: Text, symbol: String?, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.footnote.weight(.semibold))
                }
                label
                    .font(.system(.subheadline, design: .rounded).weight(.medium))
            }
            .foregroundStyle(isSelected ? .white : Theme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(isSelected ? Theme.terracottaFill : Theme.card)
            )
            .overlay(
                Capsule().strokeBorder(Theme.ink.opacity(isSelected ? 0 : 0.12))
            )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if model.isDemo {
                DemoBanner()
                    .padding(.horizontal, 20)
            }
            Spacer()
            Image(systemName: "wrench.and.screwdriver.fill")
                .font(.system(size: 52))
                .foregroundStyle(Theme.terracotta.opacity(0.5))
            Text("No services yet")
                .font(.system(.title2, design: .rounded).weight(.bold))
                .foregroundStyle(Theme.ink)
            Text("Add the people who help around the house â€” plumber, electrician, gardener â€” with their phone numbers.")
                .font(.system(.body, design: .rounded))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ServiceRow: View {
    @Environment(\.openURL) private var openURL
    let service: Service

    var body: some View {
        HStack(spacing: 14) {
            CategoryBadge(category: service.category)
            VStack(alignment: .leading, spacing: 3) {
                Text(service.name)
                    .font(.system(.headline, design: .rounded))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(2)
                Text(service.category.label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer(minLength: 8)
            if !service.dialDigits.isEmpty {
                Button {
                    if let url = URL(string: "tel:\(service.dialDigits)") {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "phone.fill")
                        .font(.title3)
                        .foregroundStyle(.white)
                        .frame(width: 46, height: 46)
                        .background(Circle().fill(Theme.callGreen))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("Call \(service.name)"))
            }
        }
        .padding(.vertical, 8)
    }
}

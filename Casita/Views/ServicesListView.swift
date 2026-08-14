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
        .navigationTitle(model.household?.name ?? "Casita")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    showingHousehold = true
                } label: {
                    Image(systemName: "person.2.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Household and members"))
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showingSettings = true
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.body.weight(.semibold))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(Text("Settings"))
            }
        }
        .safeAreaInset(edge: .bottom) {
            BigButton(title: "Add service", systemImage: "plus") {
                showingForm = true
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .padding(.top, 4)
            .background(.ultraThinMaterial)
        }
        .sheet(isPresented: $showingForm) { ServiceFormView(mode: .add) }
        .sheet(isPresented: $showingHousehold) { HouseholdView() }
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .refreshable { await model.refreshQuietly() }
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
        }
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
            Text("Add the people who help around the house — plumber, electrician, gardener — with their phone numbers.")
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

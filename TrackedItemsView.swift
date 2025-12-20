//
//  TrackedItemsView.swift
//  YourProject
//

import SwiftUI
import SwiftData

struct TrackedItemsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \TrackedItem.startDate, order: .reverse) private var trackedItems: [TrackedItem]

    @State private var showAddItemSheet: Bool = false
    @State private var itemToEdit: TrackedItem? = nil

    @State private var searchText: String = ""
    @State private var sortOption: SortOption = .name

    enum SortOption: String, CaseIterable, Identifiable {
        case name = "Name"
        case type = "Type"
        case dateAdded = "Date Added"
        var id: String { self.rawValue }
    }

    @State private var showDeletionConfirmation: Bool = false
    @State private var itemToDelete: TrackedItem? = nil

    var body: some View {
        NavigationView {
            ZStack {
                // Tap outside to dismiss keyboard
                Color.clear
                    .onTapGesture {
                        hideKeyboard()
                    }

                VStack(spacing: 0) {
                    // Search
                    SearchBar(text: $searchText)
                        .padding(.horizontal)

                    // Sort Picker
                    Picker("Sort By", selection: $sortOption) {
                        ForEach(SortOption.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .padding(.horizontal)

                    // Main list
                    List {
                        ForEach(filteredAndSortedItems) { item in
                            trackedItemRow(for: item)
                        }
                        .onDelete(perform: handleDelete)
                    }
                    .listStyle(PlainListStyle())
                    .scrollDismissesKeyboard(.interactively)
                }
            }
            .navigationTitle("Tracked Items")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showAddItemSheet.toggle() }) {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItemSheet) {
                AddTrackedItemView()
            }
            .sheet(item: $itemToEdit) { item in
                EditTrackedItemView(trackedItem: item)
            }
            .alert(isPresented: $showDeletionConfirmation) {
                Alert(
                    title: Text("Delete Item"),
                    message: Text("Are you sure you want to delete \"\(itemToDelete?.name ?? "")\"?"),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteItem()
                    },
                    secondaryButton: .cancel()
                )
            }
        }
    }

    // Row content
    private func trackedItemRow(for item: TrackedItem) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text(item.name).font(.headline)
                Text(item.type.rawValue)
                    .font(.subheadline)
                    .foregroundColor(.gray)

                if let brand = item.brand, !brand.isEmpty {
                    Text("Brand: \(brand)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Text("Started on: \(item.startDate, formatter: dateFormatter)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Toggle(isOn: Binding(
                get: { item.isActive },
                set: { newValue in
                    item.isActive = newValue
                    saveContext()
                }
            )) {
                Text(item.isActive ? "Active" : "Inactive")
                    .foregroundColor(item.isActive ? .green : .red)
            }
            .labelsHidden()
        }
        .contentShape(Rectangle())
        .onTapGesture {
            itemToEdit = item
        }
    }

    // Delete
    private func handleDelete(at offsets: IndexSet) {
        if let index = offsets.first {
            itemToDelete = filteredAndSortedItems[index]
            showDeletionConfirmation = true
        }
    }

    private func deleteItem() {
        if let item = itemToDelete {
            modelContext.delete(item)
            saveContext()
        }
    }

    // Filter & Sort
    private var filteredAndSortedItems: [TrackedItem] {
        var items = trackedItems
        if !searchText.isEmpty {
            items = items.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        switch sortOption {
        case .name:
            items.sort { $0.name.lowercased() < $1.name.lowercased() }
        case .type:
            items.sort { $0.type.rawValue.lowercased() < $1.type.rawValue.lowercased() }
        case .dateAdded:
            items.sort { $0.startDate > $1.startDate }
        }
        return items
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            print("Failed to save context: \(error)")
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    private var dateFormatter: DateFormatter {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }
}

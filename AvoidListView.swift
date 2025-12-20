import SwiftUI
import SwiftData

struct AvoidListView: View {
    @Environment(\.modelContext) private var modelContext

    // Query for recommended items
    @Query(filter: #Predicate { $0.isRecommended == true }, sort: \AvoidedItem.name)
    private var recommendedItems: [AvoidedItem]

    // Query for user-chosen items
    @Query(filter: #Predicate { $0.isRecommended == false }, sort: \AvoidedItem.name)
    private var userItems: [AvoidedItem]

    @State private var showAddAvoidItemSheet = false

    var body: some View {
        NavigationView {
            List {
                // --- Section A: Recommended ---
                Section(header: Text("Recommended to Avoid")) {
                    if recommendedItems.isEmpty {
                        Text("No recommended items right now.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(recommendedItems) { item in
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(item.name)
                                        .font(.headline)
                                    Text(item.type.rawValue)
                                        .font(.subheadline)
                                        .foregroundColor(.gray)
                                    if let reason = item.reason, !reason.isEmpty {
                                        Text("Reason: \(reason)")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                // "Confirm" moves it to user-chosen list
                                Button("Confirm") {
                                    confirmItem(item)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                        .onDelete { offsets in
                            deleteItems(offsets, from: recommendedItems)
                        }
                    }
                }

                // --- Section B: My Avoided Items ---
                Section(header: Text("My Avoided Items")) {
                    if userItems.isEmpty {
                        Text("No avoided items yet.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(userItems) { item in
                            VStack(alignment: .leading) {
                                Text(item.name)
                                    .font(.headline)
                                Text(item.type.rawValue)
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                if let reason = item.reason, !reason.isEmpty {
                                    Text("Reason: \(reason)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .onDelete { offsets in
                            deleteItems(offsets, from: userItems)
                        }
                    }
                }
            }
            .navigationTitle("Avoid List")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showAddAvoidItemSheet.toggle()
                    } label: {
                        Label("Add Item", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddAvoidItemSheet) {
                AddAvoidedItemView()  // newly added items go to recommended by default
            }
        }
        .onAppear {
            debugItems()
        }
    }

    // Debug: Print userItems + manual fetch
    private func debugItems() {
        print(">>> OnAppear: userItems.count =", userItems.count)
        for item in userItems {
            print(">>> userItem ->", item.name, "isRecommended:", item.isRecommended)
        }
        do {
            let descriptor = FetchDescriptor<AvoidedItem>()
            let allItems = try modelContext.fetch(descriptor)
            print(">>> Manual fetch: all AvoidedItem count =", allItems.count)
            for item in allItems {
                print(">>> Fetched item ->", item.name, "isRecommended:", item.isRecommended)
            }
        } catch {
            print(">>> Manual fetch error:", error)
        }
    }

    // Confirm recommended item => isRecommended = false
    private func confirmItem(_ item: AvoidedItem) {
        item.isRecommended = false
        do {
            try modelContext.save()
            print("Item confirmed: \(item.name)")
        } catch {
            print("Failed to confirm item: \(error)")
        }
    }

    // Delete from recommended or user list
    private func deleteItems(_ offsets: IndexSet, from source: [AvoidedItem]) {
        for index in offsets {
            let item = source[index]
            modelContext.delete(item)
        }
        do {
            try modelContext.save()
            print("Items deleted.")
        } catch {
            print("Failed to delete items: \(error)")
        }
    }
}

//
//  RemindersView.swift
//  Food IntolerancesI am choosing options
//
//  Created by Leo on 2/8/25.
//

import SwiftUI

struct Reminder: Identifiable {
    let id = UUID()
    var title: String
    var date: Date
    var isCompleted: Bool = false
}

struct RemindersView: View {
    @State private var reminders: [Reminder] = [
        Reminder(title: "Take Supplement A", date: Date().addingTimeInterval(3600)),
        Reminder(title: "Log Symptom", date: Date().addingTimeInterval(7200)),
        Reminder(title: "Drink Water", date: Date().addingTimeInterval(10800))
    ]
    
    @State private var newReminderTitle = ""
    @State private var newReminderDate = Date()
    @State private var showAddReminderSheet = false

    var body: some View {
        NavigationView {
            List {
                ForEach(reminders) { reminder in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(reminder.title)
                                .font(.headline)
                            Text(reminder.date, style: .time)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                        if reminder.isCompleted {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                        } else {
                            Button(action: {
                                markReminderAsCompleted(reminder)
                            }) {
                                Image(systemName: "circle")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onDelete(perform: deleteReminder)
            }
            .navigationTitle("Reminders")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showAddReminderSheet.toggle()
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                }
            }
            .sheet(isPresented: $showAddReminderSheet) {
                addReminderSheet
            }
        }
    }

    private func markReminderAsCompleted(_ reminder: Reminder) {
        if let index = reminders.firstIndex(where: { $0.id == reminder.id }) {
            reminders[index].isCompleted = true
        }
    }

    private func deleteReminder(at offsets: IndexSet) {
        reminders.remove(atOffsets: offsets)
    }

    private var addReminderSheet: some View {
        NavigationView {
            Form {
                Section(header: Text("Reminder Info")) {
                    TextField("Reminder Title", text: $newReminderTitle)
                    DatePicker("Date", selection: $newReminderDate, displayedComponents: [.date, .hourAndMinute])
                }

                Button("Save Reminder") {
                    let newReminder = Reminder(title: newReminderTitle, date: newReminderDate)
                    reminders.append(newReminder)
                    showAddReminderSheet = false
                    newReminderTitle = ""
                    newReminderDate = Date()
                }
                .disabled(newReminderTitle.isEmpty)
            }
            .navigationTitle("Add Reminder")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        showAddReminderSheet = false
                    }
                }
            }
        }
    }
}

struct RemindersView_Previews: PreviewProvider {
    static var previews: some View {
        RemindersView()
    }
}

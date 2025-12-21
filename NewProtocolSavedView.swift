
// Create a new file named NewProtocolSavedView.swift
import SwiftUI
import SwiftData

struct NewProtocolSavedView: View {
    let `protocol`: TherapyProtocol
    let onActivate: () -> Void
    let onDismiss: () -> Void
    
    @State private var enableReminders = false
    @State private var reminderTime = Date()
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Protocol Saved Successfully!")
                    .font(.title2)
                    .bold()
                
                Text(`protocol`.title)
                    .font(.headline)
                
                Divider()
                
                Text("What would you like to do next?")
                    .font(.subheadline)
                
                VStack(alignment: .leading, spacing: 15) {
                    Toggle("Enable Reminders", isOn: $enableReminders)
                    
                    if enableReminders {
                        DatePicker("Reminder Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(10)
                
                Button(action: {
                    if enableReminders {
                        `protocol`.enableReminder = true
                        `protocol`.reminderTime = reminderTime
                    }
                    
                    onActivate()
                    onDismiss()
                }) {
                    Text("Activate Protocol Now")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Button(action: onDismiss) {
                    Text("Save to Wishlist for Later")
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.secondary.opacity(0.2))
                        .foregroundColor(.primary)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                
                Text("You can always activate this protocol later from your protocol list")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
            }
            .padding()
            .navigationTitle("Protocol Saved")
            .navigationBarItems(trailing: Button("Close") {
                onDismiss()
            })
        }
    }
}

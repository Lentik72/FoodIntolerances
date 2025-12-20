// Create a new file: MoreView.swift
import SwiftUI
import SwiftData

struct MoreView: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var showNotificationSettings = false
    @State private var showAvoidList = false
    @State private var showProtocolTags = false
    
    var body: some View {
        NavigationView {
            List {
                Section(header: Text("Settings")) {
                    Button {
                        showNotificationSettings = true
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }
                    
                    Button {
                        showAvoidList = true
                    } label: {
                        Label("Avoid List", systemImage: "hand.raised.fill")
                    }
                    
                    Button {
                        showProtocolTags = true
                    } label: {
                        Label("Protocol Tags", systemImage: "tag.fill")
                    }
                }
                
                Section(header: Text("Tools")) {
                    NavigationLink(destination: CorrelationAnalysisView()) {
                        Label("Correlation Analysis", systemImage: "arrow.left.and.right")
                    }
                    
                    NavigationLink(destination: ProtocolListView()) {
                            Label("Therapy Protocols", systemImage: "heart.text.square.fill")
                        }
                    
                    NavigationLink(destination: ProtocolEffectivenessTracker()) {
                        Label("Protocol Effectiveness", systemImage: "chart.bar.doc.horizontal")
                    }
                    
                    NavigationLink(destination: GoalTrackingView()) {
                        Label("Goal Tracking", systemImage: "target")
                    }
                }
                
                Section(header: Text("Data Management")) {
                    Button {
                        // Import/Export data functionality
                    } label: {
                        Label("Import/Export Data", systemImage: "arrow.up.arrow.down")
                    }
                }
            }
            .navigationTitle("More Options")
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsView()
        }
        .sheet(isPresented: $showAvoidList) {
            AvoidListView()
        }
        .sheet(isPresented: $showProtocolTags) {
            ProtocolTagsView()
        }
    }
}

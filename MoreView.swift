// Create a new file: MoreView.swift
import SwiftUI
import SwiftData

struct MoreView: View {
    @EnvironmentObject var tabManager: TabManager
    @State private var showNotificationSettings = false
    @State private var showAvoidList = false
    @State private var showProtocolTags = false
    @State private var showFoodQuery = false
    @State private var showAIDebugInspector = false

    var body: some View {
        NavigationStack {
            List {
                // AI Assistant Section
                Section(header: Text("AI Assistant")) {
                    Button {
                        showFoodQuery = true
                    } label: {
                        Label("Can I Eat This?", systemImage: "questionmark.circle.fill")
                    }

                    NavigationLink(destination: AIInsightsView()) {
                        Label("AI Insights & Patterns", systemImage: "brain.head.profile")
                    }

                    NavigationLink(destination: UserProfileView()) {
                        Label("My Profile", systemImage: "person.crop.circle.fill")
                    }

                    NavigationLink(destination: AllergyManagementView()) {
                        Label("Allergies & Sensitivities", systemImage: "allergens")
                    }

                    NavigationLink(destination: HealthDashboardView()) {
                        Label("Health & Screenings", systemImage: "heart.text.square")
                    }
                }

                Section(header: Text("Settings")) {
                    Button {
                        showNotificationSettings = true
                    } label: {
                        Label("Notification Settings", systemImage: "bell.badge")
                    }

                    NavigationLink(destination: AISettingsView()) {
                        Label("AI Settings", systemImage: "cpu")
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

                #if DEBUG
                Section(header: Text("Developer")) {
                    Button {
                        showAIDebugInspector = true
                    } label: {
                        Label("AI Debug Inspector", systemImage: "ant.fill")
                    }
                }
                #endif
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
        .sheet(isPresented: $showFoodQuery) {
            FoodQueryView()
        }
        .sheet(isPresented: $showAIDebugInspector) {
            AIDebugInspectorView()
        }
    }
}

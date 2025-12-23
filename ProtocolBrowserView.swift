import SwiftUI
import WebKit
import SafariServices

struct ProtocolBrowserView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var searchQuery = ""
    @State private var selectedURL: URL?
    @State private var webNavigationHistory: [URL] = []
    @State private var showWebView = false
    @State private var detectedProtocol: ProtocolExtraction?
    @State private var showExtractedProtocol = false
    @State private var isLoading = false
    @State private var showExtractButton = false
    @State private var showSafariView = false
    @State private var bookmarks: [SavedBookmark] = []
    @StateObject private var fetchService = ProtocolFetchService()
    @AppStorage("hasShownWebBrowserWarning") private var hasShownWarning = false
    @State private var showInitialWarning = false
    
    // Popular health/remedy websites
    // Update the popularSites array in ProtocolBrowserView.swift

    let popularSites = [
        ("Mayo Clinic", "https://www.mayoclinic.org/diseases-conditions"),
        ("WebMD", "https://www.webmd.com/a-to-z-guides/health-topics"),
        ("NIH", "https://www.nih.gov/health-information"),
        ("Healthline", "https://www.healthline.com/health/remedies"),
        ("Medical News Today", "https://www.medicalnewstoday.com/categories/complementary_medicine"),
        ("Herb.com", "https://www.herb.com"),
        ("Traditional Medicinals", "https://www.traditionalmedicinals.com/pages/plant-power"),
        ("Wellness Mama", "https://wellnessmama.com/recipes/"),
        ("Mountain Rose Herbs", "https://blog.mountainroseherbs.com/category/recipes"),
        ("Natural Remedies", "https://naturalremedieshome.com/"),
        ("Herbal Academy", "https://theherbalacademy.com/blog/"),
        ("The Spruce Eats Recipes", "https://www.thespruceeats.com/recipes-4162086")
    ]
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                
                // Disclaimer Banner
                VStack(alignment: .leading, spacing: 4) {
                    Text("Health Information Disclaimer")
                        .font(.headline)
                        .foregroundColor(.orange)
                    
                    Text("Content found on external websites is not verified for medical accuracy. Always consult a healthcare professional before trying any treatment.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.secondarySystemBackground))
                .cornerRadius(8)
                .padding(.horizontal)
                
                // Search Bar with improved UX
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.gray)
                    
                    TextField("Search for protocols or enter URL", text: $searchQuery)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit {
                            performSearch()
                        }
                    
                    if !searchQuery.isEmpty {
                        Button(action: {
                            searchQuery = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.gray)
                        }
                    }
                    
                    Button(action: performSearch) {
                        Text("Go")
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                }
                .padding()
                
                if isLoading {
                    ZStack {
                        Color.black.opacity(0.3)
                            .edgesIgnoringSafeArea(.all)
                        
                        VStack {
                            ProgressView()
                                .scaleEffect(1.5)
                                .padding()
                            Text("Loading...")
                                .foregroundColor(.white)
                                .padding()
                        }
                        .background(Color(.systemBackground))
                        .cornerRadius(10)
                        .shadow(radius: 10)
                    }
                    .zIndex(1) // Ensure it's above the WebView
                }
                
                // Popular sites or search results
                if !showWebView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Popular Health Resources")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(popularSites, id: \.0) { site in
                                Button(action: {
                                    navigateToURL(URL(string: site.1)!)
                                }) {
                                    HStack {
                                        Text(site.0)
                                            .foregroundColor(.primary)
                                        Spacer()
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(.blue)
                                    }
                                    .padding()
                                    .background(Color(.secondarySystemBackground))
                                    .cornerRadius(10)
                                    .padding(.horizontal)
                                }
                            }
                            
                            if !bookmarks.isEmpty {
                                Text("Your Bookmarks")
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.top)
                                
                                ForEach(bookmarks) { bookmark in
                                    Button(action: {
                                        if let url = URL(string: bookmark.url) {
                                            navigateToURL(url)
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "bookmark.fill")
                                                .foregroundColor(.blue)
                                            Text(bookmark.title)
                                                .foregroundColor(.primary)
                                            Spacer()
                                            Button(action: {
                                                deleteBookmark(bookmark)
                                            }) {
                                                Image(systemName: "trash")
                                                    .foregroundColor(.red)
                                            }
                                        }
                                        .padding()
                                        .background(Color(.secondarySystemBackground))
                                        .cornerRadius(10)
                                        .padding(.horizontal)
                                    }
                                }
                            }
                        }
                    }
                } else {
                    // Web View
                    // Web View
                    WebViewContainer(url: $selectedURL,
                                    history: $webNavigationHistory,
                                    detectedProtocol: $detectedProtocol,
                                    isLoading: $isLoading,
                                    showExtractButton: $showExtractButton)  
                    
                    // Bottom toolbar for web navigation
                    HStack(spacing: 20) {
                        Button(action: goBack) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(webNavigationHistory.isEmpty ? .gray : .blue)
                                .imageScale(.large)
                        }
                        .disabled(webNavigationHistory.isEmpty)
                        
                        Button(action: {
                            // Add to bookmarks
                            addCurrentPageToBookmarks()
                        }) {
                            Image(systemName: "bookmark")
                                .foregroundColor(.blue)
                                .imageScale(.large)
                        }
                        
                        Button(action: {
                            // Open in Safari
                            if selectedURL != nil {
                                showSafariView = true
                            }
                        }) {
                            Image(systemName: "safari")
                                .foregroundColor(.blue)
                                .imageScale(.large)
                        }
                        
                        Spacer()
                        
                        Button(action: {
                            showExtractedProtocol = true
                        }) {
                            Label("Extract Protocol", systemImage: detectedProtocol != nil ? "square.and.arrow.down.fill" : "square.and.arrow.down")
                                .foregroundColor(.white)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    detectedProtocol != nil ?
                                        Color.green.opacity(showExtractButton ? 1.0 : 0.7) :
                                        Color.gray.opacity(0.7)
                                )
                                .cornerRadius(8)
                                .animation(.spring(), value: showExtractButton)
                        }
                        .disabled(detectedProtocol == nil)
                        .scaleEffect(showExtractButton ? 1.1 : 1.0)
                        .animation(.spring(), value: showExtractButton)
                        
                        Button(action: {
                            showWebView = false
                        }) {
                            Image(systemName: "house")
                                .foregroundColor(.blue)
                                .imageScale(.large)
                        }
                    }
                    .padding()
                    .background(Color(.systemBackground))
                }
            }
            .sheet(isPresented: $showExtractedProtocol) {
                if let extracted = detectedProtocol {
                    ProtocolExtractionView(extraction: extracted) { therapyProtocol in
                        // Save the extracted protocol to the database
                        modelContext.insert(therapyProtocol)
                        do {
                            try modelContext.save()
                            // Show success notification
                            detectedProtocol = nil
                            // Navigate back home
                            showWebView = false
                        } catch {
                            Logger.error(error, message: "Error saving protocol", category: .data)
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showSafariView) {
                if let url = selectedURL {
                    SafariView(url: url)
                }
            }
            .navigationTitle("Protocol Browser")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                loadBookmarks()
                
                if !hasShownWarning {
                    showInitialWarning = true
                }
            }
        }
        .sheet(isPresented: $showInitialWarning) {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 50))
                    .foregroundColor(.orange)
                
                Text("Important Health Information Disclaimer")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 10) {
                    Text("• Protocols found on the web may not be medically accurate or safe.")
                    Text("• Always consult a healthcare professional before trying any treatment.")
                    Text("• Imported protocols are marked as 'Unverified' until you review them.")
                    Text("• You use this information at your own risk.")
                }
                .padding()
                
                Button("I Understand") {
                    hasShownWarning = true
                    showInitialWarning = false
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding()
            .frame(maxWidth: 400)
        }
    }
    
    private func performSearch() {
        guard !searchQuery.isEmpty else { return }
        
        var searchURLString = searchQuery
        
        // Check if it's a URL
        if !searchURLString.contains("://") && !searchURLString.contains(".") {
            // It's not a URL, convert to a Google search
            searchURLString = "https://www.google.com/search?q=\(searchQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")+natural+protocol+remedy+treatment"
        } else if !searchURLString.hasPrefix("http") {
            // Add https:// if missing
            searchURLString = "https://" + searchURLString
        }
        
        if let url = URL(string: searchURLString) {
            navigateToURL(url)
        }
    }
    
    private func navigateToURL(_ url: URL) {
        // Only update if it's a new URL or we're not already showing the web view
        if selectedURL != url || !showWebView {
            selectedURL = url
            isLoading = true
            showWebView = true
        }
    }
    
    private func goBack() {
        guard !webNavigationHistory.isEmpty else { return }
        webNavigationHistory.removeLast()
        
        if let previousURL = webNavigationHistory.last {
            selectedURL = previousURL
        } else {
            showWebView = false
        }
    }
    
    private func addCurrentPageToBookmarks() {
        guard let url = selectedURL else { return }
        
        // Get page title using JavaScript
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        
        webView.evaluateJavaScript("document.title") { (result, error) in
            if let title = result as? String {
                let newBookmark = SavedBookmark(title: title, url: url.absoluteString)
                
                // Check if bookmark already exists
                if !self.bookmarks.contains(where: { $0.url == url.absoluteString }) {
                    self.bookmarks.append(newBookmark)
                    self.saveBookmarks()
                }
            }
        }
    }
    
    private func deleteBookmark(_ bookmark: SavedBookmark) {
        bookmarks.removeAll(where: { $0.id == bookmark.id })
        saveBookmarks()
    }
    
    private func saveBookmarks() {
        if let encodedData = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(encodedData, forKey: "protocolBookmarks")
        }
    }
    
    private func loadBookmarks() {
        if let savedBookmarks = UserDefaults.standard.data(forKey: "protocolBookmarks"),
           let decodedBookmarks = try? JSONDecoder().decode([SavedBookmark].self, from: savedBookmarks) {
            self.bookmarks = decodedBookmarks
        }
    }
}

// Model for bookmarks
struct SavedBookmark: Identifiable, Codable {
    var id = UUID()
    let title: String
    let url: String
    
    enum CodingKeys: CodingKey {
        case id, title, url
    }
}

// Safari View
struct SafariView: UIViewControllerRepresentable {
    let url: URL
    
    func makeUIViewController(context: Context) -> SFSafariViewController {
        return SFSafariViewController(url: url)
    }
    
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}

// Web View Container
struct WebViewContainer: UIViewRepresentable {
    @Binding var url: URL?
    @Binding var history: [URL]
    @Binding var detectedProtocol: ProtocolExtraction?
    @Binding var isLoading: Bool
    @Binding var showExtractButton: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        
        let configuration = WKWebViewConfiguration()
        configuration.defaultWebpagePreferences = preferences
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        
        // Add user-agent to avoid being blocked by some websites
        webView.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1"
        
        return webView
    }
    
    func updateUIView(_ webView: WKWebView, context: Context) {
        if let url = url, webView.url != url {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebViewContainer
        private var currentNavigation: WKNavigation?
        private var timeoutTask: Task<Void, Never>?
        
        init(_ parent: WebViewContainer) {
            self.parent = parent
        }
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            currentNavigation = navigation
            DispatchQueue.main.async {
                self.parent.isLoading = true
            }
            
            // Set a timeout for loading
            timeoutTask?.cancel()
            timeoutTask = Task { [weak self] in
                try? await Task.sleep(nanoseconds: 10_000_000_000) // 10 seconds
                if !Task.isCancelled {
                    DispatchQueue.main.async {
                        guard let self = self else { return }
                        self.parent.isLoading = false
                        Logger.warning("Navigation timed out after 10 seconds", category: .network)
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Make sure we only update for the current navigation
            if navigation === currentNavigation || currentNavigation == nil {
                // Cancel the timeout task
                timeoutTask?.cancel()
                
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                    if let url = webView.url {
                        // Only add to history if it's a new URL
                        if self.parent.history.last != url {
                            self.parent.history.append(url)
                        }
                    }
                }
                
                // Detect protocol content after a short delay to ensure page is loaded
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    self.detectProtocol(in: webView)
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            if navigation === currentNavigation || currentNavigation == nil {
                // Cancel the timeout task
                timeoutTask?.cancel()
                
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            if navigation === currentNavigation || currentNavigation == nil {
                // Cancel the timeout task
                timeoutTask?.cancel()
                
                DispatchQueue.main.async {
                    self.parent.isLoading = false
                    
                    // Handle specific error cases
                    if let nsError = error as NSError? {
                        // Don't show error for canceled requests
                        if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                            return
                        }

                        // Display error message for other cases
                        Logger.error("Web navigation error: \(error.localizedDescription)", category: .network)
                    }
                }
            }
        }
        
        // Update the detectProtocol

        private func detectProtocol(in webView: WKWebView) {
            // Improved JavaScript for more reliable extraction
            let javascript = """
            function extractProtocol() {
                // Enhanced title detection with better scoring
                const potentialTitleElements = Array.from(document.querySelectorAll('h1, h2, h3, h4, .title, .header-title, [class*="title"], [class*="header"], [class*="recipe-name"], [class*="recipe-title"]'));
                const protocolKeywords = ['protocol', 'remedy', 'treatment', 'recipe', 'cure', 'formula', 'regimen', 'therapy', 'healing', 'method', 'procedure', 'solution'];
                
                // Find the best title match with improved scoring
                let title = '';
                let bestScore = 0;
                
                potentialTitleElements.forEach(el => {
                    const text = el.innerText.toLowerCase();
                    let score = 0;
                    
                    protocolKeywords.forEach(keyword => {
                        if (text.includes(keyword)) score += 2;
                    });
                    
                    // Prefer shorter, more focused titles
                    if (el.tagName === 'H1') score += 4;
                    if (el.tagName === 'H2') score += 3;
                    if (el.tagName === 'H3') score += 2;
                    if (el.tagName === 'H4') score += 1;
                    if (text.length < 100 && text.length > 5) score += 2;
                    
                    if (score > bestScore) {
                        bestScore = score;
                        title = el.innerText.trim();
                    }
                });
                
                // If no title found, use page title
                if (!title || bestScore < 2) {
                    title = document.title.split('|')[0].split('-')[0].trim();
                }
                
                // Improved category detection
                let category = '';
                const categoryKeywords = {
                    'digestive': 'Digestive Health',
                    'gut': 'Digestive Health',
                    'stomach': 'Digestive Health',
                    'respiratory': 'Respiratory Health',
                    'breath': 'Respiratory Health',
                    'lung': 'Respiratory Health',
                    'immune': 'Immune Support',
                    'skin': 'Skin Health',
                    'mental': 'Mental Wellness',
                    'anxiety': 'Mental Wellness',
                    'sleep': 'Sleep Improvement',
                    'insomnia': 'Sleep Improvement',
                    'energy': 'Energy & Vitality',
                    'pain': 'Pain Management',
                    'inflammation': 'Anti-Inflammatory',
                    'hormonal': 'Hormonal Health',
                    'detox': 'Detox & Cleansing',
                    'headache': 'Pain Management',
                    'joint': 'Joint Health',
                    'muscle': 'Physical Recovery'
                };
                
                // Enhanced content analysis for better category matching
                const bodyText = document.body.innerText.toLowerCase();
                let highestCount = 0;
                
                for (const [keyword, categoryName] of Object.entries(categoryKeywords)) {
                    const regex = new RegExp('\\\\b' + keyword + '\\\\b', 'gi');
                    const count = (bodyText.match(regex) || []).length;
                    
                    if (count > highestCount) {
                        highestCount = count;
                        category = categoryName;
                    }
                }
                
                if (!category) {
                    category = 'General Health';
                }
                
                // More robust instructions extraction
                let instructions = '';
                
                // Look for structured content first - recipe steps, instructions, directions
                const instructionContainers = [
                    ...Array.from(document.querySelectorAll('[class*="instruction"], [class*="direction"], [class*="step"], [class*="method"], [class*="procedure"]')),
                    ...Array.from(document.querySelectorAll('ol, ul')).filter(el => {
                        const prev = el.previousElementSibling;
                        if (!prev) return false;
                        const text = prev.innerText.toLowerCase();
                        return text.includes('instruction') || text.includes('direction') || text.includes('step') || 
                               text.includes('method') || text.includes('procedure') || text.includes('how to');
                    })
                ];
                
                if (instructionContainers.length > 0) {
                    // Sort by content length to find the most detailed instructions
                    instructionContainers.sort((a, b) => b.innerText.length - a.innerText.length);
                    instructions = instructionContainers[0].innerText.trim();
                }
                
                // If still no instructions, look for paragraphs with action verbs
                if (!instructions || instructions.length < 50) {
                    const actionParagraphs = Array.from(document.querySelectorAll('p')).filter(p => {
                        const text = p.innerText.toLowerCase();
                        return (text.includes('take') || text.includes('use') || text.includes('mix') || 
                                text.includes('apply') || text.includes('prepare') || text.includes('combine')) &&
                                text.length > 50;
                    });
                    
                    if (actionParagraphs.length > 0) {
                        instructions = actionParagraphs.map(p => p.innerText).join('\\n\\n');
                    }
                }
                
                // Extract ingredients if available - important for protocols/recipes
                let ingredients = [];
                const ingredientContainers = [
                    ...Array.from(document.querySelectorAll('[class*="ingredient"]')),
                    ...Array.from(document.querySelectorAll('ul')).filter(el => {
                        const prev = el.previousElementSibling;
                        if (!prev) return false;
                        const text = prev.innerText.toLowerCase();
                        return text.includes('ingredient') || text.includes('what you need') || 
                               text.includes('you will need') || text.includes('items needed');
                    })
                ];
                
                if (ingredientContainers.length > 0) {
                    // Get the most detailed ingredient list
                    ingredientContainers.sort((a, b) => b.innerText.length - a.innerText.length);
                    const ingredientText = ingredientContainers[0].innerText;
                    
                    // Parse items, assuming each ingredient is on a new line or is a list item
                    ingredients = ingredientText.split('\\n')
                        .map(line => line.trim())
                        .filter(line => line.length > 0 && line.length < 100);  // Reasonable length for an ingredient
                }
                
                // Better dosage extraction with pattern recognition
                let dosage = '';
                const dosagePatterns = [
                    /take\\s+([\\d\\w\\s\\.]+)\\s+(daily|twice|times a day|every|per day)/i,
                    /([\\d\\w\\s\\.]+)\\s+(times a day|daily|twice daily|every day)/i,
                    /dose:\\s*([^\\n\\.]+)/i,
                    /dosage:\\s*([^\\n\\.]+)/i,
                    /serving\\s+(size|amount):\\s*([^\\n\\.]+)/i
                ];
                
                const allText = document.body.innerText;
                for (const pattern of dosagePatterns) {
                    const match = allText.match(pattern);
                    if (match) {
                        dosage = match[0];
                        break;
                    }
                }
                
                // Better duration extraction
                let duration = '';
                const durationPatterns = [
                    /for\\s+([\\d\\w\\s\\.]+)\\s+(weeks?|days?|months?)/i,
                    /continue\\s+for\\s+([\\d\\w\\s\\.]+)/i,
                    /duration:\\s*([^\\n\\.]+)/i,
                    /period\\s+of\\s+([\\d\\w\\s\\.]+)/i,
                    /([\\d]+)\\s*(weeks?|days?|months?)\\s+of\\s+(treatment|therapy|use)/i
                ];
                
                for (const pattern of durationPatterns) {
                    const match = allText.match(pattern);
                    if (match) {
                        duration = match[0];
                        break;
                    }
                }
                
                // Better symptom extraction
                let symptoms = [];
                const commonSymptoms = [
                    'headache', 'migraine', 'pain', 'fatigue', 'anxiety', 'depression', 
                    'stress', 'insomnia', 'cough', 'cold', 'flu', 'fever', 'nausea', 
                    'digestion', 'inflammation', 'joint pain', 'muscle pain', 'back pain',
                    'immune', 'sinus', 'congestion', 'allergies', 'skin', 'acne', 'eczema',
                    'bloating', 'gas', 'constipation', 'diarrhea'
                ];
                
                // Find sections mentioning conditions or symptoms
                const conditionSections = Array.from(document.querySelectorAll('h2, h3, h4, h5, p'))
                    .filter(el => {
                        const text = el.innerText.toLowerCase();
                        return text.includes('for ') || text.includes('treats ') || text.includes('helps with ') || 
                               text.includes('relief from ') || text.includes('symptoms') || text.includes('conditions');
                    });
                
                // Extract symptoms from these sections with context
                if (conditionSections.length > 0) {
                    const relevantText = conditionSections.map(s => s.innerText).join(' ');
                    for (const symptom of commonSymptoms) {
                        const regex = new RegExp('(for|treats|helps with|relief from)\\\\s+([^\\\\.,]+' + symptom + '[^\\\\.,]+)', 'i');
                        const match = relevantText.match(regex);
                        if (match && match[2]) {
                            symptoms.push(match[2].trim());
                        } else if (relevantText.includes(symptom)) {
                            symptoms.push(symptom.charAt(0).toUpperCase() + symptom.slice(1));
                        }
                    }
                }
                
                // If no symptoms found in specific sections, scan the whole document
                if (symptoms.length === 0) {
                    for (const symptom of commonSymptoms) {
                        if (bodyText.includes(symptom)) {
                            symptoms.push(symptom.charAt(0).toUpperCase() + symptom.slice(1));
                        }
                    }
                }
                
                // Ensure unique symptoms
                symptoms = [...new Set(symptoms)];
                
                return {
                    title: title,
                    category: category,
                    instructions: instructions,
                    ingredients: ingredients,
                    dosage: dosage,
                    duration: duration,
                    symptoms: symptoms,
                    sourceURL: window.location.href
                };
            }
            
            extractProtocol();
            """
            
            webView.evaluateJavaScript(javascript) { [weak self] result, error in
                guard let self = self else { return }

                if let error = error {
                    Logger.error(error, message: "JavaScript error", category: .network)
                    return
                }
                
                // Process the extraction result
                if let dict = result as? [String: Any] {
                    // Extract values with improved validation
                    let title = (dict["title"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let category = (dict["category"] as? String ?? "General Health").trimmingCharacters(in: .whitespacesAndNewlines)
                    let instructions = (dict["instructions"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let ingredients = dict["ingredients"] as? [String] ?? []
                    let dosage = (dict["dosage"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let duration = (dict["duration"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    let symptoms = dict["symptoms"] as? [String] ?? []
                    let sourceURL = (dict["sourceURL"] as? String ?? webView.url?.absoluteString ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                    
                    // Only process if we have meaningful content
                    if !title.isEmpty && (!instructions.isEmpty || ingredients.count > 0) {
                        DispatchQueue.main.async {
                            // Format the extracted data
                            let formattedInstructions: String
                            if !ingredients.isEmpty {
                                formattedInstructions = "INGREDIENTS:\n" + ingredients.joined(separator: "\n") + "\n\nDIRECTIONS:\n" + instructions
                            } else {
                                formattedInstructions = instructions
                            }
                            
                            var extraction = ProtocolExtraction(
                                title: title,
                                instructions: formattedInstructions,
                                dosage: dosage,
                                duration: duration,
                                sourceURL: sourceURL
                            )
                            
                            extraction.category = category
                            extraction.symptoms = symptoms
                            if self.parent.detectedProtocol != nil {
                                self.parent.showExtractButton = true
                                
                                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                                    
                                }
                            }
                            
                            self.parent.detectedProtocol = extraction
                            
                            // Show visual feedback that protocol was detected
                            // This can be done by adding a small notification or changing button color
                        }
                    }
                }
            }
        }
    }
}

// Protocol Extraction Model
struct ProtocolExtraction {
    var title: String
    var instructions: String
    var dosage: String
    var duration: String
    var sourceURL: String
    var category: String = "General Health"
    var symptoms: [String] = []
}
// Protocol Extraction View

struct ProtocolExtractionView: View {
    let extraction: ProtocolExtraction
    let onSave: (TherapyProtocol) -> Void
    
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var instructions: String
    @State private var category: String
    @State private var frequency: String = "Daily"
    @State private var timeOfDay: String = "As directed"
    @State private var duration: String
    @State private var symptoms: [String]
    @State private var notes: String
    @State private var isWishlist: Bool = false
    @State private var validationError: String?
    @State private var showValidationError = false
    
    init(extraction: ProtocolExtraction, onSave: @escaping (TherapyProtocol) -> Void) {
        self.extraction = extraction
        self.onSave = onSave
        
        // Initialize state with extracted info
        _title = State(initialValue: extraction.title)
        _instructions = State(initialValue: extraction.instructions)
        _category = State(initialValue: extraction.category)
        _duration = State(initialValue: extraction.duration.isEmpty ? "As needed" : extraction.duration)
        _symptoms = State(initialValue: extraction.symptoms)
        _notes = State(initialValue: "Source: \(extraction.sourceURL)")
        
        // Extract frequency from dosage if possible
        if extraction.dosage.lowercased().contains("daily") {
            _frequency = State(initialValue: "Daily")
        } else if extraction.dosage.lowercased().contains("weekly") {
            _frequency = State(initialValue: "Weekly")
        } else if extraction.dosage.lowercased().contains("as needed") {
            _frequency = State(initialValue: "As Needed")
        }
        
        // Extract time of day if possible
        if extraction.dosage.lowercased().contains("morning") {
            _timeOfDay = State(initialValue: "Morning")
        } else if extraction.dosage.lowercased().contains("evening") {
            _timeOfDay = State(initialValue: "Evening")
        } else if extraction.dosage.lowercased().contains("night") {
            _timeOfDay = State(initialValue: "Night")
        }
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Protocol Details")) {
                    TextField("Title", text: $title)
                    
                    Picker("Category", selection: $category) {
                        ForEach(ProtocolCategory.defaultCategories, id: \.id) { category in
                            Text(category.name).tag(category.name)
                        }
                        Text("Other").tag("Other")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Instructions")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $instructions)
                            .frame(minHeight: 100)
                    }
                }
                
                Section(header: Text("Treatment Plan")) {
                    Picker("Frequency", selection: $frequency) {
                        Text("Daily").tag("Daily")
                        Text("Multiple Times a Day").tag("Multiple Times a Day")
                        Text("Weekly").tag("Weekly")
                        Text("As Needed").tag("As Needed")
                    }
                    
                    Picker("Time of Day", selection: $timeOfDay) {
                        Text("Morning").tag("Morning")
                        Text("Afternoon").tag("Afternoon")
                        Text("Evening").tag("Evening")
                        Text("Night").tag("Night")
                        Text("As directed").tag("As directed")
                    }
                    
                    VStack(alignment: .leading) {
                        Text("Duration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $duration)
                            .frame(minHeight: 60)
                    }
                }
                
                Section(header: Text("Symptoms & Notes")) {
                    // Editable symptoms tags
                    VStack(alignment: .leading) {
                        Text("Symptoms (tap to remove)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        FlowLayout(spacing: 8) {
                            ForEach(symptoms, id: \.self) { symptom in
                                Button(action: {
                                    symptoms.removeAll { $0 == symptom }
                                }) {
                                    Text(symptom)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .foregroundColor(.blue)
                                        .cornerRadius(8)
                                }
                            }
                            
                            Button(action: {
                                // Add new symptom
                                let newSymptom = "New Symptom"
                                if !symptoms.contains(newSymptom) {
                                    symptoms.append(newSymptom)
                                }
                            }) {
                                Text("+ Add")
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.green.opacity(0.2))
                                    .foregroundColor(.green)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    
                    Toggle("Add to Wishlist", isOn: $isWishlist)
                    
                    VStack(alignment: .leading) {
                        Text("Notes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        TextEditor(text: $notes)
                            .frame(minHeight: 60)
                    }
                }
                
                Section(header: Text("Source")) {
                    Text(extraction.sourceURL)
                        .font(.caption)
                        .foregroundColor(.blue)
                }
                
                Section(header: Text("Health Disclaimer").foregroundColor(.orange)) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("This protocol was extracted from the web and has not been medically verified.")
                            .font(.subheadline)
                            .foregroundColor(.orange)
                            
                        Text("By saving this protocol, you acknowledge that:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            
                        VStack(alignment: .leading, spacing: 4) {
                            Text("• The information may not be accurate or complete")
                            Text("• You will consult a healthcare professional before use")
                            Text("• You accept responsibility for using this information")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 4)
                }
                Section {
                    Button("Save Protocol") {
                        saveProtocol()
                    }
                }
            }
            .navigationTitle("Edit Protocol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func validateProtocol() -> Bool {
        // Title validation
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationError = "Protocol title cannot be empty"
            showValidationError = true
            return false
        }
        
        // Instructions validation
        if instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            validationError = "Instructions cannot be empty"
            showValidationError = true
            return false
        }
        
        // Duration validation - ensure it has some value
        if duration.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            duration = "As needed"
        }
        
        // Symptoms validation - ensure there's at least one
        if symptoms.isEmpty {
            validationError = "Please add at least one targeted symptom"
            showValidationError = true
            return false
        }
        
        return true
    }
    
    private func saveProtocol() {
        if !validateProtocol() {
            return
        }
        
        // Create proper symptoms array - ensure it's encoded correctly
        let symptomsList = symptoms.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        
        // Create therapy protocol with proper encoding
        let newProtocol = TherapyProtocol(
            title: title,
            category: category,
            instructions: instructions,
            frequency: frequency,
            timeOfDay: timeOfDay,
            duration: duration,
            symptoms: symptomsList,
            startDate: Date(),
            endDate: nil,
            notes: notes + "\n\nDISCLAIMER: This protocol was imported from the web and has not been medically verified. Consult a healthcare professional before use.",
            isWishlist: isWishlist,
            isActive: false,
            dateAdded: Date(),
            tags: ["Imported", "Web Source - Unverified", "Requires Verification"]
        )
        
        // Double-check symptoms data before saving
        if newProtocol.symptoms == nil || newProtocol.symptoms?.isEmpty == true {
            Logger.warning("Symptoms array is empty after initialization", category: .data)
            // Use a different approach to set symptoms
            if let protocolToModify = newProtocol as? TherapyProtocol {
                do {
                    let symptomsData = try JSONEncoder().encode(symptomsList)
                    protocolToModify.symptomsData = symptomsData
                } catch {
                    Logger.error(error, message: "Error manually encoding symptoms", category: .data)
                }
            }
        }
        
        // Save the protocol
        onSave(newProtocol)
        dismiss()
    }
}

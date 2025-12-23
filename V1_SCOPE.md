# Food Intolerances v1.0 Scope

**Last Updated:** December 23, 2024
**Status:** Pre-TestFlight

---

## v1.0 INCLUDES

### Core Features
- [x] Symptom logging with severity, body location, notes
- [x] Food/drink logging with meal association
- [x] Supplement/medication tracking
- [x] Therapy protocol management (create, edit, follow)
- [x] Ongoing symptom tracking with check-ins
- [x] Avoid list management
- [x] Medicine cabinet inventory

### AI Assistant
- [x] On-device pattern recognition
- [x] Memory learning from user logs
- [x] Memory decay (stale memories lose confidence)
- [x] Cooldown system (avoid repetitive suggestions)
- [x] Pause/resume learning
- [x] Reset memories
- [x] Optional Cloud AI (OpenAI/Anthropic) for enhanced insights
- [x] Privacy controls (notes opt-in, PII redaction)
- [x] Confidence-based suggestions
- [x] "What worked before" recommendations
- [x] Trigger correlation detection

### Environmental Factors
- [x] Weather integration (temperature, humidity, pressure)
- [x] Moon phase tracking
- [x] Seasonal awareness
- [x] Pollen alerts (when available)

### Data & Privacy
- [x] All data stored on-device (SwiftData)
- [x] Optional iCloud sync
- [x] Privacy-mode notifications (generic text on lock screen)
- [x] No analytics or tracking
- [x] Cloud AI requests use ephemeral sessions

### Notifications
- [x] Protocol reminders
- [x] Symptom check-in reminders
- [x] Low supply alerts
- [x] Daily summary (optional)
- [x] Proactive weather alerts

### UI/UX
- [x] Dashboard with insights
- [x] Trends analysis with charts
- [x] Quick symptom logger
- [x] Body map selection
- [x] Onboarding flow
- [x] AI settings with granular control

---

## v1.0 DOES NOT INCLUDE

### Deferred to v1.1+
- [ ] **Doctor PDF Export** - Generate shareable health summary
- [ ] **Predictive Forecasting** - "You might have a flare tomorrow"
- [ ] **Medication Interaction Warnings** - Drug-drug or drug-food interactions
- [ ] **Automated Scheduling** - AI-suggested check-in times
- [ ] **HealthKit Integration** - Import/export health data
- [ ] **Apple Watch App** - Companion watchOS app
- [ ] **Widgets** - Home screen widgets
- [ ] **Siri Shortcuts** - Voice commands integration

### Explicitly Excluded (Safety)
- [ ] **Diagnosis Language** - No "you have X condition"
- [ ] **Treatment Recommendations** - No "take X medication"
- [ ] **Dosage Suggestions** - No specific amounts
- [ ] **Medical Advice** - Always defers to healthcare providers

---

## Existing Code Status

### Included in v1 (Already Implemented)
| Feature | File | Status |
|---------|------|--------|
| Voice Input | `VoiceInputView.swift` | Implemented - available as optional input method |
| Trigger Prediction | `SymptomPredictionService.swift` | Implemented - finds correlations, NOT future prediction |
| Protocol Effectiveness | `ProtocolEffectivenessTracker.swift` | Implemented |
| Correlation Analysis | `CorrelationAnalysisView.swift` | Implemented |

### NOT in v1 (Planned but not built)
| Feature | Status |
|---------|--------|
| Doctor PDF Export | Not implemented |
| HealthKit sync | Not implemented |
| Widgets | Not implemented |

---

## App Store Guidelines Compliance

### Language Rules
- **DO:** "Track patterns", "Log symptoms", "Personal observations"
- **DON'T:** "Diagnose", "Treat", "Cure", "Medical advice"

### Required Disclaimers
- "This app is for personal tracking only"
- "Not intended to diagnose, treat, or cure any condition"
- "Always consult a healthcare provider"

### Privacy
- Clear explanation of on-device storage
- Cloud AI is opt-in only
- No data sold or shared

---

## Release Criteria

Before TestFlight:
- [ ] Full UX walkthrough completed
- [ ] All critical paths tested
- [ ] No crashes on fresh install
- [ ] Onboarding works end-to-end
- [ ] AI responses are helpful, not annoying
- [ ] Notifications respect privacy setting

Before App Store:
- [ ] Privacy Policy URL configured
- [ ] Support URL configured
- [ ] App Store description reviewed (no medical claims)
- [ ] Screenshots for all device sizes
- [ ] TestFlight feedback incorporated

---

## Version History

| Version | Date | Notes |
|---------|------|-------|
| v1.0-rc1 | TBD | First TestFlight release |
| v1.0 | TBD | App Store release |

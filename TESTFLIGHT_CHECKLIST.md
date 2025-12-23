# TestFlight Release Checklist

**App:** Food Intolerances
**Version:** 1.0 (Build TBD)

---

## Pre-Flight Checks

### Build & Technical
- [ ] Build succeeds with no warnings
- [ ] No compiler warnings in production code
- [ ] Archive builds successfully
- [ ] App launches without crash on fresh install
- [ ] App launches without crash on upgrade (if applicable)

### App Configuration
- [ ] Bundle ID is correct: `com.leo.symptomtracker`
- [ ] Version number set: `1.0`
- [ ] Build number incremented
- [ ] App icon displays correctly (all sizes)
- [ ] Launch screen displays correctly

### Privacy & Permissions
- [ ] Info.plist has all required usage descriptions:
  - [ ] NSCameraUsageDescription
  - [ ] NSPhotoLibraryUsageDescription
  - [ ] NSHealthShareUsageDescription
  - [ ] NSLocationWhenInUseUsageDescription
  - [ ] NSUserNotificationsUsageDescription
  - [ ] NSSpeechRecognitionUsageDescription
  - [ ] NSMicrophoneUsageDescription
- [ ] No exposed API keys in code or Info.plist
- [ ] ATS exceptions are scoped (not global bypass)

---

## End-to-End UX Walkthrough

### Fresh Install Flow
- [ ] 1. App launches to onboarding (first time)
- [ ] 2. Complete onboarding step by step
- [ ] 3. Onboarding saves profile correctly
- [ ] 4. Dashboard shows after onboarding
- [ ] 5. AI mode indicator visible

### Core Logging
- [ ] 6. Log first symptom
- [ ] 7. AI response card appears after save
- [ ] 8. AI response is relevant (not generic)
- [ ] 9. Log food/drink item
- [ ] 10. Log supplement intake
- [ ] 11. Logs appear in history

### AI Features
- [ ] 12. AI provides "what worked before" (after multiple logs)
- [ ] 13. AI asks relevant follow-up questions
- [ ] 14. Tap feedback button (helpful/not helpful)
- [ ] 15. Feedback affects future suggestions
- [ ] 16. Memory learning status visible in settings

### AI Control
- [ ] 17. Pause AI learning
- [ ] 18. Verify AI still responds (but doesn't learn)
- [ ] 19. Resume AI learning
- [ ] 20. Reset AI memories
- [ ] 21. Confirm memories cleared

### Cloud AI (Optional)
- [ ] 22. Enable Cloud AI in settings
- [ ] 23. Enter API key
- [ ] 24. Cloud AI enhances responses
- [ ] 25. Disable "Include notes" toggle
- [ ] 26. Verify notes not sent to cloud
- [ ] 27. Disable Cloud AI

### Weather Integration
- [ ] 28. Grant location permission
- [ ] 29. Weather data shows on dashboard
- [ ] 30. Environmental factors in AI responses
- [ ] 31. Deny/disable location
- [ ] 32. App works gracefully without weather

### Notifications
- [ ] 33. Enable notifications
- [ ] 34. Schedule a protocol reminder
- [ ] 35. Receive notification
- [ ] 36. Open app from notification
- [ ] 37. Enable "Hide sensitive content"
- [ ] 38. Verify notification shows generic text
- [ ] 39. Disable notifications - app still works

### Settings & Profile
- [ ] 40. Edit user profile
- [ ] 41. Change AI suggestion level (minimal/standard/proactive)
- [ ] 42. Change memory detail level
- [ ] 43. Access AI Debug Inspector (if enabled)
- [ ] 44. View system status in debug view

### Edge Cases
- [ ] 45. Kill app mid-log - no data loss
- [ ] 46. Background app for 10 min - returns correctly
- [ ] 47. Rotate device - UI adapts
- [ ] 48. Large text accessibility - readable
- [ ] 49. VoiceOver - navigable

---

## Performance Checks

### Memory & Battery
- [ ] No memory leaks (Instruments check)
- [ ] No excessive battery drain
- [ ] Background tasks complete properly
- [ ] Maintenance scheduler runs max once per 24h

### Data
- [ ] 100+ logs don't slow app
- [ ] Large memory database doesn't crash
- [ ] iCloud sync works (if enabled)

---

## TestFlight Specific

### Before Upload
- [ ] Select "Manage internal/external testers"
- [ ] App description written
- [ ] What to test notes written
- [ ] Contact email configured

### Tester Feedback Questions
Ask testers to rate 1-5:
1. "Did the AI feel helpful or annoying?"
2. "Was anything confusing during onboarding?"
3. "Did you understand what the AI was telling you?"
4. "Did anything feel 'creepy' or invasive?"
5. "Was anything silent when you expected feedback?"

### Known Issues to Document
- [ ] List any known limitations
- [ ] List any features not yet implemented
- [ ] List workarounds if applicable

---

## App Store Preparation (Post-TestFlight)

### Required Assets
- [ ] App Store icon (1024x1024)
- [ ] Screenshots for:
  - [ ] iPhone 6.9" (iPhone 16 Pro Max)
  - [ ] iPhone 6.7" (iPhone 15 Plus)
  - [ ] iPhone 6.5" (iPhone 14 Pro Max)
  - [ ] iPhone 5.5" (iPhone 8 Plus)
  - [ ] iPad Pro 12.9"
  - [ ] iPad Pro 11"
- [ ] App Preview video (optional)

### Metadata
- [ ] App name (30 chars max)
- [ ] Subtitle (30 chars max)
- [ ] Description (4000 chars max)
- [ ] Keywords (100 chars max)
- [ ] Privacy Policy URL
- [ ] Support URL
- [ ] Marketing URL (optional)

### App Review Information
- [ ] Contact info for reviewer
- [ ] Demo account (if applicable)
- [ ] Notes for reviewer explaining health tracking nature

---

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Developer | | | |
| Tester | | | |

---

## Notes

_Add any observations, issues found, or feedback here:_

```
[Date] - [Note]
```

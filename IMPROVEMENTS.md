# Improvements

Tracked enhancements to implement after core features are complete.

## 1. Extract attendee emails from Google Calendar for CRM auto-matching

**Problem:** The Salesforce/HubSpot modal currently searches by participant name only, which is imprecise. Recall.ai only provides participant `name` and `is_host` - no email.

**Solution:** Google Calendar API returns attendees with emails:
```json
{
  "attendees": [
    {"email": "john@example.com", "displayName": "John Doe", "responseStatus": "accepted"}
  ]
}
```

**Implementation:**
1. Add `attendees` field to `CalendarEvent` schema (as `:map` or JSON array)
2. Update `CalendarSyncronizer.parse_google_event/3` to extract attendees from the Google Calendar response
3. When the CRM modal opens, match attendee emails against CRM contacts for accurate auto-selection

**Files to modify:**
- `lib/social_scribe/calendar/calendar_event.ex`
- `lib/social_scribe/calendar_syncronizer.ex`
- `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`
- `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex`

**Benefit:** Enables precise contact auto-selection by email instead of fuzzy name search which is prone to mistakes.

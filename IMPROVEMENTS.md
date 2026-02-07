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

## 2. Sequential multi-contact updates from a single meeting

**Problem:** When a meeting has multiple participants (e.g., 3 contacts), the user currently has to manually search and update each contact one by one. This is tedious and requires re-opening the modal multiple times.

**Solution:** Allow users to update all meeting participants sequentially without searching:
1. Pre-match all non-host participants to CRM contacts (using emails from Improvement #1)
2. Show a list of matched contacts with their suggested updates
3. Let user step through each contact: review suggestions → apply → next contact
4. Track which contacts have been updated for this meeting

**Implementation:**
1. On modal open, match all participants to CRM contacts
2. Display a contact queue/stepper UI showing all matched contacts
3. For each contact, show AI suggestions with before/after values
4. After applying updates, automatically advance to next contact
5. Optionally store update history to prevent duplicate updates

**Files to modify:**
- `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex`
- `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex`
- `lib/social_scribe/salesforce_suggestions.ex`
- `lib/social_scribe/hubspot_suggestions.ex`
- Possibly add `meeting_crm_updates` table to track applied updates

**Benefit:** Streamlined workflow - update all contacts from one meeting in a single modal session.

## 3. Unify HubSpot and Salesforce CRM integration code

**Problem:** HubSpot and Salesforce integrations are nearly identical in structure:
- Both have modal components with the same UI flow
- Both have suggestions modules with the same logic
- Both have API clients with similar patterns
- Both use the same AI prompt structure for extracting contact info

This leads to code duplication and maintenance overhead.

**Solution:** Create a unified CRM abstraction:
1. Generic `CrmModalComponent` that accepts a provider adapter
2. Unified `CrmSuggestions` module with provider-specific field mappings
3. `CrmApiBehaviour` that both HubSpot and Salesforce implement
4. Single AI prompt that specifies which fields are available per provider - AI response indicates which provider(s) each extracted field applies to
5. Field mapping config that defines:
   - Common fields (phone, email, name, company) → both providers
   - Provider-specific fields (e.g., `twitter_handle` → HubSpot only, `department` → Salesforce only)
6. UI shows provider icons next to each suggestion indicating where the update will be applied

**Implementation:**
1. Create `CrmProvider` behaviour defining common interface
2. Implement `HubspotProvider` and `SalesforceProvider` adapters
3. Create generic modal component that delegates to provider
4. Consolidate suggestions logic with field mapping config
5. Unify AI prompts with provider-specific field names

**Files to create/modify:**
- `lib/social_scribe/crm/crm_provider.ex` (behaviour)
- `lib/social_scribe/crm/hubspot_provider.ex`
- `lib/social_scribe/crm/salesforce_provider.ex`
- `lib/social_scribe_web/live/meeting_live/crm_modal_component.ex`
- Deprecate individual modal components

**Benefit:** Single codebase for all CRM integrations. Adding new CRMs (Pipedrive, Zoho, etc.) becomes trivial.

# Improvements

Tracked enhancements to implement after core features are complete.

## 1. Extract attendee emails from Google Calendar for CRM auto-matching ✅

> **Status:** Implemented as part of Chat Feature (see `PLAN_CHAT_FEATURE.md` Phase 2)

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
1. Pre-match all non-host participants to CRM contacts (using attendee emails from calendar_events)
2. Show a list of matched contacts with their suggested updates
3. Let user step through each contact: review suggestions → apply → next contact
4. Track which contacts have been updated for this meeting

**Implementation:**
1. On modal open, match all participants to CRM contacts using calendar_event.attendees
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

## 4. Add CRM IDs to contacts table

**Problem:** The chat feature's contacts table is intentionally lean (id, user_id, name, email). When we need to fetch fresh CRM data for a contact, we have no direct link to the CRM record - we must search by email.

**Solution:** Add optional CRM ID columns to the contacts table:
```elixir
# contacts (extended)
- hubspot_id (string, nullable)
- salesforce_id (string, nullable)
```

**Implementation:**
1. Add migration for new columns
2. When user creates contact from CRM search results, store the CRM ID
3. When fetching CRM data, use direct ID lookup instead of email search
4. Update contact CRM IDs when syncing

**Files to modify:**
- `priv/repo/migrations/xxx_add_crm_ids_to_contacts.exs`
- `lib/social_scribe/contacts/contact.ex`
- `lib/social_scribe/contacts.ex`

**Benefit:** Direct CRM lookups are faster and more reliable than email-based search. Enables future features like "open in HubSpot/Salesforce" links.

---

## Minor Fixes

### Double scrollbar in dashboard layout ✅

> **Status:** Resolved

**Problem:** The dashboard had a double scrollbar issue where both the body/html and the content area had scrollbars visible. This was caused by the header being outside the `h-screen` container, so header height + 100vh content exceeded the viewport height.

**Solution:** Restructured `dashboard.html.heex` to use a proper flex column layout:
- Outer container with `h-screen flex flex-col` takes exactly 100vh
- Header with `shrink-0` takes only its natural height
- Inner flex container with `flex-1 min-h-0` fills remaining space without exceeding viewport

**File modified:**
- `lib/social_scribe_web/components/layouts/dashboard.html.heex`

---

## 5. Add pattern matching with guards for type safety

**Problem:** Elixir is dynamically typed, so type mismatches (e.g., passing `user.id` instead of `user` struct) are only caught at runtime, often with cryptic errors like `expected a map, got: 1`.

**Solution:** Add pattern matching with guards in function heads to enforce types at runtime with clear error messages:

```elixir
# Instead of:
def get_user_credential(user, provider) do
  Repo.get_by(UserCredential, user_id: user.id, provider: provider)
end

# Use:
def get_user_credential(%User{} = user, provider) when is_binary(provider) do
  Repo.get_by(UserCredential, user_id: user.id, provider: provider)
end
```

**Implementation:**
1. Audit all context module functions that accept structs
2. Add struct pattern matching (`%User{}`, `%Contact{}`, etc.) in function heads
3. Add guards for primitive types (`when is_binary/1`, `when is_integer/1`, etc.)
4. Ensure typespecs (`@spec`) are added for Dialyzer support

**Priority files:**
- `lib/social_scribe/accounts.ex`
- `lib/social_scribe/contacts.ex`
- `lib/social_scribe/chat.ex`
- `lib/social_scribe/chat_ai.ex`

**Benefit:** Clearer error messages at runtime, better documentation, and Dialyzer can catch mismatches at compile time.

## 6. Code Formatting Standards

**Problem:** Inconsistent code formatting across the codebase can lead to noisy diffs and style debates during code review.

**Current State:** Elixir's built-in `mix format` is available but formatting rules may not be fully configured or enforced.

**Investigation Needed:**
1. Check if `.formatter.exs` exists and is properly configured
2. Review if formatting is enforced in CI/pre-commit hooks
3. Determine if all files pass `mix format --check-formatted`

**Potential Improvements:**
- Configure `.formatter.exs` with project-specific rules (line length, import ordering, etc.)
- Add pre-commit hook to auto-format staged files
- Add `mix format --check-formatted` to CI pipeline
- Consider additional tools like `mix credo` for static analysis

**Pre-commit Hook Implementation:**
```bash
# .git/hooks/pre-commit (make executable with chmod +x)
#!/bin/sh
mix format --check-formatted
if [ $? -ne 0 ]; then
  echo "Code is not formatted. Run 'mix format' and try again."
  exit 1
fi
```

Or use a tool like `pre-commit` (Python) or `lefthook` (Go) for more robust hook management.

**Note:** Elixir's upcoming type system may reduce reliance on Dialyzer. Avoid adding explicit `@type t()` definitions to schemas - let the compiler infer types (consistent with current codebase convention).

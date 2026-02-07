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

## 3. Unify HubSpot and Salesforce CRM integration code ✅

> **Status:** Implemented via shared helpers and components

**Problem:** HubSpot and Salesforce integrations are nearly identical in structure:
- Both have modal components with the same UI flow
- Both have suggestions modules with the same logic
- Both have API clients with similar patterns
- Both use the same AI prompt structure for extracting contact info

This leads to code duplication and maintenance overhead.

**Solution Implemented:**
1. Created `CRMModalHelpers` module with config-based approach for CRM-specific settings
2. Created `CRMModalComponents` with shared UI components (header, search, suggestions list, etc.)
3. Refactored both `HubspotModalComponent` and `SalesforceModalComponent` to use shared helpers
4. Single `handle_update/3` function handles all common update logic
5. Auto-search on modal open for both CRMs

**Files created/modified:**
- `lib/social_scribe_web/live/meeting_live/crm_modal_helpers.ex` (NEW)
- `lib/social_scribe_web/components/crm_modal_components.ex` (NEW)
- `lib/social_scribe_web/live/meeting_live/hubspot_modal_component.ex` (refactored)
- `lib/social_scribe_web/live/meeting_live/salesforce_modal_component.ex` (refactored)

**Benefit:** Adding new CRMs is now trivial - just create a new modal component with CRM-specific config and reuse all shared helpers.

## 4. Normalize contacts with calendar event attendees ✅

> **Status:** Implemented for accurate chat contact-to-meeting matching

**Problem:** The original contacts table was user-scoped (each user had their own copy of contacts). This made it difficult to accurately match contacts to meetings in the chat feature - name-based matching is ambiguous (multiple "John"s).

**Solution Implemented:**
1. Made contacts global (one record per email address)
2. Created `calendar_event_attendees` join table linking contacts to calendar events
3. Updated `CalendarSyncronizer` to create attendee records during sync
4. Chat feature now uses contact_id → attendee → calendar_event → meeting for precise matching

**Schema Changes:**
```
# Before
contacts: id, user_id, name, email

# After
contacts: id, name, email (unique)
calendar_event_attendees: id, calendar_event_id, contact_id, display_name, response_status, is_organizer
```

**Files created/modified:**
- `priv/repo/migrations/20260207181056_remove_user_id_from_contacts.exs`
- `priv/repo/migrations/20260207181106_create_calendar_event_attendees.exs`
- `lib/social_scribe/calendar/calendar_event_attendee.ex` (NEW)
- `lib/social_scribe/contacts/contact.ex` (removed user_id)
- `lib/social_scribe/contacts.ex` (new query patterns via join)
- `lib/social_scribe/calendar_syncronizer.ex` (creates attendee records)
- `lib/social_scribe/chat_ai.ex` (uses contact_id for meeting lookup)

**Benefit:** Chat feature accurately retrieves meetings for a tagged contact by email, not ambiguous name matching.

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

### Sidebar navigation causing full page reloads ✅

> **Status:** Resolved

**Problem:** Clicking sidebar links (Home, Meetings, Automations, Settings) caused full page reloads instead of LiveView navigation. This broke the chat widget persistence and caused unnecessary re-renders.

**Cause:** The sidebar component used `href={@href}` instead of `navigate={@href}` for links.

**Solution:** Changed sidebar links to use `navigate` attribute for proper LiveView client-side navigation:
```elixir
# Before
<.link href={@href} class={[...]}>

# After
<.link navigate={@href} class={[...]}>
```

**File modified:**
- `lib/social_scribe_web/components/sidebar.ex`

### Custom 404/500 error pages ✅

> **Status:** Implemented

**Problem:** Default Phoenix error pages showed plain text "Not Found" with no styling.

**Solution:** Created styled error pages matching app design with Tailwind CSS.

**Files created/modified:**
- `lib/social_scribe_web/controllers/error_html.ex` (enabled embed_templates)
- `lib/social_scribe_web/controllers/error_html/404.html.heex` (NEW)
- `lib/social_scribe_web/controllers/error_html/500.html.heex` (NEW)

### Developer experience improvements ✅

> **Status:** Implemented

**Problem:** Manual environment setup was error-prone and undocumented.

**Solutions implemented:**
1. Added `dotenvy` for automatic `.env` loading in dev/test
2. Created `.env.example` with all required environment variables
3. Updated seeds to auto-load `.env` file
4. Updated `CLAUDE.md` with testing guidelines and migration best practices

**Files created/modified:**
- `mix.exs` (added dotenvy dependency)
- `config/runtime.exs` (dotenvy source)
- `.env.example` (NEW)
- `priv/repo/seeds.exs` (dotenvy loading)
- `CLAUDE.md` (testing and migration guidelines)

### Meeting show page crash on invalid ID ✅

> **Status:** Resolved

**Problem:** Accessing `/dashboard/meetings/999` (non-existent ID) crashed with nil pointer error.

**Solution:** Added nil check in mount function with redirect to meetings list.

**File modified:**
- `lib/social_scribe_web/live/meeting_live/show.ex`

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

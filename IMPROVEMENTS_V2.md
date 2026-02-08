# Codebase Improvement Tasks

This document outlines areas for improvement in the codebase, organized by priority and category.

---

## 1. Large Modules to Break Down

These modules exceed 300+ lines and should be refactored into smaller, focused modules.

| File | Lines | Recommendation |
|------|-------|----------------|
| `lib/social_scribe_web/components/core_components.ex` | 775 | Split into domain-specific component modules (form_components.ex, table_components.ex, feedback_components.ex) |
| `lib/social_scribe_web/components/modal_components.ex` | 736 | Extract CRM-specific modals into separate files |
| `lib/social_scribe_web/live/chat_live.ex` | 672 | Extract render helpers, message formatting, and event handlers into separate modules |
| `lib/social_scribe/accounts.ex` | 574 | Split into user management, credentials, and authentication submodules |
| `lib/social_scribe/chat_ai.ex` | 556 | Extract context building, prompt formatting, and API calls into separate modules |
| `lib/social_scribe/meetings.ex` | 512 | Split into meeting CRUD, transcript handling, and participant management |
| `lib/social_scribe_web/live/chat_live/chat_component.ex` | 442 | Consider merging with chat_live.ex or extracting shared logic |
| `lib/social_scribe_web/live/meeting_live/crm_modal_helpers.ex` | 355 | Already a helper module - review if can be further simplified |

### Suggested Actions:
- [ ] Create `lib/social_scribe_web/components/form_components.ex` for form-related components
- [ ] Create `lib/social_scribe_web/components/table_components.ex` for table/list components
- [ ] Create `lib/social_scribe/accounts/credentials.ex` for credential management
- [ ] Create `lib/social_scribe/chat_ai/context_builder.ex` for context gathering
- [ ] Create `lib/social_scribe/chat_ai/prompt_builder.ex` for prompt formatting

---

## 2. Code Duplication

### 2.1 Token Refreshers
`hubspot_token_refresher.ex` and `salesforce_token_refresher.ex` share ~70% similar code.

**Current State:**
- Both implement OAuth token refresh
- Both update credentials in database
- Different only in URL endpoints and response parsing

**Recommendation:**
Create a generic `TokenRefresher` behaviour and shared implementation:

```elixir
# lib/social_scribe/token_refresher/base.ex
defmodule SocialScribe.TokenRefresher.Base do
  @callback token_url() :: String.t()
  @callback parse_response(map()) :: map()
  @callback update_credential(credential, attrs) :: {:ok, credential} | {:error, changeset}

  defmacro __using__(_opts) do
    # Shared refresh logic
  end
end
```

- [ ] Create `lib/social_scribe/token_refresher/base.ex` with shared logic
- [ ] Refactor `hubspot_token_refresher.ex` to use base
- [ ] Refactor `salesforce_token_refresher.ex` to use base

### 2.2 Suggestions Modules
`hubspot_suggestions.ex` and `salesforce_suggestions.ex` have similar structure.

**Recommendation:**
Create a shared `CrmSuggestions` behaviour:

- [ ] Create `lib/social_scribe/crm_suggestions/base.ex`
- [ ] Define shared field mapping and suggestion generation logic
- [ ] CRM-specific modules only define field mappings and API calls

### 2.3 CRM Modal Components
`hubspot_modal_component.ex` and `salesforce_modal_component.ex` (109 lines each) are nearly identical.

**Recommendation:**
- [ ] Create a generic `CrmModalComponent` with CRM-specific adapters
- [ ] Pass CRM type as assign and handle differences via pattern matching

---

## 3. Missing Documentation

The following modules lack `@moduledoc`:

### Schemas (High Priority)
- [ ] `lib/social_scribe/bots/recall_bot.ex`
- [ ] `lib/social_scribe/bots/user_bot_preference.ex`
- [ ] `lib/social_scribe/calendar/calendar_event.ex`
- [ ] `lib/social_scribe/chat/chat_message.ex`
- [ ] `lib/social_scribe/chat/chat_thread.ex`
- [ ] `lib/social_scribe/accounts/user.ex`
- [ ] `lib/social_scribe/accounts/user_credential.ex`
- [ ] `lib/social_scribe/accounts/user_token.ex`
- [ ] `lib/social_scribe/automations/automation.ex`
- [ ] `lib/social_scribe/automations/automation_result.ex`

### API Modules
- [ ] `lib/social_scribe/google_calendar_api.ex`
- [ ] `lib/social_scribe/linked_in_api.ex`
- [ ] `lib/social_scribe/facebook_api.ex`
- [ ] `lib/social_scribe/token_refresher_api.ex`

### Workers
- [ ] `lib/social_scribe/workers/ai_content_generation_worker.ex`
- [ ] `lib/social_scribe/workers/bot_status_poller.ex`

---

## 4. Test Coverage Gaps

### Modules Without Tests
| Module | Priority | Notes |
|--------|----------|-------|
| `ai_content_generator.ex` | High | Core AI functionality |
| `transcript_parser.ex` | High | Critical for meeting processing |
| `google_calendar.ex` / `google_calendar_api.ex` | Medium | Calendar sync functionality |
| `recall.ex` / `recall_api.ex` | Medium | Bot management |
| `facebook.ex` / `facebook_api.ex` | Low | Social posting |
| `linked_in.ex` / `linked_in_api.ex` | Low | Social posting |
| `poster.ex` | Low | Social posting orchestration |
| `token_refresher.ex` | Medium | Token management |

### Missing LiveView Tests
- [ ] `lib/social_scribe_web/live/home_live.ex` - No test file
- [ ] `lib/social_scribe_web/live/landing_live.ex` - No test file
- [ ] `lib/social_scribe_web/live/meeting_live/index.ex` - No test file
- [ ] `lib/social_scribe_web/live/meeting_live/show.ex` - No test file

### Suggested Actions:
- [ ] Add unit tests for `transcript_parser.ex`
- [ ] Add unit tests for `ai_content_generator.ex` (with mocks)
- [ ] Add integration tests for calendar sync flow
- [ ] Add LiveView tests for meeting pages

---

## 5. Folder Structure Improvements

### Current Issues:
1. **API behaviours mixed with implementations** - `hubspot_api.ex` and `hubspot_api_behaviour.ex` are at the same level
2. **Ueberauth strategies in non-standard location** - `lib/ueberauth/` could be in `lib/social_scribe/ueberauth/`

### Recommended Structure:
```
lib/social_scribe/
├── accounts/
│   ├── schemas/           # User, UserToken, UserCredential, etc.
│   ├── credentials.ex     # Credential management functions
│   └── accounts.ex        # User management functions
├── calendar/
│   ├── schemas/           # CalendarEvent, CalendarEventAttendee
│   ├── google_calendar.ex
│   └── calendar.ex
├── crm/
│   ├── hubspot/
│   │   ├── api.ex
│   │   ├── suggestions.ex
│   │   └── token_refresher.ex
│   ├── salesforce/
│   │   ├── api.ex
│   │   ├── suggestions.ex
│   │   └── token_refresher.ex
│   └── base/              # Shared CRM behaviours
├── chat/
│   ├── schemas/
│   ├── ai/
│   │   ├── context_builder.ex
│   │   ├── prompt_builder.ex
│   │   └── response_handler.ex
│   └── chat.ex
└── ...
```

### Actions:
- [ ] Create `schemas/` subdirectories for each context
- [ ] Group CRM integrations under `lib/social_scribe/crm/`
- [ ] Move Ueberauth strategies to `lib/social_scribe/auth/strategies/`

---

## 6. Elixir Best Practices

### 6.1 Use `with` for Sequential Operations
Some modules use nested `case` statements where `with` would be cleaner.

**Example location:** `lib/social_scribe/chat_ai.ex`

### 6.2 Consistent Error Handling
Standardize error tuples across the codebase:
- Some return `{:error, reason}` (atom)
- Some return `{:error, message}` (string)
- Some return `{:error, {type, message}}` (tuple)

**Recommendation:**
- [ ] Create `lib/social_scribe/error.ex` with standardized error types
- [ ] Define error structs for different error categories
- [ ] Update all modules to use consistent error format

### 6.3 Configuration Best Practices
Some modules have hard-coded values that should be configurable:

| File | Value | Recommendation |
|------|-------|----------------|
| `chat_ai.ex` | `@max_meetings 10` | Move to config |
| `hubspot_api.ex` | `@base_url` | Already good |
| `salesforce_api.ex` | `@api_version "v59.0"` | Move to config for easier updates |

### 6.4 Missing Typespec
Add `@spec` annotations to public functions for better documentation and dialyzer support.

Priority modules:
- [ ] `lib/social_scribe/chat_ai.ex`
- [ ] `lib/social_scribe/meetings.ex`
- [ ] `lib/social_scribe/accounts.ex`

---

## 7. LiveView Improvements

### 7.1 Extract Render Functions
Large `render/1` functions should use function components:

**Example:** `chat_live.ex` has inline HTML that could be extracted:
```elixir
# Instead of inline HTML in render/1
defp message_bubble(assigns) do
  ~H"""
  <div class={message_bubble_class(@role)}>
    ...
  </div>
  """
end
```

### 7.2 Use Slots for Flexible Components
Some components could benefit from slots for better reusability.

### 7.3 Reduce Socket Assigns
`chat_live.ex` has many assigns - consider grouping related assigns into a struct:
```elixir
# Current: 12+ individual assigns
# Better: Group into logical structs
defmodule ChatState do
  defstruct [:thread, :messages, :loading, :error]
end
```

---

## 8. Performance Considerations

### 8.1 N+1 Query Prevention
Review these modules for potential N+1 queries:
- [ ] `lib/social_scribe/meetings.ex` - Meeting list with preloads
- [ ] `lib/social_scribe/chat.ex` - Thread listing with messages

### 8.2 Add Database Indexes
Review if these queries have proper indexes:
- Contact search by email
- Meeting lookup by calendar_event_id
- Thread listing by user_id

### 8.3 Caching Opportunities
Consider caching for:
- CRM contact searches (short TTL)
- AI-generated content (by meeting ID)

---

## 9. Security Review

### 9.1 Input Validation
- [ ] Review all user inputs for proper sanitization
- [ ] Ensure HTML escaping in chat messages (currently done via `escape_html/1`)

### 9.2 Authorization Checks
- [ ] Audit all LiveView mount functions for proper user authorization
- [ ] Review handle_event callbacks for authorization

### 9.3 Sensitive Data
- [ ] Ensure API keys are never logged
- [ ] Review credential storage and encryption

---

## Priority Order

1. **High Priority (Do First)**
   - Add tests for `transcript_parser.ex` and `ai_content_generator.ex`
   - Add `@moduledoc` to schema files
   - Break down `chat_live.ex` into smaller modules

2. **Medium Priority**
   - Consolidate token refresher logic
   - Consolidate CRM suggestions logic
   - Reorganize folder structure for CRM integrations

3. **Lower Priority (Nice to Have)**
   - Add typespecs to public functions
   - Extract LiveView render helpers
   - Add caching layer

---

## Notes

- When refactoring, ensure all existing tests pass
- Add tests for new modules/functions created during refactoring
- Follow the existing code style and conventions
- Update imports/aliases when moving modules

Last updated: 2025-02-08

# CRM Integration Structure

This directory is intended to hold all CRM-related integrations (HubSpot, Salesforce, etc.).

## Intended Structure

```
lib/social_scribe/crm/
├── base/
│   ├── token_refresher.ex    # Shared token refresh behaviour
│   └── suggestions.ex        # Shared suggestion generation behaviour
├── hubspot/
│   ├── api.ex                # HubSpot API client
│   ├── api_behaviour.ex      # HubSpot API behaviour for mocking
│   ├── suggestions.ex        # HubSpot-specific suggestions
│   └── token_refresher.ex    # HubSpot token refresher
└── salesforce/
    ├── api.ex                # Salesforce API client
    ├── api_behaviour.ex      # Salesforce API behaviour for mocking
    ├── suggestions.ex        # Salesforce-specific suggestions
    └── token_refresher.ex    # Salesforce token refresher
```

## Current State

The CRM files are currently located at the top level of `lib/social_scribe/`:
- `hubspot_api.ex` → `SocialScribe.HubspotApi`
- `salesforce_api.ex` → `SocialScribe.SalesforceApi`
- `hubspot_suggestions.ex` → `SocialScribe.HubspotSuggestions`
- `salesforce_suggestions.ex` → `SocialScribe.SalesforceSuggestions`
- etc.

The base modules are in:
- `lib/social_scribe/token_refresher/base.ex` → `SocialScribe.TokenRefresher.Base`
- `lib/social_scribe/crm_suggestions/base.ex` → `SocialScribe.CRMSuggestions.Base`

## Migration Plan

When reorganizing:

1. Create new modules in the CRM directory structure
2. Update all aliases and imports to use new module paths
3. Update test files to match
4. Remove old files after verification

## Adding a New CRM

1. Create a new directory under `crm/` (e.g., `crm/pipedrive/`)
2. Implement the required modules:
   - `api.ex` - API client using Tesla
   - `api_behaviour.ex` - Behaviour for mocking
   - `suggestions.ex` - Use `SocialScribe.CRMSuggestions.Base`
   - `token_refresher.ex` - Use `SocialScribe.TokenRefresher.Base`
3. Add mock to `test/test_helper.exs`
4. Add configuration to `config/config.exs`

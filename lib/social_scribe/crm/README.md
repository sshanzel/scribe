# CRM Integration Structure

This directory holds all CRM-related integrations (HubSpot, Salesforce, etc.).

## Structure

```
lib/social_scribe/crm/
├── field_config.ex           # Base behaviour for field configurations
├── field_mapper.ex           # Shared field mapping utilities
├── prompt_builder.ex         # AI prompt building and parsing
├── suggestions/
│   └── base.ex               # Base behaviour for CRM suggestions
├── hubspot/
│   ├── field_config.ex       # HubSpot field definitions
│   ├── api.ex                # HubSpot API client
│   ├── api_behaviour.ex      # HubSpot API behaviour for mocking
│   ├── suggestions.ex        # HubSpot-specific suggestions
│   └── token_refresher.ex    # HubSpot token refresher
└── salesforce/
    ├── field_config.ex       # Salesforce field definitions
    ├── api.ex                # Salesforce API client
    ├── api_behaviour.ex      # Salesforce API behaviour for mocking
    ├── suggestions.ex        # Salesforce-specific suggestions
    └── token_refresher.ex    # Salesforce token refresher
```

## Module Naming

- `SocialScribe.CRM.FieldConfig` - Base behaviour with registry
- `SocialScribe.CRM.HubSpot.FieldConfig` - HubSpot field definitions
- `SocialScribe.CRM.HubSpot.Api` - HubSpot API client
- `SocialScribe.CRM.Salesforce.FieldConfig` - Salesforce field definitions
- `SocialScribe.CRM.Salesforce.Api` - Salesforce API client

## Adding a New CRM

1. Create a new directory under `crm/` (e.g., `crm/pipedrive/`)
2. Create `field_config.ex` implementing `SocialScribe.CRM.FieldConfig`:
   ```elixir
   defmodule SocialScribe.CRM.Pipedrive.FieldConfig do
     use SocialScribe.CRM.FieldConfig

     @impl true
     def display_name, do: "Pipedrive"

     @impl true
     def prompt_example do
       %{
         field: "organization",
         value: "Acme Corp",
         context: "John mentioned he works at Acme Corp"
       }
     end

     @impl true
     def fields do
       [
         %{name: "firstname", label: "First Name", category: "basic"},
         # ... more fields
       ]
     end
   end
   ```
3. Add the CRM to `SocialScribe.CRM.FieldConfig.for_crm/1`
4. Implement the remaining modules:
   - `api.ex` - API client using Tesla
   - `api_behaviour.ex` - Behaviour for mocking
   - `suggestions.ex` - Use `SocialScribe.CRM.Suggestions.Base`
   - `token_refresher.ex` - Use `SocialScribe.TokenRefresher.Base`
5. Add mock to `test/test_helper.exs`
6. Add configuration to `config/config.exs`

defmodule SocialScribe.CRM.PromptBuilder do
  @moduledoc """
  Builds AI prompts for CRM contact extraction and parses responses.

  This module generates prompts dynamically from `FieldConfig` and provides
  a single parser that works for all CRMs.

  ## Usage

      # Build a prompt for HubSpot
      prompt = PromptBuilder.build_extraction_prompt(:hubspot, meeting_transcript)

      # Parse the AI response (same for all CRMs)
      {:ok, suggestions} = PromptBuilder.parse_response(response)
  """

  alias SocialScribe.CRM.FieldConfig

  @doc """
  Builds an AI prompt for extracting contact information from a meeting transcript.
  """
  @spec build_extraction_prompt(FieldConfig.crm(), String.t()) :: String.t()
  def build_extraction_prompt(crm, meeting_transcript) do
    config_module = FieldConfig.for_crm(crm)
    fields = config_module.fields()
    field_list = build_field_list(fields)
    field_names = build_field_names_list(fields)
    crm_name = config_module.display_name()
    example = config_module.prompt_example()

    """
    You are an AI assistant that extracts contact information updates from meeting transcripts.

    Analyze the following meeting transcript and extract any information that could be used to update a #{crm_name} contact record.

    Look for mentions of:
    #{field_list}
    IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

    The transcript includes timestamps in [MM:SS] format at the start of each line.

    Return your response as a JSON array of objects. Each object should have:
    - "field": the field name (use exactly: #{field_names})
    - "value": the extracted value
    - "context": a brief quote of where this was mentioned
    - "timestamp": the timestamp in MM:SS format where this was mentioned

    If no contact information updates are found, return an empty array: []

    Example response format:
    [
      {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
      {"field": "#{example.field}", "value": "#{example.value}", "context": "#{example.context}", "timestamp": "05:47"}
    ]

    ONLY return valid JSON, no other text.

    Meeting transcript:
    #{meeting_transcript}
    """
  end

  @doc """
  Parses the AI response into a list of suggestion maps.

  This is a generic parser that works for all CRMs since they all use
  the same JSON structure.

  ## Returns
  - `{:ok, suggestions}` - Successfully parsed suggestions (may be empty list)
  - `{:error, :invalid_json}` - Response was not valid JSON
  - `{:error, :invalid_format}` - Response was valid JSON but not an array
  """
  @spec parse_response(String.t()) :: {:ok, [map()]} | {:error, :invalid_json | :invalid_format}
  def parse_response(response) do
    cleaned =
      response
      |> String.trim()
      |> String.replace(~r/^```json\n?/, "")
      |> String.replace(~r/\n?```$/, "")
      |> String.trim()

    case Jason.decode(cleaned) do
      {:ok, suggestions} when is_list(suggestions) ->
        formatted =
          suggestions
          |> Enum.filter(&is_map/1)
          |> Enum.map(fn s ->
            %{
              field: s["field"],
              value: s["value"],
              context: s["context"],
              timestamp: s["timestamp"]
            }
          end)
          |> Enum.filter(fn s -> s.field != nil and s.value != nil end)

        {:ok, formatted}

      {:ok, _} ->
        {:error, :invalid_format}

      {:error, _} ->
        {:error, :invalid_json}
    end
  end

  # =============================================================================
  # Private Helpers
  # =============================================================================

  # Fixed category order to ensure deterministic prompt generation
  @category_order ["basic", "phone", "work", "address", "online", "other"]

  defp build_field_list(fields) do
    fields
    |> Enum.group_by(&(&1[:category] || "other"))
    |> Enum.sort_by(fn {category, _} ->
      Enum.find_index(@category_order, &(&1 == category)) || 999
    end)
    |> Enum.map(fn {category, category_fields} ->
      field_items =
        category_fields
        |> Enum.map(&"#{&1.label} (#{&1.name})")
        |> Enum.join(", ")

      "- #{humanize_category(category)}: #{field_items}"
    end)
    |> Enum.join("\n")
  end

  defp build_field_names_list(fields) do
    fields
    |> Enum.map(& &1.name)
    |> Enum.join(", ")
  end

  defp humanize_category("basic"), do: "Basic info"
  defp humanize_category("phone"), do: "Phone numbers"
  defp humanize_category("work"), do: "Work info"
  defp humanize_category("address"), do: "Address"
  defp humanize_category("online"), do: "Online presence"
  defp humanize_category(other), do: String.capitalize(other)
end

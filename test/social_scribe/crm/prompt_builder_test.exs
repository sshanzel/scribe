defmodule SocialScribe.CRM.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias SocialScribe.CRM.PromptBuilder

  # Snapshot of expected HubSpot prompt structure
  @hubspot_prompt_snapshot """
  You are an AI assistant that extracts contact information updates from meeting transcripts.

  Analyze the following meeting transcript and extract any information that could be used to update a HubSpot contact record.

  Look for mentions of:
  - Address: Address (address), City (city), State (state), ZIP Code (zip), Country (country)
  - Basic info: First Name (firstname), Last Name (lastname), Email (email)
  - Online presence: Website (website), LinkedIn (linkedin_url), Twitter (twitter_handle)
  - Phone numbers: Phone (phone), Mobile Phone (mobilephone)
  - Work info: Company (company), Job Title (jobtitle)
  IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

  The transcript includes timestamps in [MM:SS] format at the start of each line.

  Return your response as a JSON array of objects. Each object should have:
  - "field": the field name (use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country, website, linkedin_url, twitter_handle)
  - "value": the extracted value
  - "context": a brief quote of where this was mentioned
  - "timestamp": the timestamp in MM:SS format where this was mentioned

  If no contact information updates are found, return an empty array: []

  Example response format:
  [
    {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
    {"field": "company", "value": "Acme Corp", "context": "Sarah said she just joined Acme Corp", "timestamp": "05:47"}
  ]

  ONLY return valid JSON, no other text.

  Meeting transcript:
  {{TRANSCRIPT}}
  """

  # Snapshot of expected Salesforce prompt structure
  @salesforce_prompt_snapshot """
  You are an AI assistant that extracts contact information updates from meeting transcripts.

  Analyze the following meeting transcript and extract any information that could be used to update a Salesforce contact record.

  Look for mentions of:
  - Address: Address (address), City (city), State (state), ZIP Code (zip), Country (country)
  - Basic info: First Name (firstname), Last Name (lastname), Email (email)
  - Phone numbers: Phone (phone), Mobile Phone (mobilephone)
  - Work info: Job Title (title), Department (department)
  IMPORTANT: Only extract information that is EXPLICITLY mentioned in the transcript. Do not infer or guess.

  The transcript includes timestamps in [MM:SS] format at the start of each line.

  Return your response as a JSON array of objects. Each object should have:
  - "field": the field name (use exactly: firstname, lastname, email, phone, mobilephone, title, department, address, city, state, zip, country)
  - "value": the extracted value
  - "context": a brief quote of where this was mentioned
  - "timestamp": the timestamp in MM:SS format where this was mentioned

  If no contact information updates are found, return an empty array: []

  Example response format:
  [
    {"field": "phone", "value": "555-123-4567", "context": "John mentioned 'you can reach me at 555-123-4567'", "timestamp": "01:23"},
    {"field": "title", "value": "VP of Sales", "context": "Sarah mentioned she was promoted to VP of Sales", "timestamp": "05:47"}
  ]

  ONLY return valid JSON, no other text.

  Meeting transcript:
  {{TRANSCRIPT}}
  """

  describe "build_extraction_prompt/2 snapshots" do
    test "HubSpot prompt matches expected snapshot" do
      transcript = "Test transcript content"

      prompt = PromptBuilder.build_extraction_prompt(:hubspot, transcript)
      expected = String.replace(@hubspot_prompt_snapshot, "{{TRANSCRIPT}}", transcript)

      assert prompt == expected,
             """
             HubSpot prompt does not match snapshot.

             === EXPECTED ===
             #{expected}

             === ACTUAL ===
             #{prompt}

             === DIFF ===
             If this change is intentional, update @hubspot_prompt_snapshot in the test file.
             """
    end

    test "Salesforce prompt matches expected snapshot" do
      transcript = "Test transcript content"

      prompt = PromptBuilder.build_extraction_prompt(:salesforce, transcript)
      expected = String.replace(@salesforce_prompt_snapshot, "{{TRANSCRIPT}}", transcript)

      assert prompt == expected,
             """
             Salesforce prompt does not match snapshot.

             === EXPECTED ===
             #{expected}

             === ACTUAL ===
             #{prompt}

             === DIFF ===
             If this change is intentional, update @salesforce_prompt_snapshot in the test file.
             """
    end
  end

  describe "build_extraction_prompt/2" do
    test "generates HubSpot prompt with correct structure" do
      transcript = "[00:05] John: My phone is 555-1234 and I work at Acme Corp"

      prompt = PromptBuilder.build_extraction_prompt(:hubspot, transcript)

      # Verify the prompt structure - print it for visibility
      # The prompt should contain these sections:
      #
      # 1. Role and CRM context
      assert prompt =~ "You are an AI assistant that extracts contact information"
      assert prompt =~ "HubSpot contact record"

      # 2. Field categories with labels AND field names for mapping (from HubSpot.FieldConfig)
      # Format: "Label (field_name)" tells AI what to look for and how to map it
      assert prompt =~ "Basic info: First Name (firstname), Last Name (lastname), Email (email)"
      assert prompt =~ "Phone numbers: Phone (phone), Mobile Phone (mobilephone)"
      assert prompt =~ "Work info: Company (company), Job Title (jobtitle)"
      assert prompt =~ "Address: Address (address), City (city), State (state), ZIP Code (zip), Country (country)"
      assert prompt =~ "Online presence: Website (website), LinkedIn (linkedin_url), Twitter (twitter_handle)"

      # 3. Explicit list of valid field names the AI must use
      assert prompt =~ "use exactly: firstname, lastname, email, phone, mobilephone, company, jobtitle, address, city, state, zip, country, website, linkedin_url, twitter_handle"

      # 4. JSON format instructions
      assert prompt =~ "Return your response as a JSON array"
      assert prompt =~ ~s("field": the field name)
      assert prompt =~ ~s("value": the extracted value)
      assert prompt =~ ~s("context": a brief quote)
      assert prompt =~ ~s("timestamp": the timestamp in MM:SS format)

      # 5. CRM-specific example (from HubSpot.FieldConfig.prompt_example/0)
      assert prompt =~ ~s("field": "company")
      assert prompt =~ ~s("value": "Acme Corp")
      assert prompt =~ "Sarah said she just joined Acme Corp"

      # 6. The transcript at the end
      assert prompt =~ "Meeting transcript:"
      assert prompt =~ transcript
    end

    test "generates Salesforce prompt with correct structure" do
      transcript = "[00:05] Jane: I was just promoted to VP of Sales"

      prompt = PromptBuilder.build_extraction_prompt(:salesforce, transcript)

      # 1. Role and CRM context
      assert prompt =~ "Salesforce contact record"

      # 2. Field categories with field name mappings (Salesforce has different fields - no company, no online)
      assert prompt =~ "Basic info: First Name (firstname), Last Name (lastname), Email (email)"
      assert prompt =~ "Phone numbers: Phone (phone), Mobile Phone (mobilephone)"
      assert prompt =~ "Work info: Job Title (title), Department (department)"
      assert prompt =~ "Address: Address (address), City (city), State (state), ZIP Code (zip), Country (country)"
      refute prompt =~ "Company (company)"
      refute prompt =~ "Online presence:"

      # 3. Explicit list of valid field names for Salesforce
      assert prompt =~ "use exactly: firstname, lastname, email, phone, mobilephone, title, department, address, city, state, zip, country"
      refute prompt =~ "linkedin_url"
      refute prompt =~ "twitter_handle"

      # 4. Salesforce-specific example (from Salesforce.FieldConfig.prompt_example/0)
      assert prompt =~ ~s("field": "title")
      assert prompt =~ ~s("value": "VP of Sales")
      assert prompt =~ "Sarah mentioned she was promoted to VP of Sales"

      # 5. The transcript
      assert prompt =~ transcript
    end

    test "HubSpot and Salesforce prompts differ in field lists" do
      hubspot_prompt = PromptBuilder.build_extraction_prompt(:hubspot, "test")
      salesforce_prompt = PromptBuilder.build_extraction_prompt(:salesforce, "test")

      # HubSpot has company field
      assert hubspot_prompt =~ "Company (company)"
      refute salesforce_prompt =~ "Company (company)"

      # Salesforce has department field
      assert salesforce_prompt =~ "Department (department)"
      refute hubspot_prompt =~ "Department (department)"

      # Salesforce uses "title" for job title, HubSpot uses "jobtitle"
      assert hubspot_prompt =~ "jobtitle"
      assert salesforce_prompt =~ "(title)"
      refute hubspot_prompt =~ "(title)"
    end

    @tag :verbose
    test "prints full HubSpot prompt for inspection" do
      transcript = """
      [00:05] John: Hi, I'm John Smith from Acme Corp.
      [00:15] Jane: Nice to meet you! What's your role there?
      [00:20] John: I'm the VP of Engineering. You can reach me at john@acme.com or 555-123-4567.
      """

      prompt = PromptBuilder.build_extraction_prompt(:hubspot, transcript)

      # This test exists to make the prompt visible in test output
      # Run with: mix test test/social_scribe/crm/prompt_builder_test.exs --only verbose
      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("GENERATED HUBSPOT PROMPT:")
      IO.puts(String.duplicate("=", 80))
      IO.puts(prompt)
      IO.puts(String.duplicate("=", 80) <> "\n")

      assert is_binary(prompt)
    end

    @tag :verbose
    test "prints full Salesforce prompt for inspection" do
      transcript = """
      [00:05] Jane: I work in the Sales department as Director of Sales.
      [00:15] Jane: My mobile is 555-987-6543.
      """

      prompt = PromptBuilder.build_extraction_prompt(:salesforce, transcript)

      IO.puts("\n" <> String.duplicate("=", 80))
      IO.puts("GENERATED SALESFORCE PROMPT:")
      IO.puts(String.duplicate("=", 80))
      IO.puts(prompt)
      IO.puts(String.duplicate("=", 80) <> "\n")

      assert is_binary(prompt)
    end
  end

  describe "parse_response/1" do
    test "parses valid JSON array of suggestions" do
      response = """
      [
        {"field": "phone", "value": "555-1234", "context": "John mentioned his phone", "timestamp": "01:23"},
        {"field": "company", "value": "Acme", "context": "Works at Acme", "timestamp": "02:45"}
      ]
      """

      assert {:ok, suggestions} = PromptBuilder.parse_response(response)
      assert length(suggestions) == 2

      [first, second] = suggestions
      assert first.field == "phone"
      assert first.value == "555-1234"
      assert first.context == "John mentioned his phone"
      assert first.timestamp == "01:23"

      assert second.field == "company"
      assert second.value == "Acme"
    end

    test "handles JSON wrapped in markdown code blocks" do
      response = """
      ```json
      [{"field": "email", "value": "test@example.com", "context": "Email mentioned", "timestamp": "00:30"}]
      ```
      """

      assert {:ok, [suggestion]} = PromptBuilder.parse_response(response)
      assert suggestion.field == "email"
      assert suggestion.value == "test@example.com"
    end

    test "filters out suggestions without field or value" do
      response = """
      [
        {"field": "phone", "value": "555-1234", "context": "Valid"},
        {"field": null, "value": "no field", "context": "Invalid"},
        {"field": "email", "value": null, "context": "Invalid"},
        {"field": "company", "value": "Acme", "context": "Valid too"}
      ]
      """

      assert {:ok, suggestions} = PromptBuilder.parse_response(response)
      assert length(suggestions) == 2
      assert Enum.all?(suggestions, &(&1.field != nil and &1.value != nil))
    end

    test "returns empty list for empty array" do
      assert {:ok, []} = PromptBuilder.parse_response("[]")
    end

    test "returns error for invalid JSON" do
      assert {:error, :invalid_json} = PromptBuilder.parse_response("not json at all")
      assert {:error, :invalid_json} = PromptBuilder.parse_response("{broken json")
    end

    test "returns error for non-array JSON" do
      assert {:error, :invalid_format} = PromptBuilder.parse_response("{\"field\": \"value\"}")
      assert {:error, :invalid_format} = PromptBuilder.parse_response("\"just a string\"")
      assert {:error, :invalid_format} = PromptBuilder.parse_response("123")
    end

    test "filters out non-map items in array" do
      response = """
      [
        {"field": "phone", "value": "555-1234", "context": "Valid"},
        "not a map",
        123,
        null,
        {"field": "email", "value": "test@test.com", "context": "Also valid"}
      ]
      """

      assert {:ok, suggestions} = PromptBuilder.parse_response(response)
      assert length(suggestions) == 2
    end
  end
end

defmodule SocialScribe.AIContentGeneratorTest do
  use SocialScribe.DataCase, async: false

  alias SocialScribe.AIContentGenerator
  alias SocialScribe.Meetings

  import SocialScribe.MeetingsFixtures

  describe "generate_follow_up_email/1" do
    test "returns error when meeting has no participants" do
      meeting = meeting_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_follow_up_email(meeting)

      assert {:error, :no_participants} = result
    end

    test "returns error when meeting has no transcript but has participants" do
      meeting = meeting_fixture()
      _participant = meeting_participant_fixture(%{meeting_id: meeting.id})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_follow_up_email(meeting)

      assert {:error, :no_transcript} = result
    end

    test "returns error when gemini api key is missing" do
      # Temporarily remove the API key
      original_key = Application.get_env(:social_scribe, :gemini_api_key)
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      on_exit(fn ->
        Application.put_env(:social_scribe, :gemini_api_key, original_key)
      end)

      meeting = meeting_with_transcript_and_participants_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_follow_up_email(meeting)

      assert {:error, {:config_error, message}} = result
      assert message =~ "Gemini API key is missing"
    end
  end

  describe "generate_hubspot_suggestions/1" do
    test "returns error when meeting has no participants" do
      meeting = meeting_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_hubspot_suggestions(meeting)

      assert {:error, :no_participants} = result
    end

    test "returns error when meeting has no transcript but has participants" do
      meeting = meeting_fixture()
      _participant = meeting_participant_fixture(%{meeting_id: meeting.id})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_hubspot_suggestions(meeting)

      assert {:error, :no_transcript} = result
    end

    test "returns error when gemini api key is missing" do
      original_key = Application.get_env(:social_scribe, :gemini_api_key)
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      on_exit(fn ->
        Application.put_env(:social_scribe, :gemini_api_key, original_key)
      end)

      meeting = meeting_with_transcript_and_participants_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_hubspot_suggestions(meeting)

      assert {:error, {:config_error, _}} = result
    end
  end

  describe "generate_salesforce_suggestions/1" do
    test "returns error when meeting has no participants" do
      meeting = meeting_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_salesforce_suggestions(meeting)

      assert {:error, :no_participants} = result
    end

    test "returns error when meeting has no transcript but has participants" do
      meeting = meeting_fixture()
      _participant = meeting_participant_fixture(%{meeting_id: meeting.id})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_salesforce_suggestions(meeting)

      assert {:error, :no_transcript} = result
    end

    test "returns error when gemini api key is missing" do
      original_key = Application.get_env(:social_scribe, :gemini_api_key)
      Application.put_env(:social_scribe, :gemini_api_key, nil)

      on_exit(fn ->
        Application.put_env(:social_scribe, :gemini_api_key, original_key)
      end)

      meeting = meeting_with_transcript_and_participants_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      result = AIContentGenerator.generate_salesforce_suggestions(meeting)

      assert {:error, {:config_error, _}} = result
    end
  end

  describe "generate_automation/2" do
    test "returns error when meeting has no participants" do
      meeting = meeting_fixture()
      meeting = Meetings.get_meeting_with_details(meeting.id)

      automation = %SocialScribe.Automations.Automation{
        name: "Test",
        description: "Test description",
        platform: :linkedin,
        example: "Example post"
      }

      result = AIContentGenerator.generate_automation(automation, meeting)

      assert {:error, :no_participants} = result
    end

    test "returns error when meeting has no transcript but has participants" do
      meeting = meeting_fixture()
      _participant = meeting_participant_fixture(%{meeting_id: meeting.id})
      meeting = Meetings.get_meeting_with_details(meeting.id)

      automation = %SocialScribe.Automations.Automation{
        name: "Test",
        description: "Test description",
        platform: :linkedin,
        example: "Example post"
      }

      result = AIContentGenerator.generate_automation(automation, meeting)

      assert {:error, :no_transcript} = result
    end
  end

  # Helper to create a meeting with transcript and participants
  defp meeting_with_transcript_and_participants_fixture do
    meeting = meeting_fixture()

    _participant = meeting_participant_fixture(%{meeting_id: meeting.id, name: "John Doe"})

    _transcript =
      meeting_transcript_fixture(%{
        meeting_id: meeting.id,
        content: %{
          "data" => [
            %{
              "speaker" => "John Doe",
              "words" => [
                %{"text" => "Hello", "start_timestamp" => 0.0},
                %{"text" => "everyone", "start_timestamp" => 0.5}
              ]
            },
            %{
              "speaker" => "Jane Smith",
              "words" => [
                %{"text" => "Hi", "start_timestamp" => 2.0},
                %{"text" => "John", "start_timestamp" => 2.3}
              ]
            }
          ]
        }
      })

    meeting
  end
end

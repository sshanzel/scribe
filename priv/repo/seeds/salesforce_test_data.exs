# Salesforce Test Data Seed
#
# Creates test contacts in Salesforce and a mock meeting with transcript.
# Run with: mix run priv/repo/seeds/salesforce_test_data.exs
#
# Prerequisites:
# - User must be logged in and have Salesforce connected
# - Pass your user email as an argument or set it below

alias SocialScribe.Repo
alias SocialScribe.Accounts.Credentials
alias SocialScribe.Accounts.User
alias SocialScribe.Calendar.CalendarEvent
alias SocialScribe.Bots.RecallBot
alias SocialScribe.Meetings.{Meeting, MeetingParticipant, MeetingTranscript}
alias SocialScribe.CRM.Salesforce.Api, as: SalesforceApi

# Get user - change this to your email
user_email = System.get_env("SEED_USER_EMAIL") || "your-email@example.com"

user = Repo.get_by!(User, email: user_email)
IO.puts("Found user: #{user.email}")

credential = Credentials.get_user_salesforce_credential(user.id)

if is_nil(credential) do
  IO.puts("ERROR: No Salesforce credential found for user. Please connect Salesforce first.")
  System.halt(1)
end

IO.puts("Found Salesforce credential: #{credential.uid}")

# Create test contacts in Salesforce
test_contacts = [
  %{
    "FirstName" => "John",
    "LastName" => "TestContact",
    "Email" => "john.testcontact@example.com",
    "Phone" => "555-100-0001",
    "Title" => "Software Engineer",
    "Department" => "Engineering"
  },
  %{
    "FirstName" => "Sarah",
    "LastName" => "DemoUser",
    "Email" => "sarah.demouser@example.com",
    "Phone" => "555-200-0002",
    "MobilePhone" => "555-200-0003",
    "Title" => "Product Manager",
    "Department" => "Product"
  },
  %{
    "FirstName" => "Mike",
    "LastName" => "TestLead",
    "Email" => "mike.testlead@example.com",
    "Phone" => "555-300-0003",
    "Title" => "Sales Director",
    "Department" => "Sales"
  }
]

created_contacts =
  Enum.map(test_contacts, fn contact_data ->
    IO.puts("Creating contact: #{contact_data["FirstName"]} #{contact_data["LastName"]}...")

    case SalesforceApi.create_contact(credential, contact_data) do
      {:ok, contact} ->
        IO.puts("  Created with ID: #{contact.id}")
        contact

      {:error, reason} ->
        IO.puts("  ERROR: #{inspect(reason)}")
        nil
    end
  end)
  |> Enum.filter(&(&1 != nil))

IO.puts("\nCreated #{length(created_contacts)} contacts in Salesforce")

# Now create a test meeting with transcript that mentions updated info
IO.puts("\nCreating test meeting with transcript...")

# Create calendar event
{:ok, calendar_event} =
  %CalendarEvent{}
  |> CalendarEvent.changeset(%{
    google_event_id: "test-event-#{System.unique_integer([:positive])}",
    summary: "Sales Demo Call - Test Meeting",
    description: "Test meeting for Salesforce integration",
    status: "confirmed",
    html_link: "https://calendar.google.com/test",
    start_time: DateTime.utc_now() |> DateTime.add(-3600, :second),
    end_time: DateTime.utc_now(),
    user_id: user.id,
    user_credential_id: credential.id
  })
  |> Repo.insert()

IO.puts("Created calendar event: #{calendar_event.id}")

# Create recall bot
{:ok, recall_bot} =
  %RecallBot{}
  |> RecallBot.changeset(%{
    recall_bot_id: "test-bot-#{System.unique_integer([:positive])}",
    status: "done",
    meeting_url: "https://meet.google.com/test-meeting",
    user_id: user.id,
    calendar_event_id: calendar_event.id
  })
  |> Repo.insert()

IO.puts("Created recall bot: #{recall_bot.id}")

# Create meeting
{:ok, meeting} =
  %Meeting{}
  |> Meeting.changeset(%{
    title: "Sales Demo Call - Test Meeting",
    recorded_at: DateTime.utc_now() |> DateTime.add(-3600, :second),
    duration_seconds: 1800,
    calendar_event_id: calendar_event.id,
    recall_bot_id: recall_bot.id
  })
  |> Repo.insert()

IO.puts("Created meeting: #{meeting.id}")

# Create participants
participants_data = [
  %{name: "You (Host)", is_host: true},
  %{name: "John TestContact", is_host: false},
  %{name: "Sarah DemoUser", is_host: false}
]

Enum.each(participants_data, fn p ->
  {:ok, _} =
    %MeetingParticipant{}
    |> MeetingParticipant.changeset(%{
      recall_participant_id: "participant-#{System.unique_integer([:positive])}",
      name: p.name,
      is_host: p.is_host,
      meeting_id: meeting.id
    })
    |> Repo.insert()
end)

IO.puts("Created #{length(participants_data)} participants")

# Create transcript with contact info mentions
# This transcript contains NEW information that differs from what's in Salesforce
transcript_content = %{
  "data" => [
    %{
      "speaker" => "You (Host)",
      "words" => [
        %{"text" => "Thanks", "start_time" => 0.0},
        %{"text" => "for", "start_time" => 0.3},
        %{"text" => "joining", "start_time" => 0.5},
        %{"text" => "today.", "start_time" => 0.8}
      ]
    },
    %{
      "speaker" => "John TestContact",
      "words" => [
        %{"text" => "Happy", "start_time" => 2.0},
        %{"text" => "to", "start_time" => 2.2},
        %{"text" => "be", "start_time" => 2.3},
        %{"text" => "here.", "start_time" => 2.5},
        %{"text" => "By", "start_time" => 3.0},
        %{"text" => "the", "start_time" => 3.1},
        %{"text" => "way,", "start_time" => 3.2},
        %{"text" => "my", "start_time" => 3.4},
        %{"text" => "new", "start_time" => 3.5},
        %{"text" => "phone", "start_time" => 3.6},
        %{"text" => "number", "start_time" => 3.8},
        %{"text" => "is", "start_time" => 4.0},
        %{"text" => "555-999-8888.", "start_time" => 4.2}
      ]
    },
    %{
      "speaker" => "Sarah DemoUser",
      "words" => [
        %{"text" => "I", "start_time" => 10.0},
        %{"text" => "recently", "start_time" => 10.2},
        %{"text" => "got", "start_time" => 10.4},
        %{"text" => "promoted", "start_time" => 10.6},
        %{"text" => "to", "start_time" => 10.9},
        %{"text" => "VP", "start_time" => 11.0},
        %{"text" => "of", "start_time" => 11.2},
        %{"text" => "Product.", "start_time" => 11.4},
        %{"text" => "Also,", "start_time" => 12.0},
        %{"text" => "we", "start_time" => 12.2},
        %{"text" => "moved", "start_time" => 12.4},
        %{"text" => "to", "start_time" => 12.6},
        %{"text" => "Austin,", "start_time" => 12.8},
        %{"text" => "Texas.", "start_time" => 13.0}
      ]
    },
    %{
      "speaker" => "John TestContact",
      "words" => [
        %{"text" => "Congrats!", "start_time" => 15.0},
        %{"text" => "I'm", "start_time" => 15.5},
        %{"text" => "now", "start_time" => 15.7},
        %{"text" => "at", "start_time" => 15.9},
        %{"text" => "Acme", "start_time" => 16.0},
        %{"text" => "Corporation", "start_time" => 16.3},
        %{"text" => "as", "start_time" => 16.8},
        %{"text" => "a", "start_time" => 17.0},
        %{"text" => "Senior", "start_time" => 17.1},
        %{"text" => "Engineer.", "start_time" => 17.4}
      ]
    }
  ]
}

{:ok, _transcript} =
  %MeetingTranscript{}
  |> MeetingTranscript.changeset(%{
    content: transcript_content,
    language: "en",
    meeting_id: meeting.id
  })
  |> Repo.insert()

IO.puts("Created transcript with contact info mentions")

IO.puts("""

========================================
SEED COMPLETE!
========================================

Test meeting created: #{meeting.title}
Meeting ID: #{meeting.id}

View at: /dashboard/meetings/#{meeting.id}

The transcript contains mentions of:
- John's new phone: 555-999-8888
- John's new company: Acme Corporation
- John's new title: Senior Engineer
- Sarah's new title: VP of Product
- Sarah's new city: Austin, Texas

These differ from the Salesforce contact data, so the AI should suggest updates.
""")

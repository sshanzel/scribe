# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This seeds realistic meeting data for testing the chat feature.
# Flow: Salesforce contacts → Calendar events with attendees → Local contacts

# Load .env file if it exists (for SEED_USER_EMAIL)
if File.exists?(".env") do
  {:ok, envs} = Dotenvy.source(".env")
  Enum.each(envs, fn {key, value} -> System.put_env(key, value) end)
end

alias SocialScribe.Repo
alias SocialScribe.Accounts.{User, UserCredential}
alias SocialScribe.Calendar.CalendarEvent
alias SocialScribe.Bots.RecallBot
alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}
alias SocialScribe.Contacts
alias SocialScribe.SalesforceApi

# =============================================================================
# Configuration - Update these to match your test environment
# =============================================================================

# The email of the user you're logged in as (check your Google login)
user_email = System.get_env("SEED_USER_EMAIL") || "test@example.com"

# Sample contacts - will be created in Salesforce first, then locally
contacts_data = [
  %{
    first_name: "Sarah",
    last_name: "Chen",
    email: "sarah.chen@techcorp.io",
    phone: "415-555-0123",
    title: "Head of Product"
  },
  %{
    first_name: "Marcus",
    last_name: "Johnson",
    email: "marcus.j@innovate.co",
    phone: "628-555-0456",
    title: "VP of Partnerships"
  },
  %{
    first_name: "Emily",
    last_name: "Rodriguez",
    email: "emily.r@startup.dev",
    phone: "510-555-0789",
    title: "CTO"
  },
  %{
    first_name: "David",
    last_name: "Kim",
    email: "david.kim@enterprise.com",
    phone: "408-555-0234",
    title: "Security Director"
  },
  %{
    first_name: "Lisa",
    last_name: "Thompson",
    email: "lisa.t@consulting.biz",
    phone: "917-555-0890",
    title: "Managing Partner"
  }
]

# =============================================================================
# Helper Functions
# =============================================================================

defmodule SeedHelpers do
  def generate_transcript(host_name, guest_name, topic, details) do
    segments = [
      {host_name,
       "Hi #{guest_name}, thanks for joining today's call. I wanted to discuss #{topic}."},
      {guest_name, "Thanks for having me! Yes, I've been looking forward to this discussion."},
      {host_name, "Great. So let's dive in. #{details[:question]}"},
      {guest_name, details[:answer]},
      {host_name, details[:followup]},
      {guest_name, details[:response]},
      {host_name, "That's really helpful. What about #{details[:topic2]}?"},
      {guest_name, details[:topic2_response]},
      {host_name,
       "Perfect. Let me note down your contact details. What's the best way to reach you?"},
      {guest_name, details[:contact_info]},
      {host_name,
       "Got it. Thanks so much for your time today, #{guest_name}. I'll follow up with next steps."},
      {guest_name, "Sounds great! Looking forward to it. Have a great day!"}
    ]

    {data, _final_time} =
      Enum.map_reduce(segments, 0.0, fn {speaker, text}, current_time ->
        {words, end_time} = words_to_list_with_timestamps(text, current_time)
        segment = %{"speaker" => speaker, "words" => words}
        # Add 2 seconds gap between segments
        {segment, end_time + 2.0}
      end)

    %{"data" => data}
  end

  defp words_to_list_with_timestamps(sentence, start_time) do
    words = String.split(sentence, " ")
    # Average speaking rate: ~2.5 words per second
    word_duration = 0.4

    {word_list, end_time} =
      Enum.map_reduce(words, start_time, fn word, current_time ->
        word_map = %{
          "text" => word,
          "start_timestamp" => current_time,
          "end_timestamp" => current_time + word_duration
        }

        {word_map, current_time + word_duration}
      end)

    {word_list, end_time}
  end
end

# =============================================================================
# Find or Create User
# =============================================================================

IO.puts("🔍 Looking for user with email: #{user_email}")

user =
  case Repo.get_by(User, email: user_email) do
    nil ->
      IO.puts("⚠️  User not found. Creating a test user...")

      {:ok, user} =
        %User{}
        |> User.registration_changeset(%{email: user_email, password: "password123456"})
        |> Repo.insert()

      user

    existing_user ->
      IO.puts("✅ Found existing user: #{existing_user.email}")
      existing_user
  end

# =============================================================================
# Ensure Google Credential Exists
# =============================================================================

google_credential =
  case Repo.get_by(UserCredential, user_id: user.id, provider: "google") do
    nil ->
      IO.puts("📝 Creating Google credential for user...")

      {:ok, cred} =
        %UserCredential{}
        |> UserCredential.changeset(%{
          provider: "google",
          uid: "seed_google_#{user.id}",
          token: "seed_token_#{:rand.uniform(100_000)}",
          refresh_token: "seed_refresh_token",
          expires_at: DateTime.add(DateTime.utc_now(), 30, :day),
          user_id: user.id,
          email: user_email
        })
        |> Repo.insert()

      cred

    existing ->
      IO.puts("✅ Found existing Google credential")
      existing
  end

# =============================================================================
# Find Salesforce Credential
# =============================================================================

salesforce_credential =
  case Repo.get_by(UserCredential, user_id: user.id, provider: "salesforce") do
    nil ->
      IO.puts("\n⚠️  No Salesforce credential found for user.")
      IO.puts("   Please connect Salesforce in Settings first, then re-run seeds.")
      IO.puts("   Skipping Salesforce contact creation...")
      nil

    cred ->
      IO.puts("✅ Found Salesforce credential")
      cred
  end

# =============================================================================
# Create Contacts in Salesforce (Source of Truth)
# =============================================================================

contacts =
  if salesforce_credential do
    IO.puts("\n☁️  Creating contacts in Salesforce...")

    Enum.map(contacts_data, fn contact_attrs ->
      full_name = "#{contact_attrs.first_name} #{contact_attrs.last_name}"

      # First check if contact already exists by email
      case SalesforceApi.search_contacts(salesforce_credential, contact_attrs.email) do
        {:ok, [existing | _]} ->
          IO.puts("  ⏭️  Already exists in Salesforce: #{full_name} <#{contact_attrs.email}>")
          Map.merge(contact_attrs, %{name: full_name, salesforce_id: existing.id})

        {:ok, []} ->
          # Contact doesn't exist, create it
          salesforce_data = %{
            "FirstName" => contact_attrs.first_name,
            "LastName" => contact_attrs.last_name,
            "Email" => contact_attrs.email,
            "Phone" => contact_attrs.phone,
            "Title" => contact_attrs.title
          }

          case SalesforceApi.create_contact(salesforce_credential, salesforce_data) do
            {:ok, sf_contact} ->
              IO.puts("  ✅ Created in Salesforce: #{full_name} <#{contact_attrs.email}>")
              Map.merge(contact_attrs, %{name: full_name, salesforce_id: sf_contact.id})

            {:error, reason} ->
              IO.puts("  ❌ Failed to create in Salesforce: #{full_name} - #{inspect(reason)}")
              Map.put(contact_attrs, :name, full_name)
          end

        {:error, reason} ->
          IO.puts("  ⚠️  Could not search Salesforce: #{inspect(reason)}")
          Map.put(contact_attrs, :name, full_name)
      end
    end)
  else
    # No Salesforce credential - just use local data
    Enum.map(contacts_data, fn contact_attrs ->
      Map.put(contact_attrs, :name, "#{contact_attrs.first_name} #{contact_attrs.last_name}")
    end)
  end

# =============================================================================
# Meeting Data (references Salesforce contacts by index)
# =============================================================================

meetings_data = [
  %{
    # Sarah Chen
    contact: Enum.at(contacts, 0),
    title: "Q1 Product Roadmap Review",
    days_ago: 3,
    duration: 45,
    transcript_details: %{
      question: "Can you walk me through the key features you're planning for Q1?",
      answer:
        "Absolutely. We're focusing on three main areas: improving our API performance, launching the new dashboard redesign, and rolling out the mobile app beta. The API improvements should give us about 40% faster response times.",
      followup: "That sounds ambitious. What's the timeline looking like?",
      response:
        "We're aiming to have the API updates done by end of January, dashboard by mid-February, and mobile beta by March 15th. We've already completed about 60% of the API work.",
      topic2: "the team structure for this",
      topic2_response:
        "We've got 3 engineers on the API team, 2 on dashboard, and 4 on mobile. I'm leading the mobile effort directly. We also brought in a new UX designer, Jennifer, specifically for the dashboard project.",
      contact_info:
        "Best to reach me on my cell at 415-555-0123, or you can email me at sarah.chen@techcorp.io. I usually respond within a few hours during business hours."
    }
  },
  %{
    # Marcus Johnson
    contact: Enum.at(contacts, 1),
    title: "Partnership Discussion - Innovate Co",
    days_ago: 7,
    duration: 60,
    transcript_details: %{
      question: "What kind of partnership are you envisioning between our companies?",
      answer:
        "We see a strategic integration opportunity. Our analytics platform could plug directly into your workflow tools. We've done similar integrations with Acme Corp and saw their user engagement increase by 35%.",
      followup: "Interesting. What would the technical integration look like?",
      response:
        "We'd use your REST API to sync data in real-time. Our team has already reviewed your documentation. We estimate about 3 weeks for a basic integration, 6 weeks for the full feature set.",
      topic2: "the commercial terms",
      topic2_response:
        "We're thinking a revenue share model - 15% of any upsells that come through the integration. We'd also co-market the solution. Our marketing budget for partnerships is around $50,000 per quarter.",
      contact_info:
        "My direct line is 628-555-0456. I'm also on LinkedIn - just search Marcus Johnson Innovate. My assistant Rachel can also help schedule follow-ups, she's at rachel@innovate.co."
    }
  },
  %{
    # Emily Rodriguez
    contact: Enum.at(contacts, 2),
    title: "Technical Architecture Review",
    days_ago: 14,
    duration: 90,
    transcript_details: %{
      question: "Can you explain the current pain points with your architecture?",
      answer:
        "Our biggest issue is scalability. We're hitting database bottlenecks at around 10,000 concurrent users. We're on PostgreSQL but haven't implemented proper connection pooling or read replicas yet.",
      followup: "Have you considered any specific solutions?",
      response:
        "We've looked at PgBouncer for connection pooling and potentially moving to a distributed database like CockroachDB for the long term. Short term, we need to optimize our queries - some are taking 5+ seconds.",
      topic2: "your deployment infrastructure",
      topic2_response:
        "We're on AWS, using ECS for containers. We've got about 15 microservices, but honestly, we probably over-engineered it. Thinking of consolidating to maybe 5-6 services. Our AWS bill is around $25,000/month.",
      contact_info:
        "You can reach me at emily.r@startup.dev or on my cell 510-555-0789. I'm usually in meetings from 10am to 2pm Pacific, so mornings are best for calls."
    }
  },
  %{
    # David Kim
    contact: Enum.at(contacts, 3),
    title: "Enterprise Security Assessment",
    days_ago: 21,
    duration: 75,
    transcript_details: %{
      question: "What are your primary security concerns for this deployment?",
      answer:
        "We need SOC 2 Type II compliance before we can proceed. Our security team also requires SSO integration with Okta and detailed audit logging for all data access.",
      followup:
        "We can definitely support those requirements. What's the timeline for your security review?",
      response:
        "Our CISO needs to sign off, which typically takes 4-6 weeks. We'll need your security questionnaire completed and a penetration test report from the last 12 months.",
      topic2: "data residency requirements",
      topic2_response:
        "All data must stay within US data centers. We have customers in regulated industries - healthcare and finance - so HIPAA and SOX compliance documentation would be helpful too.",
      contact_info:
        "Best to go through our procurement team for official communications - procurement@enterprise.com. But you can reach me directly at david.kim@enterprise.com or 408-555-0234 for technical questions."
    }
  },
  %{
    # Lisa Thompson
    contact: Enum.at(contacts, 4),
    title: "Consulting Engagement Kickoff",
    days_ago: 5,
    duration: 30,
    transcript_details: %{
      question: "What are the main goals for this consulting engagement?",
      answer:
        "We need help with our go-to-market strategy for the European expansion. Specifically, localization, compliance with GDPR, and building partnerships with local resellers in Germany and France.",
      followup: "What's your current presence in Europe?",
      response:
        "Minimal right now - about 50 customers, mostly in the UK. We've got a small sales team in London but no dedicated European operations. Revenue from Europe is about $200K ARR.",
      topic2: "the budget and timeline",
      topic2_response:
        "We've allocated $150,000 for the consulting engagement over 6 months. We want to have our German entity set up by Q2 and first local hires by Q3.",
      contact_info:
        "My office number is 212-555-0567, but I travel a lot. Best to text my mobile at 917-555-0890 or email lisa.t@consulting.biz. I check emails even on weekends."
    }
  },
  %{
    # Sarah Chen - Second meeting
    contact: Enum.at(contacts, 0),
    title: "Follow-up: Mobile App Beta Feedback",
    days_ago: 1,
    duration: 30,
    transcript_details: %{
      question: "How's the beta testing going so far?",
      answer:
        "Really well! We've got 500 beta users now and the feedback is mostly positive. Main complaints are around the onboarding flow - it's too long. We're cutting it from 8 screens to 4.",
      followup: "Any critical bugs?",
      response:
        "A few crashes on older Android devices, specifically Samsung Galaxy S9 and earlier. We're prioritizing those fixes. iOS has been rock solid.",
      topic2: "the launch timeline",
      topic2_response:
        "Still on track for March 15th. We'll do a soft launch first - 10% of users - then ramp up over 2 weeks. Marketing has prepared the app store assets and press release.",
      contact_info:
        "Same as before - 415-555-0123. Oh, and I changed my email to sarah@techcorp.io - dropped the dot in the middle. Either one works though."
    }
  }
]

# =============================================================================
# Create Meetings with Full Data
# =============================================================================

IO.puts("\n📅 Creating meetings with transcripts...")

Enum.each(meetings_data, fn meeting_data ->
  contact = meeting_data.contact
  contact_name = contact[:name]
  contact_email = contact[:email]
  start_time = DateTime.add(DateTime.utc_now(), -meeting_data.days_ago, :day)
  end_time = DateTime.add(start_time, meeting_data.duration, :minute)

  # Create Calendar Event (without attendees field - it's now a join table)
  {:ok, calendar_event} =
    %CalendarEvent{}
    |> CalendarEvent.changeset(%{
      google_event_id: "seed_event_#{:rand.uniform(1_000_000)}",
      summary: meeting_data.title,
      description: "Meeting with #{contact_name}",
      html_link: "https://calendar.google.com/calendar/event?eid=seed",
      hangout_link: "https://meet.google.com/abc-defg-hij",
      status: "confirmed",
      start_time: start_time,
      end_time: end_time,
      record_meeting: true,
      user_id: user.id,
      user_credential_id: google_credential.id
    })
    |> Repo.insert()

  # Create attendee records (links contacts to calendar events)
  attendees_data = [
    %{
      "email" => user_email,
      "displayName" => "You",
      "responseStatus" => "accepted",
      "organizer" => true
    },
    %{"email" => contact_email, "displayName" => contact_name, "responseStatus" => "accepted"}
  ]

  Contacts.create_attendees_from_event_data(calendar_event.id, attendees_data)

  # Create Recall Bot
  {:ok, recall_bot} =
    %RecallBot{}
    |> RecallBot.changeset(%{
      recall_bot_id: "seed_bot_#{:rand.uniform(1_000_000)}",
      status: "done",
      meeting_url: "https://meet.google.com/abc-defg-hij",
      user_id: user.id,
      calendar_event_id: calendar_event.id
    })
    |> Repo.insert()

  # Create Meeting
  {:ok, meeting} =
    %Meeting{}
    |> Meeting.changeset(%{
      title: meeting_data.title,
      recorded_at: start_time,
      duration_seconds: meeting_data.duration * 60,
      calendar_event_id: calendar_event.id,
      recall_bot_id: recall_bot.id
    })
    |> Repo.insert()

  # Create Meeting Transcript
  transcript_content =
    SeedHelpers.generate_transcript(
      "You",
      contact_name,
      meeting_data.title,
      meeting_data.transcript_details
    )

  {:ok, _transcript} =
    %MeetingTranscript{}
    |> MeetingTranscript.changeset(%{
      content: transcript_content,
      language: "en",
      meeting_id: meeting.id
    })
    |> Repo.insert()

  # Create Meeting Participants
  {:ok, _host} =
    %MeetingParticipant{}
    |> MeetingParticipant.changeset(%{
      recall_participant_id: "seed_participant_host_#{:rand.uniform(1_000_000)}",
      name: "You",
      is_host: true,
      meeting_id: meeting.id
    })
    |> Repo.insert()

  {:ok, _guest} =
    %MeetingParticipant{}
    |> MeetingParticipant.changeset(%{
      recall_participant_id: "seed_participant_guest_#{:rand.uniform(1_000_000)}",
      name: contact_name,
      is_host: false,
      meeting_id: meeting.id
    })
    |> Repo.insert()

  IO.puts("  ✅ Created meeting: #{meeting_data.title} (#{meeting_data.days_ago} days ago)")
end)

# =============================================================================
# Summary
# =============================================================================

# Count contacts created through attendee records
contact_count = Repo.aggregate(SocialScribe.Contacts.Contact, :count, :id)

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🎉 Seed data created successfully!")
IO.puts(String.duplicate("=", 60))
IO.puts("\nCreated:")
IO.puts("  • #{length(contacts)} contacts in Salesforce (if credential exists)")
IO.puts("  • #{length(meetings_data)} meetings with transcripts")
IO.puts("  • #{contact_count} contacts (from calendar attendees)")

IO.puts("\nTo test the chat feature:")
IO.puts("  1. Open the chat bubble in the dashboard")
IO.puts("  2. Start a new chat")
IO.puts("  3. Type @ and select a contact (e.g., Sarah Chen)")
IO.puts("  4. Ask questions like:")
IO.puts("     - \"What was discussed in our last meeting?\"")
IO.puts("     - \"What is Sarah's phone number?\"")
IO.puts("     - \"What are the Q1 product priorities?\"")
IO.puts("\n💡 Tip: Set SEED_USER_EMAIL in your .env file to your actual login email:")
IO.puts("   SEED_USER_EMAIL=your@email.com")

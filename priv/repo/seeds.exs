# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# This seeds realistic meeting data for testing the chat feature.

alias SocialScribe.Repo
alias SocialScribe.Accounts.{User, UserCredential}
alias SocialScribe.Calendar.CalendarEvent
alias SocialScribe.Bots.RecallBot
alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}
alias SocialScribe.Contacts.Contact

# =============================================================================
# Configuration - Update these to match your test environment
# =============================================================================

# The email of the user you're logged in as (check your Google login)
user_email = System.get_env("SEED_USER_EMAIL") || "test@example.com"

# Sample contacts - these should match emails in your Salesforce/HubSpot
contacts_data = [
  %{name: "Sarah Chen", email: "sarah.chen@techcorp.io"},
  %{name: "Marcus Johnson", email: "marcus.j@innovate.co"},
  %{name: "Emily Rodriguez", email: "emily.r@startup.dev"},
  %{name: "David Kim", email: "david.kim@enterprise.com"},
  %{name: "Lisa Thompson", email: "lisa.t@consulting.biz"}
]

# =============================================================================
# Helper Functions
# =============================================================================

defmodule SeedHelpers do
  def generate_transcript(host_name, guest_name, topic, details) do
    %{
      "data" => [
        %{
          "speaker" => host_name,
          "words" => words_to_list("Hi #{guest_name}, thanks for joining today's call. I wanted to discuss #{topic}.")
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list("Thanks for having me! Yes, I've been looking forward to this discussion.")
        },
        %{
          "speaker" => host_name,
          "words" => words_to_list("Great. So let's dive in. #{details[:question]}")
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list(details[:answer])
        },
        %{
          "speaker" => host_name,
          "words" => words_to_list(details[:followup])
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list(details[:response])
        },
        %{
          "speaker" => host_name,
          "words" => words_to_list("That's really helpful. What about #{details[:topic2]}?")
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list(details[:topic2_response])
        },
        %{
          "speaker" => host_name,
          "words" => words_to_list("Perfect. Let me note down your contact details. What's the best way to reach you?")
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list(details[:contact_info])
        },
        %{
          "speaker" => host_name,
          "words" => words_to_list("Got it. Thanks so much for your time today, #{guest_name}. I'll follow up with next steps.")
        },
        %{
          "speaker" => guest_name,
          "words" => words_to_list("Sounds great! Looking forward to it. Have a great day!")
        }
      ]
    }
  end

  defp words_to_list(sentence) do
    sentence
    |> String.split(" ")
    |> Enum.map(&%{"text" => &1})
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
# Create Contacts
# =============================================================================

IO.puts("\n📇 Creating contacts...")

contacts =
  Enum.map(contacts_data, fn contact_attrs ->
    case Repo.get_by(Contact, user_id: user.id, email: contact_attrs.email) do
      nil ->
        {:ok, contact} =
          %Contact{}
          |> Contact.changeset(Map.put(contact_attrs, :user_id, user.id))
          |> Repo.insert()
        IO.puts("  ✅ Created contact: #{contact.name} <#{contact.email}>")
        contact

      existing ->
        IO.puts("  ⏭️  Contact exists: #{existing.name} <#{existing.email}>")
        existing
    end
  end)

# =============================================================================
# Meeting Data
# =============================================================================

meetings_data = [
  %{
    contact: Enum.at(contacts, 0),  # Sarah Chen
    title: "Q1 Product Roadmap Review",
    days_ago: 3,
    duration: 45,
    transcript_details: %{
      question: "Can you walk me through the key features you're planning for Q1?",
      answer: "Absolutely. We're focusing on three main areas: improving our API performance, launching the new dashboard redesign, and rolling out the mobile app beta. The API improvements should give us about 40% faster response times.",
      followup: "That sounds ambitious. What's the timeline looking like?",
      response: "We're aiming to have the API updates done by end of January, dashboard by mid-February, and mobile beta by March 15th. We've already completed about 60% of the API work.",
      topic2: "the team structure for this",
      topic2_response: "We've got 3 engineers on the API team, 2 on dashboard, and 4 on mobile. I'm leading the mobile effort directly. We also brought in a new UX designer, Jennifer, specifically for the dashboard project.",
      contact_info: "Best to reach me on my cell at 415-555-0123, or you can email me at sarah.chen@techcorp.io. I usually respond within a few hours during business hours."
    }
  },
  %{
    contact: Enum.at(contacts, 1),  # Marcus Johnson
    title: "Partnership Discussion - Innovate Co",
    days_ago: 7,
    duration: 60,
    transcript_details: %{
      question: "What kind of partnership are you envisioning between our companies?",
      answer: "We see a strategic integration opportunity. Our analytics platform could plug directly into your workflow tools. We've done similar integrations with Acme Corp and saw their user engagement increase by 35%.",
      followup: "Interesting. What would the technical integration look like?",
      response: "We'd use your REST API to sync data in real-time. Our team has already reviewed your documentation. We estimate about 3 weeks for a basic integration, 6 weeks for the full feature set.",
      topic2: "the commercial terms",
      topic2_response: "We're thinking a revenue share model - 15% of any upsells that come through the integration. We'd also co-market the solution. Our marketing budget for partnerships is around $50,000 per quarter.",
      contact_info: "My direct line is 628-555-0456. I'm also on LinkedIn - just search Marcus Johnson Innovate. My assistant Rachel can also help schedule follow-ups, she's at rachel@innovate.co."
    }
  },
  %{
    contact: Enum.at(contacts, 2),  # Emily Rodriguez
    title: "Technical Architecture Review",
    days_ago: 14,
    duration: 90,
    transcript_details: %{
      question: "Can you explain the current pain points with your architecture?",
      answer: "Our biggest issue is scalability. We're hitting database bottlenecks at around 10,000 concurrent users. We're on PostgreSQL but haven't implemented proper connection pooling or read replicas yet.",
      followup: "Have you considered any specific solutions?",
      response: "We've looked at PgBouncer for connection pooling and potentially moving to a distributed database like CockroachDB for the long term. Short term, we need to optimize our queries - some are taking 5+ seconds.",
      topic2: "your deployment infrastructure",
      topic2_response: "We're on AWS, using ECS for containers. We've got about 15 microservices, but honestly, we probably over-engineered it. Thinking of consolidating to maybe 5-6 services. Our AWS bill is around $25,000/month.",
      contact_info: "You can reach me at emily.r@startup.dev or on my cell 510-555-0789. I'm usually in meetings from 10am to 2pm Pacific, so mornings are best for calls."
    }
  },
  %{
    contact: Enum.at(contacts, 3),  # David Kim
    title: "Enterprise Security Assessment",
    days_ago: 21,
    duration: 75,
    transcript_details: %{
      question: "What are your primary security concerns for this deployment?",
      answer: "We need SOC 2 Type II compliance before we can proceed. Our security team also requires SSO integration with Okta and detailed audit logging for all data access.",
      followup: "We can definitely support those requirements. What's the timeline for your security review?",
      response: "Our CISO needs to sign off, which typically takes 4-6 weeks. We'll need your security questionnaire completed and a penetration test report from the last 12 months.",
      topic2: "data residency requirements",
      topic2_response: "All data must stay within US data centers. We have customers in regulated industries - healthcare and finance - so HIPAA and SOX compliance documentation would be helpful too.",
      contact_info: "Best to go through our procurement team for official communications - procurement@enterprise.com. But you can reach me directly at david.kim@enterprise.com or 408-555-0234 for technical questions."
    }
  },
  %{
    contact: Enum.at(contacts, 4),  # Lisa Thompson
    title: "Consulting Engagement Kickoff",
    days_ago: 5,
    duration: 30,
    transcript_details: %{
      question: "What are the main goals for this consulting engagement?",
      answer: "We need help with our go-to-market strategy for the European expansion. Specifically, localization, compliance with GDPR, and building partnerships with local resellers in Germany and France.",
      followup: "What's your current presence in Europe?",
      response: "Minimal right now - about 50 customers, mostly in the UK. We've got a small sales team in London but no dedicated European operations. Revenue from Europe is about $200K ARR.",
      topic2: "the budget and timeline",
      topic2_response: "We've allocated $150,000 for the consulting engagement over 6 months. We want to have our German entity set up by Q2 and first local hires by Q3.",
      contact_info: "My office number is 212-555-0567, but I travel a lot. Best to text my mobile at 917-555-0890 or email lisa.t@consulting.biz. I check emails even on weekends."
    }
  },
  %{
    contact: Enum.at(contacts, 0),  # Sarah Chen - Second meeting
    title: "Follow-up: Mobile App Beta Feedback",
    days_ago: 1,
    duration: 30,
    transcript_details: %{
      question: "How's the beta testing going so far?",
      answer: "Really well! We've got 500 beta users now and the feedback is mostly positive. Main complaints are around the onboarding flow - it's too long. We're cutting it from 8 screens to 4.",
      followup: "Any critical bugs?",
      response: "A few crashes on older Android devices, specifically Samsung Galaxy S9 and earlier. We're prioritizing those fixes. iOS has been rock solid.",
      topic2: "the launch timeline",
      topic2_response: "Still on track for March 15th. We'll do a soft launch first - 10% of users - then ramp up over 2 weeks. Marketing has prepared the app store assets and press release.",
      contact_info: "Same as before - 415-555-0123. Oh, and I changed my email to sarah@techcorp.io - dropped the dot in the middle. Either one works though."
    }
  }
]

# =============================================================================
# Create Meetings with Full Data
# =============================================================================

IO.puts("\n📅 Creating meetings with transcripts...")

Enum.each(meetings_data, fn meeting_data ->
  contact = meeting_data.contact
  start_time = DateTime.add(DateTime.utc_now(), -meeting_data.days_ago, :day)
  end_time = DateTime.add(start_time, meeting_data.duration, :minute)

  # Create Calendar Event
  {:ok, calendar_event} =
    %CalendarEvent{}
    |> CalendarEvent.changeset(%{
      google_event_id: "seed_event_#{:rand.uniform(1_000_000)}",
      summary: meeting_data.title,
      description: "Meeting with #{contact.name}",
      html_link: "https://calendar.google.com/calendar/event?eid=seed",
      hangout_link: "https://meet.google.com/abc-defg-hij",
      status: "confirmed",
      start_time: start_time,
      end_time: end_time,
      record_meeting: true,
      attendees: [
        %{"email" => user_email, "displayName" => "You", "responseStatus" => "accepted"},
        %{"email" => contact.email, "displayName" => contact.name, "responseStatus" => "accepted"}
      ],
      user_id: user.id,
      user_credential_id: google_credential.id
    })
    |> Repo.insert()

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
  transcript_content = SeedHelpers.generate_transcript(
    "You",
    contact.name,
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
      name: contact.name,
      is_host: false,
      meeting_id: meeting.id
    })
    |> Repo.insert()

  IO.puts("  ✅ Created meeting: #{meeting_data.title} (#{meeting_data.days_ago} days ago)")
end)

# =============================================================================
# Summary
# =============================================================================

IO.puts("\n" <> String.duplicate("=", 60))
IO.puts("🎉 Seed data created successfully!")
IO.puts(String.duplicate("=", 60))
IO.puts("\nCreated:")
IO.puts("  • #{length(contacts)} contacts")
IO.puts("  • #{length(meetings_data)} meetings with transcripts")
IO.puts("\nTo test the chat feature:")
IO.puts("  1. Open the chat bubble in the dashboard")
IO.puts("  2. Start a new chat")
IO.puts("  3. Type @ and select a contact (e.g., Sarah Chen)")
IO.puts("  4. Ask questions like:")
IO.puts("     - \"What was discussed in our last meeting?\"")
IO.puts("     - \"What is Sarah's phone number?\"")
IO.puts("     - \"What are the Q1 product priorities?\"")
IO.puts("\n💡 Tip: Set SEED_USER_EMAIL to your actual login email:")
IO.puts("   SEED_USER_EMAIL=your@email.com mix run priv/repo/seeds.exs")

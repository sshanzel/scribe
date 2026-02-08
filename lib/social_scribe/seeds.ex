defmodule SocialScribe.Seeds do
  @moduledoc """
  Programmatic seeding for demo/testing purposes.
  Creates sample meetings with transcripts for a given user.
  """

  alias SocialScribe.Repo
  alias SocialScribe.Accounts.{User, UserCredential}
  alias SocialScribe.Calendar.CalendarEvent
  alias SocialScribe.Bots.RecallBot
  alias SocialScribe.Meetings.{Meeting, MeetingTranscript, MeetingParticipant}
  alias SocialScribe.Contacts
  alias SocialScribe.CRM.Salesforce.Api, as: SalesforceApi

  @contacts_data [
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

  @doc """
  Seeds demo data for the given user.

  Creates:
  - Contacts in Salesforce (if credential exists)
  - Local contacts via calendar attendees
  - Meetings with realistic transcripts
  - Meeting participants

  Returns `{:ok, summary}` or `{:error, reason}`.
  """
  @spec run(User.t()) :: {:ok, map()}
  def run(%User{} = user) do
    # Ensure Google credential exists
    google_credential = ensure_google_credential(user)

    # Check for Salesforce credential
    salesforce_credential = get_salesforce_credential(user)

    # Create contacts (in Salesforce if available)
    contacts = create_contacts(salesforce_credential)

    # Build meetings data
    meetings_data = build_meetings_data(contacts)

    # Create meetings
    created_meetings =
      Enum.map(meetings_data, fn meeting_data ->
        create_meeting(user, google_credential, meeting_data)
      end)

    {:ok,
     %{
       contacts_count: length(contacts),
       meetings_count: length(created_meetings),
       salesforce_connected: salesforce_credential != nil
     }}
  end

  defp ensure_google_credential(%User{} = user) do
    case Repo.get_by(UserCredential, user_id: user.id, provider: "google") do
      nil ->
        {:ok, cred} =
          %UserCredential{}
          |> UserCredential.changeset(%{
            provider: "google",
            uid: "seed_google_#{user.id}",
            token: "seed_token_#{:rand.uniform(100_000)}",
            refresh_token: "seed_refresh_token",
            expires_at: DateTime.add(DateTime.utc_now(), 30, :day),
            user_id: user.id,
            email: user.email
          })
          |> Repo.insert()

        cred

      existing ->
        existing
    end
  end

  defp get_salesforce_credential(%User{} = user) do
    Repo.get_by(UserCredential, user_id: user.id, provider: "salesforce")
  end

  defp create_contacts(nil) do
    # No Salesforce credential - just use local data
    Enum.map(@contacts_data, fn contact_attrs ->
      Map.put(contact_attrs, :name, "#{contact_attrs.first_name} #{contact_attrs.last_name}")
    end)
  end

  defp create_contacts(salesforce_credential) do
    Enum.map(@contacts_data, fn contact_attrs ->
      full_name = "#{contact_attrs.first_name} #{contact_attrs.last_name}"

      case SalesforceApi.search_contacts(salesforce_credential, contact_attrs.email) do
        {:ok, [existing | _]} ->
          Map.merge(contact_attrs, %{name: full_name, salesforce_id: existing.id})

        {:ok, []} ->
          salesforce_data = %{
            "FirstName" => contact_attrs.first_name,
            "LastName" => contact_attrs.last_name,
            "Email" => contact_attrs.email,
            "Phone" => contact_attrs.phone,
            "Title" => contact_attrs.title
          }

          case SalesforceApi.create_contact(salesforce_credential, salesforce_data) do
            {:ok, sf_contact} ->
              Map.merge(contact_attrs, %{name: full_name, salesforce_id: sf_contact.id})

            {:error, _reason} ->
              Map.put(contact_attrs, :name, full_name)
          end

        {:error, _reason} ->
          Map.put(contact_attrs, :name, full_name)
      end
    end)
  end

  defp build_meetings_data(contacts) do
    [
      %{
        contact: Enum.at(contacts, 0),
        title: "Q1 Product Roadmap Review",
        days_ago: 3,
        duration: 45,
        transcript_details: %{
          question: "Can you walk me through the key features you're planning for Q1?",
          answer:
            "Absolutely. We're focusing on three main areas: improving our API performance, launching the new dashboard redesign, and rolling out the mobile app beta.",
          followup: "That sounds ambitious. What's the timeline looking like?",
          response:
            "We're aiming to have the API updates done by end of January, dashboard by mid-February, and mobile beta by March 15th.",
          topic2: "the team structure for this",
          topic2_response:
            "We've got 3 engineers on the API team, 2 on dashboard, and 4 on mobile. I'm leading the mobile effort directly.",
          contact_info:
            "Best to reach me on my cell at 415-555-0123, or you can email me at sarah.chen@techcorp.io."
        }
      },
      %{
        contact: Enum.at(contacts, 1),
        title: "Partnership Discussion - Innovate Co",
        days_ago: 7,
        duration: 60,
        transcript_details: %{
          question: "What kind of partnership are you envisioning between our companies?",
          answer:
            "We see a strategic integration opportunity. Our analytics platform could plug directly into your workflow tools.",
          followup: "Interesting. What would the technical integration look like?",
          response:
            "We'd use your REST API to sync data in real-time. We estimate about 3 weeks for a basic integration.",
          topic2: "the commercial terms",
          topic2_response:
            "We're thinking a revenue share model - 15% of any upsells that come through the integration.",
          contact_info:
            "My direct line is 628-555-0456. I'm also on LinkedIn - just search Marcus Johnson Innovate."
        }
      },
      %{
        contact: Enum.at(contacts, 2),
        title: "Technical Architecture Review",
        days_ago: 14,
        duration: 90,
        transcript_details: %{
          question: "Can you explain the current pain points with your architecture?",
          answer:
            "Our biggest issue is scalability. We're hitting database bottlenecks at around 10,000 concurrent users.",
          followup: "Have you considered any specific solutions?",
          response:
            "We've looked at PgBouncer for connection pooling and potentially moving to a distributed database.",
          topic2: "your deployment infrastructure",
          topic2_response:
            "We're on AWS, using ECS for containers. Our AWS bill is around $25,000/month.",
          contact_info: "You can reach me at emily.r@startup.dev or on my cell 510-555-0789."
        }
      },
      %{
        contact: Enum.at(contacts, 3),
        title: "Enterprise Security Assessment",
        days_ago: 21,
        duration: 75,
        transcript_details: %{
          question: "What are your primary security concerns for this deployment?",
          answer:
            "We need SOC 2 Type II compliance before we can proceed. Our security team also requires SSO integration with Okta.",
          followup:
            "We can definitely support those requirements. What's the timeline for your security review?",
          response: "Our CISO needs to sign off, which typically takes 4-6 weeks.",
          topic2: "data residency requirements",
          topic2_response:
            "All data must stay within US data centers. We have customers in regulated industries.",
          contact_info:
            "Best to go through our procurement team. But you can reach me directly at david.kim@enterprise.com or 408-555-0234."
        }
      },
      %{
        contact: Enum.at(contacts, 4),
        title: "Consulting Engagement Kickoff",
        days_ago: 5,
        duration: 30,
        transcript_details: %{
          question: "What are the main goals for this consulting engagement?",
          answer: "We need help with our go-to-market strategy for the European expansion.",
          followup: "What's your current presence in Europe?",
          response:
            "Minimal right now - about 50 customers, mostly in the UK. Revenue from Europe is about $200K ARR.",
          topic2: "the budget and timeline",
          topic2_response:
            "We've allocated $150,000 for the consulting engagement over 6 months.",
          contact_info:
            "My mobile is 917-555-0890 or email lisa.t@consulting.biz. I check emails even on weekends."
        }
      },
      %{
        contact: Enum.at(contacts, 0),
        title: "Follow-up: Mobile App Beta Feedback",
        days_ago: 1,
        duration: 30,
        transcript_details: %{
          question: "How's the beta testing going so far?",
          answer:
            "Really well! We've got 500 beta users now and the feedback is mostly positive.",
          followup: "Any critical bugs?",
          response:
            "A few crashes on older Android devices, specifically Samsung Galaxy S9 and earlier. We're prioritizing those fixes.",
          topic2: "the launch timeline",
          topic2_response:
            "Still on track for March 15th. We'll do a soft launch first - 10% of users.",
          contact_info:
            "Same as before - 415-555-0123 or sarah.chen@techcorp.io."
        }
      }
    ]
  end

  defp create_meeting(user, google_credential, meeting_data) do
    contact = meeting_data.contact
    contact_name = contact[:name]
    contact_email = contact[:email]
    start_time = DateTime.add(DateTime.utc_now(), -meeting_data.days_ago, :day)
    end_time = DateTime.add(start_time, meeting_data.duration, :minute)

    # Create Calendar Event
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

    # Create attendee records
    attendees_data = [
      %{
        "email" => user.email,
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
    transcript_content = generate_transcript(contact_name, meeting_data.transcript_details)

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

    meeting
  end

  defp generate_transcript(guest_name, details) do
    host_name = "You"

    segments = [
      {host_name, "Hi #{guest_name}, thanks for joining today's call."},
      {guest_name, "Thanks for having me! I've been looking forward to this discussion."},
      {host_name, "Great. So let's dive in. #{details[:question]}"},
      {guest_name, details[:answer]},
      {host_name, details[:followup]},
      {guest_name, details[:response]},
      {host_name, "That's really helpful. What about #{details[:topic2]}?"},
      {guest_name, details[:topic2_response]},
      {host_name, "Perfect. What's the best way to reach you?"},
      {guest_name, details[:contact_info]},
      {host_name, "Got it. Thanks so much for your time today!"},
      {guest_name, "Sounds great! Looking forward to it."}
    ]

    {data, _final_time} =
      Enum.map_reduce(segments, 0.0, fn {speaker, text}, current_time ->
        {words, end_time} = words_to_list_with_timestamps(text, current_time)
        segment = %{"speaker" => speaker, "words" => words}
        {segment, end_time + 2.0}
      end)

    %{"data" => data}
  end

  defp words_to_list_with_timestamps(sentence, start_time) do
    words = String.split(sentence, " ")
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

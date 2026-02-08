defmodule SocialScribe.CRM.ContactSearch do
  @moduledoc """
  Hybrid contact search across local contacts and connected CRMs (HubSpot, Salesforce).

  Searches local contacts and CRMs in parallel, merging results with deduplication.
  Local contacts are guaranteed to have meeting history. CRM contacts provide
  enriched data (company, title, etc.). When a contact exists in both, CRM data
  is preferred for the richer information.
  """

  alias SocialScribe.Accounts.Credentials
  alias SocialScribe.Accounts.User
  alias SocialScribe.Contacts
  alias SocialScribe.Contacts.Contact

  @type source :: :local | :hubspot | :salesforce

  @type contact :: %{
          id: String.t(),
          contact_id: integer() | nil,
          crm_id: String.t() | nil,
          source: source(),
          name: String.t() | nil,
          email: String.t() | nil,
          company: String.t() | nil,
          title: String.t() | nil,
          crm_data: map() | nil
        }

  @doc """
  Searches for contacts across local contacts and connected CRMs.

  Fetches from local contacts, HubSpot, and Salesforce in parallel.
  Results are merged with deduplication by email - CRM data is preferred
  when a contact exists in both local and CRM (for richer data).

  Local contacts are marked with `contact_id` for direct meeting lookup.

  ## Parameters
  - `user` - The user whose contacts and CRM credentials to use
  - `query` - Search query string (name, email, etc.)

  ## Returns
  - `{:ok, [contact()]}` - List of matching contacts (may be empty)
  """
  @spec search(User.t(), String.t()) :: {:ok, [contact()]}
  def search(%User{id: user_id} = user, query) when is_binary(query) do
    hubspot_cred = Credentials.get_user_latest_credential(user_id, "hubspot")
    salesforce_cred = Credentials.get_user_latest_credential(user_id, "salesforce")

    results = search_all_sources_parallel(user, hubspot_cred, salesforce_cred, query)
    {:ok, results}
  end

  def search(%User{}, _query), do: {:ok, []}
  def search(_user, _query), do: {:ok, []}

  # =============================================================================
  # Parallel Search
  # =============================================================================

  defp search_all_sources_parallel(user, hubspot_cred, salesforce_cred, query) do
    tasks = build_search_tasks(user, hubspot_cred, salesforce_cred, query)

    # Use yield_many + shutdown to gracefully handle timeouts/crashes
    # instead of await_many which raises on timeout/exit
    all_results =
      tasks
      |> Task.yield_many(5_000)
      |> Enum.flat_map(fn
        {_task, {:ok, results}} ->
          results || []

        {task, {:exit, _reason}} ->
          Task.shutdown(task, :brutal_kill)
          []

        {task, nil} ->
          # Timeout - shutdown the task and return empty
          Task.shutdown(task, :brutal_kill)
          []
      end)
      |> Enum.reject(&is_nil/1)

    merge_and_deduplicate(all_results)
  end

  defp build_search_tasks(user, hubspot_cred, salesforce_cred, query) do
    # Always search local contacts
    local_task = Task.async(fn -> search_local(user, query) end)

    [local_task]
    |> maybe_add_crm_task(hubspot_cred, query, &search_hubspot/2)
    |> maybe_add_crm_task(salesforce_cred, query, &search_salesforce/2)
  end

  defp maybe_add_crm_task(tasks, nil, _query, _search_fn), do: tasks

  defp maybe_add_crm_task(tasks, credential, query, search_fn) do
    task = Task.async(fn -> search_fn.(credential, query) end)
    [task | tasks]
  end

  # Merge results, preferring CRM data when email matches (richer data)
  # but preserving contact_id from local contacts for meeting lookup
  defp merge_and_deduplicate(results) do
    # Group by lowercase email
    by_email =
      results
      |> Enum.filter(&(&1[:email] != nil))
      |> Enum.group_by(&String.downcase(&1.email))

    # For each email, pick best result (CRM preferred, but keep contact_id from local)
    merged =
      Enum.map(by_email, fn {_email, contacts} ->
        merge_contacts(contacts)
      end)

    # Add contacts without email (shouldn't happen but be safe)
    no_email = Enum.filter(results, &(&1[:email] == nil))

    # Sort deterministically by name to prevent dropdown order flickering
    (merged ++ no_email)
    |> Enum.sort_by(&String.downcase(&1[:name] || ""))
  end

  # Merge contacts with same email - prefer CRM data but keep local contact_id
  # Priority: Salesforce > HubSpot > Local (explicit order to prevent non-determinism)
  defp merge_contacts([single]), do: single

  defp merge_contacts(contacts) do
    local = Enum.find(contacts, &(&1.source == :local))
    # Explicit priority: Salesforce first (primary CRM), then HubSpot
    salesforce = Enum.find(contacts, &(&1.source == :salesforce))
    hubspot = Enum.find(contacts, &(&1.source == :hubspot))
    crm = salesforce || hubspot

    case {local, crm} do
      {nil, crm} ->
        crm

      {local, nil} ->
        local

      {local, crm} ->
        # Prefer CRM data but add contact_id from local for meeting lookup
        Map.put(crm, :contact_id, local.contact_id)
    end
  end

  # =============================================================================
  # Local Contacts Search
  # =============================================================================

  defp search_local(user, query) do
    user
    |> Contacts.search_contacts(query)
    |> Enum.map(&normalize_local_contact/1)
  end

  defp normalize_local_contact(%Contact{id: id, name: name, email: email}) do
    %{
      id: "local:#{id}",
      contact_id: id,
      crm_id: nil,
      source: :local,
      name: name || email,
      email: email,
      company: nil,
      title: nil,
      crm_data: nil
    }
  end

  # =============================================================================
  # HubSpot Search
  # =============================================================================

  defp search_hubspot(credential, query) do
    case hubspot_api().search_contacts(credential, query) do
      {:ok, contacts} when is_list(contacts) ->
        Enum.map(contacts, &normalize_hubspot_contact/1)

      {:error, _reason} ->
        []
    end
  rescue
    _ -> []
  end

  defp normalize_hubspot_contact(%{id: id, display_name: name, email: email} = contact) do
    %{
      id: "hubspot:#{id}",
      contact_id: nil,
      crm_id: to_string(id),
      source: :hubspot,
      name: name,
      email: email,
      company: contact[:company],
      title: contact[:jobtitle],
      crm_data: stringify_keys(contact)
    }
  end

  defp normalize_hubspot_contact(_), do: nil

  # =============================================================================
  # Salesforce Search
  # =============================================================================

  defp search_salesforce(credential, query) do
    case salesforce_api().search_contacts(credential, query) do
      {:ok, contacts} when is_list(contacts) ->
        Enum.map(contacts, &normalize_salesforce_contact/1)

      {:error, _reason} ->
        []
    end
  rescue
    _ -> []
  end

  defp normalize_salesforce_contact(%{id: id, display_name: name, email: email} = contact) do
    %{
      id: "salesforce:#{id}",
      contact_id: nil,
      crm_id: to_string(id),
      source: :salesforce,
      name: name,
      email: email,
      company: contact[:company],
      title: contact[:title],
      crm_data: stringify_keys(contact)
    }
  end

  defp normalize_salesforce_contact(_), do: nil

  # =============================================================================
  # Helpers
  # =============================================================================

  defp stringify_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  # API module getters for mocking in tests
  defp hubspot_api do
    Application.get_env(:social_scribe, :hubspot_api, SocialScribe.CRM.HubSpot.Api)
  end

  defp salesforce_api do
    Application.get_env(:social_scribe, :salesforce_api, SocialScribe.CRM.Salesforce.Api)
  end
end

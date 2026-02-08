defmodule SocialScribe.Error do
  @moduledoc """
  Standardized error types for the SocialScribe application.

  This module provides consistent error structures across the codebase.
  All errors follow the pattern `{:error, %SocialScribe.Error{}}` or
  `{:error, reason_atom}` for simple cases.

  ## Error Types

  - `:not_found` - Resource not found
  - `:unauthorized` - Authentication required or failed
  - `:forbidden` - User lacks permission
  - `:validation_error` - Input validation failed
  - `:api_error` - External API call failed
  - `:config_error` - Configuration is missing or invalid
  - `:rate_limited` - Rate limit exceeded
  - `:service_unavailable` - External service is down

  ## Usage

      # Simple error
      {:error, :not_found}

      # Detailed error
      {:error, SocialScribe.Error.api_error("HubSpot", "Contact not found", 404)}

      # Validation error with changeset
      {:error, SocialScribe.Error.validation_error(changeset)}

  """

  @type error_type ::
          :not_found
          | :unauthorized
          | :forbidden
          | :validation_error
          | :api_error
          | :config_error
          | :rate_limited
          | :service_unavailable
          | :http_error
          | :parsing_error

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map() | nil
        }

  defstruct [:type, :message, :details]

  @doc """
  Creates an API error.

  ## Examples

      iex> SocialScribe.Error.api_error("HubSpot", "Contact not found", 404)
      %SocialScribe.Error{type: :api_error, message: "HubSpot API error: Contact not found", details: %{service: "HubSpot", status: 404}}

  """
  @spec api_error(String.t(), String.t(), integer() | nil) :: t()
  def api_error(service, message, status \\ nil) do
    %__MODULE__{
      type: :api_error,
      message: "#{service} API error: #{message}",
      details: %{service: service, status: status}
    }
  end

  @doc """
  Creates a configuration error.

  ## Examples

      iex> SocialScribe.Error.config_error("GEMINI_API_KEY is not set")
      %SocialScribe.Error{type: :config_error, message: "Configuration error: GEMINI_API_KEY is not set", details: nil}

  """
  @spec config_error(String.t()) :: t()
  def config_error(message) do
    %__MODULE__{
      type: :config_error,
      message: "Configuration error: #{message}",
      details: nil
    }
  end

  @doc """
  Creates a not found error.

  ## Examples

      iex> SocialScribe.Error.not_found("Contact", 123)
      %SocialScribe.Error{type: :not_found, message: "Contact with id 123 not found", details: %{resource: "Contact", id: 123}}

  """
  @spec not_found(String.t(), term()) :: t()
  def not_found(resource, id) do
    %__MODULE__{
      type: :not_found,
      message: "#{resource} with id #{id} not found",
      details: %{resource: resource, id: id}
    }
  end

  @doc """
  Creates a validation error.

  ## Examples

      iex> SocialScribe.Error.validation_error("email", "is invalid")
      %SocialScribe.Error{type: :validation_error, message: "Validation failed: email is invalid", details: %{field: "email", error: "is invalid"}}

  """
  @spec validation_error(String.t(), String.t()) :: t()
  def validation_error(field, error) do
    %__MODULE__{
      type: :validation_error,
      message: "Validation failed: #{field} #{error}",
      details: %{field: field, error: error}
    }
  end

  @doc """
  Creates a rate limited error.
  """
  @spec rate_limited(String.t()) :: t()
  def rate_limited(service) do
    %__MODULE__{
      type: :rate_limited,
      message: "Rate limited by #{service}. Please try again later.",
      details: %{service: service}
    }
  end

  @doc """
  Creates a service unavailable error.
  """
  @spec service_unavailable(String.t()) :: t()
  def service_unavailable(service) do
    %__MODULE__{
      type: :service_unavailable,
      message: "#{service} is temporarily unavailable. Please try again later.",
      details: %{service: service}
    }
  end

  @doc """
  Creates an HTTP error.
  """
  @spec http_error(term()) :: t()
  def http_error(reason) do
    %__MODULE__{
      type: :http_error,
      message: "HTTP request failed",
      details: %{reason: reason}
    }
  end

  @doc """
  Creates a parsing error.
  """
  @spec parsing_error(String.t(), term()) :: t()
  def parsing_error(message, data \\ nil) do
    %__MODULE__{
      type: :parsing_error,
      message: message,
      details: %{data: data}
    }
  end

  @doc """
  Converts an error struct to a user-friendly message.
  """
  @spec to_user_message(t() | atom()) :: String.t()
  def to_user_message(%__MODULE__{type: :rate_limited}) do
    "Too many requests. Please wait a moment and try again."
  end

  def to_user_message(%__MODULE__{type: :service_unavailable}) do
    "The service is temporarily unavailable. Please try again later."
  end

  def to_user_message(%__MODULE__{type: :api_error, details: %{service: service}}) do
    "Unable to communicate with #{service}. Please try again."
  end

  def to_user_message(%__MODULE__{message: message}) do
    message
  end

  def to_user_message(:not_found), do: "The requested resource was not found."
  def to_user_message(:unauthorized), do: "Please sign in to continue."
  def to_user_message(:forbidden), do: "You don't have permission to access this resource."
  def to_user_message(atom) when is_atom(atom), do: "An error occurred: #{atom}"
end

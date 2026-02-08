defmodule SocialScribe.TranscriptParser do
  @moduledoc """
  Utilities for parsing and formatting meeting transcripts.

  This module provides shared functionality for extracting and formatting
  transcript data for various use cases (AI prompts, display, etc.).
  """

  @doc """
  Formats transcript for AI prompts with timestamps.
  Output: "[MM:SS] Speaker: text content"

  ## Examples

      iex> format_for_prompt(%{"data" => [%{"speaker" => "John", "words" => [%{"text" => "Hello", "start_timestamp" => 5.0}]}]})
      "[00:05] John: Hello"

  """
  def format_for_prompt(%{"data" => transcript_segments}) when is_list(transcript_segments) do
    format_segments_for_prompt(transcript_segments)
  end

  def format_for_prompt(%{data: transcript_segments}) when is_list(transcript_segments) do
    format_segments_for_prompt(transcript_segments)
  end

  def format_for_prompt(_), do: ""

  @doc """
  Formats transcript segments for AI prompts with timestamps.
  """
  def format_segments_for_prompt(transcript_segments) when is_list(transcript_segments) do
    Enum.map_join(transcript_segments, "\n", fn segment ->
      speaker = get_speaker(segment)
      words = get_words(segment)
      text = segment_to_text(segment)
      timestamp = format_timestamp(List.first(words))
      "[#{timestamp}] #{speaker}: #{text}"
    end)
  end

  def format_segments_for_prompt(_), do: ""

  @doc """
  Formats transcript for display (no timestamps).
  Output: "Speaker: text content"

  ## Examples

      iex> format_for_display(%{"data" => [%{"speaker" => "John", "words" => [%{"text" => "Hello"}]}]})
      "John: Hello"

  """
  def format_for_display(%{"data" => transcript_segments}) when is_list(transcript_segments) do
    format_segments_for_display(transcript_segments)
  end

  def format_for_display(%{data: transcript_segments}) when is_list(transcript_segments) do
    format_segments_for_display(transcript_segments)
  end

  def format_for_display(_), do: "No transcript available"

  @doc """
  Formats transcript segments for display (no timestamps).
  """
  def format_segments_for_display(transcript_segments) when is_list(transcript_segments) do
    transcript_segments
    |> Enum.map(fn segment ->
      speaker = get_speaker(segment)
      text = segment_to_text(segment)
      "#{speaker}: #{text}"
    end)
    |> Enum.join("\n")
    |> case do
      "" -> "No transcript available"
      text -> text
    end
  end

  def format_segments_for_display(_), do: "No transcript available"

  @doc """
  Formats seconds to MM:SS string.

  ## Examples

      iex> format_timestamp(%{"start_timestamp" => 65.5})
      "01:05"

      iex> format_timestamp(nil)
      "00:00"

  """
  def format_timestamp(nil), do: "00:00"

  def format_timestamp(word) when is_map(word) do
    seconds = extract_seconds(word)
    seconds_to_timestamp(seconds)
  end

  def format_timestamp(_), do: "00:00"

  @doc """
  Converts raw seconds to MM:SS format.

  ## Examples

      iex> seconds_to_timestamp(125)
      "02:05"

  """
  def seconds_to_timestamp(seconds) when is_number(seconds) do
    total_seconds = trunc(seconds)
    minutes = div(total_seconds, 60)
    secs = rem(total_seconds, 60)

    "#{String.pad_leading(Integer.to_string(minutes), 2, "0")}:#{String.pad_leading(Integer.to_string(secs), 2, "0")}"
  end

  def seconds_to_timestamp(_), do: "00:00"

  @doc """
  Extracts seconds from a word map.

  Handles different formats:
  - Map format: %{"absolute" => "...", "relative" => 41.911842}
  - Direct float format: 0.48204318
  """
  def extract_seconds(%{"relative" => relative}) when is_number(relative), do: relative
  def extract_seconds(%{relative: relative}) when is_number(relative), do: relative
  def extract_seconds(%{"start_timestamp" => ts}) when is_number(ts), do: ts
  def extract_seconds(%{start_timestamp: ts}) when is_number(ts), do: ts
  def extract_seconds(seconds) when is_number(seconds), do: seconds
  def extract_seconds(_), do: 0

  @doc """
  Extracts all segments from a specific speaker.

  ## Examples

      iex> get_segments_by_speaker(%{"data" => [%{"speaker" => "John", ...}, %{"speaker" => "Jane", ...}]}, "John")
      [%{"speaker" => "John", ...}]

  """
  def get_segments_by_speaker(%{"data" => segments}, speaker_name) when is_list(segments) do
    Enum.filter(segments, fn segment -> get_speaker(segment) == speaker_name end)
  end

  def get_segments_by_speaker(%{data: segments}, speaker_name) when is_list(segments) do
    Enum.filter(segments, fn segment -> get_speaker(segment) == speaker_name end)
  end

  def get_segments_by_speaker(_, _), do: []

  @doc """
  Gets list of unique speakers in transcript.

  ## Examples

      iex> get_speakers(%{"data" => [%{"speaker" => "John", ...}, %{"speaker" => "Jane", ...}]})
      ["John", "Jane"]

  """
  def get_speakers(%{"data" => segments}) when is_list(segments) do
    segments
    |> Enum.map(&get_speaker/1)
    |> Enum.uniq()
  end

  def get_speakers(%{data: segments}) when is_list(segments) do
    segments
    |> Enum.map(&get_speaker/1)
    |> Enum.uniq()
  end

  def get_speakers(_), do: []

  @doc """
  Extracts the text content from a segment.

  ## Examples

      iex> segment_to_text(%{"words" => [%{"text" => "Hello"}, %{"text" => "world"}]})
      "Hello world"

  """
  def segment_to_text(segment) when is_map(segment) do
    words = get_words(segment)
    Enum.map_join(words, " ", &get_text/1)
  end

  def segment_to_text(_), do: ""

  # Private helper functions

  defp get_speaker(segment) do
    Map.get(segment, "speaker") || Map.get(segment, :speaker, "Unknown Speaker")
  end

  defp get_words(segment) do
    Map.get(segment, "words") || Map.get(segment, :words, [])
  end

  defp get_text(word) do
    Map.get(word, "text") || Map.get(word, :text, "")
  end
end

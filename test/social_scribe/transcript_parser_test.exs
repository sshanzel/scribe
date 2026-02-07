defmodule SocialScribe.TranscriptParserTest do
  use ExUnit.Case, async: true

  alias SocialScribe.TranscriptParser

  describe "format_for_prompt/1" do
    test "formats transcript with timestamps" do
      transcript = %{
        "data" => [
          %{
            "speaker" => "John",
            "words" => [
              %{"text" => "Hello", "start_timestamp" => 5.0},
              %{"text" => "world", "start_timestamp" => 5.5}
            ]
          },
          %{
            "speaker" => "Jane",
            "words" => [
              %{"text" => "Hi", "start_timestamp" => 65.0},
              %{"text" => "there", "start_timestamp" => 65.5}
            ]
          }
        ]
      }

      result = TranscriptParser.format_for_prompt(transcript)

      assert result == "[00:05] John: Hello world\n[01:05] Jane: Hi there"
    end

    test "handles atom keys" do
      transcript = %{
        data: [
          %{
            speaker: "John",
            words: [%{text: "Hello", start_timestamp: 5.0}]
          }
        ]
      }

      result = TranscriptParser.format_for_prompt(transcript)

      assert result == "[00:05] John: Hello"
    end

    test "returns empty string for nil" do
      assert TranscriptParser.format_for_prompt(nil) == ""
    end

    test "returns empty string for empty map" do
      assert TranscriptParser.format_for_prompt(%{}) == ""
    end
  end

  describe "format_for_display/1" do
    test "formats transcript without timestamps" do
      transcript = %{
        "data" => [
          %{
            "speaker" => "John",
            "words" => [%{"text" => "Hello"}, %{"text" => "world"}]
          },
          %{
            "speaker" => "Jane",
            "words" => [%{"text" => "Hi"}, %{"text" => "there"}]
          }
        ]
      }

      result = TranscriptParser.format_for_display(transcript)

      assert result == "John: Hello world\nJane: Hi there"
    end

    test "returns 'No transcript available' for empty data" do
      transcript = %{"data" => []}

      result = TranscriptParser.format_for_display(transcript)

      assert result == "No transcript available"
    end

    test "returns 'No transcript available' for nil" do
      assert TranscriptParser.format_for_display(nil) == ""
    end
  end

  describe "format_timestamp/1" do
    test "formats word with start_timestamp" do
      assert TranscriptParser.format_timestamp(%{"start_timestamp" => 65.5}) == "01:05"
    end

    test "formats word with relative timestamp" do
      assert TranscriptParser.format_timestamp(%{"relative" => 125.0}) == "02:05"
    end

    test "returns 00:00 for nil" do
      assert TranscriptParser.format_timestamp(nil) == "00:00"
    end

    test "returns 00:00 for empty map" do
      assert TranscriptParser.format_timestamp(%{}) == "00:00"
    end
  end

  describe "seconds_to_timestamp/1" do
    test "converts seconds to MM:SS" do
      assert TranscriptParser.seconds_to_timestamp(0) == "00:00"
      assert TranscriptParser.seconds_to_timestamp(5) == "00:05"
      assert TranscriptParser.seconds_to_timestamp(60) == "01:00"
      assert TranscriptParser.seconds_to_timestamp(65) == "01:05"
      assert TranscriptParser.seconds_to_timestamp(125) == "02:05"
      assert TranscriptParser.seconds_to_timestamp(3661) == "61:01"
    end

    test "handles floats" do
      assert TranscriptParser.seconds_to_timestamp(65.9) == "01:05"
    end

    test "returns 00:00 for non-numeric values" do
      assert TranscriptParser.seconds_to_timestamp("invalid") == "00:00"
      assert TranscriptParser.seconds_to_timestamp(nil) == "00:00"
    end
  end

  describe "extract_seconds/1" do
    test "extracts from relative key (string)" do
      assert TranscriptParser.extract_seconds(%{"relative" => 41.5}) == 41.5
    end

    test "extracts from relative key (atom)" do
      assert TranscriptParser.extract_seconds(%{relative: 41.5}) == 41.5
    end

    test "extracts from start_timestamp key (string)" do
      assert TranscriptParser.extract_seconds(%{"start_timestamp" => 65.0}) == 65.0
    end

    test "extracts from start_timestamp key (atom)" do
      assert TranscriptParser.extract_seconds(%{start_timestamp: 65.0}) == 65.0
    end

    test "returns raw number" do
      assert TranscriptParser.extract_seconds(42.0) == 42.0
    end

    test "returns 0 for nil or invalid" do
      assert TranscriptParser.extract_seconds(nil) == 0
      assert TranscriptParser.extract_seconds(%{}) == 0
    end
  end

  describe "get_speakers/1" do
    test "returns unique speakers" do
      transcript = %{
        "data" => [
          %{"speaker" => "John", "words" => []},
          %{"speaker" => "Jane", "words" => []},
          %{"speaker" => "John", "words" => []}
        ]
      }

      assert TranscriptParser.get_speakers(transcript) == ["John", "Jane"]
    end

    test "handles atom keys" do
      transcript = %{
        data: [
          %{speaker: "Alice", words: []},
          %{speaker: "Bob", words: []}
        ]
      }

      assert TranscriptParser.get_speakers(transcript) == ["Alice", "Bob"]
    end

    test "returns empty list for nil" do
      assert TranscriptParser.get_speakers(nil) == []
    end
  end

  describe "get_segments_by_speaker/2" do
    test "filters segments by speaker" do
      transcript = %{
        "data" => [
          %{"speaker" => "John", "words" => [%{"text" => "Hello"}]},
          %{"speaker" => "Jane", "words" => [%{"text" => "Hi"}]},
          %{"speaker" => "John", "words" => [%{"text" => "Goodbye"}]}
        ]
      }

      result = TranscriptParser.get_segments_by_speaker(transcript, "John")

      assert length(result) == 2
      assert Enum.all?(result, fn seg -> seg["speaker"] == "John" end)
    end

    test "returns empty list when speaker not found" do
      transcript = %{"data" => [%{"speaker" => "John", "words" => []}]}

      assert TranscriptParser.get_segments_by_speaker(transcript, "Unknown") == []
    end
  end

  describe "segment_to_text/1" do
    test "joins words from segment" do
      segment = %{
        "words" => [
          %{"text" => "Hello"},
          %{"text" => "world"},
          %{"text" => "!"}
        ]
      }

      assert TranscriptParser.segment_to_text(segment) == "Hello world !"
    end

    test "handles atom keys" do
      segment = %{words: [%{text: "Hello"}, %{text: "there"}]}

      assert TranscriptParser.segment_to_text(segment) == "Hello there"
    end

    test "returns empty string for nil" do
      assert TranscriptParser.segment_to_text(nil) == ""
    end
  end
end

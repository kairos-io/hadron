# frozen_string_literal: true

# Exercises the release-notes excerpt that .github/scripts/autobumper-changelog.rb
# puts into the body of a bump pull request (kairos-io/kairos#5646).
#
# The excerpt is upstream text pasted into a hadron pull request, so anything
# GitHub turns into a notification or a link has to come out inert: an
# @mention pings the upstream author, a bare #123 links to hadron's own #123,
# and a code fence left open by the 25-line/1200-character cut swallows the
# closing </details> of the body.

require "minitest/autorun"

load File.expand_path("../.github/scripts/autobumper-changelog.rb", __dir__)

class AutobumperChangelogTest < Minitest::Test
  def excerpt(notes, **opts)
    format_notes(notes, **opts).first
  end

  # The shape GitHub's generated release notes use for every entry.
  def test_generated_entry_is_defanged
    got = excerpt("* Fix the parser by @alice in https://github.com/foo/bar/pull/12")
    assert_equal "* Fix the parser by `@alice` in https://github.com/foo/bar/pull/12", got
  end

  def test_team_mention_is_defanged
    assert_equal "thanks `@foo/maintainers`", excerpt("thanks @foo/maintainers")
  end

  def test_bare_issue_references_are_defanged
    assert_equal "closes `#123` and `GH-45`", excerpt("closes #123 and GH-45")
  end

  def test_qualified_references_and_addresses_are_kept
    text = "see foo/bar#12, mail dev@example.org, &#123; and ## 1.2 heading"
    assert_equal text, excerpt(text)
  end

  def test_inline_code_is_kept
    text = "use `@ts-ignore` or `#1` here, not @bob"
    assert_equal "use `@ts-ignore` or `#1` here, not `@bob`", excerpt(text)
  end

  def test_fenced_code_is_kept
    text = "```\nnpm i @scope/pkg # see #1\n```\nby @carol"
    assert_equal "```\nnpm i @scope/pkg # see #1\n```\nby `@carol`", excerpt(text)
  end

  def test_line_cut_inside_fence_closes_it
    text = "intro\n```sh\n" + (1..40).map { |n| "echo #{n}" }.join("\n") + "\n```\nafter"
    got, truncated = format_notes(text)
    assert truncated
    assert got.end_with?("echo 23\n```"), got
  end

  def test_character_cut_inside_fence_closes_it
    text = "~~~~\n" + "x" * 2000 + "\n~~~~"
    got, truncated = format_notes(text)
    assert truncated
    assert got.end_with?("…\n~~~~"), got
  end

  def test_closed_fence_is_not_closed_twice
    text = "```\ncode\n```"
    assert_equal text, excerpt(text)
  end

  def test_rendered_body_keeps_details_outside_the_fence
    text = "```\n" + (1..30).map(&:to_s).join("\n")
    block = render_notes("release_notes" => text)
    fences = block.lines.count { |line| line.start_with?("```") }
    assert fences.even?, block
    assert block.end_with?("```\n\n</details>\n\n"), block
  end
end

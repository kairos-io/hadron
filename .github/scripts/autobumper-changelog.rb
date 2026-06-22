#!/usr/bin/env ruby
# frozen_string_literal: true

# Build the title, commit message and PR body for an Updatecli bump PR.
#
# This script is invoked by .github/workflows/autobumper.yml after
# `updatecli apply` has rewritten ARG instructions in the Dockerfile. It reads
# the staged Dockerfile diff together with the Updatecli manifest referenced by
# the UPDATECLI_MANIFEST environment variable and enriches the PR body with
# changelog context (release notes, changelog links and tag-to-tag compare
# links) for every bumped dependency.
#
# Changelog enrichment is derived automatically for sources hosted on GitHub
# and GitLab (whether declared as `githubrelease`, `gittag` or `gitlab` kinds).
# Sources that cannot be derived automatically (cgit hosts, shell/http sources,
# other forges) can supply an optional `changelog` hint block in the manifest,
# for example:
#
#   sources:
#     grep:
#       kind: gittag
#       spec:
#         url: git://git.git.savannah.gnu.org/grep.git
#       changelog:
#         url: https://git.savannah.gnu.org/cgit/grep.git/tree/NEWS
#         compare: "https://git.savannah.gnu.org/cgit/grep.git/diff/?id={new_tag}&id2={old_tag}"
#
# Supported placeholders in `changelog.url` and `changelog.compare` are
# {old}, {new} (the Dockerfile versions) and {old_tag}, {new_tag} (the upstream
# git tags reconstructed by reversing the source transformers).
#
# Outputs are written to /tmp/pr_title.txt, /tmp/commit_msg.txt and
# /tmp/pr_body.md so the calling workflow can use them with the gh CLI.

require "json"
require "net/http"
require "uri"
require "yaml"
require "cgi"

# Parse the staged Dockerfile diff into a list of ARG version bumps. Removed
# (`-ARG NAME=...`) and added (`+ARG NAME=...`) lines are paired by their ARG
# name, so the result is correct regardless of how the diff groups the lines.
def parse_bumps(diff_text)
  removed = {}
  added = {}
  order = []

  diff_text.each_line do |line|
    if line.start_with?("-") && !line.start_with?("---")
      if (match = line[1..].strip.match(/^ARG\s+([A-Z0-9_]+)=(.+)$/))
        removed[match[1]] = match[2]
      end
    elsif line.start_with?("+") && !line.start_with?("+++")
      if (match = line[1..].strip.match(/^ARG\s+([A-Z0-9_]+)=(.+)$/))
        added[match[1]] = match[2]
        order << match[1] unless order.include?(match[1])
      end
    end
  end

  order.filter_map do |matcher|
    old_version = removed[matcher]
    new_version = added[matcher]
    next if old_version.nil? || new_version.nil? || old_version == new_version

    {
      "matcher" => matcher,
      "old_version" => old_version,
      "new_version" => new_version
    }
  end
end

# Apply the source transformers to a value (tag -> version). Used to match a
# GitHub release tag against the version stored in the Dockerfile.
def apply_transformers(value, transformers)
  return value if value.nil?

  Array(transformers).reduce(value.dup) do |current, transformer|
    key, spec = transformer.first

    case key
    when "trimprefix"
      current.start_with?(spec.to_s) ? current.delete_prefix(spec.to_s) : current
    when "trimsuffix"
      current.end_with?(spec.to_s) ? current.delete_suffix(spec.to_s) : current
    when "replacer"
      current.gsub(spec.fetch("from").to_s, spec.fetch("to").to_s)
    else
      current
    end
  end
end

# Reverse the source transformers (version -> tag) so we can reconstruct the
# upstream git tag from the value stored in the Dockerfile. This is a
# best-effort inverse of apply_transformers used to build compare links.
def reverse_transformers(value, transformers)
  return value if value.nil?

  Array(transformers).reverse.reduce(value.dup) do |current, transformer|
    key, spec = transformer.first

    case key
    when "trimprefix"
      current.start_with?(spec.to_s) ? current : spec.to_s + current
    when "trimsuffix"
      current.end_with?(spec.to_s) ? current : current + spec.to_s
    when "replacer"
      current.gsub(spec.fetch("to").to_s, spec.fetch("from").to_s)
    else
      current
    end
  end
end

# Substitute {old}, {new}, {old_tag} and {new_tag} placeholders in a template.
def render_template(template, bump)
  template.to_s
          .gsub("{old}", bump["old_version"].to_s)
          .gsub("{new}", bump["new_version"].to_s)
          .gsub("{old_tag}", bump["old_tag"].to_s)
          .gsub("{new_tag}", bump["new_tag"].to_s)
end

def github_api_get(url, token)
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/vnd.github+json"
  request["User-Agent"] = "hadron-autobumper"
  request["Authorization"] = "Bearer " + token unless token.to_s.empty?

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    response = http.request(request)
    raise "GitHub API request failed for #{url}: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end

def http_get_json(url)
  uri = URI(url)
  request = Net::HTTP::Get.new(uri)
  request["Accept"] = "application/json"
  request["User-Agent"] = "hadron-autobumper"

  Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
    response = http.request(request)
    raise "Request failed for #{url}: #{response.code} #{response.message}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  end
end

# Extract the GitHub owner/repository from a git remote URL, if any.
def github_coords(url)
  match = url.to_s.match(%r{github\.com[/:]+([^/]+)/([^/]+?)(?:\.git)?/?$})
  return nil unless match

  { "owner" => match[1], "repository" => match[2] }
end

# Extract the GitLab host and project path from a git remote URL, if any.
def gitlab_coords(url)
  match = url.to_s.match(%r{(?:https?://|git://)?(gitlab[^/]*)/(.+?)(?:\.git)?/?$})
  return nil unless match

  { "host" => match[1], "path" => match[2] }
end

# Look up the GitHub release matching the bumped version and return its URL and
# notes. Falls back to the releases index link when the release cannot be found
# or the API is unreachable.
def fetch_github_release(bump, token)
  owner = bump["owner"]
  repository = bump["repository"]
  return {} if owner.to_s.empty? || repository.to_s.empty?

  begin
    1.upto(10) do |page|
      releases = github_api_get("https://api.github.com/repos/#{owner}/#{repository}/releases?per_page=100&page=#{page}", token)
      break if releases.empty?

      matched = releases.find do |release|
        apply_transformers(release["tag_name"].to_s, bump["transformers"]) == bump["new_version"]
      end

      return {
        "release_url" => matched["html_url"],
        "release_notes" => matched["body"].to_s,
        "release_notes_status" => matched["body"].to_s.strip.empty? ? "empty" : "available"
      } if matched
    end
  rescue StandardError => e
    warn "Unable to fetch release details for #{owner}/#{repository}: #{e.message}"
    return {
      "release_url" => "https://github.com/#{owner}/#{repository}/releases",
      "release_notes_status" => "lookup_failed"
    }
  end

  {
    "release_url" => "https://github.com/#{owner}/#{repository}/releases",
    "release_notes_status" => "unavailable"
  }
end

# Best-effort lookup of a GitLab release's notes for the bumped tag. GitLab
# public projects allow unauthenticated reads, so no token is required.
def fetch_gitlab_release(bump)
  host = bump["gitlab_host"]
  path = bump["gitlab_path"]
  return {} if host.to_s.empty? || path.to_s.empty?

  encoded = CGI.escape(path)
  tag = bump["new_tag"]

  begin
    release = http_get_json("https://#{host}/api/v4/projects/#{encoded}/releases/#{CGI.escape(tag)}")
    notes = release["description"].to_s
    {
      "release_notes" => notes,
      "release_notes_status" => notes.strip.empty? ? "empty" : "available"
    }
  rescue StandardError => e
    warn "Unable to fetch GitLab release for #{path} #{tag}: #{e.message}"
    {}
  end
end

def format_notes(notes, limit: 1200, max_lines: 25)
  text = notes.to_s.gsub("\r\n", "\n").strip
  return nil if text.empty?

  excerpt = text.lines.first(max_lines).join.strip
  truncated = text.lines.length > max_lines

  if excerpt.length > limit
    excerpt = excerpt[0, limit].rstrip + "…"
    truncated = true
  end

  [excerpt, truncated]
end

# Render the release notes excerpt block (folded <details>) or a short status
# line explaining why no excerpt is available.
def render_notes(bump)
  notes = format_notes(bump["release_notes"])
  if notes
    excerpt, truncated = notes
    block = +"- Notes:\n\n"
    block << "<details>\n"
    block << "<summary>Release notes excerpt#{truncated ? " (truncated)" : ""}</summary>\n\n"
    block << excerpt
    block << "\n\n</details>\n\n"
    block
  else
    case bump["release_notes_status"]
    when "empty"
      "- Notes: no release notes published for this release\n"
    when "lookup_failed"
      "- Notes: unable to retrieve release notes during the workflow run\n"
    when "available"
      "- Notes: unavailable for this release\n"
    else
      nil
    end
  end
end

# Build the markdown changelog lines for a single bump.
def changelog_lines(bump, token)
  lines = []

  if bump["github_owner"] && bump["github_repository"]
    owner = bump["github_owner"]
    repository = bump["github_repository"]
    bump.merge!(fetch_github_release(bump.merge("owner" => owner, "repository" => repository), token))

    status = bump["release_notes_status"]
    if %w[available empty].include?(status) && !bump["release_url"].to_s.empty?
      lines << "- Release: [#{owner}/#{repository} #{bump["new_version"]}](#{bump["release_url"]})\n"
    else
      lines << "- Release: [#{owner}/#{repository} releases](https://github.com/#{owner}/#{repository}/releases)\n"
    end

    notes = render_notes(bump)
    lines << notes if notes

    compare = "https://github.com/#{owner}/#{repository}/compare/#{bump["old_tag"]}...#{bump["new_tag"]}"
    lines << "- Compare: [#{bump["old_tag"]}...#{bump["new_tag"]}](#{compare})\n"
    return lines
  end

  if bump["gitlab_host"] && bump["gitlab_path"]
    host = bump["gitlab_host"]
    path = bump["gitlab_path"]
    bump.merge!(fetch_gitlab_release(bump))

    notes = render_notes(bump)
    lines << notes if notes

    compare = "https://#{host}/#{path}/-/compare/#{bump["old_tag"]}...#{bump["new_tag"]}"
    lines << "- Compare: [#{bump["old_tag"]}...#{bump["new_tag"]}](#{compare})\n"
    return lines
  end

  hint = bump["changelog_hint"]
  if hint.is_a?(Hash)
    if hint["url"]
      lines << "- Changelog: [#{bump.fetch("name")}](#{render_template(hint["url"], bump)})\n"
    end
    if hint["compare"]
      lines << "- Compare: [#{bump["old_tag"]}...#{bump["new_tag"]}](#{render_template(hint["compare"], bump)})\n"
    end
    return lines unless lines.empty?
  end

  if bump["source_url"].to_s.empty?
    lines << "- Source: #{bump["source_kind"] || "unknown"}\n"
  else
    lines << "- Source: [upstream](#{bump["source_url"]}) (#{bump["source_kind"]})\n"
  end
  lines << "- Notes: unavailable for this source type\n"
  lines
end

manifest = YAML.safe_load(File.read(ENV.fetch("UPDATECLI_MANIFEST")), aliases: false)
targets = manifest.fetch("targets", {})
sources = manifest.fetch("sources", {})

target_lookup = {}
targets.each do |target_name, target|
  matcher = target.dig("spec", "instruction", "matcher")
  next if matcher.to_s.empty?

  target_lookup[matcher] = {
    "target_name" => target_name,
    "sourceid" => target["sourceid"]
  }
end

bumps = parse_bumps(`git diff --cached -U0 -- Dockerfile`).map do |bump|
  target = target_lookup[bump["matcher"]] || {}
  sourceid = target["sourceid"]
  source = sources[sourceid] || {}
  transformers = source["transformers"] || []
  source_url = source.dig("spec", "url")
  source_kind = source["kind"]

  enriched = bump.merge(
    "name" => (target["target_name"] || bump["matcher"].downcase),
    "sourceid" => sourceid,
    "source_kind" => source_kind,
    "source_url" => source_url,
    "transformers" => transformers,
    "changelog_hint" => source["changelog"],
    "old_tag" => reverse_transformers(bump["old_version"], transformers),
    "new_tag" => reverse_transformers(bump["new_version"], transformers)
  )

  # Resolve the forge coordinates used for automatic changelog enrichment.
  hint = source["changelog"]
  forge = hint.is_a?(Hash) ? hint["forge"] : nil

  if source_kind == "githubrelease"
    enriched["github_owner"] = source.dig("spec", "owner")
    enriched["github_repository"] = source.dig("spec", "repository")
  elsif forge == "github"
    enriched["github_owner"] = hint["owner"]
    enriched["github_repository"] = hint["repository"]
  elsif forge == "gitlab"
    enriched["gitlab_host"] = hint["host"]
    enriched["gitlab_path"] = hint["path"]
  elsif (coords = github_coords(source_url))
    enriched["github_owner"] = coords["owner"]
    enriched["github_repository"] = coords["repository"]
  elsif source_kind.to_s.start_with?("gitlab") && source.dig("spec", "owner") && source.dig("spec", "repository")
    host = (gitlab_coords(source_url) || {})["host"] || URI(source_url.to_s).host
    enriched["gitlab_host"] = host
    enriched["gitlab_path"] = "#{source.dig("spec", "owner")}/#{source.dig("spec", "repository")}"
  elsif (coords = gitlab_coords(source_url))
    enriched["gitlab_host"] = coords["host"]
    enriched["gitlab_path"] = coords["path"]
  end

  enriched
end

if bumps.empty?
  File.write("/tmp/pr_title.txt", "Automatic version bumps")
  File.write("/tmp/commit_msg.txt", "Automatic version bumps")
  File.write("/tmp/pr_body.md", "No version metadata was collected for this update.")
  exit 0
end

token = ENV["GITHUB_TOKEN"].to_s

title_names = bumps.first(8).map { |bump| bump["name"] }
overflow = bumps.length - title_names.length
title_suffix = overflow.positive? ? " and #{overflow} more" : ""
joined_names = title_names.join(", ")
pr_title = "Automatic version bumps for #{joined_names}#{title_suffix}"

summary_lines = bumps.map do |bump|
  "- #{bump["name"]} was updated #{bump["old_version"]} -> #{bump["new_version"]}"
end

commit_msg = +"Automatic bumps for #{joined_names}#{title_suffix}\n\n"
commit_msg << summary_lines.join("\n")

body = +"## Summary\n\n"
body << summary_lines.join("\n")
body << "\n\n## Changelog\n"

bumps.each do |bump|
  body << "\n### #{bump["name"]}\n"
  body << "- Version: `#{bump["old_version"]}` -> `#{bump["new_version"]}`\n"
  changelog_lines(bump, token).each { |line| body << line }
end

File.write("/tmp/pr_title.txt", pr_title)
File.write("/tmp/commit_msg.txt", commit_msg)
File.write("/tmp/pr_body.md", body)

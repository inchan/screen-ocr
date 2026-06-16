#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby <<'RUBY'
require "pathname"
require "uri"

root = Pathname.pwd
excluded_parts = [".build", ".git", ".omx", ".swiftpm", "artifacts", "dist"]

def local_target?(target)
  return false if target.empty? || target.start_with?("#")
  return false if target.match?(/\A[a-z][a-z0-9+.-]*:/i)

  true
end

def normalized_target(raw)
  target = raw.to_s.strip
  target = target[1...-1] if target.start_with?("<") && target.end_with?(">")
  target
end

def path_part(target)
  target.split("#", 2).first.split("?", 2).first
end

markdown_files = Dir.glob("**/*.md", File::FNM_DOTMATCH).reject do |path|
  parts = Pathname(path).each_filename.to_a
  parts.any? { |part| excluded_parts.include?(part) || part.start_with?(".venv") }
end.sort

missing = []

markdown_files.each do |file|
  text = File.read(file)
  dirname = Pathname(file).dirname

  text.scan(/\[[^\]\n]+\]\(([^)\n]+)\)/) do |match|
    target = normalized_target(match.first)
    next unless local_target?(target)

    relative = path_part(target)
    next if relative.empty?

    decoded = URI::DEFAULT_PARSER.unescape(relative)
    candidate = dirname.join(decoded).cleanpath
    next if candidate.exist?

    missing << "#{file}: missing local link target #{target}"
  end

  text.scan(/^\s*\[[^\]\n]+\]:\s+(\S+)/) do |match|
    target = normalized_target(match.first)
    next unless local_target?(target)

    relative = path_part(target)
    next if relative.empty?

    decoded = URI::DEFAULT_PARSER.unescape(relative)
    candidate = dirname.join(decoded).cleanpath
    next if candidate.exist?

    missing << "#{file}: missing local reference target #{target}"
  end
end

if missing.empty?
  puts "DOC_LINKS=PASS checked=#{markdown_files.size}"
else
  warn missing.join("\n")
  warn "DOC_LINKS=FAIL missing=#{missing.size}"
  exit 1
end
RUBY

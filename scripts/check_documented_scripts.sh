#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ruby <<'RUBY'
search_files = [
  "README.md",
  "AGENTS.md",
  "CLAUDE.md",
  ".github/workflows/unsigned-release.yml",
  *Dir.glob("docs/**/*.{md,xml}")
].select { |path| File.file?(path) }

references = Hash.new { |hash, key| hash[key] = [] }

search_files.each do |file|
  File.foreach(file).with_index(1) do |line, line_number|
    line.scan(%r{scripts/[A-Za-z0-9._/-]+}) do |raw|
      script = raw.sub(%r{[.,;:]+$}, "")
      next if script.include?("...") || script.end_with?("/")

      references[script] << "#{file}:#{line_number}"
    end
  end
end

missing = references.keys.sort.reject { |script| File.file?(script) }

if missing.empty?
  puts "DOC_SCRIPT_REFS=PASS checked=#{references.size}"
else
  missing.each do |script|
    warn "#{script} referenced at #{references[script].join(', ')}"
  end
  warn "DOC_SCRIPT_REFS=FAIL missing=#{missing.size}"
  exit 1
end
RUBY

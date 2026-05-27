#!/usr/bin/env ruby
# Read-only note retriever for OpenJarvis context assembly.

require "set"

root = File.expand_path(File.join(__dir__, "..", "..", "SPPStudioDocs"))
query = ARGV.join(" ").strip
abort("usage: openjarvis-retrieve.rb <query>") if query.empty?

terms = query.downcase.scan(/[a-z0-9]+/)
files = Dir.glob(File.join(root, "**", "*.md"))

def extract_tags(text)
  tags = []
  text.scan(/#(?:[a-z0-9]+(?:\/[a-z0-9_-]+)+)/i) { |m| tags << m.downcase }
  tags.uniq
end

def extract_links(text)
  text.scan(/\[\[([^\]]+)\]\]/).flatten.map { |l| l.split("|").first.split("#").first.strip }.reject(&:empty?).uniq
end

rows = files.map do |path|
  rel = path.sub(root + "/", "")
  text = File.read(path)
  title = text[/^#\s+(.+)$/, 1] || File.basename(path, ".md")
  tags = extract_tags(text)
  links = extract_links(text)
  score = 0
  blob = "#{rel}\n#{title}\n#{tags.join(" ")}\n#{links.join(" ")}\n#{text}".downcase
  terms.each do |term|
    score += 5 if rel.downcase.include?(term)
    score += 4 if title.downcase.include?(term)
    score += 4 if tags.any? { |t| t.include?(term) }
    score += 3 if links.any? { |l| l.downcase.include?(term) }
    score += blob.scan(/\b#{Regexp.escape(term)}\b/).size
  end
  score += 6 if rel.include?("/30_AI_Coordination/") && query.downcase.include?("coord")
  score += 6 if rel.include?("/20_ArchitectureMemory/") && query.downcase.include?("arch")
  score += 6 if rel.include?("/50_RuntimeOps/") && query.downcase.include?("runtime")
  score += 6 if rel.include?("/60_DeliveryValidation/") && query.downcase.include?("valid")
  score += 6 if rel.include?("/70_SessionContinuity/") && query.downcase.include?("session")
  score += 4 if rel.include?("/80_SessionMemory/") && query.downcase.include?("memory")
  [score, rel, title, tags, links]
end

rows = rows.select { |score,| score > 0 }.sort_by { |score, rel, title,| [-score, rel] }.first(12)

puts "OpenJarvis retrieval candidates for: #{query}"
rows.each_with_index do |(score, rel, title, tags, links), idx|
  puts format("%2d. [%d] %s", idx + 1, score, rel)
  puts "    title: #{title}"
  puts "    tags: #{tags.first(4).join(' ')}" unless tags.empty?
  puts "    links: #{links.first(4).join(' ')}" unless links.empty?
end

# coding: utf-8
require 'morph'

# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# Examples:
#
#   cities = City.create([{ :name => 'Chicago' }, { :name => 'Copenhagen' }])
#   Mayor.create(:name => 'Daley', :city => cities.first)

WikiPage.destroy_all

module Morph
  class Item
    include Morph

    def first_lead_dg
      lead_dg.split("\n").first
      lead_dg.split(/–|-/).last.strip
    end

    def other_dg
      dgs = (lead_dg.sub(first_lead_dg,'') + associated_dg.to_s).split("\n")
      dgs.map {|dg| dg.split(/–|-/).last.strip}.join("\n")
    end
  end
end

def clean_text text
  text = text.gsub("\t",' ').gsub("\r",' ').gsub("\n",' ').gsub('"','').gsub('“','').gsub('”','').squeeze(' ').strip
  if text.encoding.name != "UTF-8"
    puts text.encoding.name
    text.encode!("UTF-8")
  end
  text
end

def path name
  title = clean_text(name)
  slug = FriendlyId::SlugString.new(title)
  normalized = slug.normalize!
  normalized = slug.approximate_ascii! unless slug.approximate_ascii!.blank?
  normalized.gsub!('ǎ','a')
  normalized.gsub!('ș','s')
  normalized.gsub!('ț','t')
  normalized
end

def load_file file
  csv = IO.read("#{RAILS_ROOT}/data/#{file}")
  items = Morph.from_csv(csv, 'Item')
  yield items
  items
end

def create_page path, title, content
  content = content.flatten.join("\n") if content.is_a?(Array)
  page = WikiPage.find_or_create_by_path(path)
  page.title = title
  page.content = content
  page.save
end

def create_group_page group, individuals
  content = []
  dg = "Directorate Generals"
  content << "[[#{path(dg)}|#{dg}]] -> [[#{path(group.first_lead_dg)}|#{clean_text(group.first_lead_dg)}]] -> #{group.en_name}\n"
  # content << "h2. #{group.code} \"#{group.name.strip.sub('“','').sub('”','')}\":#{group.uri} #{group.abbreviation ? "(#{group.abbreviation})" : ""}"
  # content << "#{ group.name.strip != group.en_name.strip ? " %(group-name-translated)#{group.en_name}%" : "" }"

  content << "h2. #{group.code} \"#{group.name.strip.sub('“','').sub('”','').gsub('"','')}\":#{group.uri} #{group.abbreviation ? "(#{group.abbreviation})" : ""}"

  content << "\n"
  content << "- Mission := #{group.mission}" if group.mission
  content << "- Task := #{group.task}" if group.task
  content << "- Group type := #{group.group_type}"
  content << "- Active since := #{group.active_since}"
  content << "- Creating act := #{group.creating_act}" if group.creating_act
  content << "- Composition := #{group.composition}"
  content << "- Status := #{group.status}"
  content << "- Scope := #{group.scope}"
  content << "- Policy area := #{group.policy_area}"
  content << "- Lead DG := [[#{path(group.first_lead_dg)}|#{group.first_lead_dg}]]"
  content << "- Associated DG := #{group.other_dg}" if group.other_dg.strip.size > 0
  content << "- Link to website := #{group.link_to_website}" if group.link_to_website
  content << "- Content last updated := #{group.last_updated}" if group.last_updated

  if individuals && individuals.size > 0
    content << "\nh3. Individual Group Members\n"
    individuals.each do |individual|
      content << "[[#{path(individual.name)}|#{individual.name}]]"
    end
  end

create_page path(group.en_name), group.en_name, content
end

def create_dg_index dg, groups, individuals
  content = [""]
  dgs = "Directorate Generals"
  content << "[[#{path(dgs)}|#{dgs}]] -> #{dg}\n"

  content << "The *#{dg.sub(' DG',' Directorate General')}* is lead DG for #{groups.size} expert group#{groups.size > 1 ? 's and other similar entities' : ''}."
  by_policy_area = groups.group_by {|g| g.policy_area.split("\n").join(", ") }
  by_policy_area.keys.sort.each do |policy_area|
    list = by_policy_area[policy_area]
    content << "\nh3. #{policy_area} expert group#{list.size > 1 ? 's' : ''}\n"
    sorted_groups = list.sort_by {|g| g.en_name}
    content << sorted_groups.collect {|g| "* [[#{g.en_name}]] %(group-code)#{g.code}%"}

    sorted_groups.each {|g| create_group_page g, individuals[g.code]}
  end
  title = "#{dg} - European Commission Expert Groups"
  create_page path(dg), title, content
end

def create_individual_page  name, list, group_to_en_name
  content = []
  content << "h2. #{name}\n"
  list.each do |i|
    group_name = group_to_en_name[clean_text(i.group_name)]
    content << "*Registry page*: #{i.uri}" if i.uri && i.uri.size > 0
    content << "*Member of group*: #{path(group_name)}|#{group_name}"
    content << "*Member of subgroup*: i.subgroup_name" if i.subgroup_name && i.subgroup_name.size > 0
  end
  create_page path(name), name, content
end

individuals = {}
load_file('ec_expert_group_individual_members.csv') do |items|
  individuals = items
end

group_to_en_name = {}

load_file('ec_expert_groups.csv') do |items|
  items.each {|i| group_to_en_name[clean_text(i.name)] = clean_text(i.en_name) }
  content = ['h2. Directorate-Generals with Expert Groups']
  by_dg = items.group_by { |item| item.first_lead_dg }

  by_dg.keys.sort.each do |dg|
    groups = by_dg[dg]
    create_dg_index dg, groups, individuals.group_by(&:group_code)
    content << "* [[#{path(dg)}|#{dg}]] %(group-count)#{groups.size} groups%"
  end

  create_page('directorate-generals','European Commission Expert Groups', content)
end

individuals.group_by(&:name).each do |name, list|
  create_individual_page name, list, group_to_en_name
end

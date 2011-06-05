# coding: utf-8
require 'morph'

# WikiPage.destroy_all

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

    def policy_areas
      policy_area.split("\n").compact.map(&:strip)
    end

    def link_name
      if member_type == 'Organisation'
        if name == 'Competent national authority'
          "#{name} (#{countries_areas_represented})"
        else
          acronym ? acronym : name
        end
      else
        name
      end
    end

    def active_since_year
      case active_since
        when /^(\d\d\d\d)$/
          $1
        when /^\d\d\/\d\d\/(\d\d\d\d)$/
          $1
        when /^\d\d\/\d\d\/(\d\d)$/
          "20#{$1}"
        else
          raise active_since.to_s
      end
    end
  end
end

def clean_text text
  t = text.gsub("\t",' ')
  t.gsub!('(c)','(c )')
  t.gsub!("\r",' ')
  t.gsub!("\n",' ')
  t.gsub!('"','')
  t.gsub!('“','')
  t.gsub!('”','')
  t.squeeze!(' ')
  t.strip!

  if t.encoding.name != "UTF-8"
    puts t.encoding.name
    t.encode!("UTF-8")
  end

  if t.include?('?')
    raise "#{text} ~~~> #{t}"
  end

  t
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
  csv = IO.read("#{RAILS_ROOT}/public/#{file}")
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

def create_group_page group, individuals, organisations, administrations
  content = []
  dgs = "Directorate Generals"

  content << crumb_trail(dgs, clean_text(group.first_lead_dg), group.en_name)

  policy_areas = group.policy_areas.map {|p| "[[#{path(p)}|#{p}]]"}.join("\n")

  content << "\n"
  content << "- Name :=\n#{group.name} =:" if clean_text(group.name) != clean_text(group.en_name)
  if group.policy_areas.size > 1
    content << "- Policy area(s) :=\n#{ policy_areas } =:"
  else
    content << "- Policy area(s) := #{ policy_areas }"
  end
  content << "- Lead DG := [[#{path(group.first_lead_dg)}|#{group.first_lead_dg}]]"
  content << "- Mission :=\n#{group.mission} =:" if group.mission
  content << "- Task :=\n#{group.task} =:" if group.task
  content << "- Group type := #{group.group_type}"
  content << "- Associated DG := #{group.other_dg.strip}" if group.other_dg.strip.size > 0
  content << "- Active since := #{group.active_since}"
  content << "- Creating act := #{group.creating_act}" if group.creating_act
  content << "- Composition := #{group.composition}"
  content << "- Status := #{group.status}"
  content << "- Scope := #{group.scope}"
  content << "- Link to website := #{group.link_to_website}" if group.link_to_website
  content << "- Content last updated := #{group.last_updated}" if group.last_updated
  content << "- Register entry := #{group.uri}"

  if individuals && individuals.size > 0
    content << "\nh3. Individual Group Members\n"
    individuals.sort_by(&:name).each do |individual|
      content << "[[#{path(individual.name)}|#{ clean_text(individual.name) }]]"
    end
  end

  if organisations && organisations.size > 0
    content << "\nh3. Organisation Group Members\n"
    organisations.sort_by(&:name).each do |organisation|
      content << "[[#{path(organisation.link_name)}|#{ clean_text(organisation.name) }]]"
    end
  end

  if administrations && administrations.size > 0
    content << "\nh3. Administrations Group Members\n"
    administrations.sort_by(&:name).each do |administration|
      content << "[[#{path(administration.name)}|#{ clean_text(administration.name) }]]"
    end
  end
  title = "#{group.en_name.strip.sub('“','').sub('”','').gsub('"','')} #{group.abbreviation ? "(#{group.abbreviation})" : ""} (#{group.code})"

  create_page path(group.en_name), title, content
end

def crumb_trail *list
  last = list.pop
  eg = 'European Commission Expert Groups'
  trail = ["[[ |#{eg}]]"]

  list.each do |item|
    trail << "[[#{path(item)}|#{item}]]"
  end

  trail << last
  trail.join(" -> ") + "\n"
end

def group_count_sentence start, groups
  "#{start} for #{groups.size} expert group#{groups.size > 1 ? 's and other similar entities' : ''}."
end

def create_policy_index policy, groups
  content = [ crumb_trail("Policy Areas", policy) ]

  content <<  group_count_sentence("*#{policy}* is the policy area", groups)

  by_year = groups.group_by {|g| g.active_since_year }
  by_year.keys.sort.each do |year|
    list = by_year[year]
    content << "\nh3. Active since #{year}\n"
    sorted_groups = list.sort_by {|g| g.en_name}
    content << sorted_groups.collect {|g| "* [[#{path(g.en_name)}|#{g.en_name}]] %(group-code)#{g.code}%"}
  end

  title = "#{policy} - European Commission Expert Groups"
  create_page path(policy), title, content
end

def create_dg_index dg, groups, individuals, organisations, administrations
  content = [ crumb_trail("Directorate Generals", dg) ]

  content <<  group_count_sentence("The *#{dg.sub(' DG',' Directorate General')}* is lead DG", groups)

  by_policy_area = groups.group_by {|g| g.policy_area.split("\n").join(", ") }
  by_policy_area.keys.sort.each do |policy_area|
    list = by_policy_area[policy_area]
    content << "\nh3. #{policy_area} expert group#{list.size > 1 ? 's' : ''}\n"
    sorted_groups = list.sort_by {|g| g.en_name}
    content << sorted_groups.collect {|g| "* [[#{path(g.en_name)}|#{g.en_name}]] %(group-code)#{g.code}%"}

    sorted_groups.each {|g| create_group_page g, individuals[g.code], organisations[g.code], administrations[g.code] }
  end
  title = "#{dg} - European Commission Expert Groups"
  create_page path(dg), title, content
end

def add_field content, entity, title, attribute
  content << "- #{title} := #{entity.send(attribute)}" if entity.send(attribute) && entity.send(attribute).size > 0
end

def add_organisation_fields name, organisation, content
  add_field content, organisation, 'Name', :name if organisation.name != name
  add_field content, organisation, 'Member type', :member_type
  add_field content, organisation, 'Area represented', :countries_areas_represented
  unless organisation.representatives[/Representative may vary/]
    content << "- Representatives :=\n#{organisation.representatives} =:" if organisation.representatives && organisation.representatives.size > 0
  end
end

def add_administration_fields administration, content
  content << "- Public authorities :=\n#{administration.public_authorities} =:" if administration.public_authorities && administration.public_authorities.size > 0
  unless organisation.representatives[/Representative may vary/]
    content << "- Representatives :=\n#{administration.representatives} =:" if administration.representatives && administration.representatives.size > 0
  end
end

def add_individual_fields individual, content
  add_field content, individual, 'Member type', :member_type
  add_field content, individual, 'Membership status', :membership_status
  add_field content, individual, 'Professional title', :professional_title
  add_field content, individual, 'Professional profile', :professional_profile
  add_field content, individual, 'Interest represented', :interest_represented
  add_field content, individual, 'Nationality', :nationality
  add_field content, individual, 'Gender', :gender
end

def create_entity_page name, list, group_to_en_name, type, supertype, subtype=nil
  content = if supertype
              if subtype
                [crumb_trail(supertype, subtype, type, name)]
              else
                [crumb_trail(supertype, type, name)]
              end
            else
              [crumb_trail(type, name)]
            end
  by_group = list.group_by(&:group_name)
  content << "\n*#{name}* is a member of #{by_group.keys.uniq} expert group#{by_group.keys.uniq.size > 1 ? 's' : ''}.\n"
  by_group.keys.sort.each do |group_name|
    items = by_group[group_name]
    group_name = group_to_en_name[clean_text(group_name)]
    uri = if with_uri = items.detect {|x| x.uri && x.uri.size > 0}
      with_uri.uri
    else
      nil
    end
    content << "\n\n- Member of group := [[#{path(group_name)}|#{group_name}]]"

    subgroups = []
    items.each do |i|
      if i.subgroup_name && i.subgroup_name.size > 0
        subgroups << i.subgroup_name
      end
    end

    content << "- Member of subgroup#{subgroups.size > 1 ? 's' : ''} :=\n#{subgroups.join("\n")} =:" if subgroups.size > 0

    fields = []
    items.each do |entity|
      yield name, entity, fields
    end
    fields = fields.uniq
    fields.each {|f| content << f}

    content << "- Source := \"EC Register of Expert Groups\":#{uri}" if uri
  end
  create_page path(name), name, content
end

def create_index_for content, groups_by_label
  groups_by_label.keys.sort.each do |label|
    list = groups_by_label[label]
    content << "* [[#{path(label)}|#{label}]] %(group-count)#{list.size} group#{list.size > 1 ? 's' : ''}%"
  end
  content << "\n"
  content
end

def create_dg_indexes groups, individuals, organisations, administrations
  content = [crumb_trail('Directorate Generals')]
  content << 'h2. Directorate-Generals with Expert Groups'

  by_dg = groups.group_by { |g| g.first_lead_dg }
  content = create_index_for(content, by_dg)
  create_page('directorate-generals','Directorate Generals - European Commission Expert Groups', content)

  by_dg.each do |dg, list|
    create_dg_index dg, list, individuals.group_by(&:group_code), organisations.group_by(&:group_code), administrations.group_by(&:group_code)
  end
end

def create_policy_indexes groups, group_to_en_name
  content = [crumb_trail('Policy Areas')]
  content << 'h2. Expert Group Policy Areas'

  by_policy = Hash.new {|h,k| h[k] = []}
  groups.each do |group|
    group.policy_areas.uniq.each do |policy|
      by_policy[policy] << group
    end
  end
  content = create_index_for(content, by_policy)
  create_page('policy-areas','Policy Areas - European Commission Expert Groups', content)

  by_policy.each do |policy, list|
    create_policy_index policy, list
  end
end

def set_acronym list, acronym
  list.each {|o| o.acronym = acronym}
end

def set_category list, category
  list.each {|o| o.category = category}
end

def remove_singleton_acronyms(organisations)
  organisations.group_by(&:acronym).each do |acronym, list|
    if acronym == "" || list.size < 2 || acronym == 'CES'
      set_acronym list, nil
    elsif acronym == 'COPA/COGECA' || acronym == 'COPA'
      set_acronym list, 'COPA-COGECA'
    elsif acronym == 'EUROCHAMBERS'
      set_acronym list, 'EUROCHAMBRES'
    end
  end

  organisations.group_by(&:acronym).each do |acronym, list|
    if acronym && list.map(&:category).uniq.size > 1
      case acronym
      when 'EUREAU'
        set_category list, 'International organization'
      when 'CEEP'
        set_category list, 'Trade Union'
      when 'COPA-COGECA'
        set_category list, 'International organization'
      when 'EUROCHAMBRES'
        set_category list, 'Corporate'
      when 'UEAPME'
        set_category list, 'Association'
      when 'BEUC'
        set_category list, 'NGO'
      when 'CELCAA'
        set_category list, 'Association'
      when 'CIAA'
        set_category list, 'Corporate'
      when 'EFFAT'
        set_category list, 'Trade Union'
      when 'IFOAM'
        set_category list, 'Association'
      when 'WWF'
        set_category list, 'NGO'
      when 'ECVC'
        set_category list, 'Association'
      else
        set_category list, list.last.category
        puts acronym # each acronym should only have one category
      end
    end
  end

  organisations.group_by(&:link_name).each do |link_name, list|
    if list.map(&:category).uniq.size > 1
      set_category list, list.last.category
      puts link_name # each link_name should only have one category
    end
  end
end

def create_organisation_indexes organisations, group_to_en_name
  remove_singleton_acronyms(organisations)
  organisations_by_category = organisations.group_by {|x| x.category.pluralize }

  organisations_by_category.each do |category, list|

    organisations_by_region = list.group_by do |x|
      if x.countries_areas_represented && x.countries_areas_represented.size > 0
        if x.countries_areas_represented.split("\n").size > 1
          "#{category} (Multiple)"
        else
          "#{category} (#{x.countries_areas_represented})"
        end
      else
        "#{category} (Other)"
      end
    end

    content = [crumb_trail('Organisations', category)]
    content << "h2. #{category} in Expert Groups\n"
    content = create_index_for(content, organisations_by_region)
    create_page(category.downcase.gsub(' ','-'), "#{category} - European Commission Expert Groups", content)

    organisations_by_region.each do |category_region, orgs|
      title = category_region
      create_entity_indexes(orgs, group_to_en_name, title, 'Organisations', category) do |name, entity, fields|
        add_organisation_fields name, entity, fields
      end
    end
  end

  content = [crumb_trail('Organisations')]
  content << "h2. Organisations in Expert Groups"
  create_index_for(content, organisations_by_category)
  create_page('organisations', "Organisations - European Commission Expert Groups", content)
end

def create_entity_indexes entities, group_to_en_name, title, supertype, subtype=nil
  content = if supertype
              if subtype
                [crumb_trail(supertype, subtype, title)]
              else
                [crumb_trail(supertype, title)]
              end
            else
              [crumb_trail(title)]
            end
  content << "h2. #{title} in Expert Groups\n"
  by_name = entities.group_by {|x| clean_text(x.link_name) }

  content = create_index_for(content, by_name)
  create_page(path(title.downcase.gsub(' ','-')), "#{title} - European Commission Expert Groups", content)

  entities.group_by(&:link_name).each do |name, list|
    create_entity_page(clean_text(name), list, group_to_en_name, title, supertype, subtype) do |name, entity, fields|
      yield name, entity, fields
    end
  end
end

def create_home_page
  content = ["This site contains a copy of the *Register of European Commission Expert Groups and Other Similar Entities*. For each group, the register provides standard information such as the Commission department running the group, as well as the group's mission, tasks and membership.\n\n"]

  content << "*Browse* the expert groups by:"
  content << "* [[policy-areas|Policy Area]]"
  content << "* [[directorate-generals|Directorate Generals]]\n"

  content << "*Download* the data under the share-alike attribution Open Database License:"
  content << %Q|* [["List of expert groups":/ec_expert_groups.csv]] csv|
  content << %Q|* [["Organisations that are members of expert groups":/ec_expert_group_organisation_members.csv]] csv|
  content << %Q|* [["National administrations that are members of expert groups":/ec_expert_group_national_administration_members.csv]] csv|
  content << %Q|* [["Individual that are members of expert groups":/ec_expert_group_individual_members.csv]] csv\n\n|

  content << "Data source: \"Register of Commission Expert Groups\":http://ec.europa.eu/transparency/regexpert/index.cfm (external site)"
  create_page('expert-groups','European Commission Expert Groups', content)
end

create_home_page

individuals = {}
load_file('ec_expert_group_individual_members.csv') { |items| individuals = items }

organisations = {}
load_file('ec_expert_group_organisation_members.csv') { |items| organisations = items }

administrations = {}
load_file('ec_expert_group_national_administration_members.csv') { |items| administrations = items }

group_to_en_name = {}

load_file('ec_expert_groups.csv') do |groups|
  groups.each {|g| group_to_en_name[clean_text(g.name)] = clean_text(g.en_name) }

  create_dg_indexes groups, individuals, organisations, administrations
  create_policy_indexes groups, group_to_en_name
end

create_entity_indexes(individuals, group_to_en_name, 'Individuals', nil) { |name, entity, fields| add_individual_fields entity, fields }

create_organisation_indexes organisations, group_to_en_name

create_entity_indexes(administrations, group_to_en_name, 'National Administrations', nil) { |name, entity, fields| add_administration_fields entity, fields }


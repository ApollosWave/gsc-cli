# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/gsc/skill_pack'

class SkillPackTest < Minitest::Test
  def setup
    @pack = GSC::SkillPack.new
  end

  def test_generate_skill_markdown
    md = @pack.generate_skill_markdown

    assert_includes md, '---'
    assert_includes md, 'name: gsc'
    assert_includes md, 'description:'
    assert_includes md, 'gsc performance'
    assert_includes md, 'gsc mobile-parity'
    assert_includes md, 'gsc rich-results'
    assert_includes md, 'gsc kw-value'
    assert_includes md, 'gsc eeat'
    assert_includes md, 'gsc inspect'
    assert_includes md, 'Autonomous Execution Recipes for AI Agents'
  end

  def test_generate_recipes_json
    recipes = @pack.generate_recipes_json

    assert_equal 'gsc', recipes[:skill]
    assert_equal GSC::VERSION, recipes[:version]
    refute_empty recipes[:recipes]

    recipe_names = recipes[:recipes].map { |r| r[:name] }
    assert_includes recipe_names, 'diagnose_traffic_drop'
    assert_includes recipe_names, 'optimize_striking_distance'
    assert_includes recipe_names, 'technical_page_audit'
  end

  def test_dry_run_packaging
    res = GSC::SkillPack.package({ dry_run: true })

    assert_equal 'gsc', res[:skill_name]
    assert res[:dry_run]
    assert res[:destinations_count] > 0
    assert_equal 0, res[:installed_locations].size
    refute_nil res[:verification]
    assert_includes ['READY_FOR_AI_AGENTS', 'BINARY_NEEDS_INSTALL'], res[:verification][:status]
  end

  def test_packaging_to_custom_directory
    Dir.mktmpdir do |tmpdir|
      res = GSC::SkillPack.package({}, tmpdir)

      refute res[:dry_run]
      assert_equal 1, res[:installed_locations].size
      loc = res[:installed_locations].first

      assert File.exist?(loc[:skill_path])
      assert File.exist?(loc[:recipe_path])

      skill_content = File.read(loc[:skill_path], encoding: 'UTF-8')
      recipe_content = File.read(loc[:recipe_path], encoding: 'UTF-8')

      assert_includes skill_content, 'name: gsc'
      assert_includes recipe_content, '"skill": "gsc"'
    end
  end
end

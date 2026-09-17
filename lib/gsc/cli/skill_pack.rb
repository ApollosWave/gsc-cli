# encoding: utf-8
# frozen_string_literal: true

require 'json'
require_relative 'base'
require_relative '../skill_pack'
require_relative '../color'

module GSC
  class CLI
    module SkillPack
      module_function

      def run(command, target, extra, options, api = nil, site_url = nil, hostname = nil)
        target_dir = target || (extra && extra.first)

        puts "📦 Packaging autonomous AI Agent Skill specification for #{Color.cyan(target_dir || options[:target] || 'all agent platforms')}..." unless options[:json]

        res = GSC::SkillPack.package(options, target_dir)

        if options[:json]
          puts JSON.pretty_generate(res)
          return
        end

        render_terminal(res)
      end

      def render_terminal(res)
        puts "\n#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"
        puts "#{Color.bold("🤖 AUTONOMOUS AI AGENT SKILL PACKAGING & INTEGRATION")}"
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}"

        puts "  • Skill Package Name:             #{Color.bold(res[:skill_name])} (v#{res[:version]})"
        puts "  • Execution Recipes Packaged:     #{Color.bold(res[:recipes_count].to_s)} autonomous playbooks"
        puts "  • Mode:                           #{res[:dry_run] ? Color.yellow("DRY RUN (Preview Only)") : Color.green("INSTALLED & ACTIVE")}"

        v = res[:verification]
        status_color = v[:status] == 'READY_FOR_AI_AGENTS' ? Color.green(v[:status]) : Color.red(v[:status])
        puts "  • AI Agent Execution Health:      [ #{Color.bold(status_color)} ]"
        puts "  • Target Binary Executable:       #{v[:binary_path]}"
        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}\n"

        if res[:installed_locations].any?
          puts "#{Color.bold("INSTALLED AGENT SKILL LOCATIONS:")}\n"
          res[:installed_locations].each do |loc|
            puts "  ✅ #{Color.bold(loc[:platform])}:"
            puts "     📄 SKILL.md:     #{Color.cyan(loc[:skill_path])}"
            puts "     📋 recipes.json: #{Color.cyan(loc[:recipe_path])}\n"
          end
        end

        puts "#{Color.bold("───────────────────────────────────────────────────────────────────────────")}"
        puts "#{Color.bold("AI AGENT USAGE TRIGGER PROMPT:")}"
        puts "  Copy and paste into your AI agent or IDE (Cursor, Claude, Antigravity, Windsurf, Codex):"
        puts Color.cyan("  \"Inspect our SEO health for my active domain using `gsc audit --json`")
        puts Color.cyan("   and diagnose any striking distance keyword opportunities with `gsc kw-value --json`.\"")
        puts "#{Color.bold("═══════════════════════════════════════════════════════════════════════════")}\n"
      end
    end
  end
end

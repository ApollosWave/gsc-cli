# frozen_string_literal: true

module GSC
  module Color
    RESET     = "\e[0m"
    BOLD      = "\e[1m"
    DIM       = "\e[2m"
    UNDERLINE = "\e[4m"
    RED       = "\e[31m"
    GREEN     = "\e[32m"
    YELLOW    = "\e[33m"
    BLUE      = "\e[34m"
    MAGENTA   = "\e[35m"
    CYAN      = "\e[36m"
    WHITE     = "\e[37m"
    GRAY      = "\e[90m"

    def self.c(text, *styles)
      t = text.to_s.dup.force_encoding('UTF-8').scrub
      "#{styles.join}#{t}#{RESET}"
    end

    def self.cyan(str); c(str, CYAN); end
    def self.yellow(str); c(str, YELLOW); end
    def self.green(str); c(str, GREEN); end
    def self.red(str); c(str, RED); end
    def self.bold(str); c(str, BOLD); end
    def self.gray(str); c(str, GRAY); end
    def self.magenta(str); c(str, MAGENTA); end
    def self.white(str); c(str, WHITE); end
    def self.dim(str); c(str, DIM); end

    def self.strip_ansi(str)
      str.to_s.gsub(/\e\[[0-9;]*[mK]/, '')
    end
  end
end

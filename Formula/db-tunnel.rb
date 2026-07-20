require "download_strategy"
require "fileutils"
require "system_command"

class GitHubCliDownloadStrategyError < RuntimeError; end

class GitHubCliDownloadStrategy < CurlDownloadStrategy
  def initialize(url, name, version, **meta)
    super

    match_data = %r{^https://github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)/releases/download/(?<tag>[^/]+)/(?<filename>[^/]+)$}.match(@url)
    return unless match_data

    @owner = match_data[:owner]
    @repo = match_data[:repo]
    @tag = match_data[:tag]
    @filename = match_data[:filename]
  end

  def fetch(timeout: nil)
    raise GitHubCliDownloadStrategyError, "Unsupported GitHub release URL: #{url}" unless @owner && @repo && @tag && @filename

    if cached_location.exist?
      puts "Already downloaded: #{cached_location}"
    else
      gh = ["/opt/homebrew/bin/gh", "/usr/local/bin/gh"].find { |path| File.executable?(path) }
      raise GitHubCliDownloadStrategyError, "GitHub CLI is required. Install it with: brew install gh" unless gh

      begin
        temporary_path.dirname.mkpath
        system_command(
          gh,
          args: [
            "release", "download", @tag,
            "--repo", "#{@owner}/#{@repo}",
            "--pattern", @filename,
            "--dir", temporary_path.dirname.to_s,
            "--clobber",
          ],
          print_stderr: true,
        )
      rescue ErrorDuringExecution
        raise GitHubCliDownloadStrategyError, "GitHub CLI download failed for: #{url}. Run: gh auth login"
      end

      downloaded_file = temporary_path.dirname.join(@filename)
      raise GitHubCliDownloadStrategyError, "Downloaded file not found: #{downloaded_file}" unless downloaded_file.exist?

      cached_location.dirname.mkpath
      FileUtils.mv(downloaded_file, cached_location)
    end

    symlink_location.dirname.mkpath
    FileUtils.ln_s cached_location.relative_path_from(symlink_location.dirname), symlink_location, force: true
  end
end

class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.1.5"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.1.5/db-tunnel-v0.1.5.tar.gz",
      using: GitHubCliDownloadStrategy
  sha256 "25f329c157a93021ef7da038abd12767934d870a4e8a27eb621ac2d37c4eefbd"

  depends_on "awscli"
  depends_on "jq"

  def install
    bin.install "bin/db-tunnel"
    bin.install "bin/db-auth-token"
    pkgshare.install "share/db-tunnels.json"
  end

  def caveats
    <<~EOS
      db-tunnel opens AWS SSM sessions and requires Amazon's Session Manager
      plugin. If it is missing, db-tunnel will offer to install it with:

        brew install --cask session-manager-plugin
    EOS
  end

  test do
    assert_match "Available database tunnels:", shell_output("#{bin}/db-tunnel list")
  end
end

require_relative "lib/github_cli_download_strategy"

class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.1.6"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.1.6/db-tunnel-v0.1.6.tar.gz",
      using: GitHubCliDownloadStrategy
  sha256 "594859b915bab617093d54db1e79cc53eb1ed613bb900d8a4777be2bc054b359"

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

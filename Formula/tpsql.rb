require_relative "lib/github_cli_download_strategy"

class Tpsql < Formula
  desc "psql wrapper that authenticates to Aura db-tunnel endpoints with a fresh IAM token"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.1.1"

  url "https://github.com/aura-app/homebrew-tap/releases/download/tpsql-v0.1.1/tpsql-v0.1.1.tar.gz",
      using: GitHubCliDownloadStrategy
  sha256 "67bd5a7c38931d58664dfe8ce8d2cb6cad01c01fa1108b6ba0ce2d8c11e23ff1"

  depends_on "db-tunnel"
  depends_on "jq"
  depends_on "libpq"

  def install
    bin.install "bin/tpsql"
    bin.install_symlink Formula["libpq"].opt_bin/"psql"
  end

  test do
    assert_match "Usage:", shell_output("#{bin}/tpsql --help")
  end
end

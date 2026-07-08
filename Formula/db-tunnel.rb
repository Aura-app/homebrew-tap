class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.1.0"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.1.0/db-tunnel-v0.1.0.tar.gz"
  sha256 "35ef1604d197cfcce094eba976f505a88f0f0b688620dfb3a51badcdb52d6929"

  depends_on "awscli"
  depends_on "jq"
  depends_on "session-manager-plugin"

  def install
    bin.install "bin/db-tunnel"
    bin.install "bin/db-auth-token"
    pkgshare.install "share/db-tunnels.json"
  end

  test do
    assert_match "Available database tunnels:", shell_output("#{bin}/db-tunnel list")
  end
end

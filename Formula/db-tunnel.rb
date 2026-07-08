class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.1.1"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.1.1/db-tunnel-v0.1.1.tar.gz"
  sha256 "9e265b2444c675c227a5676f305c5c4d626c3d403d4a9bb1b272f44857d4d882"

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

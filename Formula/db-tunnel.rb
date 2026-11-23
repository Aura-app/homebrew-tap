class DbTunnel < Formula
  desc "Aura database tunnel helper"
  homepage "https://github.com/aura-app/homebrew-tap"
  version "0.4.0"

  url "https://github.com/aura-app/homebrew-tap/releases/download/db-tunnel-v0.4.0/db-tunnel-v0.4.0.tar.gz"
  sha256 "8144fc477b0c35e4fd71b96bda784ed3177243788376dc8e521f72a7204bf900"

  depends_on "awscli"
  depends_on "jq"

  def install
    bin.install "bin/db-tunnel"
    bin.install "bin/db-auth-token"
    pkgshare.install "share/db-tunnels.json"
    valentina_hook = buildpath/"share/valentina-pre-connect.py"
    pkgshare.install valentina_hook if valentina_hook.exist?
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

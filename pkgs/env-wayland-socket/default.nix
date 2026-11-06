{ lib, stdenv, wayland, wayland-protocols, wayland-scanner, pkg-config }:
stdenv.mkDerivation {
  pname = "env-wayland-socket";
  version = "0.1";
  src = ./.;
  strictDeps = true;
  nativeBuildInputs = [ wayland-scanner pkg-config ];
  buildInputs = [ wayland ];
  buildPhase = ''
    xml=${wayland-protocols}/share/wayland-protocols/staging/security-context/security-context-v1.xml
    wayland-scanner client-header "$xml" security-context-v1-client-protocol.h
    wayland-scanner private-code "$xml" security-context-v1-protocol.c
    $CC -O2 -Wall -Wextra -Werror -o env-wayland-socket main.c security-context-v1-protocol.c \
      $(pkg-config --cflags --libs wayland-client)
  '';
  installPhase = "install -Dm755 env-wayland-socket $out/bin/env-wayland-socket";
  meta = {
    description = "Create a sandboxed (wp_security_context_v1) Wayland socket for an env";
    license = lib.licenses.mit;
    mainProgram = "env-wayland-socket";
  };
}

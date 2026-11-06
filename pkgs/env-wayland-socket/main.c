// env-wayland-socket: create a Wayland socket for one env through the compositor's
// wp_security_context_v1. Clients connecting to it are marked as sandboxed, so the
// compositor withholds privileged protocols (screen capture, clipboard managers, virtual
// keyboards, window management) while ordinary windows and GPU buffers work normally.
//
// usage: env-wayland-socket SOCKET_PATH NAME
// Connects to the compositor named by WAYLAND_DISPLAY, then stays running: the compositor
// keeps accepting connections on SOCKET_PATH until this process exits.
#define _GNU_SOURCE // pipe2
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>
#include <wayland-client.h>
#include "security-context-v1-client-protocol.h"

static struct wp_security_context_manager_v1 *manager;

static void global_add(void *data, struct wl_registry *registry, uint32_t name,
                       const char *interface, uint32_t version) {
    (void)data; (void)version;
    if (strcmp(interface, wp_security_context_manager_v1_interface.name) == 0)
        manager = wl_registry_bind(registry, name, &wp_security_context_manager_v1_interface, 1);
}
static void global_remove(void *data, struct wl_registry *registry, uint32_t name) {
    (void)data; (void)registry; (void)name;
}
static const struct wl_registry_listener registry_listener = { global_add, global_remove };

int main(int argc, char **argv) {
    if (argc != 3) {
        fprintf(stderr, "usage: %s SOCKET_PATH NAME\n", argv[0]);
        return 2;
    }
    const char *path = argv[1], *name = argv[2];

    struct wl_display *display = wl_display_connect(NULL);
    if (!display) { fprintf(stderr, "can't connect to the compositor (WAYLAND_DISPLAY)\n"); return 1; }
    struct wl_registry *registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &registry_listener, NULL);
    wl_display_roundtrip(display);
    if (!manager) { fprintf(stderr, "compositor has no wp_security_context_manager_v1\n"); return 1; }

    struct sockaddr_un addr = { .sun_family = AF_UNIX };
    if (strlen(path) >= sizeof(addr.sun_path)) { fprintf(stderr, "socket path too long\n"); return 1; }
    strcpy(addr.sun_path, path);
    unlink(path);
    int listen_fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (listen_fd < 0 || bind(listen_fd, (struct sockaddr *)&addr, sizeof(addr)) < 0 || listen(listen_fd, 128) < 0) {
        fprintf(stderr, "can't listen on %s: %s\n", path, strerror(errno));
        return 1;
    }
    chmod(path, 0700); // only the owner; the env sees it as its own through an idmapped mount

    // The compositor stops listening when the other end of this pipe closes, i.e. when we exit.
    int close_pipe[2];
    if (pipe2(close_pipe, O_CLOEXEC) < 0) { perror("pipe2"); return 1; }

    struct wp_security_context_v1 *ctx =
        wp_security_context_manager_v1_create_listener(manager, listen_fd, close_pipe[0]);
    wp_security_context_v1_set_sandbox_engine(ctx, "nixos-envs");
    wp_security_context_v1_set_app_id(ctx, name);
    wp_security_context_v1_set_instance_id(ctx, name);
    wp_security_context_v1_commit(ctx);
    wp_security_context_v1_destroy(ctx);
    if (wl_display_roundtrip(display) < 0) { fprintf(stderr, "compositor refused the security context\n"); return 1; }

    close(listen_fd);
    close(close_pipe[0]);
    fprintf(stderr, "env %s: sandboxed Wayland socket at %s\n", name, path);

    // Stay alive (holding the pipe's write end) for as long as the compositor runs.
    while (wl_display_dispatch(display) != -1) { }
    return 0;
}

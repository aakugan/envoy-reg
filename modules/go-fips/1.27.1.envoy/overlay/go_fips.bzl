"""Host-architecture-aware fetch of the FIPS-pinned Go runtime.

The module source is the linux-amd64 Go tarball, so on any other architecture
BoringSSL's FIPS build runs an x86_64 `go` and its delocate step fails with
"Exec format error". This rule fetches the same Go version built for the host
instead.

The version must stay the one this module pins. BoringSSL's FIPS validation
names exact build tool versions, so this selects a different architecture,
never a different version.
"""

GO_FIPS_VERSION = "1.27.1"

# The module source is the linux-amd64 tarball, so amd64 is reused from the module
# root rather than fetched again, and source.json's integrity covers its hash.
_MODULE_SOURCE_ARCH = "amd64"

# sha256 of https://go.dev/dl/go{version}.linux-{arch}.tar.gz
_GO_FIPS_SHA256 = {
    "arm64": "3450b45a3f9ee8568792736a5c5e70a1f2e9b36c35a8f74958c03e51d7d92bec",
}

# repository_ctx.os.arch reports the JVM's os.arch, which is "amd64" on x86_64
# and "aarch64" on arm64, while Go's download names are "amd64" and "arm64".
# Accept both spellings of each so this does not depend on which one a given
# Bazel or JVM reports.
_GO_ARCH = {
    "amd64": "amd64",
    "x86_64": "amd64",
    "aarch64": "arm64",
    "arm64": "arm64",
}

_BUILD_FILE = """\
package(default_visibility = ["//visibility:public"])

exports_files([
    "bin/go",
    "bin/gofmt",
])

filegroup(
    name = "go_sdk",
    srcs = glob(
        ["**"],
        exclude = ["**/test/**"],
    ),
)

filegroup(
    name = "go",
    srcs = ["bin/go"],
)
"""

def _go_fips_impl(repository_ctx):
    host_arch = repository_ctx.os.arch
    go_arch = _GO_ARCH.get(host_arch)
    if go_arch == None:
        fail("go_fips: unsupported host architecture {}, expected one of {}".format(
            host_arch,
            sorted(_GO_ARCH),
        ))

    if go_arch == _MODULE_SOURCE_ARCH:
        # This module's own source is the linux-amd64 tarball, already extracted at the
        # module root, so link it in instead of downloading the same bytes again. The
        # overlay files are skipped: this repo gets its own BUILD.bazel below.
        module_root = repository_ctx.path(Label("//:MODULE.bazel")).dirname
        for entry in module_root.readdir():
            if entry.basename.endswith((".bzl", ".bazel")):
                continue
            repository_ctx.symlink(entry, entry.basename)
    else:
        repository_ctx.download_and_extract(
            url = "https://go.dev/dl/go{}.linux-{}.tar.gz".format(GO_FIPS_VERSION, go_arch),
            sha256 = _GO_FIPS_SHA256[go_arch],
            stripPrefix = "go",
        )
    repository_ctx.file("BUILD.bazel", _BUILD_FILE)

go_fips = repository_rule(
    implementation = _go_fips_impl,
    doc = "Downloads the FIPS-pinned Go toolchain for the host architecture.",
)
